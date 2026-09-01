{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    { config, pkgs, ... }:
    let
      pythonCompile = pkgs.replaceVarsWith {
        name = "nix-seal-python-compile";
        src = ./scripts/python-compile.sh;
        isExecutable = true;
        replacements = {
          bash = lib.getExe pkgs.bash;
          mktemp = "${pkgs.coreutils}/bin/mktemp";
          python = lib.getExe pkgs.python3;
          rm = lib.getExe' pkgs.coreutils "rm";
        };
      };
    in
    {
      pre-commit = {
        check.enable = pkgs.stdenv.hostPlatform.isDarwin;
        settings = {
          package = pkgs.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
              pass_filenames = true;
            };
            pinact = {
              enable = true;
              name = "pinact";
              entry = "${lib.getExe pkgs.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            cargo-fmt = {
              enable = true;
              entry = "cargo fmt --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.rustfmt
              ];
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            cargo-check = {
              enable = true;
              entry = "cargo check --workspace --all-targets";
              language = "system";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-fmt" ];
            };
            cargo-clippy = {
              enable = true;
              name = "cargo clippy";
              entry = "cargo clippy --workspace --all-targets -- -D warnings";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.clippy
              ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-check" ];
            };
            cargo-test = {
              enable = true;
              entry = "cargo test --workspace";
              language = "system";
              extraPackages = [ pkgs.cargo ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-clippy" ];
            };
            cargo-deny = {
              enable = true;
              entry = "cargo deny check";
              language = "system";
              extraPackages = [ pkgs.cargo-deny ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-test" ];
            };
            ruff-format = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} format --check --config pyproject.toml nix/tests/scripts";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} check --no-fix --config pyproject.toml nix/tests/scripts";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff-format" ];
            };
            ty = {
              enable = true;
              # NixOS test drivers inject their globals at runtime; the VM test
              # itself validates that dynamic contract.
              entry = "${lib.getExe pkgs.ty} check --project . --ignore unresolved-reference --python ${lib.getExe pkgs.python3}";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };
            python-compile = {
              enable = true;
              name = "python syntax";
              entry = toString pythonCompile;
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ty" ];
            };

            end-of-file-fixer = {
              enable = true;
              excludes = [ ".*\\.age$" ];
            };
            trim-trailing-whitespace = {
              enable = true;
              excludes = [ ".*\\.age$" ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              excludes = [ ".*\\.age$" ];
            };
            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;
            detect-private-keys.enable = true;
            check-case-conflicts.enable = true;
            check-added-large-files.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable = {
              enable = true;
              excludes = [ ".*\\.rs$" ];
            };
            fix-byte-order-marker.enable = true;
            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;
            editorconfig-checker = {
              enable = true;
              excludes = [
                "^LICENSE-.*$"
                "^docs/runbooks\\.md$"
                "^crates/nix-seal-cli/tests/authoring\\.rs$"
              ];
            };
            typos = {
              enable = true;
              settings.configPath = ".typos.toml";
            };
            zizmor = {
              enable = true;
              args = [
                "--persona=pedantic"
                "--min-severity=medium"
              ];
            };
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --staged --redact --no-banner";
              language = "system";
              always_run = true;
              pass_filenames = false;
            };
            flake-checker.enable = true;

            nix-flake-check = {
              enable = true;
              entry = "${lib.getExe pkgs.nix} flake check --no-build";
              language = "system";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };
    };
}
