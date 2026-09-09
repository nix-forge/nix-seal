# Threat model

## Assets and trust boundaries

Assets are canonical plaintext, administrator and target identities, signing
keys, delegated-create capabilities and authorizer keys, target artifacts,
runtime generations, prompt input, and generator output.
Trust boundaries exist at Git review, administrator machines, age plugins and
agents, the ciphertext cache, Nix builders/binary caches, deployment transport,
target activation, generators/editors, and privileged service consumers.

Repository metadata and ciphertext are attacker-controlled input. Nix store and
binary caches are public. A target trusts only its configured plan root,
approval keys, and target identity. Repository authorization remains part of the
root of trust even when artifacts are signed.

Preparation over SSH keeps decryption and signing keys on the explicitly selected
administrator host. It transfers bounded canonical ciphertext and public plans,
then independently checks the returned signed artifacts against the initiating
machine's plans before importing any destination cache. Request paths must be
relative, traversal-free, and exactly cover the selected canonical sources.
Transfer and installation do not authorize activation or change signature
bindings. Cache imports run as the configured owner; elevation is limited to
ciphertext installation and public readiness checks. An interrupted import can
leave a subset of validated artifacts, so the complete readiness check must pass
before switching. SSH host configuration and the chosen remote executable are
trusted operator inputs. Plaintext and private identities are never serialized
into the preparation exchange.

## Adversaries

- Malicious repository contributors and substituted cache/transport objects.
- Compromised administrator workstations, decryption keys, or signing keys.
- Thieves possessing a target private key or historical Git checkout.
- Unprivileged local users racing or traversing runtime filesystem operations.
- Malicious plugins, agents, editors, generator executables, and migration
  tools.
- Supply-chain attackers affecting dependencies, CI, release identity, or Nix
  inputs.
- Attackers causing resource exhaustion, interrupted writes, concurrent races,
  malformed/oversized input, downgrade, replay, or partial activation.

## Required controls

Plans are strict, versioned, bounded, canonical, and signed by policy. Target
manifests bind all public security context. Crypto uses standard age behind an
adapter. Cache writes and activation use locks, private directories, same-device
atomic transactions, fsync, link/path checks, and fail-closed generation switch.
Plaintext is excluded from store, argv, ordinary environment, JSON, diagnostics,
logs, and CI. External processes receive a minimal environment, explicit file
descriptors, deadlines, output bounds, and the least required secret set.
Generator prompt input is non-interactive by default. Explicit interactive input
uses only a verified controlling terminal, masks hidden values with guaranteed
terminal-mode restoration, bounds bytes, and zeroizes transient read buffers. On
Linux, a Rust worker attempts a fresh network namespace before launching an
external generator. If the kernel or container denies that operation, execution
falls back once with a diagnostic warning. macOS and other platforms warn
because network isolation is unavailable. Generator executables and declared
runtime inputs remain trusted-code boundaries on every platform.

Generator executables, runtime input directories, and their entries must resolve
inside `/nix/store` before secret inputs are staged. An empty runtime input list
creates an empty PATH; empty components in a nonempty PATH are rejected.
Persistent prompt responses live in an owner-only, repository-keyed XDG state
directory outside the checkout. Repository-local legacy prompt state blocks
generation until the operator relocates or removes it before Nix evaluation.
The checked-in direnv file performs no evaluation, so a prior direnv approval
does not authorize a later branch's Nix code.

Identity, group, and target IDs occupy disjoint authorization namespaces.
Approval thresholds count distinct Ed25519 key material across native and
OpenSSH encodings. Legacy SSH signature IDs remain verifiable but cannot add a
second vote for the same key. Normal encryption and decryption reject SSH RSA;
explicit migration alone may decrypt legacy RSA sources.

