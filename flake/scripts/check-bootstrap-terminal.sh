# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @nix_tests_scripts_bootstrap_tty_py@ @nixSeal@/bin/nix-seal
touch "$out"
