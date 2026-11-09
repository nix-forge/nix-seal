{ inputs, lib, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = { pkgs, ... }: {
    treefmt.settings.global.excludes = [ "vendor/age/**" ];
    treefmt.programs = {
      actionlint = {
        enable = true;
        priority = 200;
      };
      yamlfmt = {
        enable = true;
        priority = 100;
        settings.formatter.max_line_length = 100;
      };
      yamllint = {
        enable = true;
        priority = 300;
        settings = {
          extends = "default";
          rules = {
            # Repository YAML uses one document per file.
            document-start = "disable";
            # yamlfmt emits one space before inline comments.
            comments.min-spaces-from-content = 1;
            # GitHub Actions uses the YAML 1.2 key `on`.
            truthy.check-keys = false;
            line-length = {
              max = 160;
              level = "error";
            };
          };
        };
      };

      deadnix = {
        enable = true;
        priority = 100;
      };
      statix = {
        enable = true;
        priority = 200;
      };
      nixfmt = {
        enable = true;
        width = 100;
        strict = true;
        priority = 300;
      };
      nixf-diagnose = {
        enable = true;
        autoFix = false;
        priority = 400;
      };

      shfmt = {
        enable = true;
        indent_size = 2;
        priority = 100;
      };
      shellcheck = {
        enable = true;
        priority = 200;
      };
      ruff-check.enable = true;
      ruff-format.enable = true;
      rustfmt.enable = true;
      taplo.enable = true;
      rumdl-check.enable = true;
      typos = {
        enable = true;
        configFile = ".typos.toml";
      };
      prettier = {
        enable = true;
        excludes = [
          "*.md"
          "*.yaml"
          "*.yml"
        ];
        settings.proseWrap = "always";
      };
      keep-sorted.enable = true;
      just.enable = true;
    };
    treefmt.settings.formatter = {
      # Spelling suggestions require review before changing runtime identifiers.
      typos.options = lib.mkForce [
        "--force-exclude"
        "--config"
        ".typos.toml"
      ];
      nix-template = {
        command = "${
          pkgs.buildPackages.writeShellApplication {
            name = "format-nix-template";
            runtimeInputs = [
              pkgs.buildPackages.nixfmt
              pkgs.buildPackages.coreutils
            ];
            text = builtins.readFile ./scripts/format-nix-template.sh;
          }
        }/bin/format-nix-template";
        includes = [ "*.nix.in" ];
      };
      shfmt.includes = [ "*.sh.in" ];
      shellcheck.includes = [ "*.sh.in" ];
    };
  };
}
