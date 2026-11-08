# shellcheck shell=bash
# Activation/build supplies variables and functions.
# shellcheck disable=SC2154,SC2329
@runtimeSetup@
@runtimeGuard@
run @lib_getExe_cfg_package@ activate \
  --spec @spec@ \
  --identity @lib_escapeShellArg_cfg_identityFile@ \
  --runtime-root @runtimeRoot@
@cleanupLegacyDarwinRuntime@
