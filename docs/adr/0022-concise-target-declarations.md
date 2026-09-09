# ADR 0022: Concise target declarations

Status: accepted

Ordinary Nix consumers should declare names and exceptions without rebuilding
attribute sets with `lib.genAttrs` or repeating platform metadata. `secrets` and
`templates` accept lists of names and named option sets. The frontend normalizes
these into the existing submodules, preserving priorities, merge conflicts,
explicit sources, and advanced options. Attribute-set declarations remain valid.

Nonempty declarations enable integration by default. An explicit disable takes
precedence. One administrator catalog selects itself; several require an
explicit choice. Explicit null retains unscoped identity mode. This selection
does not discover recipients from files or relax approval policy.

`publicKey` declares the ordinary target identity without repeating its kind.
Identity declarations merge recursively and reject conflicting public keys.
The default runtime identity path is the existing Ed25519 SSH host key for
systems and the profile user's Ed25519 SSH key for Home Manager. These are paths,
never evaluation inputs. No key is read or generated, and activation still
requires a matching private identity. Dedicated age-key paths remain supported.

The framework adapter supplies the calling flake root. Standalone consumers
still provide their root once, and custom storage directories remain explicit.
Neither current working directory nor filesystem discovery defines policy.

A template defaults to its referenced secrets' common activation phase. It
cannot move a field to another phase or combine fields across phases. Runtime
ownership, modes, recipient sets, and service actions remain independent policy.
The default mode stays read-only `0400`; writable files still require `0600`.

The plan schema, cryptography, cache trust, and activation implementation are
unchanged. Existing explicit configurations retain their evaluated behavior.
Previously ambiguous implicit catalog selection now fails with a choice of names;
previously conflicting identity declarations now fail instead of overwriting.
