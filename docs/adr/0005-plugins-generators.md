# ADR 0005: Plugins and generators

Status: accepted; standard age plugin worker, hardened generator prompts, and
Linux generator network-isolation worker implemented

Age identities use the standard plugin protocol. Generators are built-in Rust or
direct declared executables from Nix packages; no shell evaluation. Processes
receive a sanitized environment, explicit descriptors and secret dependencies,
private workspace, time/output bounds, and network isolation when enforceable.
On Linux, nix-seal attempts generator network isolation in a dedicated Rust
worker by creating a fresh network namespace before launching the executable. If
the kernel or container denies that operation, it falls back once to the direct
process-group path and emits a diagnostic warning. macOS and other platforms
emit the capability warning because network isolation is unavailable. Generators
and declared runtime inputs must therefore be treated as trusted code. On Unix,
nix-seal places generators and migration helpers in a dedicated process group so
timeout and failure cleanup terminates descendants that could otherwise retain
access to staged plaintext; other platforms retain direct child termination as
their portable fallback. External generators receive each explicitly declared
canonical secret dependency as one numbered `0600` file beneath a private
`NIX_SEAL_SECRET_DIR`; no dependency value is passed through arguments, an
ordinary environment value, or the Nix store. Built-ins reject secret
dependencies. The CLI checks canonical recipient authorization before streaming
any dependency into that workspace. Plugin errors are redacted and unrelated
descriptors are closed.

The Rust adapter executes standard age plugin recipients and identities through
the hidden `__plugin-worker` command. The parent resolves each required
`age-plugin-*` executable only from canonical `/nix/store` paths before
launching it, then starts a private worker with a cleared environment, a narrow
allowlist for hardware integration, no inherited standard error, bounded framed
input/output, and a process-group timeout. It never forwards `SSH_AUTH_SOCK` to
plugins; plugin access to an SSH agent requires a separately designed, explicit
capability. The worker uses `NoCallbacks`, so interactive plugin
prompts fail closed rather than blocking or leaking prompt text. Plugin identity
public values remain opaque: authorization prechecks compare the plugin name,
while age stanza decryption is the authoritative key proof. Malformed frames,
oversized fields, excessive recipients, missing binaries, non-zero exits, output
overflows, and timeout/cleanup failures are redacted as one
`CryptoError::Plugin` category.

Generator prompts remain non-interactive unless the operator explicitly passes
`nix-seal generate --interactive`. The CLI opens `/dev/tty` directly, verifies
that it is a terminal, sanitizes public prompt labels, bounds input to 1 MiB,
and uses an RAII terminal-mode guard for hidden prompts so echo is restored on
every failure path. Single-line prompts read one canonical terminal line;
multiline prompts require Ctrl-D and preserve entered line endings. Prompt input
never passes through stdin/stdout, argv, ordinary environment variables, the
plan, or logs. Platforms without the reviewed termios implementation fail
closed.

Before staging secret inputs, generator executables and runtime input paths are
canonicalized and required to remain inside `/nix/store`, including symlinked
entries in runtime `bin` directories. A generator without runtime inputs receives
an empty PATH. A nonempty PATH cannot contain an empty component that would
search the workspace.

Persistent prompt responses are plaintext credentials. They live beneath the
user's XDG state directory outside the checkout, keyed by hashes of the canonical
repository path and the separate generator and prompt IDs. Directory ownership,
permissions, and links are checked before use. Responses are persisted only after
ciphertext publication; a persistence failure can require the operator to supply
the prompt again. Legacy repository-local prompt state blocks generation and
requires explicit cleanup before Nix evaluation. The repository's direnv file
is inert to prevent a durable approval from evaluating a changed checkout.
