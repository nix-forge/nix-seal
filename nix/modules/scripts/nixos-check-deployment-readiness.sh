# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
readiness_failed=0
@lib_concatMapStringsSep_n_check_cfg_deploymentTargets@
if [ "$readiness_failed" -ne 0 ]; then
  echo "nix-seal: preparation is required before switching; services have not been stopped." >&2
  exit 1
fi
