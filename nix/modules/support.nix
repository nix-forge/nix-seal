{ lib, pkgs }: {
  # Home Manager does not supply the NixOS `utils` module argument.
  inherit
    (import (pkgs.path + "/nixos/lib/utils.nix") {
      inherit lib pkgs;
      config = { };
    })
    escapeSystemdExecArgs
    ;

  groupCredentials =
    bindings:
    lib.mapAttrs (_: map (binding: "${binding.name}:${binding.path}")) (
      lib.groupBy (binding: lib.removeSuffix ".service" binding.unit) bindings
    );
}
