#![forbid(unsafe_code)]
//! Full CLI preparation and SSH transport with generated identities and isolated caches.
use secrecy::ExposeSecret;
use serde_json::{Value, json};
use sha2::Digest;
use std::os::unix::fs::PermissionsExt;
use std::{
    collections::BTreeMap,
    path::PathBuf,
    process::{Command, Output},
};

type TestResult = Result<(), Box<dyn std::error::Error>>;
fn write_private(path: &std::path::Path, value: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)?;
    file.set_permissions(std::fs::Permissions::from_mode(0o600))?;
    file.write_all(value)
}
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
    write_private(&signing_path, signing_key.encode_private()?.as_bytes())?;
    let mut ciphertext = std::fs::File::create(secrets.join("token.age"))?;
    nix_seal_crypto::encrypt(
        b"direct-cli-canary".as_slice(),
        &mut ciphertext,
        std::slice::from_ref(&target_recipient),
    )?;
    ciphertext.sync_all()?;

    let source_hash = format!(
        "{:x}",
        base16ct::HexDisplay(&sha2::Sha256::digest(std::fs::read(
            secrets.join("token.age")
        )?))
    );
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
fn cli(fixture: &Fixture, args: &[&str]) -> Result<Output, std::io::Error> {
    Command::new(env!("CARGO_BIN_EXE_nix-seal"))
        .args(args)
        .env("XDG_CACHE_HOME", fixture.temporary.path().join("xdg-cache"))
        .current_dir(&fixture.repository)
        .output()
}
fn successful(output: &Output) {
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}
fn deployment(fixture: &Fixture) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let plan: nix_seal_core::PlanV2 = serde_json::from_slice(&std::fs::read(&fixture.plan_path)?)?;
    let policy = nix_seal_policy::target_policy(&plan, &fixture.target)?;
    let spec = fixture.temporary.path().join("activation.json");
    let cache = fixture.temporary.path().join("installed");
    let artifacts: Vec<_> = policy
        .secrets
        .iter()
        .map(|(id, secret)| {
            json!({
                "secretId": id, "owner":secret.runtime.owner, "group":secret.runtime.group,
                "mode":secret.runtime.mode, "phase":secret.phase, "compatibilitySymlink":null
            })
        })
        .collect();
    std::fs::write(
        &spec,
        serde_json::to_vec(&json!({
            "schema":"nix-seal.activation.v2", "plan":fixture.plan_path, "targetId":fixture.target,
            "phase":"activation", "artifactCacheRoot":cache, "runtimeRoot":fixture.temporary.path().join("runtime"),
            "runtimeStorage":"persistent", "allowedClockSkew":300, "artifacts":artifacts, "templates":[], "postSwitch":null
        }))?,
    )?;
    let user =
        uzers::get_user_by_uid(rustix::process::geteuid().as_raw()).ok_or("missing test user")?;
    let description = fixture.temporary.path().join("deployment.json");
    std::fs::write(
        &description,
        serde_json::to_vec(&json!({
            "schema":"nix-seal.deployment.v1", "targets":[{
                "target":fixture.target, "plan":fixture.plan_path, "cacheRoot":cache,
                "user":user.name().to_str().ok_or("test username must be UTF-8")?, "specs":[spec]
            }]
        }))?,
    )?;
    Ok(description)
}

