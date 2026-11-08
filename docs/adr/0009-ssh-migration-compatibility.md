# ADR 0009: OpenSSH migration compatibility

Status: accepted; RSA exception isolated by ADR 0031

`nix-seal` must migrate existing OpenSSH Ed25519 and RSA age ciphertext without
a separate scripting runtime. Normal builds enable age's Ed25519 `ssh` feature.
RSA migration is selected through the independently resolved `nix-seal-legacy`
executable, which reuses the same CLI source and adds age's `ssh-rsa` feature.
See [ADR 0031](0031-isolated-rsa-migration-build.md).

Native X25519 age recipients and reviewed age plugins remain the default.
OpenSSH Ed25519 remains supported for interoperability, with comments
normalized away before authorization comparison or fingerprinting. OpenSSH RSA
is rejected by normal plan, encryption, decryption, reveal, and rekey paths. It
is accepted only as the source identity of an explicit migration operation;
replacement recipients and the round-trip verification identity must be
non-RSA. The non-interactive CLI rejects encrypted OpenSSH identities instead
of presenting a prompt or attempting agent integration.

Only the independent legacy workspace brings in RustCrypto `rsa`.
That crate is subject to unfixed `RUSTSEC-2023-0071` (Marvin timing attack).
The legacy `cargo-deny` policy records a narrowly scoped exception because no
safe upgrade is available and dropping migration would break compatibility.
Normal and fuzz
graphs must not contain RSA, and their advisory gates have no RSA exception. The
compensating controls are:

- The tool has no network listener, daemon, or remote decryption API.
- RSA cannot enter new plans or new ciphertext recipient sets.
- No encrypted SSH key is prompted for or passed to a background process.
- SSH support is assessed on every `age` or `rsa` update and must be removed or
  redesigned before any network-facing secret provider is introduced.

This exception is not a finding closure. It is a documented release blocker for
any future deployment that could expose RSA decryption timing to an attacker.
