//! Preparation, transfer validation, and retry behavior with generated test keys.
use super::{
    Bundle, Deployment, Destination, Request, WorkerArgs, decode, inspect_all, make_request,
    materialize_sources, prepare_request, shell_quote, stage_bundle,
};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use std::{collections::BTreeMap, path::PathBuf};

type TestResult = Result<(), Box<dyn std::error::Error>>;
struct Fixture {
    temporary: tempfile::TempDir,
    repository: PathBuf,
    plan_path: PathBuf,
    signing_path: PathBuf,
    target: nix_seal_core::Id,
}
fn fixture() -> Result<Fixture, Box<dyn std::error::Error>> {
    let temporary = tempfile::tempdir()?;
    let repository = temporary.path().join("repository");
    let secrets = repository.join("secrets");
    std::fs::create_dir_all(&secrets)?;
    let plan_path = temporary.path().join("plan.v2.json");
    let signing_path = temporary.path().join("release.signing-key");

    let (_target_identity, target_recipient) = nix_seal_crypto::generate_x25519();
    let target_id = nix_seal_core::Id::parse("host.direct")?;
    let secret_id = nix_seal_core::Id::parse("application/token")?;
    let signer_id = nix_seal_core::Id::parse("signer.release")?;
    let signing_key = nix_seal_manifest::ApprovalSigningKey::generate()?;
    crate::write_new_private(&signing_path, signing_key.encode_private()?.as_bytes())?;
    let mut ciphertext = std::fs::File::create(secrets.join("token.age"))?;
    nix_seal_crypto::encrypt(
        b"direct-cli-canary".as_slice(),
        &mut ciphertext,
        std::slice::from_ref(&target_recipient),
    )?;
    ciphertext.sync_all()?;

    let source_hash = crate::canonical_ciphertext_hash(&repository, "secrets/token.age")?;
    let mut plan = nix_seal_core::PlanV2::default();
    plan.identities.insert(
        nix_seal_core::Id::parse("target.direct")?,
        nix_seal_core::Identity {
            kind: nix_seal_core::IdentityKind::Target,
            public: target_recipient,
        },
    );
    plan.identities.insert(
        signer_id.clone(),
        nix_seal_core::Identity {
            kind: nix_seal_core::IdentityKind::Signer,
            public: signing_key.encode_public()?,
        },
    );
    plan.targets.insert(
        target_id.clone(),
        nix_seal_core::Target {
            kind: nix_seal_core::TargetKind::NixOs,
            system: "x86_64-linux".to_owned(),
            identity: nix_seal_core::Id::parse("target.direct")?,
            username: None,
            configuration: None,
            environment: None,
            tags: Vec::new(),
            service_actions: None,
        },
    );
    plan.secrets.insert(
        secret_id.clone(),
        nix_seal_core::Secret {
            source: "secrets/token.age".to_owned(),
            source_ciphertext_hash: source_hash,
            delivery: nix_seal_core::DeliveryMode::Direct,
            administrators: Vec::new(),
            consumers: vec![target_id.clone()],
            selectors: nix_seal_core::TargetSelectors::default(),
            phase: nix_seal_core::ActivationPhase::Activation,
            runtime: nix_seal_core::RuntimeSettings::default(),
            runtime_overrides: BTreeMap::default(),
            lifecycle: nix_seal_core::Lifecycle::default(),
            approval_policy: None,
            repository_only: false,
        },
    );
    nix_seal_policy::validate(&plan)?;
    std::fs::write(&plan_path, nix_seal_policy::canonical_json(&plan)?)?;

    Ok(Fixture {
        temporary,
        repository,
        plan_path,
        signing_path,
        target: target_id,
    })
}
impl Fixture {
    fn request(&self) -> anyhow::Result<Request> {
        make_request(
            &Deployment {
                schema: "nix-seal.deployment.v1".to_owned(),
                targets: vec![Destination {
                    target: self.target.clone(),
                    plan: self.plan_path.clone(),
                    cache_root: self.temporary.path().join("installed"),
                    user: None,
                    specs: Vec::new(),
                }],
            },
            &self.repository,
        )
    }
    fn arguments(&self, execute: bool) -> WorkerArgs {
        WorkerArgs {
            identity: None,
            signing_key: self.signing_path.clone(),
            generation: None,
            execute,
        }
    }
}

