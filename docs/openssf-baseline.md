# OpenSSF baseline policy

This repository uses the [OSPS Baseline](https://baseline.openssf.org/versions/2026-08-28)
version 2026.08.28 as its security policy reference. The policy applies to the Rust CLI, Nix modules, release
artifacts, documentation, CI, and source history.

## Current assessed status

The [current self-assessment](https://www.bestpractices.dev/en/projects/14636/baseline-2)
records OSPS Baseline Level 2 for version 2026.08.28. The project does
**not** claim Level 3. OSPS-QA-07.01 at Level 3 requires every change to receive
approval from at least one human reviewer who did not author it. The project
currently has one maintainer, and the protected `main` branch requires zero
approving reviews. This control is **unmet** in the published assessment,
so the Baseline badge displays Level 2. A future Level 3 claim needs both the independent
review process and an evidence-backed assessment of all other Level 3 controls.

## Project scope and releases

nix-seal is a security-first secret manager for NixOS, nix-darwin, and Home
Manager. It is pre-1.0. A release may include source archives, platform
packages, checksums, an SBOM, and OIDC-backed provenance. The release assets
are built and attested by the pinned reusable builder described in
[docs/slsa.md](slsa.md). The gates and verification process are documented in
[docs/release.md](release.md). Release tags are immutable and follow the
repository's SemVer policy.

This repository is part of the related projects listed in the
[nix-forge project security contract](https://github.com/nix-forge/.github/blob/main/PROJECTS.md).
Related repositories enforce the same minimum security contract or a stricter
one for their own code and release surfaces.

## Change and build controls

Every commit must carry a matching Signed-off-by trailer. The DCO file defines
the certificate and .github/workflows/dco.yml checks proposed non-merge commits
on pull requests and merge-group refs.

All workflows start with empty default permissions. Each job grants only the
scopes it needs, checkout does not persist credentials, and third-party actions
use full commit SHAs. Pull requests and merge groups run the required checks
before protected main can advance. CI includes dependency review, CodeQL,
secret scanning, Scorecard, cargo audit, cargo deny, cargo vet, and the test
suite.

The normal evidence set is:

    cargo fmt --all -- --check
    cargo check --workspace --all-targets --all-features --locked
    cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
    cargo test --workspace --all-targets --all-features --locked
    cargo deny --locked check
    cargo vet --locked
    nix flake check

Major behavior changes include a regression test or an explicit test plan in
the pull request. Never put real secrets, private identities, or plaintext
test fixtures in commits or CI.

## Dependency and release controls

Cargo.lock, flake inputs, and the cargo-vet policy are reviewed with each
dependency change. The [dependency-management policy](dependency-management.md)
and [secret-management policy](secret-management.md) define the SCA,
remediation, storage, access, and rotation requirements. Dependency review
blocks new low-or-higher severity vulnerabilities. SCA and SAST findings must
be fixed before release unless a reviewed suppression records why the finding
is not exploitable.

The release workflow produces a unique tag, a change log entry, checksums, an
SBOM, and an OIDC attestation. Release documentation explains the actor and
workflow, public interfaces, security changes, artifact verification, and the
support window. The threat model is reviewed before a release that changes the
trust boundary or artifact process.

## Governance and vulnerability response

The maintainers listed in [GOVERNANCE.md](../GOVERNANCE.md) own repository
administration, Actions secrets, Pages, dependency policy, and releases.
Access to those resources is granted after review of contribution history and
intended responsibility. New maintainers start with the narrowest role needed.

Report vulnerabilities privately through [SECURITY.md](../SECURITY.md) or
GitHub private vulnerability reporting. The maintainer acknowledges a report
within three business days, provides an initial assessment within seven days,
and coordinates a public advisory after users have a fixed version or a
documented mitigation. [security/vex.json](../security/vex.json) records
non-affectability statements. Pre-1.0 support follows [SUPPORT.md](../SUPPORT.md).

## Control evidence

| Control area | Evidence |
| --- | --- |
| Least-privilege CI and trusted inputs | Empty default permissions, job scopes, pinned actions, quoted inputs, and no fork secrets |
| Releases and change logs | [docs/release.md](release.md), immutable tags, checksums, SBOM, and OIDC attestation |
| Dependencies | Cargo.lock, flake.lock, cargo-vet, cargo-deny, audit, and dependency review |
| Build and test instructions | [CONTRIBUTING.md](../CONTRIBUTING.md) and the CI workflow |
| Governance | [GOVERNANCE.md](../GOVERNANCE.md) |
| Contributor legal agreement | [DCO](../DCO) and .github/workflows/dco.yml |
| Security assessment | [THREAT_MODEL.md](../THREAT_MODEL.md) |
| Vulnerability response | [SECURITY.md](../SECURITY.md), private reporting, advisories, and [security/vex.json](../security/vex.json) |
| Release identity and integrity | Signed-off source history, checksums, SBOM, and OIDC provenance |
| Support lifecycle | [SUPPORT.md](../SUPPORT.md) and the release policy |

Review this file when cryptography, policy schemas, activation, dependencies,
CI trust, or release behavior changes.
