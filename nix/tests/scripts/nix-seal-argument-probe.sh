# shellcheck shell=bash
set -eu
test "$1" = @pkgs_lib_escapeShellArg_literalArgument@
test "$2" = /run
