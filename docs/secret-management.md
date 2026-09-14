# Secret management policy

This policy covers local development, GitHub Actions, release automation,
test fixtures, and documentation. No repository workflow may require a
long-lived secret to validate pull-request code.

## Storage and handling

Private keys, plaintext secrets, credentials, and deployment state stay in the
operator's protected secret store. They must not be committed, placed in the
Nix store, passed in command-line arguments, included in fixtures or artifacts,
or printed in logs. Pull-request and fork workflows receive no repository
secrets. Tests use disposable public fixtures or generated values.

The release workflow uses a protected `release` environment and short-lived
GitHub OIDC build attestations rather than a long-lived signing or cloud key.
Actions receive only the job permissions they need and checkout does not retain
credentials.

## Access, rotation, and response

Maintainers review access to Actions secrets, environments, Pages, and release
automation before granting it. Access is individual, least-privilege, and
removed when responsibility ends. Credentials have an owner, purpose, and
review date; rotate them at least annually and immediately after suspected
exposure, maintainer change, provider change, or trust-boundary change.

Suspected exposure triggers revocation, replacement, log and artifact review,
and a private report through [SECURITY.md](../SECURITY.md). `security/vex.json`
contains no secret values or private incident details.
