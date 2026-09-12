# Start with nix-seal

nix-seal delivers encrypted secrets to NixOS, nix-darwin, and Home Manager
configurations. It keeps public policy in the configuration, ciphertext in the
repository, and decrypted values in restricted runtime storage.

The project is pre-release. It has not received the independent audit required
for 1.0 and is not ready for production secrets. Read the
[security status](../README.md#security-status) and [roadmap](../ROADMAP.md)
before deciding whether to evaluate it.

## Choose a path

| You need to… | Read |
| --- | --- |
| Declare a disposable value in a Nix configuration | [Nix authoring](nix-authoring.md) |
| Understand where public files and ciphertext belong | [Storage layout](storage-layout.md) |
| Provision, rotate, or recover access | [Operational runbooks](runbooks.md) |
| Inspect an existing secret-manager layout | [Migration inspection](../README.md#migration-inspection) |
| Evaluate the implementation's trust assumptions | [Security policy](../SECURITY.md) and the implementation specification |
| Understand release artifacts and verification | [Release controls](release.md) |

## What happens to a secret

1. Public declarations name the value, its authorized consumers, and policy.
2. An authorized author encrypts a value. The repository retains ciphertext.
3. Provisioning prepares target-specific signed artifacts under that policy.
4. Activation verifies the artifact and delivers the plaintext to its runtime
   location with the configured permissions.

The [README](../README.md) explains activation phases, delivery modes, template
substitution, and platform-specific storage. A successful build does not prove
that target identities, provisioning, or runtime storage are ready for activation.

## Evaluate with disposable data

Use a temporary test environment and a value that has no real authority. Follow
the complete authoring setup, then exercise creation, provisioning, activation,
rotation, and recovery. Keep private identities outside the Nix store and Git.
Do not copy an example public key as your own trust configuration.

Before using any secret manager for an important workload, understand how you
would recover from a lost identity and how to remove a compromised recipient.
The runbooks describe nix-seal's mechanisms; your own backup and recovery process
still needs a real test.

Existing users of sops-nix or agenix should compare the authoring, provisioning,
recovery, and platform workflows before migrating. Migration inspection commands
are not proof that every behavior of another provider transfers unchanged.
