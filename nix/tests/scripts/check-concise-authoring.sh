# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
nix-seal check --nix-plan @concise_planFile@
touch "$out"