Foreign cache imports are validated in a private staging cache before publishing
entries under one destination lock. Imports have aggregate entry and byte
limits, and inventory has an envelope-memory limit. Conflicting or malformed
input cannot publish a partially validated import. Physical I/O failure during
publication may leave a subset of independently validated entries; retry remains
append-only and idempotent. Activation ignores unauthenticated envelopes and
requires a verified matching artifact for every selected secret. Migration
traversal bounds every visited entry, including directories and unrelated files.

Delegated creation accepts only a short-lived, one-use capability for one
missing declared source, public recipient set, and plaintext commitment. The CLI
derives every binding from a strict bootstrap plan and rejects replay,
replacement, expiry, source or recipient substitution, altered commitments,
and artifact-signer reuse. The delegate has no age identity. Capability
receipts contain no plaintext and use private, no-follow repository paths.
The signed protocol limits delegated plaintext to 64 KiB. Direct bootstrap
completion proves current private-key possession with a fresh random challenge
before reading plaintext, including when the authorizer uses an SSH agent.

Native Nix template shorthand resolves only explicitly declared secrets. It
validates references and phase constraints before exporting a plan. Pending
fields and their templates cannot enter activation until the ciphertext exists;
the separate creation plan contains no template outputs. Public template text
and names remain public metadata. UTF-8 substitution does not escape the
consumer's configuration language.

Public template inputs use a separate `{{public:name}}` namespace and are
resolved by Nix before plan compilation. They enter the public store. Evaluation
rejects missing or unused bindings, expansion beyond 2 MiB, nested reserved
markers, and replacement-boundary changes to secret markers. Public substitution
does not grant access to additional fields or change secret phase policy.

Nix name lists normalize into the same validated declarations. A single public
administrator catalog may select itself; multiple catalogs require an explicit
choice. Target public keys remain explicit and conflicting identity declarations
fail evaluation. Default SSH identity paths are runtime paths only: evaluation
does not read private keys, generate identities, or discover recipients. Template
phase inference follows existing field phases and rejects mixed-phase inputs.

Interactive bootstrap creation resolves a local name to exactly one canonical
ID before proving authorizer possession or requesting input. The challenge
binds that canonical ID. Hidden terminal input restores echo and retains the
same size and create-only limits as stdin. Ambiguous names never select a
recipient or destination implicitly.

On NixOS, a root-owned pre-start helper may start the configured embedded
profile's user manager before service-related activation. Its username is
shell-escaped public configuration, its executables are store paths, and its
UID comes from the local account database. Secret activation remains under the
profile owner's UID; this helper cannot read or modify plaintext or policy.

Security tests cover traversal, symlink/hardlink/TOCTOU races, malformed crypto
and signatures, replay and target substitution, disk exhaustion, crashes,
concurrency, secret canaries, and denial-of-service bounds. Post-switch service
actions are constrained to the expected manager binary and protected canonical
paths; writable or non-executable manager files are rejected before any process
is spawned.
The target-policy hash also binds the exact service executable and timeout, so
an activation document cannot substitute another otherwise valid command.

## Out of scope and unavoidable limits

- Root on a target can read that target's runtime plaintext.
- A compromised administrator identity exposes canonical ciphertext addressed to
  it; a compromised target identity exposes matching direct/historical objects.
- Re-encryption cannot make already-decrypted historical ciphertext secret
  again.
- Secure deletion is not guaranteed on SSDs or copy-on-write filesystems.
- Zeroization cannot prove every compiler/runtime copy disappeared.
- Static rotation cannot update an external service without a rotation provider.
- Availability under a fully compromised host/kernel is out of scope.
- Offline capabilities cannot be globally revoked before their bounded expiry.

## Review cadence

Every cryptography, signing, manifest, activation, plugin, migration, or trust
root change updates this document and its ADR. Release candidates include an
attack-path review. The security team reviews the model at least once per minor
release and after every incident.

The operational procedures in [`docs/runbooks.md`](docs/runbooks.md) are part of
the threat-model control set. They must be exercised for administrator-key,
target-key, signer, cache-loss, rollback, and recovery scenarios before a 1.0
release and after any material trust-root change.
