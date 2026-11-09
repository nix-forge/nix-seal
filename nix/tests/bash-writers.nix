{ pkgs }:
let
  inherit (pkgs) lib;
  writeBashTemplate = (import ../lib/writers.nix { inherit lib; }).writeBashTemplate {
    inherit pkgs;
  };
  expected = "quotes: '\" dollar: $HOME backslash: \\";
  template = pkgs.writeText "writer.sh.in" (builtins.readFile ./scripts/writer.sh.in);
  scriptFor =
    dir:
    writeBashTemplate {
      name = "writer-probe";
      src = template;
      inherit dir;
      replacements = {
        bash = lib.getExe pkgs.bash;
        value = lib.escapeShellArg expected;
      };
    };
  bin = scriptFor "bin";
  single = scriptFor null;
  libexec = scriptFor "libexec";
  bodyFor =
    body:
    writeBashTemplate {
      name = "body-probe";
      dir = "bin";
      src = pkgs.writeText "body.sh.in" "#!@bash@\n@body@\n";
      replacements = {
        bash = lib.getExe pkgs.bash;
        inherit body;
      };
    };
  relaxed = bodyFor "false\nprintf '%s\\n' continued";
  parseOnly = bodyFor "exit 71";
  pathReplacementSource = ./bash-writers.nix;
  pathReplacement = writeBashTemplate {
    name = "path-replacement-probe";
    dir = "bin";
    src = pkgs.writeText "path-replacement.sh.in" (builtins.readFile ./scripts/path-replacement.sh.in);
    replacements = {
      bash = lib.getExe pkgs.bash;
      source = pathReplacementSource;
    };
  };
  isolatedRuntime = writeBashTemplate {
    name = "isolated-runtime-probe";
    dir = "bin";
    src = pkgs.writeText "isolated-runtime.sh.in" (builtins.readFile ./scripts/isolated-runtime.sh.in);
    replacements = {
      bash = lib.getExe pkgs.bash;
      hello = lib.escapeShellArg (lib.getExe pkgs.hello);
      runtimePath = lib.escapeShellArg (lib.makeBinPath [ pkgs.hello ]);
    };
    runtimeInputs = [ pkgs.hello ];
    inheritPath = false;
  };
  alias = writeBashTemplate {
    name = "alias-probe";
    src = pkgs.writeText "invocation-name-probe.sh" (
      builtins.readFile ./scripts/invocation-name-probe.sh
    );
    replacements = { };
  };
  activationFor =
    mountRuntime:
    writeBashTemplate {
      name = "runtime-activation-probe";
      src = ../modules/scripts/runtime-activation.sh;
      replacements = {
        bash = lib.getExe pkgs.bash;
        inherit mountRuntime;
        prepare = "printf '%s\\n' prepare >> events";
      };
    };
  activation = activationFor "printf '%s\\n' mount >> events";
  failedMount = activationFor "false";
in
{
  bash-runtime-activation = pkgs.runCommand "bash-runtime-activation" { } (
    (import ../lib/render-text.nix) ./scripts/check-runtime-activation-ordering.sh {
      inherit activation;
      inherit failedMount;
    }
  );
  bash-template-writer =
    assert bin.meta.mainProgram == "writer-probe";
    assert libexec.meta.mainProgram == "writer-probe";
    pkgs.runCommand "bash-template-writer" { inherit expected; } (
      (import ../lib/render-text.nix) ./scripts/bash-template-writer.sh {
        lib_getExe_bin = lib.getExe bin;
        inherit single;
        inherit libexec;
        lib_getExe_pkgs_bashNonInteractive = lib.getExe pkgs.bashNonInteractive;
        lib_getExe_relaxed = lib.getExe relaxed;
        lib_getExe_parseOnly = lib.getExe parseOnly;
        lib_getExe_pathReplacement = lib.getExe pathReplacement;
        lib_getExe_isolatedRuntime = lib.getExe isolatedRuntime;
        inherit alias;
      }
    );
  bash-template-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = bodyFor "if then";
    expectedBuilderExitCode = 2;
    expectedBuilderLogEntries = [ "syntax error" ];
  };
  bash-template-invalid-lint = pkgs.testers.testBuildFailure' {
    drv = bodyFor "printf '%s\\n' $1";
    expectedBuilderLogEntries = [ "SC2086" ];
  };
}
