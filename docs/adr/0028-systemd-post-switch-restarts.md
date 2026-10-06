# ADR 0028: Skip inactive systemd units during post-switch restarts

Status: accepted

## Context

NixOS can run nix-seal's secret activation before systemd has loaded a newly
declared unit. A post-switch `try-restart` for that unit can fail even though
NixOS will start it later in the same switch. The failure leaves nix-seal's
pending-action marker in place and blocks the next activation.

## Decision

Before each systemd `restartUnits` action, ask the same system or user manager
whether the unit is active. Restart an active unit with `try-restart`. Skip a
unit when `is-active` reports inactive or unknown (exit status 3 or 4). Treat
other query failures and failed restarts as service-action failures. Keep
`reloadUnits` and launchd actions unchanged.

This preserves the existing retry behavior for actions that actually fail.
Skipping a unit that has not started leaves its first start to the normal
NixOS or Home Manager service activation. A systemd unit in the failed state
is also non-active, matching `try-restart` semantics.

## Verification

The runtime regression test covers inactive, unknown, active, and unexpected
query results. The Rust workspace and Nix flake checks validate the change.
