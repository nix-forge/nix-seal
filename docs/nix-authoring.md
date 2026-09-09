# Define and create secrets with Nix

Import nix-seal's NixOS, nix-darwin, or Home Manager module. No configuration
framework or flake-parts module is required. Configure public trust once, then
declare secrets beside their consumers.

## Declare a value or template

After the setup below, list the values you need:

```nix
nixSeal.secrets = [ "token" "password" ];
```

Their sources default to `<secretDirectory>/<name>.age`. Ordinary declarations
need no `lib.genAttrs` or empty attribute sets. Add named options in the same
list when a value needs an exception:

```nix
nixSeal.secrets = [
  "token"
  "password"
  { registry-token.shared = true; }
  { database-password.source = "services/database/password.age"; }
];
```

A secret's `source` is a repository-relative string. `shared = true` selects
`sharedSecretDirectory`.
These settings select storage; they do not grant access to another target.

For a runtime configuration file, reference the declared secret in Nix:

```nix
{ config, ... }: {
  nixSeal.secrets = [ "token" ];
  nixSeal.templates.service = ''
    TOKEN=${config.nixSeal.placeholder.token}
  '';
}
```

The interpolation inserts a public marker, never the private value. A typo in
the secret name fails Nix evaluation. No JSON inventory or separate binding file
is needed. For names containing `/`, use the explicit alias described below.

For a separate public file, write `TOKEN={{nix-seal:token}}` in
`templates/service.env.template` and select it by name:

```nix
nixSeal.templates = [ "service.env" ];
```

`templateDirectory` changes the base directory once for the target. An explicit
file, such as `nixSeal.templates.service = ./service.env.template;`, overrides
that convention. The [storage guide](storage-layout.md) explains defaults,
shared files, and layouts for small and multi-target repositories. Include the
format extension before `.template`; keep conventional extensionless filenames
such as `ssh_config.template`. The named example above exposes its runtime file
at `config.nixSeal.templates."service.env".path`.

Each placeholder refers to a same-named declared secret. No inventory file or
repeated mapping is needed. Use `config.nixSeal.secrets.token.path` for the raw
credential and `config.nixSeal.templates.service.path` for the rendered file.
Only public template text enters the Nix store; substitution runs at activation.
To edit a template, edit that public text or file and rebuild. To change a
credential, edit its encrypted secret through nix-seal. Never replace a marker
with a real credential in the template.

Template lists also accept named exceptions, such as
`templates = [ "service.env" { client = ./client.conf.template; } ];`.
Attribute sets remain supported, including `secrets.token = { };` and
`templates.service = { };`. A later imported module can extend a listed name
with `nixSeal.secrets.token.restartUnits = [ "example.service" ];`. List entries
use the ordinary Nix module merge, including priorities and conflict errors.

The full options remain available:

```nix
nixSeal.templates.service = {
  source = ./service.env.template;
  placeholders.token = "credentials/api-token";
  mode = "0600";
  restartUnits = [ "example.service" ];
};
```

Declare `secrets."credentials/api-token"` when using that alias. An encoding
override uses `placeholders.token = { secret = "credentials/api-token";
encoding = "base64"; };`. Supported encodings are `utf8`, `base64`, and `hex`.
UTF-8 inserts the original bytes. It does **not** escape shell, JSON, TOML, INI,
or dotenv syntax. Use values validated for the destination format, or keep an
entire private configuration in one encrypted file when its syntax or field
names must remain private. Never put a private value in Nix `content` or `source`.

Templates inherit the common activation phase of their fields. Configure a
field's `phase = "services"` once; its templates follow it. Fields with different
phases cannot be combined in one template. An explicit template phase must still
match its fields. Referencing a field does not change its ownership, permissions,
phase, recipients, or service actions. Configure those on the secret when needed. Unknown names, unused
overrides, malformed placeholders, and phase mismatches fail plan evaluation.

## Mix public values and secrets

File-based templates can receive public values from your Nix configuration.
For example, an `allowed_signers.template` file can contain:

```text
{{nix-seal:email}} namespaces="git" {{public:signing-key}}
```

Declare its public input once:

```nix
{ lib, ... }: {
  nixSeal.secrets = [ "email" ];
  nixSeal.templates.allowed-signers = {
    source = ./allowed_signers.template;
    publicValues.signing-key = lib.removeSuffix "\n" (builtins.readFile ./signing.pub);
  };
}
```

An existing public Nix option can supply the value instead of a `.pub` file.
Public values are strings; use `toString` or a format-specific serializer for
other data. They enter the public Nix store. Keep passwords and private keys in
`secrets`, never in `publicValues`.

Nix resolves `{{public:name}}` once, then nix-seal resolves `{{nix-seal:name}}`
from decrypted fields at activation. Repeating a public marker reuses the same
value. Missing and unused public bindings fail evaluation. Values cannot contain
or introduce public or secret markers, and expanded public text is limited to
2 MiB. Substitution is literal and does not escape the destination format.

