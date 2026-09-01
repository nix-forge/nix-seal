{
  self,
  system,
  pkgs,
}:
let
  # A real VM test complements module evaluation and the Rust runtime tests.
  # Every private identity and secret value is generated inside the guest, so
  # the Nix evaluation graph, store, test derivation, and host never contain a
  # plaintext fixture or a private key.
  nixSeal = self.packages.${system}.nix-seal;
in
pkgs.testers.nixosTest {
  name = "nix-seal-runtime-activation";

  nodes.machine = { pkgs, ... }: {
    environment.systemPackages = [
      nixSeal
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];
    systemd.services.nix-seal-test = {
      description = "nix-seal VM credential consumer";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential = "database-password:/run/nix-seal/current/app/token";
        ExecStart = pkgs.replaceVarsWith {
          name = "nix-seal-test-service";
          src = ./scripts/nix-seal-test-service.sh;
          isExecutable = true;
          replacements = {
            bash = "${pkgs.bash}/bin/bash";
            cat = "${pkgs.coreutils}/bin/cat";
          };
        };
      };
    };
    virtualisation.memorySize = 1024;
    system.stateVersion = "26.05";
  };

  testScript = builtins.readFile ./scripts/runtime-vm-test.py;
}
