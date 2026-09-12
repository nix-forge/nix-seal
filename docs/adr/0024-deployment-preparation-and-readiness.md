# Deployment preparation and readiness

Status: accepted

Configuration changes can invalidate signed artifacts before any secret value
changes. Activation must continue to reject those artifacts, but operators need
to discover the problem before a system switch stops services. Readiness now uses
the same artifact selection and verification as activation. NixOS runs it through
`system.preSwitchChecks` for system and embedded home targets, under each cache
owner. Home Manager checks before its write boundary. Activation repeats the
verification because readiness cannot reserve cache state or prevent expiry.
Generated checks pass the public deployment description and whether it came from
the flake's saved default to readiness. A default failure prints the stable bare
preparation command; a previous or explicitly selected generation prints a
shell-quoted exact-built recovery command. JSON reports expose the same command
to deployment wrappers.

The modules expose a public deployment description containing target IDs, plans,
activation specifications, cache destinations, and cache owners. A project may
save `flake.nixSeal.defaultConfiguration`; bare `prepare` uses the current flake's
saved selector, while `--flake <ref>#<configuration>` remains an override and
`--deployment` remains exact-built recovery. No hostname, username, or sole
candidate is selected implicitly. `prepare` validates a complete
batch before creating artifacts, reuses matching verified artifacts, and imports
ciphertext under each destination owner. Preparation and installation do not
activate a configuration. Interrupted installation can be retried without deleting
previous cache generations or re-encrypting already prepared artifacts.

An optional administrator SSH host receives bounded canonical plans and canonical
ciphertext. Private keys stay on that host. The target independently verifies the
returned signed artifacts against its original plans before any privileged import.
SSH arguments are quoted as individual shell words. Transfers use strict JSON with
bounded base64 ciphertext, private staging directories, no archive extraction,
and a five-minute subprocess deadline. Imported artifacts still pass ordinary
cache validation and final activation verification. Transport is not an approval
mechanism. The selected repository/configuration and administrator executable
remain trusted code inputs.

`doctor` distinguishes valid policy from artifact readiness and exits nonzero
when required artifacts are absent. The existing JSON schema gains additive
`planValid`, `ready`, and per-target readiness fields; `ok` now also requires
readiness. Candidate rejection reasons are public diagnostics, not assertions
that an unverified envelope is authentic. Neither signature bindings nor approval
thresholds change. Automatic preparation creates single-signer artifacts;
threshold policies can reuse fully approved artifacts and otherwise require the
existing explicit approval workflow.
