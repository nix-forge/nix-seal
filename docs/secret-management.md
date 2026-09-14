# Secret management policy

This policy covers repository administration, GitHub Actions, release
automation, local development, and the nix-seal test and deployment boundary.
The repository must remain useful to fork and review without exposing a
maintainer or consumer secret.

## Storage and handling

Secrets are stored only in the consumer's configured secret backend or in
GitHub's protected repository or environment secret stores when automation
actually requires them. They must never be committed, placed in a Nix store,
passed as command-line arguments, written to ordinary environment dumps, or
printed in logs, artifacts, test fixtures, issues, or pull requests.

Pull-request workflows, including fork workflows, receive no repository
secrets. Release workflows use short-lived GitHub OIDC credentials where the
provider supports it; long-lived cloud keys are not used as a replacement.
The release workflow's permissions and environment boundary are reviewed with
each release change.

## Access and review

Repository administrators review Actions secrets, environments, Pages, and
release access before granting it. Access begins at the narrowest role needed,
is removed when responsibility ends, and is not shared between people. The
maintainer reviews secret names, environment protection, and workflow usage
before enabling a new secret.

## Rotation and incident response

Secrets are rotated at least annually and immediately when a maintainer,
provider, workflow trust boundary, or authorization scope changes. Suspected
exposure triggers immediate revocation, replacement, log and artifact review,
and a private vulnerability report or incident record. A rotation must not
publish the old value or embed the replacement in repository history.

The repository's encrypted data and key-handling design is documented in the
threat model. `security/vex.json` records only reviewed non-affectability
statements and never contains secret values.
