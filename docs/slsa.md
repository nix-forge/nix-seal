# SLSA build provenance

The supported `nix-seal` release assets are the platform executable, its
CycloneDX SBOM, checksum file, and build metadata. Each asset is created in a
GitHub-hosted job from the immutable release tag and attested before it leaves
the builder.

The release workflow pins the organization-owned
`nix-forge/ci/.github/workflows/slsa-nix-seal-release.yml` reusable builder to
commit `bb1b39a9082f72dc6c7ce596103ce7a5e4d29b01`. The builder has read-only
source access, no release-write permission, no long-lived signing key, and no
shared release cache. A separate `release` environment protects publication.
The publisher verifies every expected subject, its checksum, source commit,
signer workflow, and builder commit before creating the GitHub Release.

Verify a downloaded executable with:

```console
gh attestation verify nix-seal-vX.Y.Z-x86_64-linux \
  --repo nix-forge/nix-seal \
  --signer-workflow nix-forge/ci/.github/workflows/slsa-nix-seal-release.yml \
  --signer-digest bb1b39a9082f72dc6c7ce596103ce7a5e4d29b01
```

This is a bounded SLSA Build track claim for the named release subjects. It
does not claim that a local Nix build, arbitrary cache, or unrelated CI output
has the same provenance. See the [SLSA Build specification](https://slsa.dev/spec/v1.2/)
and [GitHub's Level 3 guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating)
for the model and verification requirements.
