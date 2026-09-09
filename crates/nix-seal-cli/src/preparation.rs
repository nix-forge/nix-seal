//! Explicit preparation; only canonical ciphertext and signed artifacts cross SSH.
use anyhow::{Context, Result, bail};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use nix_seal_core::{ActivationPhase, Id, PlanV2};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
};

const WIRE_LIMIT: u64 = 128 * 1024 * 1024;
const ENTRY_LIMIT: usize = 10_000;
const PHASES: [ActivationPhase; 4] = [
    ActivationPhase::Partitioning,
    ActivationPhase::Users,
    ActivationPhase::Activation,
    ActivationPhase::Services,
];

#[derive(clap::Args)]
pub(super) struct Args {
    /// Nix configuration selector, e.g. .#nixosConfigurations.workstation.
    #[arg(
        long,
        required_unless_present = "deployment",
        conflicts_with = "deployment"
    )]
    flake: Option<String>,
    /// Generated nixSeal.deploymentFile, or a built system containing nix-seal-deployment.json.
    #[arg(long, required_unless_present = "flake")]
    deployment: Option<PathBuf>,
    /// Checkout containing the canonical ciphertext referenced by the plans.
    #[arg(long, default_value = ".")]
    repository_root: PathBuf,
    /// SSH destination that holds the administrator and signing keys.
    #[arg(long)]
    administrator_host: Option<String>,
    /// nix-seal executable on the administrator host. Must support this protocol.
    #[arg(long, default_value = "nix-seal")]
    administrator_program: String,
    /// Administrator identity path, on the administrator host when using SSH.
    #[arg(long)]
    identity: Option<PathBuf>,
    /// Approval key path, on the administrator host when using SSH.
    #[arg(long)]
    signing_key: PathBuf,
    /// Override the automatic timestamp generation for newly prepared artifacts.
    #[arg(long)]
    generation: Option<u64>,
    /// Write missing artifacts and install them in the declared target caches.
    #[arg(long)]
    execute: bool,
}

#[derive(clap::Args)]
pub(super) struct WorkerArgs {
    #[arg(long)]
    identity: Option<PathBuf>,
    #[arg(long)]
    signing_key: PathBuf,
    #[arg(long)]
    generation: Option<u64>,
    #[arg(long)]
    execute: bool,
}

