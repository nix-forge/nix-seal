# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
(
  unset XDG_RUNTIME_DIR
  @home_home_activation_nixSeal_data@
  test "$XDG_RUNTIME_DIR" = "/run/user/$(@pkgs_coreutils@/bin/id -u)"
  export XDG_RUNTIME_DIR="$TMPDIR/custom-runtime"
  @home_home_activation_nixSealServices_data@
  test "$XDG_RUNTIME_DIR" = "$TMPDIR/custom-runtime"
)
