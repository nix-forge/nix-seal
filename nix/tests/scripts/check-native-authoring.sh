# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
nix-seal check --nix-plan @native_planFile@
nix-seal template check --plan @native_planFile@
jq -e -f @filter1@ @native_planFile@ >/dev/null
jq -e -f @filter2@ @native_bootstrapPlanFile@ >/dev/null
touch "$out"
