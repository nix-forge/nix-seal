# shellcheck shell=bash
XDG_RUNTIME_DIR="/run/user/$(@pkgs_coreutils@/bin/id -u)"
export XDG_RUNTIME_DIR
@pkgs_systemd@/bin/systemctl --user show-environment >/dev/null
