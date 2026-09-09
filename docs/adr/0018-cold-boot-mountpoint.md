# ADR 0018: Create the volatile mountpoint during cold boot

Status: accepted

NixOS stage-2 activation can run before systemd creates the mountpoint for the
declared volatile runtime filesystem. Calling `mount` by its fstab path then
fails because the directory is absent. Later runtime services can recover,
but the initial system activation has already failed to materialize secrets.

When the runtime is not mounted, create its directory before mounting the
declared filesystem. Retain the existing mountpoint check so repeated
activation preserves mounted generations. Preparation still validates the
filesystem, mount options, ownership, and permissions before writing secrets.
Dry activation creates neither a directory nor a mount.

The generated activation regression check models mount's requirement that its
destination exist. It covers an absent directory, repeated activation with an
existing generation, and dry activation. It does not replace the runtime's
filesystem validation or claim to test an actual kernel mount.

This repairs the lifecycle described in [ADR 0015](0015-runtime-preparation-ordering.md).
It changes no cryptography, secret format, or trust boundary.
