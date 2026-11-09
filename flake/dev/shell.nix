_: {
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
    in
    {
      devShells.default = pkgs.buildPackages.mkShellNoCC {
        inherit shellHook;
        LIBRARY_PATH = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "${pkgs.buildPackages.libiconv}/lib";
        NIX_LDFLAGS = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "-L${pkgs.buildPackages.libiconv}/lib";
        packages =
          enabledPackages
          ++ [ package ]
          ++ (with pkgs.buildPackages; [
            age
            actionlint
            cargo-audit
            cargo-deny
            cargo-fuzz
            cargo-nextest
            cargo-vet
            deadnix
            direnv
            editorconfig-checker
            gitleaks
            keep-sorted
            just
            nixd
            nixf-diagnose
            nixfmt
            osv-scanner
            pinact
            prettier
            prek
            (python3.withPackages (ps: [ ps.pytest ]))
            rumdl
            rage
            rustc
            clippy
            rust-analyzer
            rustfmt
            shellcheck
            shfmt
            statix
            taplo
            treefmt
            typos
            yamlfmt
            yamllint
            zizmor
          ])
          ++ pkgs.buildPackages.lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isDarwin [
            pkgs.buildPackages.libiconv
          ];
      };
    };
}
