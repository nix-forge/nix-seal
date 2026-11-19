# Contributing

Discuss substantial design changes before implementation and add an ADR for any
change to cryptography, signatures, manifests, cache/store trust, activation,
plugins, or migration. Changes must include relevant library or Rust tests, user-facing documentation,
and threat-model updates when trust boundaries move.

All commits require Developer Certificate of Origin sign-off:

```console
git commit -s
```

## Testing and security gates

Run the focused test for the behavior you changed, then the complete checks
listed below before requesting review. CI runs these checks on pull requests
and merge groups, and protected `main` requires the resulting statuses to
pass.

Nix behavior tests cover functions in `nix/lib/` only, through nix-unit cases in
`nix/lib/tests/`. Rust unit, integration, fuzz, Miri and sanitizer tests remain
supported. Other automation is static formatting, lint, syntax, type, schema,
documentation and security analysis. Do not add module/VM fixtures, generated
activation regression tests or Python behavioral suites. Keep module setting
assertions and production runtime/input validation.

Run `nix build .#checks.x86_64-linux.lib-tests` for the Nix library suite (replace
the system for another native platform), or `nix-unit --flake '.#libTests'` in the
development shell. Library tests do not establish boot or service integration.
Dependency and security findings follow the
[dependency-management policy](docs/dependency-management.md).

Run `cargo fmt --all -- --check`,
`cargo check --workspace --all-targets --all-features --locked`,
`cargo clippy --workspace --all-targets --all-features --locked -- -D warnings`,
`cargo test --workspace --all-targets --all-features --locked`,
`cargo deny --locked check`, `cargo vet --locked`, and `nix flake check`. Never
put real secrets, private identities, prompt answers, or plaintext test fixtures
in commits or CI.

The opt-in `legacy/` workspace has a separate lockfile and policy. Also run
`cargo fmt --manifest-path legacy/Cargo.toml --all -- --check`,
`cargo clippy --manifest-path legacy/Cargo.toml --all-targets --locked -- -D warnings`,
`cargo deny --manifest-path legacy/Cargo.toml --config legacy/deny.toml --locked check`, and
`cargo vet --manifest-path legacy/Cargo.toml --store-path supply-chain --locked`.
The `nix-seal-legacy` Nix check runs its migration regressions against a separately
built normal executable. See [the compatibility build](legacy/README.md).

Security-critical code requires a documented maintainer review; seek an
independent CODEOWNER review when another qualified owner is available.
Dependencies are reviewed one at a time; lockfile updates must explain security
and compatibility impact.
`supply-chain/config.toml` is the committed cargo-vet policy. Its exemptions are
a recorded bootstrap baseline, not an audit claim: reduce them only with a
documented review or a trusted imported audit. Refresh imports deliberately and
commit the resulting `supply-chain/imports.lock` change with the dependency
update.

For generated programs, use `writeShellApplication` with `runtimeInputs` for a
short installed Bash command. Use `nix/lib/writers.nix` for checked Bash source
templates, and `writers.writePython3Bin` for a single Python executable. Use
`replaceVars` or `replaceVarsWith` for complete `@name@` file templates and
`builtins.replaceStrings` only for small evaluation-time strings. Package-phase
source edits must use `substituteInPlace --replace-fail`.

## Rust source boundaries

The Nix package includes Cargo manifests and configuration, toolchain metadata,
licenses, crates with their tests and fixtures, and embedded schemas. Workflow,
documentation and Nix-module edits do not invalidate the Rust package source.
Documentation and module checks retain their own inputs. Update
`flake/rust-source.nix` when the Rust build gains another input location.

A native package build verifies that the filtered source supplies the Rust
workspace and its retained tests.

## CI inventories

The stable compiler and components come from `rust-toolchain.toml`; the MSRV
comes from `workspace.package.rust-version` in `Cargo.toml`. The Nix package and
documentation versions also use the workspace version. Update those manifests
instead of repeating version edits in workflows.

Fuzz smoke tests run every binary registered in `fuzz/Cargo.toml`, each with the
same bounded time budget. Adding or removing a target changes CI automatically.
Python syntax checks cover tracked Python files, and Ruff discovers files from
the repository root. The type checker covers surviving Python CI helpers.

Portable formatter and hook checks are exposed as `lintChecks` and run in the
required x86 Linux Nix job. `ciChecks` contains every remaining native check,
computed from `checks` rather than a separate allowlist. All three platforms
build those checks through the shared CI action and validate flake output
schemas. Ordinary `nix flake check` still builds the complete local check set.

## Test evidence

Rust recovery tests exercise CLI behavior using disposable state. Module
assertions validate setting combinations; library tests validate pure helper
contracts. Neither establishes real boot, mount or service behavior. Record
native deployment and operational recovery evidence separately.

## Source filenames

Use lowercase snake_case for Python sources, including executable helpers and
test fixtures. Use lowercase kebab-case for shell helpers and ordinary assets.
Name scripts by their behavior or package phase, such as `post-install.sh`,
rather than extraction ordinals, line numbers or interpolation fragments. Keep
native manifests, language entry points, public package/module identities, real
version numbers and discovery-test filenames stable. An installed command can
keep its hyphenated name when its Python source uses underscores.

Update callers, imports, fixture loaders, source filters and per-file lint
selections when moving a source. Check derived filenames as well as literal
paths, and preserve file permissions.
