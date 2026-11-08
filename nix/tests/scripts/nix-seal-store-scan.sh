# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
bash @scripts_check_store_scan_sh@ @scripts_assert_no_store_secret_sh@
touch "$out"
