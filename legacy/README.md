# Opt-in offline RSA migration

This independent workspace builds `nix-seal-legacy` from the canonical CLI
source. It alone enables age's RSA implementation. Normal and fuzz workspaces
do not request that feature, including when built with `--all-features`.

Use `nix run .#nix-seal-legacy -- migrate ...` for an existing RSA source, keeping
the same migration arguments and explicit `--execute` acknowledgement. New
recipients and verification identities must remain non-RSA. Encrypted SSH
identities are rejected. This executable is for reviewed offline migration only;
its timing-advisory exception is not a vulnerability closure.

The duplicated manifest declarations are checked against the canonical workspace.
Keep the separate lockfile, source overrides, dependency policy and package build
in sync. The shared cargo-vet store retains the recorded legacy baselines; use
`cargo vet --manifest-path legacy/Cargo.toml --store-path supply-chain --locked`.
Do not add this directory to the normal workspace or forward its age feature.

Native Nix checks build the normal and legacy packages separately and run
generated-key tests for OpenSSH and PKCS#1 migration, normal rejection and
encrypted-key rejection. To run that test outside Nix, build both packages and
set `NIX_SEAL_NORMAL_TEST_BINARY` to the normal executable; `age` and `ssh-keygen`
must be available. Generated identities stay in private temporary directories.

See [ADR 0031](../docs/adr/0031-isolated-rsa-migration-build.md) and
[ADR 0009](../docs/adr/0009-ssh-migration-compatibility.md).
