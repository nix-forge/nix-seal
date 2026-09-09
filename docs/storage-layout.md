# Choose a storage layout

nix-seal separates a secret's identity, ciphertext location, access policy, and
runtime path. Organize files for the people maintaining the repository. Moving
a ciphertext does not require renaming its secret ID or its application-facing
runtime path.

## Start with two directories

A small repository can use:

```text
flake.nix
secrets/
  token.age
templates/
  app.env.template
```

Once public trust and `repositoryRoot` are configured:

```nix
nixSeal.secrets.token = { };
nixSeal.templates = [ "app.env" ];
```

The template contains public text such as `TOKEN={{nix-seal:token}}`. A user
creates the value through nix-seal's authoring command; no plaintext credential
belongs in either directory. A whole private configuration can be one `.age`
file and needs no public template.

These defaults do not assume a host-directory convention or a configuration
framework:

| Declaration | Default repository-relative source |
| --- | --- |
| Unscoped secret `token` | `secrets/token.age` |
| Administrator-scoped secret `token` | `secrets/<administrator>/<secretScope>/token.age` |
| Unscoped secret with `shared = true` | `secrets/shared/token.age` |
| Administrator-scoped secret with `shared = true` | `secrets/<administrator>/shared/token.age` |
| Public template `app.env` | `templates/app.env.template` |

Administrator-scoped ciphertext defaults keep independently managed namespaces
apart. They preserve existing layouts. If a small project selects an
administrator catalog but wants the flat tree above, set
`nixSeal.secretDirectory = "secrets"` once. Public templates default to one
repository-wide directory because the same public syntax can serve several
targets, each with its own bindings and permissions.

Only declared names are loaded. Adding another `.age` or `.template` file never
registers a secret, adds a consumer, or changes a recipient set. Declaring a
missing ciphertext produces a pending creation entry. Declaring a missing
public template fails with its expected filename; write that public file or
use inline `content`.

## Grow by ownership

For a repository with several targets, a centralized tree is easy to inspect:

```text
secrets/
  shared/
    registry-token.age
  servers/
    web/database-password.age
    worker/queue-password.age
templates/
  services/web.env.template
  services/worker.env.template
```

For a repository already organized around modules, colocating files often makes
changes easier to review:

```text
hosts/server/
  default.nix
  secrets/database-password.age
  templates/database.conf.template
shared/
  registry.nix
  secrets/registry-token.age
  templates/registry.conf.template
```

Configure the first target's directories once:

```nix
nixSeal = {
  secretDirectory = "hosts/server/secrets";
  sharedSecretDirectory = "shared/secrets";
  templateDirectory = "hosts/server/templates";
  secrets.database-password = { };
  secrets.registry-token.shared = true;
  templates = [ "database.conf" ];
};
```

An individual secret's repository-relative `source` overrides its directory.
A template's explicit `source` or inline `content` overrides its named file.
This supports existing filenames and public templates beside their consumer
module without copying files into a prescribed tree. All directory settings
are relative to `repositoryRoot`, not the importing module or shell directory.

Shared Nix modules can own common declarations, and targets can import them.
nix-seal does not need to discover those modules or prescribe their filenames.
Use lowercase stable names and `/` for namespaces when needed. For example,
`templates."services/web.env" = { };` selects `templates/services/web.env.template`.

Use the intended output filename, including its format extension, followed by
`.template`: `app.toml.template`, `settings.json.template`, or `service.env.template`.
For conventionally extensionless files, use names such as `ssh_config.template`
or `allowed_signers.template`. nix-seal preserves dots in declared names and does
not guess a format or search for alternative extensions.

When renaming an existing public file, keep its logical name and set an explicit
source, for example `templates.app = ./templates/app.env.template;`. This keeps
the application's runtime path stable. New configurations can use
`templates = [ "app.env" ];` and `config.nixSeal.templates."app.env".path` directly.

## Decide what should be shared

Keep one ciphertext per independently authorized and rotated value. Reuse that
file when consumers need the same value and canonical recipient policy. Each
target can still assign its own runtime owner, permissions, and service actions.
If recipients or rotation requirements differ, use separate files even when
their initial values happen to match. A directory named `shared` grants no access.

Share public templates when their syntax is identical. Different targets can
bind the same placeholder to different ciphertexts. A shared template does not
make those ciphertexts shared. Keep a target-specific template with its target
when its syntax differs; avoid making one large conditional template describe
unrelated applications.

Keep an entire settings bundle encrypted when its field names or structure are
private, or when all values share one access and rotation policy. Split fields
when independent reuse or access control warrants it. Templates insert literal
bytes; they do not automatically escape the destination configuration language.

## Keep runtime state outside the source tree

Commit canonical ciphertext, public templates, and public Nix declarations.
Private identities, signing keys, plaintext, editor workspaces, and retained
prompt answers belong outside the checkout and Nix store. Ciphertext caches
are generated state, not another canonical source tree. Use the platform's
cache and protected runtime defaults unless its deployment requires overrides.

Reorganize ciphertext by moving the encrypted bytes and updating `source` or
the directory options. Preserve IDs when the logical secret is unchanged.
Because plans bind ciphertext source paths, export fresh plans and provision
matching signed target artifacts before deployment. Retain previous ciphertext
cache generations for rollback. Public template moves with unchanged content
still need evaluation so consumers and plans are checked together.

The layout adds no recursive directory scan or independent inventory. Evaluation
reads declared ciphertexts and public templates; the Rust implementation retains
its bounded template validation and runtime rendering. See the
[authoring guide](nix-authoring.md) for setup and creation commands.
