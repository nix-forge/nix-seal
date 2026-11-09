{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    { config, pkgs, ... }:
    let
      checkPython = pkgs.buildPackages.python3.withPackages (
        ps:
        lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isLinux [
          # Module conversion enables metadata checks that the application's
          # placeholder project version does not satisfy.
          (ps.toPythonModule (
            pkgs.buildPackages.nixos-test-driver.overridePythonAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ ps.pyprojectVersionPatchHook ];
            })
          ))
        ]
      );
      pythonCompile =
        (import ../../nix/lib/writers.nix { inherit (pkgs) lib; }).writeBashTemplate
          { pkgs = pkgs.buildPackages; }
          {
            name = "nix-seal-python-compile";
            src = ./scripts/python-compile.sh;
            replacements = {
              bash = lib.getExe pkgs.buildPackages.bash;
              mktemp = "${pkgs.buildPackages.coreutils}/bin/mktemp";
              python = lib.getExe pkgs.buildPackages.python3;
              rm = lib.getExe' pkgs.buildPackages.coreutils "rm";
            };
          };
    in
    {
      pre-commit = {
        check.enable = true;
        settings = {
          package = pkgs.buildPackages.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              # treefmt schedules its formatters; avoid many concurrent wrappers.
              require_serial = true;
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
              pass_filenames = true;
            };
            pinact = {
              enable = true;
              name = "pinact";
              entry = "${lib.getExe pkgs.buildPackages.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            cargo-fmt = {
              enable = true;
              entry = "cargo fmt --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.buildPackages.cargo
                pkgs.buildPackages.rustfmt
              ];
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            cargo-fmt-fuzz = {
              enable = true;
              name = "Rust fuzz formatting";
              entry = "cargo fmt --manifest-path fuzz/Cargo.toml --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.buildPackages.cargo
                pkgs.buildPackages.rustfmt
              ];
              always_run = true;
              pass_filenames = false;
              after = [ "cargo-fmt" ];
            };
            cargo-check = {
              enable = true;
              entry = "cargo check --workspace --all-targets --all-features --locked";
              language = "system";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-fmt" ];
            };
            cargo-fmt-legacy = {
              enable = true;
              name = "Rust legacy migration formatting";
              entry = "cargo fmt --manifest-path legacy/Cargo.toml --all -- --check";
              language = "system";
              extraPackages = [
                pkgs.buildPackages.cargo
                pkgs.buildPackages.rustfmt
              ];
              always_run = true;
              pass_filenames = false;
              after = [ "cargo-fmt-fuzz" ];
            };
            cargo-clippy = {
              enable = true;
              name = "cargo clippy";
              entry = "cargo clippy --workspace --all-targets --all-features --locked -- -D warnings";
              language = "system";
              extraPackages = [
                pkgs.buildPackages.cargo
                pkgs.buildPackages.clippy
              ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-check" ];
            };
            cargo-test = {
              enable = true;
              entry = "cargo test --workspace --all-targets --all-features --locked";
              language = "system";
              extraPackages = [ pkgs.buildPackages.cargo ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-clippy" ];
            };
            cargo-deny = {
              enable = true;
              entry = "cargo deny --locked check";
              language = "system";
              extraPackages = [ pkgs.buildPackages.cargo-deny ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-test" ];
            };
            cargo-deny-legacy = {
              enable = true;
              entry = "cargo deny --manifest-path legacy/Cargo.toml --config legacy/deny.toml --locked check";
              language = "system";
              extraPackages = [ pkgs.buildPackages.cargo-deny ];
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "cargo-deny" ];
            };
            ruff-format = {
              enable = true;
              entry = "${lib.getExe pkgs.buildPackages.ruff} format --check --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.buildPackages.ruff} check --no-fix --config pyproject.toml .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff-format" ];
            };
            ty = {
              enable = true;
              # Use the real driver types on Linux; Darwin permits that platform import.
              entry = "${lib.getExe pkgs.buildPackages.ty} check --project . --python ${lib.getExe checkPython}";
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
              excludes = [
                ".*\\.age$"
                "^vendor/age/"
                # Preserve the pinned upstream notice bytes, including its final blank line.
                "^vendor/LICENSE-APACHE$"
              ];
            };
            trim-trailing-whitespace = {
              enable = true;
              excludes = [
                ".*\\.age$"
                "^vendor/age/"
              ];
            };
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
              excludes = [
                ".*\\.age$"
                "^vendor/age/"
              ];
            };
            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;
            detect-private-keys = {
              enable = true;
              # Public upstream test keys; every byte is pinned by the source
              # inventory test. Never use these identities for real secrets.
              excludes = [
                "^vendor/age/src/ssh/identity\\.rs$"
                "^vendor/age/tests/testdata/empty_recipient_body_key\\.txt$"
              ];
            };
            check-case-conflicts.enable = true;
            check-added-large-files.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable = {
              enable = true;
              excludes = [
                # Interpreter placeholders are resolved before execution.
                ".*\\.sh\\.in$"
                ".*\\.rs$"
              ];
            };
            fix-byte-order-marker = {
              enable = true;
              excludes = [ "^vendor/age/" ];
            };
            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;
            editorconfig-checker = {
              enable = true;
              excludes = [ "^vendor/age/" ];
            };
            typos = {
              enable = true;
              # The upstream hook's generated empty [default] table overrides configPath.
              entry = "${lib.getExe pkgs.buildPackages.typos} --config .typos.toml --force-exclude";
            };
            zizmor = {
              enable = true;
              args = [ "--persona=pedantic" ];
            };
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              entry = "${lib.getExe pkgs.buildPackages.gitleaks} git --pre-commit --staged --redact --no-banner";
              # The complete entry owns its arguments; do not append hook defaults.
              args = [ ];
              language = "system";
              always_run = true;
              pass_filenames = false;
            };
            flake-checker.enable = true;

            nix-flake-check = {
              enable = true;
              # Use the Nix installation that supplies the daemon and its settings.
              # Injecting nixpkgs' CLI rejects Determinate's schemas/settings.
              # Realize filtered sources as well as checking their outputs. A dry-run
              # check can reference an unmaterialized cleanSource on a fresh tree.
              entry = "nix flake check";
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
