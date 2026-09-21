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
It attaches the portable `*.intoto.jsonl` bundles beside the binaries before
making the release immutable.

Verify a downloaded executable with:

```console
gh attestation verify nix-seal-vX.Y.Z-x86_64-linux \
  --repo nix-forge/nix-seal \
  --bundle nix-seal-vX.Y.Z-x86_64-linux.intoto.jsonl \
  --signer-workflow nix-forge/ci/.github/workflows/slsa-nix-seal-release.yml \
  --signer-digest bb1b39a9082f72dc6c7ce596103ce7a5e4d29b01
```

These are release controls, not a verified Level 3 claim yet. No published
release asset was available to verify on 21 September 2026. The builder also
permits Nix binary substitution, so its attestation alone does not establish
where executable bytes were compiled. Define and test the trusted build or
substitution policy, then verify downloaded release subjects before making a
Build track claim. A local Nix build, arbitrary cache, or unrelated CI output
has separate provenance. See the
[SLSA Build specification](https://slsa.dev/spec/v1.2/)
and [GitHub's Level 3 guidance](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/increase-security-rating)
for the model and verification requirements.