#[test]
fn doctor_and_readiness_fail_before_preparation_and_pass_after_install() -> TestResult {
    let fixture = fixture()?;
    let deployment = deployment(&fixture)?;
    let spec = fixture.temporary.path().join("activation.json");
    let mut symbolic: Value = serde_json::from_slice(&std::fs::read(&spec)?)?;
    symbolic["runtimeRoot"] = json!("%t/nix-seal");
    std::fs::write(&spec, serde_json::to_vec(&symbolic)?)?;
    let before = cli(
        &fixture,
        &[
            "readiness",
            "--spec",
            spec.to_str().ok_or("path")?,
            "--json",
        ],
    )?;
    assert!(!before.status.success());
    let report: Value = serde_json::from_slice(&before.stdout)?;
    assert_eq!(report["ready"], false);
    assert_eq!(
        report["artifacts"][0]["missing"][0]["secretId"],
        "application/token"
    );
    assert!(!fixture.temporary.path().join("runtime").exists());
    let plan = fixture.plan_path.to_str().ok_or("path")?;
    let doctor = cli(&fixture, &["doctor", "--plan", plan, "--json"])?;
    assert!(!doctor.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&doctor.stdout)?["ok"],
        false
    );
    let args = [
        "prepare",
        "--deployment",
        deployment.to_str().ok_or("path")?,
        "--signing-key",
        fixture.signing_path.to_str().ok_or("path")?,
        "--json",
    ];
    let dry = cli(&fixture, &args)?;
    successful(&dry);
    assert_eq!(
        serde_json::from_slice::<Value>(&dry.stdout)?["installed"],
        false
    );
    assert!(!fixture.temporary.path().join("installed").exists());
    let mut execute = args.to_vec();
    execute.push("--execute");
    let prepared = cli(&fixture, &execute)?;
    successful(&prepared);
    let report: Value = serde_json::from_slice(&prepared.stdout)?;
    assert_eq!(report["installed"], true);
    assert_eq!(report["activated"], false);
    assert!(!fixture.temporary.path().join("runtime").exists());
    let retry = cli(&fixture, &execute)?;
    successful(&retry);
    assert_eq!(
        serde_json::from_slice::<Value>(&retry.stdout)?["created"],
        0
    );
    successful(&cli(
        &fixture,
        &[
            "readiness",
            "--spec",
            spec.to_str().ok_or("path")?,
            "--json",
        ],
    )?);
    Ok(())
}

#[test]
fn remote_administrator_rekeys_and_installs_without_copying_keys() -> TestResult {
    let fixture = fixture()?;
    let remote = fixture.temporary.path().join("remote admin 'quoted'");
    std::fs::create_dir(&remote)?;
    let (administrator, recipient) = nix_seal_crypto::generate_x25519();
    let identity = remote.join("administrator.agekey");
    write_private(&identity, administrator.expose_secret().as_bytes())?;
    let signing = remote.join("release.key");
    std::fs::rename(&fixture.signing_path, &signing)?;
    let mut plan: nix_seal_core::PlanV2 =
        serde_json::from_slice(&std::fs::read(&fixture.plan_path)?)?;
    let admin_id = nix_seal_core::Id::parse("administrator")?;
    plan.identities.insert(
        admin_id.clone(),
        nix_seal_core::Identity {
            kind: nix_seal_core::IdentityKind::Administrator,
            public: recipient.clone(),
        },
    );
    let secret = plan.secrets.values_mut().next().ok_or("secret")?;
    secret.delivery = nix_seal_core::DeliveryMode::Rekeyed;
    secret.administrators = vec![admin_id];
    let source = fixture.repository.join(&secret.source);
    let mut ciphertext = std::fs::File::create(&source)?;
    nix_seal_crypto::encrypt(b"remote-canary".as_slice(), &mut ciphertext, &[recipient])?;
    secret.source_ciphertext_hash = format!(
        "{:x}",
        base16ct::HexDisplay(&sha2::Sha256::digest(std::fs::read(source)?))
    );
    std::fs::write(&fixture.plan_path, nix_seal_policy::canonical_json(&plan)?)?;
    let deployment = deployment(&fixture)?;
    let bin = fixture.temporary.path().join("bin");
    std::fs::create_dir(&bin)?;
    let ssh = bin.join("ssh");
    // Execute the actual remote command via a POSIX shell, as SSH does. The
    // process uses a separate administrator cache and real generated keys.
    let remote_cache = remote.join("cache");
    let remote_cache = remote_cache
        .to_str()
        .ok_or("remote cache path")?
        .replace('\'', "'\\''");
    std::fs::write(
        &ssh,
        format!(
            "#!/bin/sh\nset -eu\ntest \"$1\" = --\ntest \"$2\" = admin.example\nexport XDG_CACHE_HOME='{remote_cache}'\nexec /bin/sh -c \"$3\"\n"
        ),
    )?;
    std::fs::set_permissions(&ssh, std::fs::Permissions::from_mode(0o700))?;
    let output = Command::new(env!("CARGO_BIN_EXE_nix-seal"))
        .args(["prepare", "--deployment"])
        .arg(deployment)
        .args([
            "--administrator-host",
            "admin.example",
            "--administrator-program",
            env!("CARGO_BIN_EXE_nix-seal"),
            "--identity",
        ])
        .arg(&identity)
        .arg("--signing-key")
        .arg(&signing)
        .args(["--execute", "--json"])
        .env(
            "PATH",
            format!("{}:{}", bin.display(), std::env::var("PATH")?),
        )
        .env(
            "XDG_CACHE_HOME",
            fixture.temporary.path().join("local-cache"),
        )
        .current_dir(&fixture.repository)
        .output()?;
    successful(&output);
    let response: Value = serde_json::from_slice(&output.stdout)?;
    assert_eq!(response["created"], 1);
    assert_eq!(response["installed"], true);
    assert!(!fixture.temporary.path().join("local-cache").exists());
    let records = nix_seal_cache::Cache::open(fixture.temporary.path().join("installed"))?
        .artifact_records()?;
    assert_eq!(records.len(), 1);
    assert!(identity.exists() && signing.exists());
    assert!(!String::from_utf8_lossy(&output.stdout).contains("remote-canary"));
    assert!(!String::from_utf8_lossy(&output.stderr).contains("remote-canary"));
    Ok(())
}

