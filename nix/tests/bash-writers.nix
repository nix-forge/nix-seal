{ pkgs }:
let
  inherit (pkgs) lib;
  writeBashTemplate = (import ../lib/writers.nix { inherit lib; }).writeBashTemplate {
    inherit pkgs;
  };
  expected = "quotes: '\" dollar: $HOME backslash: \\";
  template = pkgs.writeText "writer.sh.in" ''
    #!@bash@
    set -euo pipefail
    # Literal dollar signs and a trailing backslash are intentional test data.
    # shellcheck disable=SC2016,SC1003
    printf '%s\n' @value@ "$@"
  '';
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
  alias = writeBashTemplate {
    name = "alias-probe";
    src = pkgs.writeText "alias-body.sh" ''
      printf '%s\n' "''${0##*/}"
    '';
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
  bash-runtime-activation = pkgs.runCommand "bash-runtime-activation" { } ''
    DRY_ACTIVATE=1 ${activation}
    test ! -e events
    DRY_ACTIVATE=0 ${activation}
    printf '%s\n' mount prepare > expected
    cmp expected events
    rm events
    if DRY_ACTIVATE=0 ${failedMount}; then
      echo "Activation continued after a failed mount" >&2
      exit 1
    fi
    test ! -e events
    touch "$out"
  '';
  bash-template-writer =
    assert bin.meta.mainProgram == "writer-probe";
    assert libexec.meta.mainProgram == "writer-probe";
    pkgs.runCommand "bash-template-writer" { inherit expected; } ''
      for script in ${lib.getExe bin} ${single} ${libexec}/libexec/writer-probe; do
        test -x "$script"
        test "$(grep -c '^#!' "$script")" = 1
        test "$(head -n 1 "$script")" = '#! ${lib.getExe pkgs.bashNonInteractive}'
        "$script" 'argument with spaces' > actual
        printf '%s\n' "$expected" 'argument with spaces' > expected-output
        cmp actual expected-output
        "$script" "" $'line\nbreak' -- -n > actual
        printf '%s\n' "$expected" "" $'line\nbreak' -- -n > expected-output
        cmp actual expected-output
      done
      test "$(${lib.getExe relaxed})" = continued
      # Building a program that exits nonzero proves validation doesn't run it.
      test -x ${lib.getExe parseOnly}
      # The Nix workload launcher dispatches by the invoked symlink's name.
      ln -s ${alias} writer-alias
      test "$(./writer-alias)" = writer-alias
      touch "$out"
    '';
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
