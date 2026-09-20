# ADR 0027: Secret-scoped target-artifact bindings

Status: accepted; artifact v3 and cache-address v3 implemented

## Context

Artifact v2 authenticated every target ciphertext against the complete plan and
complete target-policy projection. That was fail-closed, but it made unrelated
changes operationally expensive: adding or removing another secret, changing a
target tag, changing a template, or changing a Nix store path for a service
manager forced every artifact for the target to be prepared again. The target
could retain valid ciphertext, but readiness reported it as unusable. Repeated
pre-switch failures were especially confusing for root-owned system caches and
embedded Home Manager caches.

The complete plan remains authoritative for activation-document projection,
target selection, templates, service actions, pending-action retries, and
runtime generation identity. An artifact itself does not need to be rebound to
unrelated policy data when the artifact's ciphertext and authorization inputs
are unchanged.

## Decision

Artifact v3 adds `artifactPolicyHash`. It is a domain-separated BLAKE3 hash of
the canonical `nix-seal.secret-artifact-policy.v1` projection for exactly one
target and secret. The projection includes:

- target ID, kind, system, username, recipient identity, and recipient;
- the selected secret's source path and ciphertext hash;
- delivery mode, activation phase, runtime ownership/mode, and approval keys
  and threshold.

It deliberately excludes other secrets, templates, target tags, generators,
service actions, and their Nix store executable paths. A change in an excluded
field cannot change this target ciphertext's decryption recipient, source
binding, runtime policy, or approval rule. The canonical source ciphertext
hash remains part of the projection and is independently checked against Git.

`planHash` and `targetPolicyHash` remain signed manifest metadata for provenance
and diagnostics. They are still used by the activation document and runtime
generation/pending-action protocol. They are no longer artifact authorization
bindings. Artifact verification, cache addressing, preparation reuse, and GC
use `artifactPolicyHash` plus the source, target, recipient, secret, generation,
signature, and ciphertext bindings.

The manifest payload type, signature namespace, and deterministic cache address
are versioned to v3. Existing v2 envelopes and addresses are not accepted by
the new implementation. A one-time preparation is therefore required after
upgrading; old cache entries remain ciphertext-only candidates and can be
handled by normal cache GC. Subsequent unrelated plan changes reuse matching
verified artifacts. Changes to a selected secret's policy, source ciphertext,
target recipient, approval policy, or other included input still require
preparation.

Readiness reports the specific “different secret policy” reason, states that
activation was not attempted, and prints a dry-run preparation command. For a
saved default it uses the stable bare command. For an explicitly selected
configuration it prints a copyable `--flake` selector instead of requiring the
user to find a Nix store path. The `--deployment` option remains available for
advanced exact-built recovery. The command explicitly says that preparation
updates only the ciphertext cache and that earlier generations are retained for
rollback.

## Security considerations

The narrower hash does not trust cache filenames or unsigned metadata. The
target recomputes the projection from its installed public plan, recalculates
the ciphertext hash, reconstructs the v3 address, verifies the signed manifest
and approval threshold, and only then decrypts. A cache or transport cannot
choose an artifact-policy hash that the target accepts. Full activation
projection verification continues to reject stale templates, service actions,
phase declarations, and target metadata before runtime materialization.

The design intentionally preserves invalidation for changes that can alter the
selected secret's bytes, recipient, permissions, lifecycle phase, or approval
authority. It does not treat artifact generation as credential rotation; the
application value must still be rotated explicitly when required.

## Verification

Regression coverage proves that unrelated target metadata remains ready and is
reused, while a selected secret runtime-policy change reprovisions and retains
the earlier cache generation. Cache GC applies the same secret-scoped binding.
Nix module evaluation also checks that integrated Home Manager service actions
use the stable operating-system `systemctl` path.
