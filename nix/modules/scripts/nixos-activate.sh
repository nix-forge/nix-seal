# shellcheck shell=bash
@lib_getExe_cfg_package@ activate \
  --spec @spec@ \
  --identity @lib_escapeShellArg_cfg_identityFile@
