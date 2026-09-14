# nix-seal

`nix-seal` prepares encrypted secrets outside Nix evaluation and activates them
as volatile files for NixOS, nix-darwin, and Home Manager. Start with the
[setup guide](start-here.md), then use the [runbooks](runbooks.md) for routine
authoring, deployment, recovery, and migration.

> **Pre-release.** `nix-seal` has not received the independent audit required
> for 1.0 and is not ready for production secrets. Use disposable examples while
> evaluating it. The
> [roadmap](https://github.com/nix-forge/nix-seal/blob/main/ROADMAP.md) records
> the remaining release gates.

The [storage layout](storage-layout.md) explains which files are public,
encrypted, or available only at runtime. The
[Nix authoring guide](nix-authoring.md) covers module declarations and generated
configuration. Read the
[threat model](https://github.com/nix-forge/nix-seal/blob/main/THREAT_MODEL.md)
before changing recipients, activation policy, signatures, or cache behavior.

This website publishes user and operator documentation. The normative
[specification](https://github.com/nix-forge/nix-seal/blob/main/SPEC.md),
security policy, ADR history, Rust source, and release history remain in the
[GitHub repository](https://github.com/nix-forge/nix-seal).

## Maintain the documentation

Build the same static artifact that CI publishes:

```console
nix build .#documentation-site
```

Preview edits locally:

```console
nix develop .#docs --command mkdocs serve --config-file site/mkdocs.yml
```

The site build checks local page and anchor targets. The existing `documentation`
package continues to own the man page, schemas, and shell completions.
