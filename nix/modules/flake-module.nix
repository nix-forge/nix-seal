{ inputs, lib, ... }:
let
  administratorCatalogType = import ./catalog.nix { inherit lib; };
in
{
  options.flake.nixSeal = lib.mkOption {
    type = lib.types.submodule {
      options = {
        administrators = lib.mkOption {
          type = administratorCatalogType;
          default = { };
          description = "Public administrator catalogs used by nix-seal target modules.";
        };
        defaultConfiguration = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.addCheck lib.types.str (
              value:
              lib.any (prefix: lib.hasPrefix prefix value && value != prefix) [
                "nixosConfigurations."
                "darwinConfigurations."
                "homeConfigurations."
              ]
              && !(lib.hasInfix "\n" value)
              && !(lib.hasInfix "\r" value)
            )
          );
          default = null;
          example = "nixosConfigurations.workstation";
          description = "Configuration selected by nix-seal prepare when --flake has no attribute.";
        };
      };
    };
    default = { };
    description = "Public nix-seal policy and preparation metadata. Private identities, signing keys, and plaintext never belong here.";
  };

  config.perSystem = { system, ... }: {
    packages.nix-seal = inputs.nix-seal.packages.${system}.nix-seal;
  };
}
