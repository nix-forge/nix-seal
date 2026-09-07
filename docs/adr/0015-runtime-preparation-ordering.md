# ADR 0015: Preserve runtime mounts and order user preparation

Status: accepted

Repeated NixOS activation must preserve the mounted secret generations. Mounting
another tmpfs over `/run/nix-seal` hides the active generation and any existing
runtime identities. Mount the configured filesystem only when the path is not
already a mountpoint, then run the existing runtime validator in both cases.
An existing mount is not evidence that it is safe: preparation still rejects
an invalid filesystem, mount options, ownership, or permissions.

Prepare the system runtime before users-phase secrets and account creation,
without resolving embedded Home Manager user names. A separate activation
script prepares those users' private roots after the standard `users` script.
This permits first deployment to an account that does not exist yet while
retaining the requirement that users-phase secret outputs belong to root.

At boot, embedded Home Manager system services require runtime preparation and
run after it. User managers also run after it and want it, so lingering users
receive the same ordering without stopping login sessions whenever runtime
preparation restarts. The secret activation runtime continues to validate its
own destination; user-manager ordering does not grant access or bypass a failed
runtime validation.

NixOS dry activation must not mount or prepare the runtime. The runtime
activation helper also honors `DRY_ACTIVATE=1` when invoked directly. Home
Manager calls activation and legacy Darwin runtime cleanup through its `run`
helper, so Home Manager dry runs print those commands without executing them.

This changes lifecycle ordering, not cryptography, runtime ownership, or the
trusted administrator and kernel boundary. No options or secret paths migrate.
Regression tests cover repeated mount preparation and identity preservation,
preparation before account creation, unsafe existing mounts, and dry activation.