#[test]
fn dry_run_then_prepare_transfer_and_retry() -> TestResult {
    let fixture = fixture()?;
    let request = fixture.request()?;
    let cache = fixture.temporary.path().join("administrator-cache");
    let dry = prepare_request(&request, &fixture.arguments(false), &cache)?;
    assert!(!dry.prepared);
    assert!(dry.bundle.artifacts.is_empty());
    assert!(
        !cache.exists(),
        "dry run must not create an administrator cache"
    );
    let first = prepare_request(&request, &fixture.arguments(true), &cache)?;
    assert_eq!((first.created, first.reused), (1, 0));
    let retry = prepare_request(&request, &fixture.arguments(true), &cache)?;
    assert_eq!((retry.created, retry.reused), (0, 1));
    assert_eq!(
        first.bundle.artifacts[0].ciphertext,
        retry.bundle.artifacts[0].ciphertext
    );
    assert_eq!(
        first.bundle.artifacts[0].envelope,
        retry.bundle.artifacts[0].envelope
    );
    let transported: Bundle = decode(serde_json::to_vec(&first.bundle)?.as_slice())?;
    let installed = fixture.temporary.path().join("installed");
    stage_bundle(&transported, &installed)?;
    assert_eq!(inspect_all(&installed, &request.targets[0])?.len(), 1);
    assert!(
        crate::run_doctor(
            &fixture.plan_path,
            &fixture.repository,
            Some(installed),
            None,
            true
        )
        .is_ok()
    );
    Ok(())
}

#[test]
fn changed_plan_reprovisions_and_preserves_previous_generation() -> TestResult {
    let fixture = fixture()?;
    let mut request = fixture.request()?;
    let cache = fixture.temporary.path().join("cache");
    prepare_request(&request, &fixture.arguments(true), &cache)?;
    let secret = request.targets[0]
        .plan
        .secrets
        .values_mut()
        .next()
        .ok_or("missing secret")?;
    secret.runtime.mode = "0600".to_owned();
    let missing = crate::readiness::plan_reports(&request.targets[0].plan, &cache)?;
    assert!(!missing[0].is_ready());
    assert!(missing[0].failure_message().contains("different plan"));
    let response = prepare_request(&request, &fixture.arguments(true), &cache)?;
    assert_eq!(response.created, 1);
    assert_eq!(
        nix_seal_cache::Cache::open(&cache)?
            .artifact_records()?
            .len(),
        2
    );
    assert!(
        crate::readiness::plan_reports(&request.targets[0].plan, &cache)?
            .iter()
            .all(crate::readiness::Report::is_ready)
    );
    Ok(())
}

#[test]
fn tampered_response_never_counts_as_ready() -> TestResult {
    let fixture = fixture()?;
    let request = fixture.request()?;
    let response = prepare_request(
        &request,
        &fixture.arguments(true),
        &fixture.temporary.path().join("cache"),
    )?;
    let mut bundle = response.bundle;
    bundle.artifacts[0].ciphertext = STANDARD.encode(b"tampered ciphertext");
    let stage = fixture.temporary.path().join("tampered");
    stage_bundle(&bundle, &stage)?;
    assert!(inspect_all(&stage, &request.targets[0])?.is_empty());
    Ok(())
}

#[test]
fn request_rejects_traversal_and_source_mismatch_without_cache_writes() -> TestResult {
    let fixture = fixture()?;
    let mut request = fixture.request()?;
    request
        .sources
        .insert("../escape.age".to_owned(), STANDARD.encode(b"canary"));
    assert!(materialize_sources(&request, fixture.temporary.path()).is_err());
    let mut request = fixture.request()?;
    request
        .sources
        .insert("secrets/token.age".to_owned(), STANDARD.encode(b"canary"));
    let cache = fixture.temporary.path().join("cache");
    assert!(prepare_request(&request, &fixture.arguments(true), &cache).is_err());
    assert!(!cache.exists());
    Ok(())
}

