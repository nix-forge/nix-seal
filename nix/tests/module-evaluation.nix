{
  inputs,
  self,
  system,
  pkgs,
}:
let
  lib = inputs.nixpkgs.lib;
  targetId = "host/test";
  secretId = "service/token";
  source = "nix-seal.example.toml";
  identities = {
    administrator = {
      kind = "administrator";
      public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
    };
    release = {
      kind = "signer";
      public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
    };
    target = {
      kind = "target";
      public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
    };
  };
  target = {
    kind = "nixOs";
    inherit system;
    identity = "target";
  };
  approvalPolicies.release = {
    threshold = 1;
    signers = [ "release" ];
  };
  scopedCatalog = {
    administrators = {
      alice = {
        identities = {
          administrator = {
            kind = "administrator";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          recovery = {
            kind = "recovery";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          release = {
            kind = "signer";
            public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
          };
        };
        approvalPolicies.release = {
          threshold = 1;
          signers = [ "release" ];
        };
        defaultApprovalPolicy = "release";
      };
      bob = {
        identities.administrator = {
          kind = "administrator";
          public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
        };
      };
    };
  };
  scopedRepositoryRoot = ./fixtures;
  configuration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          inherit
            targetId
            identities
            target
            approvalPolicies
            ;
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = ../../.;
          secrets.${secretId} = {
            inherit source;
            administrators = [ "administrator" ];
            approvalPolicy = "release";
          };
        };
      }
    ];
  };
  scopedConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
        };
      }
    ];
  };
  standaloneHomeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.homeManagerModules.default
      {
        home.username = "tester";
        home.homeDirectory = "/home/tester";
        home.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/home/tester/.cache/nix-seal";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
          secrets."service-token" = {
            phase = "services";
            source = "secrets/alice/users/tester/nix-access-tokens.age";
            serviceCredentials = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              {
                unit = "example.service";
                name = "service-token";
              }
            ];
          };
        };
      }
    ];
  };
  overrideConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          targetId = "host/custom";
          secretScope = "systems/custom";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
        };
      }
    ];
  };
in
{
  plan-v2 =
    assert
      (builtins.fromJSON (
        self.lib.mkPlan {
          inherit identities approvalPolicies;
          targets.${targetId} = target;
          secrets.${secretId} = {
            inherit source;
            consumers = [ targetId ];
            administrators = [ "administrator" ];
            approvalPolicy = "release";
            runtime = {
              owner = "root";
              group = "root";
              mode = "0400";
            };
          };
          repositoryRoot = ../../.;
        }
      )).schema == "nix-seal.plan.v2";
    pkgs.runCommand "nix-seal-plan-v2" { } "touch $out";
  module-cache-discovery =
    pkgs.runCommand "nix-seal-module-cache-discovery" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          .schema == "nix-seal.activation.v2" and
          .artifactCacheRoot == "/var/lib/nix-seal/cache/v1" and
          (.artifacts | length) == 1 and
          (.artifacts[0] | has("ciphertext") | not) and
          (.artifacts[0] | has("envelope") | not)
        ' ${configuration.config.nixSeal.activationSpec} >/dev/null
        touch "$out"
      '';
  scoped-target-and-administrator-projection =
    assert scopedConfiguration.config.nixSeal.targetId == "host/nixos/fixture";
    assert scopedConfiguration.config.nixSeal.secretScope == "hosts/nixos/fixture";
    assert
      scopedConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/hosts/nixos/fixture/nix-access-tokens";
    assert
      scopedConfiguration.config.nixSeal.secrets."nix-access-tokens".source
      == "secrets/alice/hosts/nixos/fixture/nix-access-tokens.age";
    pkgs.runCommand "nix-seal-scoped-target-and-administrator-projection" { } "touch $out";
  scoped-plan-administrator-projection =
    pkgs.runCommand "nix-seal-scoped-plan-administrator-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          (.identities | has("alice/administrator")) and
          (.identities | has("alice/recovery")) and
          (.identities | has("alice/release")) and
          ((.identities | has("bob/administrator")) | not) and
          (.approvalPolicies | has("alice/release")) and
          (.secrets | has("alice/hosts/nixos/fixture/nix-access-tokens")) and
          (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].administrators == ["alice/administrator", "alice/recovery"]) and
          (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].consumers == ["host/nixos/fixture"])
        ' ${scopedConfiguration.config.nixSeal.planFile} >/dev/null
        touch "$out"
      '';
  derived-home-target =
    assert standaloneHomeConfiguration.config.nixSeal.targetId == "home/tester/fixture";
    assert standaloneHomeConfiguration.config.nixSeal.secretScope == "users/tester";
    assert
      standaloneHomeConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/users/tester/nix-access-tokens";
    assert
      standaloneHomeConfiguration.config.nixSeal.secrets."nix-access-tokens".source
      == "secrets/alice/users/tester/nix-access-tokens.age";
    assert
      lib.any (
        warning:
        lib.hasInfix "standalone Home Manager target for tester on Linux" warning
        && lib.hasInfix "$XDG_RUNTIME_DIR/nix-seal" warning
      ) standaloneHomeConfiguration.config.warnings == pkgs.stdenv.hostPlatform.isLinux;
    pkgs.runCommand "nix-seal-derived-home-target" { } "touch $out";
  home-service-activation-order =
    assert builtins.elem "nixSeal"
      standaloneHomeConfiguration.config.home.activation.nixSealServices.after;
    assert
      builtins.elem "setupLaunchAgents" standaloneHomeConfiguration.config.home.activation.nixSealServices.after
      == pkgs.stdenv.hostPlatform.isDarwin;
    pkgs.runCommand "nix-seal-home-service-activation-order" { } "touch $out";
  service-credential-policy-projection =
    pkgs.runCommand "nix-seal-service-credential-policy-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          .secrets["alice/users/tester/service-token"].runtime.restartUnits
          == ${if pkgs.stdenv.hostPlatform.isLinux then "[\"example.service\"]" else "[]"}
        ' ${standaloneHomeConfiguration.config.nixSeal.planFile} >/dev/null
        touch "$out"
      '';
  explicit-scope-overrides =
    assert overrideConfiguration.config.nixSeal.targetId == "host/custom";
    assert overrideConfiguration.config.nixSeal.secretScope == "systems/custom";
    assert
      overrideConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/systems/custom/nix-access-tokens";
    pkgs.runCommand "nix-seal-explicit-scope-overrides" { } "touch $out";
  legacy-explicit-identity-mode =
    assert configuration.config.nixSeal.administrator == null;
    assert configuration.config.nixSeal.secrets.${secretId}.id == secretId;
    pkgs.runCommand "nix-seal-legacy-explicit-identity-mode" { } "touch $out";
}
