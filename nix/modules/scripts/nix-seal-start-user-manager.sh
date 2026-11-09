# shellcheck shell=bash
set -eu
uid="$(@pkgs_coreutils@/bin/id -u -- @lib_escapeShellArg_user@)"
exec @pkgs_systemd@/bin/systemctl start "user@$uid.service"
