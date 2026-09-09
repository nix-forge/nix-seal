{ self, ... }: {
  # Portable lint has one required Linux owner. Native checks remain complete
  # as package, module, and runtime checks are added or removed.
  flake = {
    lintChecks = builtins.mapAttrs (_: checks: { inherit (checks) pre-commit treefmt; }) self.checks;
    ciChecks = builtins.mapAttrs (
      system: checks: removeAttrs checks (builtins.attrNames self.lintChecks.${system})
    ) self.checks;
  };
}