#[test]
fn remote_request_contains_no_private_key_material_or_locations() -> TestResult {
    let fixture = fixture()?;
    let request = fixture.request()?;
    let wire = serde_json::to_string(&request)?;
    assert!(!wire.contains("release.signing-key"));
    assert!(!wire.contains("PRIVATE"));
    let decoded: Request = decode(wire.as_bytes())?;
    assert_eq!(decoded.targets[0].target, fixture.target);
    assert_eq!(decoded.sources.len(), 1);
    assert_eq!(
        shell_quote("/keys/a 'quoted' $(name)"),
        "'/keys/a '\\''quoted'\\'' $(name)'"
    );
    Ok(())
}

#[test]
fn multiple_generations_cannot_hide_a_missing_secret() -> TestResult {
    let fixture = fixture()?;
    let mut request = fixture.request()?;
    let second = nix_seal_core::Id::parse("application/second")?;
    let first = nix_seal_core::Id::parse("application/token")?;
    let mut secret = request.targets[0].plan.secrets[&first].clone();
    secret.source = "secrets/second.age".to_owned();
    std::fs::copy(
        fixture.repository.join("secrets/token.age"),
        fixture.repository.join(&secret.source),
    )?;
    request.sources.insert(
        secret.source.clone(),
        request.sources["secrets/token.age"].clone(),
    );
    request.targets[0]
        .plan
        .secrets
        .insert(second.clone(), secret);
    let cache = fixture.temporary.path().join("cache");
    let mut arguments = fixture.arguments(true);
    arguments.generation = Some(1);
    prepare_request(&request, &arguments, &cache)?;
    let records = nix_seal_cache::Cache::open(&cache)?.artifact_records()?;
    for record in &records {
        let envelope = serde_json::from_slice(&record.envelope)?;
        if nix_seal_manifest::inspect_unverified(&envelope)?.secret_id == second {
            std::fs::remove_dir_all(record.ciphertext_path.parent().ok_or("bundle parent")?)?;
        }
    }
    let target = &request.targets[0];
    std::fs::write(
        &fixture.plan_path,
        nix_seal_policy::canonical_json(&target.plan)?,
    )?;
    crate::run_rekey(
        crate::RekeyArgs {
            plan: fixture.plan_path.clone(),
            repository_root: fixture.repository.clone(),
            identity: None,
            target: target.target.clone(),
            secret: first,
            generation: 2,
            signing_key: fixture.signing_path.clone(),
            expires_at: None,
            cache_root: Some(cache.clone()),
        },
        true,
    )?;
    assert_eq!(
        nix_seal_cache::Cache::open(&cache)?
            .artifact_records()?
            .len(),
        2
    );
    let reports = crate::readiness::plan_reports(&target.plan, &cache)?;
    assert_eq!(reports[0].verified, 1);
    assert_eq!(reports[0].required, 2);
    assert_eq!(reports[0].missing[0].secret_id, second);
    assert!(
        crate::run_doctor(
            &fixture.plan_path,
            &fixture.repository,
            Some(cache),
            None,
            true
        )
        .is_err()
    );
    Ok(())
}

#[test]
fn rejected_signature_is_reported_without_printing_envelope_contents() -> TestResult {
    let fixture = fixture()?;
    let request = fixture.request()?;
    let mut response = prepare_request(
        &request,
        &fixture.arguments(true),
        &fixture.temporary.path().join("cache"),
    )?;
    let encoded = STANDARD.decode(&response.bundle.artifacts[0].envelope)?;
    let mut envelope: nix_seal_manifest::SignedEnvelopeV1 = serde_json::from_slice(&encoded)?;
    envelope.signatures[0].signature = "private-canary-invalid-signature".to_owned();
    response.bundle.artifacts[0].envelope = STANDARD.encode(serde_json::to_vec(&envelope)?);
    let cache = fixture.temporary.path().join("untrusted");
    stage_bundle(&response.bundle, &cache)?;
    let reports = crate::readiness::plan_reports(&request.targets[0].plan, &cache)?;
    assert!(!reports[0].is_ready());
    let message = reports[0].failure_message();
    assert!(message.contains("candidate rejected"));
    assert!(!message.contains("private-canary"));
    Ok(())
}
