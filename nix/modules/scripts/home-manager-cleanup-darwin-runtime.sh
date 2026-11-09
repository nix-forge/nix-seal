# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
run @lib_getExe_cfg_package@ __darwin-runtime cleanup-persistent \
  --root @lib_escapeShellArg_config_home_homeDirectory_Library_Caches_@
