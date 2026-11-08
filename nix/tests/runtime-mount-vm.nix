{
  inputs,
  self,
  system,
  pkgs,
}:
let
  # Evaluate the real activation module separately so the guest can exercise
  # its mount preparation before the target account exists, without needing
  # production ciphertext or keys.
  fixture = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      ({ lib, ... }: {
        options.home-manager.users = lib.mkOption {
          type = lib.types.attrs;
          default.tester.nixSeal = {
            enable = true;
            secrets.token.restartUnits = [ "example.service" ];
            templates.token = { };
          };
        };
        config = {
          system.stateVersion = "26.05";
          nixSeal = {
            enable = true;
            targetId = "host/test";
            target = {
              kind = "nixOs";
              inherit system;
              identity = "target";
            };
            identities.target = {
              kind = "target";
              public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
            };
            identityFile = "/run/keys/unused";
            artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
            repositoryRoot = ../../.;
            secrets.token.source = "nix-seal.example.toml";
          };
        };
      })
    ];
  };
in
pkgs.testers.nixosTest {
  name = "nix-seal-runtime-mount";
  nodes.machine = {
    environment.systemPackages = [ pkgs.git ];
    systemd.services.home-manager-tester.serviceConfig = {
      Type = "oneshot";
      User = "tester";
      ExecStartPre = fixture.config.systemd.services.home-manager-tester.serviceConfig.ExecStartPre;
      ExecStart = pkgs.writeShellScript "check-user-manager" (
        (import ../lib/render-text.nix) ./scripts/check-user-manager.sh {
          pkgs_coreutils = pkgs.coreutils;
          pkgs_systemd = pkgs.systemd;
        }
      );
    };
    virtualisation.fileSystems."/run/nix-seal" = fixture.config.fileSystems."/run/nix-seal";
    environment.etc."nix-seal-runtime-activation".source =
      fixture.config.system.activationScripts.nixSealRuntime.text;
    environment.etc."nix-seal-runtime-users".text =
      fixture.config.system.activationScripts.nixSealRuntimeUsers.text
        or fixture.config.systemd.services.nix-seal-runtime.serviceConfig.ExecStart;
    virtualisation.memorySize = 1024;
    system.stateVersion = "26.05";
  };
  testScript = builtins.readFile ./scripts/runtime_mount_vm_test.py;
}
