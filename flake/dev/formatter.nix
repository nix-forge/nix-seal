{ inputs, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt.programs = {
    actionlint.enable = true;
    yamlfmt = {
      enable = true;
      settings.formatter.max_line_length = 100;
    };
    yamllint = {
      enable = true;
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

    deadnix.enable = true;
    statix.enable = true;
    nixfmt = {
      enable = true;
      width = 100;
      strict = true;
    };
    nixf-diagnose = {
      enable = true;
      autoFix = false;
    };

    shfmt.enable = true;
    shellcheck.enable = true;
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
}
