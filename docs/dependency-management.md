# Dependency management policy

This policy applies to the Rust workspace, Nix inputs, GitHub Actions, and
release tooling maintained in nix-seal. Dependency changes are part of the
security review for the project, not routine metadata-only changes.

## Inventory and provenance

The authoritative dependency records are `Cargo.lock`, `flake.lock`, the
Cargo manifests, and the pinned action references in `.github/workflows/`.
Cargo registry and Git sources, Nix flake inputs, and action commits are
reviewed as separate trust boundaries. A dependency update must identify the
new version or commit, its source, and any changed transitive dependencies.

Dependabot keeps supported ecosystems current and opens reviewable updates.
The CI dependency-review, `cargo audit`, `cargo deny`, and `cargo vet` jobs
provide overlapping checks for known vulnerabilities, license policy, and
reviewed Rust provenance. The Nix flake check validates the Nix dependency
surface.

## Selection and review

Maintainers review updates for upstream provenance, maintenance status,
security advisories, licensing, MSRV compatibility, and behavior changes.
Action updates use immutable commit SHAs. Lockfiles and source hashes are
updated together with their manifests or package expressions; generated
changes are inspected rather than accepted blindly.

## Release gate and exceptions

Before a release, all applicable dependency-review, audit, deny, vet, CodeQL,
and test checks must pass. A high- or critical-severity finding, an
unreviewed license violation, or a failed provenance check blocks release.
The only exception is a reviewed, time-bounded record in the pull request and
release notes that names the component, explains why it is not exploitable in
this project, identifies an owner, and gives a remediation date. The
`security/vex.json` file records non-affectability statements in OpenVEX form;
it is not a substitute for fixing an affectable dependency.

## Update and rollback

Updates are tested on the supported Rust and Nix platforms before merge. A
regression is rolled back by reverting the reviewed lockfile and manifest
change, then a follow-up issue records the safer update path. Emergency
security updates may use the smallest safe version change and are still
reviewed and recorded after deployment.