#[derive(clap::Args)]
pub(super) struct InstallArgs {
    #[arg(long)]
    root: PathBuf,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Deployment {
    schema: String,
    targets: Vec<Destination>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Destination {
    target: Id,
    plan: PathBuf,
    cache_root: PathBuf,
    /// Null means the system's root-owned cache.
    user: Option<String>,
    specs: Vec<PathBuf>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Request {
    schema: String,
    targets: Vec<TargetRequest>,
    /// Canonical relative names only; values are base64 ciphertext.
    sources: BTreeMap<String, String>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct TargetRequest {
    target: Id,
    plan: PlanV2,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Bundle {
    schema: String,
    artifacts: Vec<Artifact>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Artifact {
    ciphertext: String,
    envelope: String,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct Response {
    schema: String,
    prepared: bool,
    reused: usize,
    created: usize,
    bundle: Bundle,
}

fn decode<T: serde::de::DeserializeOwned>(reader: impl Read) -> Result<T> {
    let mut bytes = Vec::new();
    reader.take(WIRE_LIMIT + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > WIRE_LIMIT {
        bail!("preparation exchange exceeds 128 MiB");
    }
    serde_json::from_slice(&bytes)
        .context("invalid preparation exchange; both machines need a compatible nix-seal")
}

fn invoke(command: &mut Command, input: &[u8]) -> Result<Vec<u8>> {
    if input.len() as u64 > WIRE_LIMIT {
        bail!("preparation exchange exceeds 128 MiB");
    }
    // Preserve login/SSH discovery and cache location, not arbitrary application credentials.
    command.env_clear();
    for name in [
        "PATH",
        "HOME",
        "USER",
        "LOGNAME",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "TERM",
        "SSH_AUTH_SOCK",
        "XDG_CACHE_HOME",
        "XDG_RUNTIME_DIR",
        "TMPDIR",
    ] {
        if let Some(value) = std::env::var_os(name) {
            command.env(name, value);
        }
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let mut stdin = child.stdin.take().context("missing child stdin")?;
    let stdout = child.stdout.take().context("missing child stdout")?;
    let input = input.to_owned();
    let (sender, receiver) = std::sync::mpsc::channel();
    let writer_sender = sender.clone();
    std::thread::spawn(move || {
        let result = stdin
            .write_all(&input)
            .map(|()| None)
            .map_err(anyhow::Error::from);
        drop(stdin);
        let _ = writer_sender.send(result);
    });
    std::thread::spawn(move || {
        let result = (|| {
            let mut output = Vec::new();
            stdout.take(WIRE_LIMIT + 1).read_to_end(&mut output)?;
            if output.len() as u64 > WIRE_LIMIT {
                bail!("preparation response exceeds 128 MiB");
            }
            Ok(Some(output))
        })();
        let _ = sender.send(result);
    });
    let deadline = std::time::Instant::now() + std::time::Duration::from_mins(5);
    let result = (|| {
        let mut output = Vec::new();
        for _ in 0..2 {
            if let Some(bytes) = receiver
                .recv_timeout(deadline.saturating_duration_since(std::time::Instant::now()))
                .context("preparation subprocess exceeded the five-minute deadline")??
            {
                output = bytes;
            }
        }
        loop {
            if let Some(status) = child.try_wait()? {
                if !status.success() {
                    bail!("preparation subprocess failed; target activation was not attempted");
                }
                return Ok(output);
            }
            if std::time::Instant::now() >= deadline {
                bail!("preparation subprocess exceeded the five-minute deadline");
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }

    result
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn resolve_deployment(arguments: &Args) -> Result<PathBuf> {
    if let Some(path) = &arguments.deployment {
        return Ok(if path.is_dir() {
            path.join("nix-seal-deployment.json")
        } else {
            path.clone()
        });
    }
    let selector = arguments
        .flake
        .as_ref()
        .context("missing configuration selector")?;
    if !selector.contains('#') {
        bail!("select a configuration, for example --flake .#nixosConfigurations.workstation");
    }
    let output = Command::new("nix")
        .args(["build", "--no-link", "--print-out-paths", "--"])
        .arg(format!("{selector}.config.nixSeal.deploymentFile"))
        .stderr(Stdio::inherit())
        .output()
        .context("could not evaluate the deployment description with Nix")?;
    if !output.status.success() {
        bail!("could not build nixSeal.deploymentFile for the selected configuration");
    }
    let path = String::from_utf8(output.stdout)?;
    let paths: Vec<_> = path.lines().collect();
    if paths.len() != 1 || !Path::new(paths[0]).is_absolute() {
        bail!("Nix did not return one deployment description");
    }
    Ok(PathBuf::from(paths[0]))
}

fn make_request(deployment: &Deployment, root: &Path) -> Result<Request> {
    if deployment.schema != "nix-seal.deployment.v1" || deployment.targets.len() > ENTRY_LIMIT {
        bail!("unsupported or oversized deployment description");
    }
    let mut targets = Vec::new();
    let mut sources = BTreeMap::new();
    let mut seen = BTreeSet::new();
    let mut total = 0_u64;
    for destination in &deployment.targets {
        if !seen.insert(destination.target.clone()) {
            bail!("duplicate deployment target {}", destination.target);
        }
        if !destination.cache_root.is_absolute() {
            bail!("target cache root must be absolute");
        }
        let plan = super::read_plan_bounded(&destination.plan)?;
        let policy = nix_seal_policy::target_policy(&plan, &destination.target)?;
        for spec in &destination.specs {
            let spec = super::readiness::read_spec(spec)?;
            if spec.target_id != destination.target
                || spec.plan != destination.plan
                || spec.artifact_cache_root != destination.cache_root
            {
                bail!("deployment destination does not match its activation specification");
            }
            super::verify_activation_projection(&spec, &policy)?;
        }
        for secret in policy.secrets.values() {
            if sources.contains_key(&secret.source) {
                continue;
            }
            let path = super::existing_secret_path(root, &secret.source)?;
            if super::canonical_ciphertext_hash(root, &secret.source)?
                != secret.source_ciphertext_hash
            {
                bail!(
                    "canonical ciphertext changed; reevaluate the configuration before preparation"
                );
            }
            let mut bytes = Vec::new();
            super::open_public_ciphertext(&path)?
                .take(70 * 1024 * 1024 + 1)
                .read_to_end(&mut bytes)?;
            total += bytes.len() as u64;
            if total > 70 * 1024 * 1024 {
                bail!("preparation sources exceed 70 MiB");
            }
            sources.insert(secret.source.clone(), STANDARD.encode(bytes));
        }
        targets.push(TargetRequest {
            target: destination.target.clone(),
            plan,
        });
    }
    Ok(Request {
        schema: "nix-seal.prepare-request.v1".to_owned(),
        targets,
        sources,
    })
}

fn materialize_sources(request: &Request, root: &Path) -> Result<()> {
    if request.schema != "nix-seal.prepare-request.v1"
        || request.targets.len() > ENTRY_LIMIT
        || request.sources.len() > ENTRY_LIMIT
    {
        bail!("unsupported or oversized preparation request");
    }
    let mut required = BTreeSet::new();
    let mut seen_targets = BTreeSet::new();
    let mut projected_response_size = 0_usize;
    for target in &request.targets {
        if !seen_targets.insert(&target.target) {
            bail!("duplicate target in preparation request");
        }
        nix_seal_policy::validate(&target.plan)?;
        super::validate_plan_identity_material(&target.plan)?;
        let policy = nix_seal_policy::target_policy(&target.plan, &target.target)?;
        for secret in policy.secrets.values() {
            let source = request
                .sources
                .get(&secret.source)
                .context("missing canonical source")?;
            projected_response_size = projected_response_size
                .checked_add(source.len())
                .and_then(|size| size.checked_add(16 * 1024))
                .context("preparation size overflow")?;
            if projected_response_size as u64 > WIRE_LIMIT - 16 * 1024 * 1024 {
                bail!(
                    "prepared batch would exceed the exchange limit; prepare fewer targets or use provision and cache export/import"
                );
            }
        }
        required.extend(policy.secrets.values().map(|secret| secret.source.clone()));
    }
    if required != request.sources.keys().cloned().collect() {
        bail!("preparation request sources must exactly match target policies");
    }
    let mut total = 0_usize;
    for (name, encoded) in &request.sources {
        if name.is_empty()
            || !Path::new(name)
                .components()
                .all(|component| matches!(component, Component::Normal(_)))
        {
            bail!("preparation sources must use relative paths without traversal");
        }
        let bytes = STANDARD.decode(encoded)?;
        total = total
            .checked_add(bytes.len())
            .context("source size overflow")?;
        if total > 70 * 1024 * 1024 {
            bail!("preparation sources exceed 70 MiB");
        }
        let path = root.join(name);
        std::fs::create_dir_all(path.parent().context("source has no parent")?)?;
        super::write_private_bytes(&path, &bytes)?;
    }
    Ok(())
}

fn inspect_all(
    cache: &Path,
    target: &TargetRequest,
) -> Result<BTreeMap<Id, super::DiscoveredActivationArtifact>> {
    let policy = nix_seal_policy::target_policy(&target.plan, &target.target)?;
    let mut selected = BTreeMap::new();
    for phase in PHASES {
        selected.extend(
            super::inspect_activation_artifacts(
                cache,
                &policy,
                phase,
                super::readiness::now()?,
                300,
            )?
            .selected,
        );
    }
    Ok(selected)
}

fn prepare_request(
    request: &Request,
    arguments: &WorkerArgs,
    cache_root: &Path,
) -> Result<Response> {
    let temporary = tempfile::tempdir()?;
    materialize_sources(request, temporary.path())?;
    let signer = super::read_signing_key(&arguments.signing_key)?;
    let identity = arguments
        .identity
        .as_deref()
        .map(super::read_identity)
        .transpose()?;
    let now = super::readiness::now()?;
    // Validate the complete batch before writing any persistent cache entry.
    for target in &request.targets {
        let policy = nix_seal_policy::target_policy(&target.plan, &target.target)?;
        let selected = inspect_all(cache_root, target)?;
        for (id, secret) in &policy.secrets {
            if selected.contains_key(id) {
                continue;
            }
            super::ensure_signing_key_authorized(secret, &signer, id)?;
            if secret.approval.threshold > 1 {
                bail!(
                    "target {} needs multiple approvals; use provision and artifact approve before retrying preparation",
                    target.target
                );
            }
            if matches!(secret.delivery, nix_seal_core::DeliveryMode::Rekeyed) {
                super::ensure_rekey_identity_authorized(&target.plan, id, identity.as_ref())?;
            }
            let path = super::existing_secret_path(temporary.path(), &secret.source)?;
            nix_seal_crypto::validate_ciphertext_header(super::open_public_ciphertext(&path)?)?;
            if super::canonical_ciphertext_hash(temporary.path(), &secret.source)?
                != secret.source_ciphertext_hash
            {
                bail!("canonical ciphertext does not match the approved plan for {id}");
            }
        }
    }
    let mut response = Response {
        schema: "nix-seal.prepare-response.v1".to_owned(),
        prepared: arguments.execute,
        reused: 0,
        created: 0,
        bundle: Bundle {
            schema: "nix-seal.prepared-artifacts.v1".to_owned(),
            artifacts: Vec::new(),
        },
    };
    for target in &request.targets {
        let policy = nix_seal_policy::target_policy(&target.plan, &target.target)?;
        let selected = inspect_all(cache_root, target)?;
        response.reused += selected.len();
        if arguments.execute {
            let cache = nix_seal_cache::Cache::open(cache_root)?;
            let max_existing = selected
                .values()
                .map(|artifact| artifact.generation)
                .max()
                .unwrap_or(0);
            let generation = arguments.generation.unwrap_or(
                now.max(
                    max_existing
                        .checked_add(1)
                        .context("artifact generation exhausted")?,
                ),
            );
            let policy_hash = nix_seal_policy::target_policy_hash(&policy)?;
            for (id, secret) in &policy.secrets {
                if selected.contains_key(id) {
                    continue;
                }
                super::create_target_artifact(
                    &cache,
                    &policy,
                    &policy_hash,
                    secret,
                    temporary.path(),
                    &target.target,
                    id,
                    identity.as_ref(),
                    generation,
                    now,
                    None,
                    &signer,
                )?;
                response.created += 1;
            }
            let selected = inspect_all(cache_root, target)?;
            if selected.len() != policy.secrets.len() {
                bail!(
                    "prepared artifact verification failed for {}",
                    target.target
                );
            }
            append_artifacts(&mut response.bundle, selected.values())?;
        }
    }
    Ok(response)
}

fn append_artifacts<'a>(
    bundle: &mut Bundle,
    selected: impl Iterator<Item = &'a super::DiscoveredActivationArtifact>,
) -> Result<()> {
    let mut size: u64 = bundle
        .artifacts
        .iter()
        .map(|artifact| (artifact.ciphertext.len() + artifact.envelope.len() + 128) as u64)
        .sum();
    for artifact in selected {
        let bytes = std::fs::metadata(&artifact.ciphertext)?.len()
            + std::fs::metadata(&artifact.envelope)?.len();
        let encoded_bound = bytes
            .checked_mul(2)
            .and_then(|size| size.checked_add(128))
            .context("artifact size overflow")?;
        if size
            .checked_add(encoded_bound)
            .is_none_or(|size| size > WIRE_LIMIT - 1024)
        {
            bail!(
                "prepared response exceeds the exchange limit; use provision and cache export/import"
            );
        }
        let artifact = Artifact {
            ciphertext: STANDARD.encode(std::fs::read(&artifact.ciphertext)?),
            envelope: STANDARD.encode(std::fs::read(&artifact.envelope)?),
        };
        size += (artifact.ciphertext.len() + artifact.envelope.len() + 128) as u64;
        bundle.artifacts.push(artifact);
    }
    Ok(())
}

fn stage_bundle(bundle: &Bundle, root: &Path) -> Result<()> {
    if bundle.schema != "nix-seal.prepared-artifacts.v1" || bundle.artifacts.len() > ENTRY_LIMIT {
        bail!("unsupported or oversized prepared artifact bundle");
    }
    let cache = nix_seal_cache::Cache::open(root)?;
    for artifact in &bundle.artifacts {
        let envelope = STANDARD.decode(&artifact.envelope)?;
        let signed = serde_json::from_slice(&envelope)?;
        let manifest = nix_seal_manifest::inspect_unverified(&signed)?;
        let address = nix_seal_cache::ArtifactAddress::new(
            &manifest.plan_hash,
            &manifest.target_policy_hash,
            &manifest.source_ciphertext_hash,
            &manifest.recipient_fingerprint,
            manifest.target_id.as_str(),
            manifest.secret_id.as_str(),
            manifest.artifact_generation,
        )?;
        let ciphertext = STANDARD.decode(&artifact.ciphertext)?;
        cache.put_artifact(&address, ciphertext.as_slice(), &envelope)?;
    }
    Ok(())
}

pub(super) fn worker(arguments: &WorkerArgs) -> Result<()> {
    let request: Request = decode(std::io::stdin().lock())?;
    let response = prepare_request(&request, arguments, &super::default_cache_root())?;
    serde_json::to_writer(std::io::stdout().lock(), &response)?;
    Ok(())
}

pub(super) fn install(arguments: &InstallArgs) -> Result<()> {
    let bundle: Bundle = decode(std::io::stdin().lock())?;
    let staging = tempfile::tempdir()?;
    let root = staging.path().join("cache");
    stage_bundle(&bundle, &root)?;
    nix_seal_cache::Cache::open(&arguments.root)?.import_from(&root)?;
    Ok(())
}

fn worker_arguments(arguments: &Args) -> Result<Vec<String>> {
    let mut values = vec![
        "__prepare-worker".to_owned(),
        "--signing-key".to_owned(),
        arguments
            .signing_key
            .to_str()
            .context("key path must be UTF-8")?
            .to_owned(),
    ];
    if let Some(identity) = &arguments.identity {
        values.extend([
            "--identity".to_owned(),
            identity
                .to_str()
                .context("identity path must be UTF-8")?
                .to_owned(),
        ]);
    }
    if let Some(generation) = arguments.generation {
        values.extend(["--generation".to_owned(), generation.to_string()]);
    }
    if arguments.execute {
        values.push("--execute".to_owned());
    }
    Ok(values)
}

fn as_owner(user: Option<&str>) -> Result<Command> {
    let executable = std::env::current_exe()?;
    #[cfg(unix)]
    {
        let desired = user.unwrap_or("root");
        let current = uzers::get_user_by_uid(rustix::process::geteuid().as_raw());
        if current
            .as_ref()
            .is_some_and(|current| current.name() == std::ffi::OsStr::new(desired))
        {
            return Ok(Command::new(executable));
        }
        if desired.is_empty() || desired.starts_with('-') || desired.contains(['\n', '\r', '\0']) {
            bail!("invalid cache owner");
        }
        let mut command = Command::new("sudo");
        command.args(["--user", desired, "--"]).arg(executable);
        Ok(command)
    }
    #[cfg(not(unix))]
    {
        let _ = user;
        Ok(Command::new(executable))
    }
}

fn install_response(deployment: &Deployment, request: &Request, response: &Response) -> Result<()> {
    let temporary = tempfile::tempdir()?;
    let staging = temporary.path().join("cache");
    stage_bundle(&response.bundle, &staging)?;
    // Independently verify every destination before the first privileged import.
    for target in &request.targets {
        let required = nix_seal_policy::target_policy(&target.plan, &target.target)?
            .secrets
            .len();
        if inspect_all(&staging, target)?.len() != required {
            bail!(
                "administrator response lacks required verified artifacts for {}",
                target.target
            );
        }
    }
    for destination in &deployment.targets {
        for spec in &destination.specs {
            let report = super::readiness::spec_report_in_cache(spec, Some(&staging))?;
            if !report.is_ready() {
                bail!("{}", report.failure_message());
            }
        }
    }
    for (destination, target) in deployment.targets.iter().zip(&request.targets) {
        let selected = inspect_all(&staging, target)?;
        let mut target_bundle = Bundle {
            schema: "nix-seal.prepared-artifacts.v1".to_owned(),
            artifacts: Vec::new(),
        };
        append_artifacts(&mut target_bundle, selected.values())?;
        let bundle = serde_json::to_vec(&target_bundle)?;
        invoke(as_owner(destination.user.as_deref())?.arg("__install-prepared").arg("--root").arg(&destination.cache_root), &bundle)
            .with_context(|| format!("could not install {}; preparation is retained on the administrator machine, rerun the same command to retry", destination.target))?;
    }
    let mut failures = Vec::new();
    for destination in &deployment.targets {
        if destination.specs.is_empty() {
            continue;
        }
        let mut command = as_owner(destination.user.as_deref())?;
        command.args(["readiness", "--json"]);
        for spec in &destination.specs {
            command.arg("--spec").arg(spec);
        }
        if let Err(error) = invoke(&mut command, &[]) {
            failures.push(format!("{}: {error:#}", destination.target));
        }
    }
    if !failures.is_empty() {
        bail!("installed cache readiness failed:\n{}", failures.join("\n"));
    }
    Ok(())
}

pub(super) fn run(arguments: &Args, json: bool) -> Result<()> {
    let path = resolve_deployment(arguments)?;
    let deployment: Deployment = super::read_json_bounded(&path)?;
    let request = make_request(&deployment, &arguments.repository_root)?;
    let response = if let Some(host) = &arguments.administrator_host {
        if host.is_empty() || host.starts_with('-') || host.contains(['\n', '\r', '\0']) {
            bail!("invalid administrator SSH destination");
        }
        let mut words = vec![arguments.administrator_program.clone()];
        words.extend(worker_arguments(arguments)?);
        let remote = words
            .iter()
            .map(|word| shell_quote(word))
            .collect::<Vec<_>>()
            .join(" ");
        let output = invoke(
            Command::new("ssh").args(["--", host, &remote]),
            &serde_json::to_vec(&request)?,
        )?;
        decode(output.as_slice())?
    } else {
        prepare_request(
            &request,
            &WorkerArgs {
                identity: arguments.identity.clone(),
                signing_key: arguments.signing_key.clone(),
                generation: arguments.generation,
                execute: arguments.execute,
            },
            &super::default_cache_root(),
        )?
    };
    if response.schema != "nix-seal.prepare-response.v1" || response.prepared != arguments.execute {
        bail!("administrator returned an incompatible preparation response");
    }
    if arguments.execute {
        install_response(&deployment, &request, &response)?;
    }
    if json {
        println!(
            "{}",
            serde_json::json!({"schema":"nix-seal.prepare.v1", "prepared":response.prepared,
            "installed":arguments.execute, "activated":false, "reused":response.reused, "created":response.created,
            "targets":deployment.targets.iter().map(|target| &target.target).collect::<Vec<_>>()})
        );
    } else if arguments.execute {
        println!(
            "Prepared and installed {} target(s): {} artifacts reused, {} created. Destination readiness passed. Activation has not run; retry your normal switch command.",
            deployment.targets.len(),
            response.reused,
            response.created
        );
    } else {
        println!(
            "Preparation dry run passed for {} target(s); {} existing artifacts can be reused. Rerun with --execute to prepare and install. Activation has not run.",
            deployment.targets.len(),
            response.reused
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests;
