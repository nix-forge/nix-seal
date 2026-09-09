//! Public artifact readiness uses the same selection and verification as activation.
use anyhow::{Result, bail};
use nix_seal_core::{ActivationPhase, Id, PlanV2};
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::Write as _,
    path::{Path, PathBuf},
};

#[derive(clap::Args)]
pub(super) struct Args {
    /// Generated activation specifications. Repeat to check every phase or target.
    #[arg(long, required = true)]
    pub spec: Vec<PathBuf>,
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MissingArtifact {
    pub secret_id: Id,
    /// Candidate metadata is diagnostic only; it never authorizes an artifact.
    pub reasons: BTreeSet<String>,
}

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Report {
    pub target: Id,
    pub phase: ActivationPhase,
    pub cache_root: PathBuf,
    pub required: usize,
    pub verified: usize,
    pub missing: Vec<MissingArtifact>,
}

impl Report {
    pub fn is_ready(&self) -> bool {
        self.missing.is_empty()
    }

    pub fn failure_message(&self) -> String {
        let mut message = format!(
            "target-local cache lacks verified artifacts for target {} ({:?}): {}/{} ready\ncache: {}",
            self.target,
            self.phase,
            self.verified,
            self.required,
            self.cache_root.display()
        );
        for missing in &self.missing {
            let _ = write!(
                message,
                "\n  {}: {}",
                missing.secret_id,
                missing
                    .reasons
                    .iter()
                    .cloned()
                    .collect::<Vec<_>>()
                    .join("; ")
            );
        }
        message.push_str("\nPrepare this configuration with nix-seal prepare on the administrator machine, install its signed ciphertext, then retry the switch. Keep earlier cache generations for rollback.");
        message
    }
}

pub(super) struct Inspection {
    pub report: Report,
    pub selected: BTreeMap<Id, super::DiscoveredActivationArtifact>,
}

pub(super) fn now() -> Result<u64> {
    Ok(std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs())
}

pub(super) fn plan_reports(plan: &PlanV2, cache: &Path) -> Result<Vec<Report>> {
    let mut reports = Vec::new();
    let now = now()?;
    for target in plan.targets.keys() {
        let policy = nix_seal_policy::target_policy(plan, target)?;
        for phase in [
            ActivationPhase::Partitioning,
            ActivationPhase::Users,
            ActivationPhase::Activation,
            ActivationPhase::Services,
        ] {
            if policy.secrets.values().any(|secret| secret.phase == phase) {
                reports.push(
                    super::inspect_activation_artifacts(cache, &policy, phase, now, 300)?.report,
                );
            }
        }
    }
    Ok(reports)
}

pub(super) fn read_spec(path: &Path) -> Result<nix_seal_runtime::ActivationSpecV2> {
    let mut spec: nix_seal_runtime::ActivationSpecV2 = super::read_json_bounded(path)?;
    // Standalone Home Manager supplies %t and resolves it at activation. Readiness
    // validates its shape without requiring a login session or touching runtime state.
    if let Ok(suffix) = spec.runtime_root.strip_prefix("%t") {
        #[cfg(unix)]
        {
            spec.runtime_root = PathBuf::from("/run/user")
                .join(rustix::process::geteuid().as_raw().to_string())
                .join(suffix);
        }
    }
    spec.validate()?;
    Ok(spec)
}

pub(super) fn spec_report(path: &Path) -> Result<Report> {
    spec_report_in_cache(path, None)
}

pub(super) fn spec_report_in_cache(path: &Path, cache: Option<&Path>) -> Result<Report> {
    let spec = read_spec(path)?;
    let plan = super::read_plan_bounded(&spec.plan)?;
    let policy = nix_seal_policy::target_policy(&plan, &spec.target_id)?;
    super::verify_activation_projection(&spec, &policy)?;
    Ok(super::inspect_activation_artifacts(
        cache.unwrap_or(&spec.artifact_cache_root),
        &policy,
        spec.phase,
        now()?,
        spec.allowed_clock_skew,
    )?
    .report)
}

pub(super) fn run(arguments: &Args, json: bool) -> Result<()> {
    let mut reports = Vec::new();
    let mut errors = Vec::new();
    for spec in &arguments.spec {
        match spec_report(spec) {
            Ok(report) => reports.push(report),
            Err(error) => errors.push(format!("{}: {error:#}", spec.display())),
        }
    }
    let ready = errors.is_empty() && reports.iter().all(Report::is_ready);
    if json {
        println!(
            "{}",
            serde_json::json!({"schema":"nix-seal.readiness.v1", "ready":ready,
            "artifacts":reports, "errors":errors})
        );
    } else {
        for report in &reports {
            if report.is_ready() {
                println!(
                    "{}: {}/{} {:?} artifacts ready",
                    report.target, report.verified, report.required, report.phase
                );
            } else {
                eprintln!("{}", report.failure_message());
            }
        }
        for error in errors {
            eprintln!("{error}");
        }
    }
    if !ready {
        bail!("artifact readiness failed; activation was not attempted");
    }
    Ok(())
}
