# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export DRY_RUN=1
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
run() {
  printf 'skipped\n' >>"$TMPDIR/skipped"
}
@standaloneHomeConfiguration_config_home_activation_nixSeal_d@
@standaloneHomeConfiguration_config_home_activation_nixSealSe@
test "$(wc -l <"$TMPDIR/skipped")" -eq 2
test ! -e "$XDG_RUNTIME_DIR"
touch "$out"
