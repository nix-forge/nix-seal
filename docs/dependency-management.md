# Dependency management policy

This policy covers Rust crates, Nix inputs, release tooling, GitHub Actions,
and the test and documentation tools used by `nix-seal`. Dependency changes
are part of the project's security and compatibility review.

## Inventory and provenance

The authoritative dependency records are `Cargo.lock`, `flake.lock`, the
committed Rust toolchain, `supply-chain/config.toml`, package source hashes,
and immutable action references in `.github/workflows/`. A change records the
upstream source, revision, license, and material transitive or generated
changes. Release inputs are rebuilt from the reviewed lockfiles.

## Automated evaluation

Pull requests and merge groups run dependency review, `cargo audit`,
`cargo deny`, `cargo vet`, OSV scanning for supported lockfiles, CodeQL, and
the repository test suite. The required status checks block the protected
branch. A scanner or dependency-review failure is a release blocker; it is not
silently converted into a warning.

## Remediation and exceptions

Known exploited vulnerabilities, high or critical findings, malicious
dependencies, and prohibited licenses must be fixed before release. Lower
severity findings are also fixed before release unless a reviewed,
time-bounded record names the component, explains non-exploitability, assigns
an owner, and gives a remediation date. `security/vex.json` records only
reviewed non-affectability statements and never suppresses an affectable
finding.

Maintainers review provenance, maintenance status, advisories, licensing,
reproducibility, and platform support. Emergency updates use the smallest safe
change and receive normal review retrospectively when immediate action is
required. A regression is rolled back by reverting the lockfile or source
declaration and tracking the follow-up issue.
