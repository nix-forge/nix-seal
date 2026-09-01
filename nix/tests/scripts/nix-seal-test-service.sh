#!@bash@
# shellcheck shell=bash
set -euo pipefail
umask 077
@cat@ "$CREDENTIALS_DIRECTORY/database-password" >/run/nix-seal-service-observed