`publicValues` works with inline `content` too. Inline Nix templates can also use
ordinary Nix interpolation for public values alongside `config.nixSeal.placeholder`.
`templates.<name>.source` remains the original public file;
`templates.<name>.renderedSource` exposes the generated public text with secret
markers still intact. No JSON binding file is required.

## Configure public trust once

For example, this module sets up a NixOS target. Replace the public-key
placeholders with the outputs of your key-generation commands:

```nix
{ inputs, ... }: {
  imports = [ inputs.nix-seal.nixosModules.default ];
  nixSeal = {
    repositoryRoot = ../.; # Adjust to the checkout root.
    administrators.team = {
      identities = {
        admin = { kind = "administrator"; public = "age1..."; };
        release = { kind = "signer"; public = "nix-seal-ed25519-v1:..."; };
        create = { kind = "authorizer"; public = "nix-seal-ed25519-v1:..."; };
      };
      approvalPolicies.release = { threshold = 1; signers = [ "release" ]; };
      defaultApprovalPolicy = "release";
    };
    publicKey = "age1...";
    identityFile = "/var/lib/nix-seal/target.agekey";
    secrets = [ "token" ];
    templates.service = "TOKEN={{nix-seal:token}}\n";
  };
}
```

Store private keys outside the checkout and Nix store. `key generate` creates
an age identity; `key generate-signing` creates a signing key. Generate separate
keys for release approval and first-time creation. The target identity belongs
on the target machine. A creation key cannot decrypt a canonical age file or
approve a deployment artifact. Add recovery recipients and approval thresholds
to the shared catalog as your deployment requires.

Import the same public catalog module on other targets. The optional flake
catalog and configuration-framework adapter remain supported. Direct
`nixSeal.administrators` declarations override the adapter's catalog default.

Declarations enable nix-seal automatically; `enable = false` disables integration
explicitly. A single administrator catalog is selected automatically. With
multiple catalogs, set `administrator` to the intended name. An explicit
`administrator = null` preserves the advanced unscoped identity interface.

`publicKey` replaces the repeated `identities.target.kind/public` structure.
Use the existing `identities` interface for custom target identity IDs. Conflicting
public-key declarations fail evaluation. A target public key is required public
trust data; nix-seal does not read local keys or discover recipients at evaluation.

The default runtime identity is the existing Ed25519 SSH host key for NixOS and
nix-darwin, or `~/.ssh/id_ed25519` for Home Manager. The dedicated age-key example
above overrides that default. Neither path is read or generated by Nix evaluation.
Activation fails if the required key is absent or cannot decrypt the artifact.

Standalone modules set `repositoryRoot` once. The optional configuration-framework
adapter supplies the calling flake's root automatically. Directory options remain
relative to this root and can be configured once in a shared module. nix-seal
cannot infer a repository's custom storage layout from a target's name.

NixOS and nix-darwin derive the target ID from `networking.hostName`; Home
Manager defaults to `home/<username>`. Set `targetId` explicitly for multiple
standalone homes with the same username. Framework-supplied target names keep
their existing behavior. Cache locations and file permissions have platform
defaults; explicit values still take precedence. Native system files default
to root ownership and mode `0400`, with group `root` on Linux and `wheel` on
macOS. Home Manager uses the profile username, and group `staff` on macOS or
the username on Linux. Configure another group when that group does not exist.

## Create the missing values

Declare the secret and its templates before creating ciphertext. Missing
declared sources enter a separate creation plan. Templates waiting for those
sources appear in `nixSeal.pendingTemplates`, with the missing local names.
They cannot enter the activation plan until every field exists. A typo that
references an undeclared secret is an error, not a pending field.

From the checkout, export the target's creation plan and enter a value privately:

```sh
bootstrap=$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.server.config.nixSeal.bootstrapPlanFile)
nix-seal secret bootstrap complete \
  --bootstrap-plan "$bootstrap" --secret token \
  --authorizer-key /absolute/private/create.key --interactive
```

The command accepts a local name only when it identifies one pending secret.
Use the full canonical ID if the name is ambiguous. Enter finishes a single
line without storing the newline. For a multiline value, add `--multiline` and
finish with Ctrl-D. Values are hidden, bounded to 64 KiB, and excluded from
arguments and ordinary output. Automation can omit `--interactive` and supply
stdin through a protected pipe. Existing ciphertext is never overwritten.

Add the new `.age` file to Git's index so a Git-based flake can see it, then
evaluate the normal plan again. The template becomes ready automatically.
`bootstrapPlanFile` becomes null when no declared sources are missing. Export
`nixSeal.planFile`, run `nix-seal template check --plan <plan>`, and use the
existing signed provisioning workflow before activating the target. Creating
canonical ciphertext does not deploy it.

The plan JSON is generated by nix-seal from these Nix declarations. It is a
machine interface for validation and signing, not a configuration file to write
or keep synchronized. Templates require only the Nix declaration and optional
public `.template` file.

For later changes, `secret edit` uses an explicit editor in a private workspace;
`secret batch` handles mapped collections; generators and delegated creation
remain available. See the [command reference](nix-seal.1) and
[operational runbooks](runbooks.md).
