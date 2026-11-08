# shellcheck shell=bash
# Mounting an already mounted tmpfs hides every existing secret generation.
# The runtime validator below still rejects an unsafe existing mount.
if ! @pkgs_util_linux@/bin/mountpoint --quiet -- @lib_escapeShellArg_cfg_linux_volatileRuntime_root@; then
  # Stage-2 activation can precede systemd's mount-directory creation.
  @pkgs_coreutils@/bin/mkdir -p -- @lib_escapeShellArg_cfg_linux_volatileRuntime_root@
  @pkgs_util_linux@/bin/mount -- @lib_escapeShellArg_cfg_linux_volatileRuntime_root@
fi
