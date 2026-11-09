# ADR 0031: Resolve RSA migration independently

Status: accepted for implementation; native checks and maintainer review required

The normal application must not link RustCrypto RSA while its timing advisory
remains unresolved. Existing offline RSA source migration must remain available,
and normal OpenSSH Ed25519 interoperability must continue.

The local age patch separates `ssh-rsa` from `ssh`. Root and fuzz enable only
`ssh`; no root feature forwards `ssh-rsa`. The independent `legacy/` Cargo
workspace alone enables RSA. It has a separate lockfile and Nix derivation and
builds `nix-seal-legacy` from the canonical CLI source. Worker relaunches use that
same executable. The normal output neither installs nor invokes it implicitly.
No cryptographic algorithm or subprocess decryption backend is replaced.

Public RSA migration inventory uses ssh-key's allocation-only wire parser,
without its RSA arithmetic feature. Modulus and exponent bounds remain those
of the released age parser. Normal operations still reject RSA even in the
legacy executable. Normal RSA source migration fails with an explicit instruction
to select the legacy build; all existing migration arguments and transaction
checks remain available in that build. Encrypted SSH identities remain rejected.

Tests require RSA absence from root and fuzz lockfiles, legacy presence, and
agreement of duplicated dependency declarations, patches, version, release
profile and lint policy. Separate native package checks exercise RSA OpenSSH
and PKCS#1 migration, normal-build rejection, encrypted-key rejection, unchanged
sources and verification of the new non-RSA ciphertext. Source filtering keeps
legacy-only edits out of the normal Rust package while including them in the
legacy package. The legacy check uses a separately built normal executable.

The RSA advisory exception moves to the legacy workspace's policy. This is
isolation, not a claim that the library is repaired or universally safe. Retain
ADR 0009's offline and noninteractive restrictions. Reassess on age/RSA updates;
retire the exception and forked feature boundary after an upstream OAEP fix and
legacy-key compatibility review, or remove the legacy artifact after migration.
