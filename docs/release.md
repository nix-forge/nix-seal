# Release controls

Version tags matching `v*.*.*` run the release workflow. The workflow builds the
Nix package natively on x86_64 Linux, aarch64 Linux, and aarch64 macOS, then
publishes the executable, CycloneDX SBOM, SHA-256 checksums, and build metadata
only after a protected `release` environment approval.

The build jobs call the pinned, organization-owned reusable builder in
`nix-forge/ci`. The builder creates the executable, CycloneDX SBOM, checksum,
and build metadata, then creates GitHub artifact attestations before upload. It
does not receive release-write access or use a shared release cache. The
publisher verifies every subject with that signer workflow, attaches the assets
to a draft release, and only then uses the protected `release` environment to
publish. It does not use a long-lived signing key or package-registry
credential. Repository administrators must
configure the `release` environment with the required reviewers and keep tag
creation protected. A 1.0 tag additionally requires the independent security
audit and all gates in [`SPEC.md`](../SPEC.md); those human assurance gates are
intentionally not replaced by CI automation.

Before tagging, create `docs/releases/vX.Y.Z.md` with a `## Changelog` section
covering functional changes, security impact, affected consumers, migration
notes, verification, and the support and end-of-life window. The release job
rejects a tag without this descriptive record. Each published asset includes
the release tag and platform in its name, and each platform checksum file
covers the executable, SBOM, and build metadata.

To verify a release, download all assets and run the checksum file in the same
directory, then verify the executable's GitHub attestation:

```console
gh release download vX.Y.Z --repo nix-forge/nix-seal --dir release-vX.Y.Z
(cd release-vX.Y.Z && sha256sum -c nix-seal-vX.Y.Z-x86_64-linux.sha256)
gh attestation verify release-vX.Y.Z/nix-seal-vX.Y.Z-x86_64-linux \
  --repo nix-forge/nix-seal \
  --signer-workflow nix-forge/ci/.github/workflows/slsa-nix-seal-release.yml \
  --signer-digest bf01ac186602f722c516823520aef97c8670fcb8
```

The expected release identity is the `nix-forge/nix-seal` repository and the
pinned `nix-forge/ci/.github/workflows/slsa-nix-seal-release.yml` reusable
builder. Keep the digest in this command synchronized with
`.github/workflows/release.yml`.

The current Nix package set deliberately omits x86_64-darwin until a supported
nixpkgs/runners combination is available. The platform contract and release
matrix must be expanded when that limitation is removed.
