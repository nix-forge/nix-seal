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
  literalArgument = "/run/keys/test identity%literal$dollar'quote";
  inherit
    (import ../modules/support.nix {
      inherit pkgs;
      inherit (pkgs) lib;
    })
    escapeSystemdExecArgs
    ;
  argumentProbe = pkgs.writeShellScript "nix-seal-argument-probe" ''
    set -eu
    test "$1" = ${pkgs.lib.escapeShellArg literalArgument}
    test "$2" = /run
  '';
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
      (pkgs.writeShellScriptBin "assert-no-store-secret" (
        builtins.readFile ./scripts/assert-no-store-secret.sh
      ))
    ];
    systemd.services.nix-seal-argument-probe = {
      serviceConfig = {
        Type = "oneshot";
        ExecStart =
          escapeSystemdExecArgs [
            argumentProbe
            literalArgument
          ]
          + " \"%t\"";
      };
    };
    systemd.services.nix-seal-test = {
      description = "nix-seal VM credential consumer";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredential = "database-password:/run/nix-seal/current/app/token";
        ExecStart =
          (import ../lib/writers.nix { inherit (pkgs) lib; }).writeBashTemplate { inherit pkgs; }
            {
              name = "nix-seal-test-service";
              src = ./scripts/nix-seal-test-service.sh;
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
