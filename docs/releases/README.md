# Release notes

Create one file named `vX.Y.Z.md` for every release. Start it with a
`## Changelog` section and describe functional changes, security impact,
affected consumers, compatibility or migration requirements, the checks that
ran, and the support and end-of-life window. Name the reviewed source commit
and release workflow when documenting verification.

The release workflow requires the tag-specific file, includes it in the
release source, names every asset with the release tag and platform, publishes
checksums and CycloneDX SBOMs, and calls the pinned `nix-forge/ci` reusable
builder. The builder creates GitHub build provenance and an SBOM attestation
before the protected publisher verifies and releases those exact assets. Keep
release notes descriptive and review them together with the code before
creating the tag.