#[test]
fn batch_installation_routes_each_targets_artifacts_to_its_own_cache() -> TestResult {
    let fixture = fixture()?;
    let second = nix_seal_core::Id::parse("host.second")?;
    let mut plan: nix_seal_core::PlanV2 =
        serde_json::from_slice(&std::fs::read(&fixture.plan_path)?)?;
    plan.targets
        .insert(second.clone(), plan.targets[&fixture.target].clone());
    for secret in plan.secrets.values_mut() {
        secret.consumers.push(second.clone());
    }
    std::fs::write(&fixture.plan_path, nix_seal_policy::canonical_json(&plan)?)?;
    let path = deployment(&fixture)?;
    let mut description: Value = serde_json::from_slice(&std::fs::read(&path)?)?;
    let mut other = description["targets"][0].clone();
    let spec_path = fixture.temporary.path().join("second-spec.json");
    let second_cache = fixture.temporary.path().join("second-cache");
    let mut spec: Value = serde_json::from_slice(&std::fs::read(
        fixture.temporary.path().join("activation.json"),
    )?)?;
    spec["targetId"] = json!(second);
    spec["artifactCacheRoot"] = json!(second_cache);
    std::fs::write(&spec_path, serde_json::to_vec(&spec)?)?;
    other["target"] = json!(second);
    other["cacheRoot"] = json!(second_cache);
    other["specs"] = json!([spec_path]);
    description["targets"]
        .as_array_mut()
        .ok_or("target array")?
        .push(other);
    std::fs::write(&path, serde_json::to_vec(&description)?)?;
    let output = cli(
        &fixture,
        &[
            "prepare",
            "--deployment",
            path.to_str().ok_or("path")?,
            "--signing-key",
            fixture.signing_path.to_str().ok_or("path")?,
            "--execute",
            "--json",
        ],
    )?;
    successful(&output);
    for (cache, target) in [
        (fixture.temporary.path().join("installed"), fixture.target),
        (second_cache, second),
    ] {
        let records = nix_seal_cache::Cache::open(cache)?.artifact_records()?;
        assert_eq!(records.len(), 1);
        let envelope = serde_json::from_slice(&records[0].envelope)?;
        assert_eq!(
            nix_seal_manifest::inspect_unverified(&envelope)?.target_id,
            target
        );
    }
    Ok(())
}
