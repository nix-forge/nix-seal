{ inputs, ... }:
let
  inherit (inputs.nixpkgs) lib;
  manifest = fromTOML (builtins.readFile ../Cargo.toml);
  inherit (manifest.workspace.package) version;

  exportSchema = what: valid: {
    version = 1;
    doc = "Validate the shape of exported ${what}; behavioral checks are in checks.";
    inventory = output: {
      evalChecks.isAttributeSet = builtins.isAttrs output;
      children = builtins.mapAttrs (_: value: {
        inherit what;
        evalChecks.isValidExport = valid value;
      }) output;
    };
  };
  moduleSchema = exportSchema "Nix module" (
    value: builtins.isFunction value || builtins.isAttrs value
  );

  packageFor = system: packageVariantFor system false;
  legacyPackageFor = system: packageVariantFor system true;
  packageVariantFor =
    system: legacy:
    let
      pkgs = import inputs.nixpkgs (import ./platform-args.nix system);
      # CI, docs and Nix module edits do not change the Rust build. Keep schemas,
      # test fixtures and Cargo configuration in the explicitly declared source.
      src = import ./rust-source.nix {
        inherit lib;
        inherit legacy;
        root = ../.;
      };
    in
    pkgs.rustPlatform.buildRustPackage {
      pname = if legacy then "nix-seal-legacy" else "nix-seal";
      inherit version;
      inherit src;
      cargoRoot = lib.optionalString legacy "legacy";
      buildAndTestSubdir = lib.optionalString legacy "legacy";
      cargoLock.lockFile = if legacy then "${src}/legacy/Cargo.lock" else "${src}/Cargo.lock";
      cargoLock.outputHashes."i18n-config-0.4.8" = "sha256-ujGHZLORc4e5lXu7i10jtBKS/Hcipuz3mwZ4+V+pJ9k=";
      buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
      nativeCheckInputs = [
        pkgs.age
        pkgs.openssh
        pkgs.rage
      ];
      preCheck =
        (import ../nix/lib/render-text.nix) ./scripts/configure-interop-tests.sh {
          inputs_cctv = inputs.cctv;
        }
        + lib.optionalString legacy ''
          export NIX_SEAL_NORMAL_TEST_BINARY=${packageFor system}/bin/nix-seal
        '';
      postInstall = builtins.readFile ./scripts/install-vendored-age-notices.sh;
      cargoBuildFlags = [
        "--package"
        (if legacy then "nix-seal-legacy" else "nix-seal")
      ];
      cargoTestFlags =
        if legacy then
          [
            "--test"
            "rsa_migration"
          ]
        else
          [ "--workspace" ];
      meta = {
        description = "Security-first secret management for Nix";
        homepage = "https://github.com/nix-forge/nix-seal";
        license = with lib.licenses; [
          mit
          asl20
        ];
        mainProgram = if legacy then "nix-seal-legacy" else "nix-seal";
        platforms = lib.platforms.linux ++ lib.platforms.darwin;
      };
    };

  documentationFor =
    system:
    let
      pkgs = import inputs.nixpkgs (import ./platform-args.nix system);
      nixSeal = packageFor system;
    in
    pkgs.runCommand "nix-seal-documentation-${version}"
      {
        nativeBuildInputs = [
          nixSeal
          pkgs.mandoc
        ];
      }
      (
        (import ./../nix/lib/render-text.nix) ./scripts/install-documentation-and-completions.sh {
          docs_nix_seal_1 = ../docs/nix-seal.1;
        }
      );

  documentationSiteFor =
    system:
    let
      pkgs = import inputs.nixpkgs (import ./platform-args.nix system);
      mkdocs = pkgs.python3.withPackages (python: [ python.mkdocs ]);
    in
    pkgs.runCommand "nix-seal-documentation-site-${version}" { nativeBuildInputs = [ mkdocs ]; } (
      (import ../nix/lib/render-text.nix) ./scripts/build-documentation-site.sh {
        docs = ../docs;
        site = ../site;
      }
    );
in
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs (import ./platform-args.nix system);
      nixSeal = packageFor system;
      documentation = documentationFor system;
      nixSealLegacy = legacyPackageFor system;
      documentationSite = documentationSiteFor system;
    in
    {
      packages = {
        default = nixSeal;
        nix-seal = nixSeal;
        nix-seal-legacy = nixSealLegacy;
        inherit documentation;
        documentation-site = documentationSite;
      };

      apps = {
        default = {
          type = "app";
          program = "${nixSeal}/bin/nix-seal";
          meta.description = nixSeal.meta.description;
        };
        nix-seal = {
          type = "app";
          program = "${nixSeal}/bin/nix-seal";
          meta.description = nixSeal.meta.description;
        };
        nix-seal-legacy = {
          type = "app";
          program = "${nixSealLegacy}/bin/nix-seal-legacy";
          meta.description = "Opt-in offline legacy RSA migration";
        };
      };

      checks = {
        nix-seal = nixSeal;
        nix-seal-legacy = nixSealLegacy;
        inherit documentation;
        store-scan = import ../nix/tests/store-scan.nix { inherit pkgs; };
        bootstrap-terminal =
          pkgs.runCommand "nix-seal-bootstrap-terminal" { nativeBuildInputs = [ pkgs.python3 ]; }
            (
              (import ../nix/lib/render-text.nix) ./scripts/check-bootstrap-terminal.sh {
                nix_tests_scripts_bootstrap_tty_py = ../nix/tests/scripts/bootstrap_tty.py;
                inherit nixSeal;
              }
            );
      }
      // lib.optionalAttrs (system == "x86_64-linux") { documentation-site = documentationSite; }
      // import ../nix/tests/bash-writers.nix { inherit pkgs; }
      // import ../nix/tests/module-evaluation.nix {
        inherit inputs system pkgs;
        inherit (inputs) self;
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && system == "x86_64-linux") {
        runtime-mount-vm = import ../nix/tests/runtime-mount-vm.nix {
          inherit inputs system pkgs;
          inherit (inputs) self;
        };
        runtime-vm = import ../nix/tests/runtime-vm.nix {
          inherit system pkgs;
          inherit (inputs) self;
        };
      };
      devShells.docs = pkgs.mkShellNoCC {
        packages = [ (pkgs.python3.withPackages (python: [ python.mkdocs ])) ];
      };
    };

  flake = {
    schemas = inputs.flake-schemas.exportedSchemas // {
      ciChecks = inputs.flake-schemas.exportedSchemas.checks;
      lintChecks = inputs.flake-schemas.exportedSchemas.checks;
      flakeModules = moduleSchema;
      homeManagerModules = moduleSchema;
      lib = exportSchema "library function or schema constant" (
        value: builtins.isFunction value || builtins.isString value || builtins.isPath value
      );
    };
    nixosModules.default = import ../nix/modules/nixos.nix inputs.self;
    darwinModules.default = import ../nix/modules/darwin.nix inputs.self;
    homeManagerModules.default = import ../nix/modules/home-manager.nix inputs.self;
    flakeModules.default = import ../nix/modules/flake-module.nix;
    flakeModules.nix-config-framework = import ../nix/modules/nix-config-framework.nix;
    lib = (import ../nix/lib { inherit lib; }) // {
      packagesFor = platform: {
        default = packageFor platform;
        nix-seal = packageFor platform;
        nix-seal-legacy = legacyPackageFor platform;
        documentation = documentationFor platform;
        documentation-site = documentationSiteFor platform;
      };
    };
  };
}
