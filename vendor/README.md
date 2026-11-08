# Temporary age dependency patch

`age/` starts from the published `age 0.12.1` crate archive. Its original
checksums, the modified files and four removed files are recorded in
[`security/age-source.json`](../security/age-source.json). The offline CI test
checks every retained file and rejects additions, deletions and symlinks.
The crate archive omits the repository-level license files linked by its README.
Unchanged copies of those files from its recorded upstream Git revision are
provided at [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE),
including Jack Grigg's original attribution. Their pinned source URLs and
hashes are recorded separately as `supplementalFiles`; the crate byte inventory
remains unchanged. Both executable variants install these notices.
Keep upstream license files and attribution intact. `Cargo.toml` is the
published normalized manifest used by Cargo; `Cargo.toml.orig` is provenance.

Upstream source and fixtures include deliberately public test identities.
Gitleaks exceptions match those exact identities, key-body fragments and file
hashes at the reviewed paths. Other credentials still scan. Formatting and
private-key delimiter hooks defer to the byte inventory for the two upstream
files with public PEM fixtures. Never use these identities for real secrets.

The patch removes native `tag` and `tagpq` recipients, which nix-seal does not
accept, and their P-256, HPKE, ML-KEM and SHA-3 dependencies from this crate.
The released X25519, scrypt, stream encryption and plugin implementations are
unchanged. SSH adds conditional compilation around the existing RSA
implementation:
`ssh` retains Ed25519, and only the independent legacy workspace selects
`ssh-rsa`. Retained cryptographic operations are unchanged. Released `age-core`
still uses HPKE's allocation-only surface,
without its P-256 feature. The unused upstream tagpq test-vector asset is retained
unchanged. The upstream development lockfile is removed.

This removes the affected `crypto-bigint` dependency and isolates RSA without
changing working cryptographic primitives. It does not repair the RSA timing
advisory; its exception is retained only in the independently built legacy
artifact. Root, fuzz and legacy workspaces must use the same source overrides.
Neither vendored age nor its upstream development dependencies belong in an
application workspace. See [ADR 0031](../docs/adr/0031-isolated-rsa-migration-build.md).

Replace this patch with a supported upstream release after reviewing its full
dependency delta and proving the same recipient compatibility, advisory gates
and native package checks. Do not run formatters over upstream source: updating
it requires a deliberate provenance update and source review.
