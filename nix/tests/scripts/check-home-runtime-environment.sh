# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
@exercise_true@
@exercise_false@
if (
  unset XDG_RUNTIME_DIR
  @standaloneHomeConfiguration_config_home_activation_nixSeal_d@
); then
  echo "standalone activation accepted a missing runtime environment" >&2
  exit 1
fi
