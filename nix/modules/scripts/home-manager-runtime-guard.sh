# shellcheck shell=bash
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  echo "nix-seal: XDG_RUNTIME_DIR is required for Linux Home Manager activation" >&2
  exit 1
fi
