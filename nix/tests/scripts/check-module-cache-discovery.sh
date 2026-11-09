# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
jq -e -f @filter1@ @configuration_config_nixSeal_activationSpec@ >/dev/null
touch "$out"
