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
  (
    (import ../lib/render-text.nix) ./scripts/nix-seal-store-scan.sh {
      scripts_check_store_scan_sh = ./scripts/check-store-scan.sh;
      scripts_assert_no_store_secret_sh = ./scripts/assert-no-store-secret.sh;
    }
  )
