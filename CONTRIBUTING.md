# Contributing

Discuss substantial design changes before implementation and add an ADR for any
change to cryptography, signatures, manifests, cache/store trust, activation,
plugins, or migration. Changes must include tests, user-facing documentation,
and threat-model updates when trust boundaries move.

All commits require Developer Certificate of Origin sign-off:

```console
git commit -s
```

Run `cargo fmt --check`,
`cargo clippy --workspace --all-targets -- -D warnings`,
`cargo test --workspace`, `cargo vet --locked`, and `nix flake check`. Never put
real secrets, private identities, prompt answers, or plaintext test fixtures in
commits or CI.

Security-critical code requires CODEOWNER review. Dependencies are reviewed one
at a time; lockfile updates must explain security and compatibility impact.
`supply-chain/config.toml` is the committed cargo-vet policy. Its exemptions are
a recorded bootstrap baseline, not an audit claim: reduce them only with a
documented review or a trusted imported audit. Refresh imports deliberately and
commit the resulting `supply-chain/imports.lock` change with the dependency
update.

## Rust source boundaries

The Nix package includes Cargo manifests and configuration, toolchain metadata,
licenses, crates with their tests and fixtures, and embedded schemas. Workflow,
documentation and Nix-module edits do not invalidate the Rust package source.
Documentation and module checks retain their own inputs. Update
`flake/rust-source.nix` when the Rust build gains another input location.

Run `python3 -m unittest discover -s .github/tests` in the development shell to
check that metadata edits preserve the source hash while code, schemas, Cargo
inputs and new fixtures change it. A native package build verifies that the
filtered source still supplies everything needed by the workspace and its tests.

## CI inventories

The stable compiler and components come from `rust-toolchain.toml`; the MSRV
comes from `workspace.package.rust-version` in `Cargo.toml`. The Nix package and
documentation versions also use the workspace version. Update those manifests
instead of repeating version edits in workflows.

Fuzz smoke tests run every binary registered in `fuzz/Cargo.toml`, each with the
same bounded time budget. Adding or removing a target changes CI automatically.
Python syntax checks cover tracked Python files, and Ruff discovers files from
the repository root. The type checker retains explicit scope for the runtime
test DSL and CI scripts.
