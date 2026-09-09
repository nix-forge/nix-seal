{ inputs, lib, ... }:
let
  administratorCatalogType = import ./catalog.nix { inherit lib; };
in
{
  options.flake.nixSeal = lib.mkOption {
    type = lib.types.submodule {
      options.administrators = lib.mkOption {
        type = administratorCatalogType;
        default = { };
        description = "Public administrator catalogs used by nix-seal target modules.";
      };
    };
    default = { };
    description = "Public nix-seal policy metadata. Private identities and plaintext never belong here.";
  };

  config.perSystem = { system, ... }: {
    packages.nix-seal = inputs.nix-seal.packages.${system}.nix-seal;
  };
}
