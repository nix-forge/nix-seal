# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @pkgs_replaceVars_scripts_module_evaluation_check_py_py_pkgs_@
touch "$out"
