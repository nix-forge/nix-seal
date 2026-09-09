# ADR 0016: Encode literal service arguments for systemd

Status: accepted

Activation service commands use the pinned NixOS `escapeSystemdExecArgs` utility
so spaces, quotes, percent signs, and dollar signs in configured paths reach the
CLI unchanged. Shell activation continues to use shell escaping, and Darwin
`ProgramArguments` remains an argument list.

Standalone Home Manager deliberately preserves `%t` only in its internally
constructed runtime-root argument, which systemd expands to the user's runtime
directory. Configured identity and runtime paths receive literal encoding;
encoding the complete command would break the intentional runtime specifier.
Home Manager imports the utility from its package set's NixOS support library
because that module system does not supply the NixOS `utils` argument.

Credential grouping uses a shared `groupBy` transformation that preserves input
order within each unit. Duplicate-binding validation, activation ordering,
runtime permissions, and dry-run behavior retain their existing contracts.
