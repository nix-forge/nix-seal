self:
{ config, lib, ... }:
let
  cfg = config.nixSeal;
  embeddedHomeManagerUsers =
    if builtins.hasAttr "home-manager" config then
      builtins.attrNames (config."home-manager".users or { })
    else
      [ ];
  bootPhases = [
    "users"
    "activation"
    "services"
  ];
  runtimeArguments =
    command:
    [
      (lib.getExe cfg.package)
      "__darwin-runtime"
      command
      "--root"
      cfg.darwin.volatileRuntime.root
      "--size"
      cfg.darwin.volatileRuntime.size
    ]
    ++ lib.concatMap (user: [
      "--user"
      user
    ]) embeddedHomeManagerUsers;
  prepareArguments = runtimeArguments "prepare";
  prepare = lib.escapeShellArgs prepareArguments;
  activateArguments =
    spec:
    if cfg.darwin.volatileRuntime.enable then
      runtimeArguments "activate"
      ++ [
        "--spec"
        (toString spec)
        "--identity"
        cfg.identityFile
      ]
    else
      [
        (lib.getExe cfg.package)
        "activate"
        "--spec"
        (toString spec)
        "--identity"
        cfg.identityFile
      ];
  activate = spec: lib.escapeShellArgs (activateArguments spec);
in
{
  imports = [
    ((import ./shared.nix) {
      inherit self;
      targetKind = "darwin";
      runtimeDirectory = "/private/var/run/nix-seal/system";
      serviceManager = "launchd-system";
      serviceExecutable = "/bin/launchctl";
      supportsServiceCredentials = false;
      serviceCredentialConfig = _: { };
      homeManagerRuntimeIdentity = false;
    })
  ];
  options.nixSeal.darwin.volatileRuntime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use a root-managed tmpfs for nix-seal plaintext runtime generations.";
    };
    root = lib.mkOption {
      type = lib.types.str;
      default = "/private/var/run/nix-seal";
      readOnly = true;
      description = "Fixed shared Darwin tmpfs mount root in macOS's canonical /private/var namespace.";
    };
    size = lib.mkOption {
      type = lib.types.strMatching "[1-9][0-9]*[mMgG]";
      default = "256m";
      description = "Bounded total capacity of the Darwin nix-seal tmpfs.";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      nixSeal.runtimeStorage = lib.mkDefault (
        if cfg.darwin.volatileRuntime.enable then "volatile-tmpfs" else "persistent"
      );
      assertions = [
        {
          assertion = !(cfg.activationSpecs ? partitioning);
          message = "nixSeal partitioning-phase secrets require installer provisioning and cannot run in nix-darwin activation";
        }
        {
          assertion =
            !(cfg.activationSpecs ? users)
            || lib.all (secret: secret.owner == "root" && secret.group == "wheel") (
              builtins.attrValues (lib.filterAttrs (_: secret: secret.phase == "users") cfg.secrets)
            );
          message = "nixSeal users-phase secrets must be owned by root:wheel until macOS accounts exist";
        }
        {
          assertion =
            !(cfg.activationSpecs ? users)
            || lib.all (template: template.owner == "root" && template.group == "wheel") (
              builtins.attrValues (lib.filterAttrs (_: template: template.phase == "users") cfg.templates)
            );
          message = "nixSeal users-phase templates must be owned by root:wheel until macOS accounts exist";
        }
      ];
      # nix-darwin activation snippets have a fixed phase order and do not
      # support NixOS-style `deps`. Prepare the mount before any activation,
      # materialize normal system state in the main activation phase, and run
      # service work after Home Manager has installed its user-level state.
      system.activationScripts = {
        preActivation.text = lib.mkAfter (lib.optionalString cfg.darwin.volatileRuntime.enable prepare);
        extraActivation.text = lib.mkAfter (
          lib.concatStringsSep "\n" (
            lib.optional (cfg.activationSpecs ? users) (activate cfg.activationSpecs.users)
            ++ lib.optional (cfg.activationSpecs ? activation) (activate cfg.activationSpecs.activation)
          )
        );
        postActivation.text = lib.mkAfter (
          lib.optionalString (cfg.activationSpecs ? services) (activate cfg.activationSpecs.services)
        );
      };
      launchd.daemons =
        lib.optionalAttrs cfg.darwin.volatileRuntime.enable {
          nix-seal-runtime.serviceConfig = {
            Label = "io.nix-seal.runtime";
            ProgramArguments = prepareArguments;
            RunAtLoad = true;
            ProcessType = "Background";
          };
        }
        // lib.listToAttrs (
          lib.concatMap (
            phase:
            lib.optional (builtins.hasAttr phase cfg.activationSpecs) {
              name = "nix-seal-${phase}";
              value.serviceConfig = {
                Label = "io.nix-seal.${phase}";
                ProgramArguments = activateArguments cfg.activationSpecs.${phase};
                RunAtLoad = true;
                ProcessType = "Background";
              };
            }
          ) bootPhases
        );
      warnings =
        lib.optional (!cfg.darwin.volatileRuntime.enable)
          "macOS nix-seal plaintext runtime is persistent; enable nixSeal.darwin.volatileRuntime for tmpfs storage";
    })
    {
      nixSeal.deploymentTargets = lib.mkAfter (
        lib.concatMap (
          user: config.home-manager.users.${user}.nixSeal.deploymentTargets or [ ]
        ) embeddedHomeManagerUsers
      );
      # Check every cache before preparing our runtime or entering the ordinary
      # nix-darwin activation phases, including hosts with only home secrets.
      system.activationScripts.preActivation.text = lib.mkIf (cfg.deploymentTargets != [ ]) (
        lib.mkBefore (
          let
            check =
              destination:
              let
                command = lib.escapeShellArgs (
                  lib.optionals (destination.user != null) [
                    "/usr/bin/sudo"
                    "-H"
                    "-u"
                    destination.user
                    "--"
                  ]
                  ++ [
                    (lib.getExe cfg.package)
                    "readiness"
                  ]
                  ++ lib.concatMap (spec: [
                    "--spec"
                    (toString spec)
                  ]) destination.specs
                );
              in
              lib.optionalString (destination.specs != [ ]) ''
                if ! ${command}; then readiness_failed=1; fi
              '';
          in
          ''
            readiness_failed=0
            ${lib.concatMapStringsSep "\n" check cfg.deploymentTargets}
            if [ "$readiness_failed" -ne 0 ]; then
              echo "nix-seal: prepare this configuration before retrying activation; nix-seal runtime preparation has not run." >&2
              echo "nix-seal: use '${lib.getExe cfg.package} prepare --deployment ${cfg.deploymentFile} --identity /path/to/admin.agekey --signing-key /path/to/release.key'." >&2
              echo "nix-seal: replace the key paths, review the dry run, then repeat with --execute. Add --administrator-host when the keys are remote." >&2
              exit 1
            fi
          ''
        )
      );
    }
  ];
}
