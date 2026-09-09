# ADR 0020: Prepare embedded user service managers

Status: accepted

An embedded Home Manager activation can refresh user service credentials during
boot, before any login has supplied a user bus or session environment. Requiring
each consumer to hardcode a UID and user-manager dependency makes nix-seal's
activation contract depend on local repairs.

For an enabled home with service actions or service credentials, the NixOS
module adds a root-owned pre-start command to its Home Manager unit. The command
resolves the configured account's current UID and starts `user@<uid>.service`.
Systemd executes that setup command as root; Home Manager and secret activation
still run as the profile owner. Volatile runtime preparation retains its
existing ordering. The module neither enables lingering nor changes accounts.

Integrated Linux Home Manager activation fills an absent XDG runtime directory
with `/run/user/<current-uid>`. An existing session value takes precedence.
Standalone Home Manager retains its requirement for a supplied XDG runtime
directory. Runtime mount validation, signed service actions, and activation
permissions remain unchanged.
