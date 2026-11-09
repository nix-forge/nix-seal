# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2034
if ! @command@; then readiness_failed=1; fi
