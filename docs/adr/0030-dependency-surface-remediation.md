# ADR 0030: Remove unsupported recipient dependencies before crypto migration

Status: accepted for implementation; release requires the normal security gates

Published age 0.12.1 pulls affected `crypto-bigint` through its native tagged
recipient implementations. nix-seal accepts X25519, plugins and OpenSSH Ed25519,
with RSA confined to explicit offline migration; it does not expose native
`tag` or `tagpq`. The existing released graph cannot upgrade that arithmetic
through a compatible lockfile-only change.

Vendor the published age archive and remove only those two recipient modules,
their recipient-file branches, their exports and their direct dependencies.
Keep every supported cryptographic implementation unchanged. Record archive
provenance and every file hash; CI checks the complete retained inventory and
both workspace lockfiles. Exclude this dependency from the application workspace
and formatting so upstream development features cannot reintroduce P-256.

An unreleased upstream age migration also replaces many arithmetic and cipher
dependencies. Removing the unused surface is a smaller review boundary and
avoids accepting that migration before its full source and compatibility review.
The local patch adds maintenance responsibility; replace it after a supported
upstream release passes the same checks. See [vendor provenance](../../vendor/README.md).

Independently pin i18n-config to upstream's merged parser replacement commit
`2ce7b1dfe9a8cc224288bf50cbc2a67a6de863c4`. Keep released localization consumers
and the already reviewed maintained TOML parser. Review its Git-qualified
cargo-vet delta and Nix source hash. Tests exercise age-shaped configuration,
Cargo metadata and malformed input through the real parser APIs.

No new advisory ignore or bootstrap exemption is added. The separate RSA timing
advisory is isolated by [ADR 0031](0031-isolated-rsa-migration-build.md), preserving
ADR 0009's compatibility and constraints without enabling RSA in normal builds.
Root and independent fuzz workspaces must resolve the same patches. Rollback
restores the previous release blocker; ciphertext formats do not change.
