{ pkgs }:
pkgs.runCommand "nix-seal-store-scan"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
    ];
  }
  ''
    bash ${./scripts/check-store-scan.sh} ${./scripts/assert-no-store-secret.sh}
    touch "$out"
  ''
