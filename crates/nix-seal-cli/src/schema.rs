use anyhow::Result;
use clap::ValueEnum;

#[derive(Clone, Copy, ValueEnum)]
pub(super) enum SchemaKind {
    Plan,
    TargetPolicy,
    SecretArtifactPolicy,
    SecretRecipients,
    Activation,
    Collection,
}

pub(super) fn run_schema(kind: SchemaKind) -> Result<()> {
    println!(
        "{}",
        match kind {
            SchemaKind::Plan => nix_seal_policy::json_schema()?,
            SchemaKind::TargetPolicy => nix_seal_policy::target_policy_json_schema()?,
            SchemaKind::SecretArtifactPolicy => {
                nix_seal_policy::secret_artifact_policy_json_schema()?
            }
            SchemaKind::SecretRecipients => nix_seal_policy::secret_recipients_json_schema()?,
            SchemaKind::Activation => nix_seal_runtime::activation_json_schema()?,
            SchemaKind::Collection =>
                include_str!("../../../schemas/collection-v1.schema.json").to_owned(),
        }
    );
    Ok(())
}
