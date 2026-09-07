#!@bash@
# shellcheck shell=bash
set -euo pipefail

# Direct invocations must honor dry activation too, including preparation.
if [ "${DRY_ACTIVATE:-0}" = 1 ]; then
  exit 0
fi

@mountRuntime@
@prepare@
