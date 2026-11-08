# shellcheck shell=bash
# XDG_RUNTIME_DIR is supplied by the activation environment.
# shellcheck disable=SC2154
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(@coreutils@/bin/id -u)}"
