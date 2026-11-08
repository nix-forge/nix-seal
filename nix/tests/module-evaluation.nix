{
  inputs,
  self,
  system,
  pkgs,
}:
let
  lib = inputs.nixpkgs.lib;
  targetId = "host/test";
  literalIdentity = "/run/keys/test identity%literal$dollar'quote";
  encodedIdentity = ''"/run/keys/test identity%%literal$$dollar'quote"'';
  secretId = "service/token";
  source = "nix-seal.example.toml";
  identities = {
    administrator = {
      kind = "administrator";
      public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
    };
    release = {
      kind = "signer";
      public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
    };
    target = {
      kind = "target";
      public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
    };
  };
  target = {
    kind = "nixOs";
    inherit system;
    identity = "target";
  };
  approvalPolicies.release = {
    threshold = 1;
    signers = [ "release" ];
  };
  scopedCatalog = {
    administrators = {
      alice = {
        identities = {
          administrator = {
            kind = "administrator";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          recovery = {
            kind = "recovery";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          release = {
            kind = "signer";
            public = "nix-seal-ed25519-v1:bGfuLIxQvDrT8IMpu931WWcILSKDrDmaCJ8oPFyT3X4=";
          };
          bootstrap-authorizer = {
            kind = "authorizer";
            public = "nix-seal-ed25519-v1:hL79NFnL0cYSFuYdO+WRjQSHruyBznn7MGEIVJKMuOE=";
          };
        };
        approvalPolicies.release = {
          threshold = 1;
          signers = [ "release" ];
        };
        defaultApprovalPolicy = "release";
      };
      bob = {
        identities.administrator = {
          kind = "administrator";
          public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
        };
      };
    };
  };
  scopedRepositoryRoot = ./fixtures;
  customDirectoryConfiguration = scopedConfiguration.extendModules {
    modules = [ { nixSeal.secretDirectory = "hosts/shared"; } ];
  };
  sharedDirectoryConfiguration = scopedConfiguration.extendModules {
    modules = [
      {
        nixSeal = {
          sharedSecretDirectory = "modules/shared";
          secrets."nix-access-tokens".shared = true;
        };
      }
    ];
  };
  sharedHomeConfiguration = standaloneHomeConfiguration.extendModules {
    modules = [
      {
        nixSeal = {
          secretDirectory = "homes/shared";
          sharedSecretDirectory = "modules/shared";
          secrets."nix-access-tokens".shared = true;
        };
      }
    ];
  };
  explicitSourceConfiguration = sharedDirectoryConfiguration.extendModules {
    modules = [
      { nixSeal.secrets."nix-access-tokens".source = "hosts/shared/nix-access-tokens.age"; }
    ];
  };
  configuration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          inherit
            targetId
            identities
            target
            approvalPolicies
            ;
          identityFile = literalIdentity;
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = ../../.;
          secrets.${secretId} = {
            inherit source;
            administrators = [ "administrator" ];
            approvalPolicy = "release";
          };
        };
      }
    ];
  };
  scopedConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
        };
      }
    ];
  };
  bootstrapConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."first-token" = {
            source = "secrets/alice/hosts/nixos/fixture/first-token.age";
          };
        };
      }
    ];
  };
  standaloneHomeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      nixSealCatalog = scopedCatalog;
      nixSealDefaultConfiguration = "homeConfigurations.tester@fixture";
    };
    modules = [
      self.homeManagerModules.default
      {
        _module.args = {
          targetName = "fixture";
          configName = "tester@fixture";
        };
        home.username = "tester";
        home.homeDirectory = "/home/tester";
        home.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          identityFile = literalIdentity;
          artifactCacheRoot = "/home/tester/.cache/nix-seal";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
          secrets."service-token" = {
            phase = "services";
            source = "secrets/alice/users/tester/nix-access-tokens.age";
            serviceCredentials = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              {
                unit = "example.service";
                name = "service-token";
              }
            ];
          };
        };
      }
    ];
  };
  integratedHomeConfiguration = standaloneHomeConfiguration.extendModules {
    specialArgs = {
      nixSealDefaultConfiguration = "${
        if pkgs.stdenv.hostPlatform.isDarwin then "darwinConfigurations" else "nixosConfigurations"
      }.fixture-host";
      osConfig = {
        _module.specialArgs.configName = "fixture-host";
        nixSeal = {
          enable = true;
          linux.volatileRuntime.enable = false;
          darwin.volatileRuntime.enable = false;
        };
      };
    };
  };
  overrideConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog = scopedCatalog;
      targetName = "fixture";
    };
    modules = [
      self.nixosModules.default
      {
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          targetId = "host/custom";
          secretScope = "systems/custom";
          identityFile = "/run/keys/nix-seal-target";
          artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
          repositoryRoot = scopedRepositoryRoot;
          identities.target = {
            kind = "target";
            public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
          };
          secrets."nix-access-tokens" = { };
        };
      }
    ];
  };
  nativeConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      {
        networking.hostName = "native";
        system.stateVersion = "26.05";
        nixSeal = {
          enable = true;
          administrator = "alice";
          inherit (scopedCatalog) administrators;
          identityFile = "/run/keys/target";
          repositoryRoot = scopedRepositoryRoot;
          secretDirectory = "hosts/shared";
          identities.target = identities.target;
          secrets.nix-access-tokens = { };
          secrets.pending = { };
          templates.ready = "token={{nix-seal:nix-access-tokens}}\n";
          templates.from-file = ./fixtures/templates/token.conf;
          templates.named = { };
          templates.aliased = {
            content = "token={{nix-seal:token}}\n";
            placeholders.token = "nix-access-tokens";
          };
          templates.waiting = "token={{nix-seal:pending}}\n";
        };
      }
    ];
  };
  nativeHome =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.default
        {
          home.username = "tester";
          home.homeDirectory = "/home/tester";
          home.stateVersion = "26.05";
          nixSeal = {
            identities = identities // {
              bootstrap-authorizer = scopedCatalog.administrators.alice.identities.bootstrap-authorizer;
            };
            repositoryRoot = scopedRepositoryRoot;
            secrets = [ "token" ];
          };
        }
      ];
    }).config.nixSeal;
  nativeDarwinConfiguration = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      self.darwinModules.default
      {
        networking.hostName = "native";
        system.stateVersion = 6;
        nixSeal = {
          identities = identities // {
            bootstrap-authorizer = scopedCatalog.administrators.alice.identities.bootstrap-authorizer;
          };
          repositoryRoot = scopedRepositoryRoot;
          secrets = [ "token" ];
          templates.service = "{{nix-seal:token}}";
        };
      }
    ];
  };
  nativeDarwin = nativeDarwinConfiguration.config.nixSeal;
  native = nativeConfiguration.config.nixSeal;
  conciseConfiguration = lib.nixosSystem {
    inherit system;
    specialArgs = {
      nixSealCatalog.administrators.alice = scopedCatalog.administrators.alice;
      nixSealRepositoryRoot = scopedRepositoryRoot;
    };
    modules = [
      self.nixosModules.default
      {
        networking.hostName = "native";
        system.stateVersion = "26.05";
        nixSeal = {
          publicKey = identities.target.public;
          secretDirectory = "hosts/shared";
          secrets = [
            "nix-access-tokens"
            "pending"
            { pending.mode = lib.mkDefault "0600"; }
          ];
          templates = [
            "named"
            { inline = "{{nix-seal:nix-access-tokens}}"; }
          ];
        };
      }
      { nixSeal.secrets.pending.mode = "0400"; }
    ];
  };
  concise = conciseConfiguration.config.nixSeal;
  promoted =
    (nativeConfiguration.extendModules {
      modules = [ { nixSeal.secrets.pending.source = "hosts/shared/nix-access-tokens.age"; } ];
    }).config.nixSeal;
  templatePlanSucceeds =
    settings:
    (builtins.tryEval (
      builtins.deepSeq
        (nativeConfiguration.extendModules { modules = [ { nixSeal.templates.test = settings; } ]; })
        .config.nixSeal.planFile
        true
    )).success;

in
{
  darwin-boot-readiness =
    let
      configurations = {
        volatile = nativeDarwinConfiguration;
        persistent = nativeDarwinConfiguration.extendModules {
          modules = [ { nixSeal.darwin.volatileRuntime.enable = false; } ];
        };
      };
      arguments = lib.concatMapAttrs (
        mode: configuration:
        lib.mapAttrs' (
          name: daemon: lib.nameValuePair "${mode}-${name}" daemon.serviceConfig.ProgramArguments
        ) (lib.filterAttrs (name: _: lib.hasPrefix "nix-seal-" name) configuration.config.launchd.daemons)
      ) configurations;
      fixture = pkgs.writeText "darwin-boot-arguments.json" (
        builtins.unsafeDiscardStringContext (builtins.toJSON arguments)
      );
    in
    pkgs.runCommand "nix-seal-darwin-boot-readiness" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${./scripts/check_darwin_boot.py} ${fixture}
      touch "$out"
    '';
  darwin-deployment-readiness =
    let
      integrated = nativeDarwinConfiguration.extendModules {
        modules = [
          { nixSeal.secrets.token.source = "hosts/shared/nix-access-tokens.age"; }
          ({ lib, ... }: {
            options.home-manager.users = lib.mkOption {
              type = lib.types.attrs;
              default.tester = standaloneHomeConfiguration.config;
            };
          })
        ];
      };
      persistent = integrated.extendModules {
        modules = [ { nixSeal.darwin.volatileRuntime.enable = false; } ];
      };
      homeOnly = integrated.extendModules { modules = [ { nixSeal.enable = lib.mkForce false; } ]; };
      # Replace only executable paths; exercise the generated shell control flow.
      script =
        configuration:
        builtins.unsafeDiscardStringContext (
          lib.replaceStrings
            [ (lib.getExe configuration.config.nixSeal.package) "/usr/bin/sudo" ]
            [ "\"$PWD/nix-seal\"" "\"$PWD/sudo\"" ]
            configuration.config.system.activationScripts.preActivation.text
        );
    in
    pkgs.runCommand "nix-seal-darwin-deployment-readiness" { } (
      (import ../lib/render-text.nix) ./scripts/check-darwin-deployment-readiness.sh {
        pkgs_runtimeShell = pkgs.runtimeShell;
        pkgs_writeText_darwin_preactivation_script_integrated = pkgs.writeText "darwin-preactivation" (
          script integrated
        );
        pkgs_writeText_darwin_persistent_preactivation_script_persis = pkgs.writeText "darwin-persistent-preactivation" (
          script persistent
        );
        pkgs_writeText_darwin_home_only_preactivation_script_homeOnly = pkgs.writeText "darwin-home-only-preactivation" (
          script homeOnly
        );
        sudoFixture = pkgs.replaceVars ./scripts/sudo-fixture.sh.in {
          pkgs_runtimeShell = pkgs.runtimeShell;
        };
        nix_sealFixture = pkgs.replaceVars ./scripts/nix-seal-fixture.sh.in {
          pkgs_runtimeShell = pkgs.runtimeShell;
        };
      }
    );
  deployment-readiness =
    let
      expectedServiceExecutable =
        if pkgs.stdenv.hostPlatform.isLinux then
          "/run/current-system/sw/bin/systemctl"
        else
          "/bin/launchctl";
      integrated = configuration.extendModules {
        specialArgs = {
          configName = "fixture";
          nixSealDefaultConfiguration = "nixosConfigurations.fixture";
        };
        modules = [
          ({ lib, ... }: {
            options.home-manager.users = lib.mkOption {
              type = lib.types.attrs;
              default.tester = integratedHomeConfiguration.config;
            };
          })
        ];
      };
      destinations = integrated.config.nixSeal.deploymentTargets;
      preflight = integrated.config.system.preSwitchChecks.nixSealReadiness;
      preflightScript = pkgs.writeText "nixos-readiness-preflight" (
        builtins.unsafeDiscardStringContext (
          lib.replaceStrings
            [ (lib.getExe integrated.config.nixSeal.package) "${integrated.pkgs.util-linux}/bin/runuser" ]
            [ "\"$PWD/readiness-probe\"" "\"$PWD/runuser-probe\"" ]
            preflight
        )
      );
      nonDefaultHome = standaloneHomeConfiguration.extendModules {
        specialArgs.nixSealDefaultConfiguration = "nixosConfigurations.fixture";
      };
      homePreflightScript = pkgs.writeText "home-readiness-preflight" (
        builtins.unsafeDiscardStringContext (
          lib.replaceStrings
            [ (lib.getExe nonDefaultHome.config.nixSeal.package) ]
            [ ''"$PWD/readiness-probe"'' ]
            nonDefaultHome.config.home.activation.nixSealReadiness.data
        )
      );
    in
    assert
      map (destination: destination.target) destinations == [
        targetId
        "home/tester/fixture"
      ];
    assert (builtins.head destinations).user == null;
    assert (builtins.elemAt destinations 1).user == "tester";
    assert builtins.elem "writeBoundary"
      standaloneHomeConfiguration.config.home.activation.nixSealReadiness.before;
    pkgs.runCommand "nix-seal-deployment-readiness"
      {
        nativeBuildInputs = [
          self.packages.${system}.nix-seal
          pkgs.jq
        ];
      }
      (
        (import ../lib/render-text.nix) ./scripts/check-deployment-readiness.sh {
          pkgs_runtimeShell = pkgs.runtimeShell;
          inherit preflightScript;
          inherit homePreflightScript;
          integrated_config_nixSeal_deploymentFile = integrated.config.nixSeal.deploymentFile;
          lib_escapeShellArg_expectedServiceExecutable = lib.escapeShellArg expectedServiceExecutable;
          configuration_config_nixSeal_activationSpecs_activation =
            configuration.config.nixSeal.activationSpecs.activation;
          configuration_config_nixSeal_deploymentFile = configuration.config.nixSeal.deploymentFile;
          runuser_probeFixture = pkgs.replaceVars ./scripts/runuser-probe-fixture.sh.in {
            pkgs_runtimeShell = pkgs.runtimeShell;
          };
          readiness_probeFixture = pkgs.replaceVars ./scripts/readiness-probe-fixture.sh.in {
            pkgs_runtimeShell = pkgs.runtimeShell;
          };
        }
      );
  public-template-values =
    let
      templates = import ../lib/templates.nix { inherit lib; };
      raw = "{{nix-seal:nix-access-tokens}} {{public:key}} {{public:key}}\n";
      expected = "{{nix-seal:nix-access-tokens}} ssh-ed25519 fixture ssh-ed25519 fixture\n";
      withValues = nativeConfiguration.extendModules {
        modules = [
          {
            nixSeal.templates.public-example = {
              content = raw;
              publicValues.key = "ssh-ed25519 fixture";
            };
          }
        ];
      };
      rejects = content: values: !(builtins.tryEval (templates.renderPublic content values)).success;
    in
    assert templates.renderPublic raw { key = "ssh-ed25519 fixture"; } == expected;
    assert
      builtins.readFile withValues.config.nixSeal.templates.public-example.renderedSource == expected;
    assert
      builtins.attrNames withValues.config.nixSeal.templates.public-example.placeholders
      == [ "nix-access-tokens" ];
    assert rejects raw { };
    assert rejects raw {
      key = "value";
      unused = "unused";
    };
    assert rejects "{{public:invalid name}}" { };
    assert rejects raw { key = "{{nix-seal:pending}}"; };
    assert rejects raw { key = "{{public:other}}"; };
    assert rejects "{{public:key}}{nix-seal:pending}}" { key = "{"; };
    assert rejects (lib.concatStrings (lib.replicate 3 "{{public:key}}")) {
      key = lib.concatStrings (lib.replicate 1024 (lib.concatStrings (lib.replicate 1024 "x")));
    };
    assert templates.renderPublic "{{nix-seal:token}}" { } == "{{nix-seal:token}}";
    assert templates.renderPublic "{{public:value}}" { value = ""; } == "";
    pkgs.runCommand "nix-seal-public-template-values"
      { nativeBuildInputs = [ self.packages.${system}.nix-seal ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-public-template-values.sh {
          withValues_config_nixSeal_planFile = withValues.config.nixSeal.planFile;
        }
      );
  concise-authoring =
    let
      ambiguous = conciseConfiguration.extendModules {
        modules = [ { nixSeal.administrators = scopedCatalog.administrators; } ];
      };
      disabled = conciseConfiguration.extendModules { modules = [ { nixSeal.enable = false; } ]; };
      unscoped = conciseConfiguration.extendModules { modules = [ { nixSeal.administrator = null; } ]; };
    in
    assert concise.enable;
    assert !disabled.config.nixSeal.enable;
    assert
      !(conciseConfiguration.extendModules {
        modules = [
          {
            nixSeal.secrets = lib.mkForce { };
            nixSeal.templates = lib.mkForce { };
          }
        ];
      }).config.nixSeal.enable;
    assert concise.administrator == "alice";
    assert unscoped.config.nixSeal.administrator == null;
    assert !(builtins.tryEval ambiguous.config.nixSeal.administrator).success;
    assert concise.identityFile == "/etc/ssh/ssh_host_ed25519_key";
    assert concise.identities.target == identities.target;
    assert concise.placeholder.nix-access-tokens == "{{nix-seal:nix-access-tokens}}";
    assert !(concise.placeholder ? undeclared);
    assert
      (conciseConfiguration.extendModules {
        modules = [
          ({ config, ... }: {
            nixSeal.templates.interpolated = "TOKEN=${config.nixSeal.placeholder.nix-access-tokens}";
          })
        ];
      }).config.nixSeal.templates.interpolated.placeholders.nix-access-tokens.secret
      == "nix-access-tokens";
    assert concise.repositoryRoot == scopedRepositoryRoot;
    assert concise.secrets.pending.mode == "0400";
    assert
      builtins.attrNames concise.secrets == [
        "nix-access-tokens"
        "pending"
      ];
    assert
      builtins.attrNames concise.templates == [
        "inline"
        "named"
      ];
    assert concise.templates.named.placeholders.nix-access-tokens.secret == "nix-access-tokens";
    assert
      !(builtins.tryEval
        (conciseConfiguration.extendModules { modules = [ { nixSeal.secrets = [ "../outside" ]; } ]; })
        .config.nixSeal.secrets
      ).success;
    assert
      !(builtins.tryEval
        (conciseConfiguration.extendModules {
          modules = [ { nixSeal.identities.target.public = "conflicting-public-key"; } ];
        }).config.nixSeal.identities.target.public
      ).success;
    assert
      (conciseConfiguration.extendModules {
        modules = [ { nixSeal.secrets.nix-access-tokens.phase = "services"; } ];
      }).config.nixSeal.templates.named.phase == "services";
    assert
      !(builtins.tryEval
        (conciseConfiguration.extendModules {
          modules = [
            {
              nixSeal.secrets.nix-access-tokens.phase = "services";
              nixSeal.templates.mixed = "{{nix-seal:nix-access-tokens}}{{nix-seal:pending}}";
            }
          ];
        }).config.nixSeal.templates.mixed.phase
      ).success;
    pkgs.runCommand "nix-seal-concise-authoring"
      { nativeBuildInputs = [ self.packages.${system}.nix-seal ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-concise-authoring.sh {
          concise_planFile = concise.planFile;
        }
      );
  native-authoring =
    assert native.targetId == "host/nixos/native";
    assert native.templateDirectory == "templates";
    assert
      toString native.templates.named.source
      == toString (scopedRepositoryRoot + "/templates/named.template");
    assert
      !(builtins.tryEval
        (nativeConfiguration.extendModules { modules = [ { nixSeal.templateDirectory = "../outside"; } ]; })
        .config.nixSeal.templateDirectory
      ).success;
    assert
      !(builtins.tryEval
        (nativeConfiguration.extendModules { modules = [ { nixSeal.templates.absent = { }; } ]; })
        .config.nixSeal.templates.absent.source
      ).success;
    assert
      toString
        (nativeConfiguration.extendModules {
          modules = [
            {
              nixSeal.templateDirectory = "not-present";
              nixSeal.templates.named.source = ./fixtures/templates/token.conf;
            }
          ];
        }).config.nixSeal.templates.named.source == toString ./fixtures/templates/token.conf;
    assert nativeHome.targetId == "home/tester";
    assert nativeHome.enable;
    assert nativeHome.identityFile == "/home/tester/.ssh/id_ed25519";
    assert nativeHome.secrets.token.source == "secrets/token.age";
    assert nativeDarwin.targetId == "host/darwin/native";
    assert nativeDarwin.enable;
    assert nativeDarwin.identityFile == "/etc/ssh/ssh_host_ed25519_key";
    assert nativeDarwin.secrets.token.group == "wheel";
    assert nativeDarwin.templates.service.group == "wheel";
    assert native.secretScope == "hosts/nixos/native";
    assert native.artifactCacheRoot == "/var/lib/nix-seal/cache/v1";
    assert native.secrets.nix-access-tokens.source == "hosts/shared/nix-access-tokens.age";
    assert native.pendingTemplates == { waiting = [ "pending" ]; };
    assert promoted.pendingTemplates == { };
    assert promoted.bootstrapPlanFile == null;
    assert native.templates.ready.placeholders.nix-access-tokens.secret == "nix-access-tokens";
    assert native.templates.aliased.placeholders.token.secret == "nix-access-tokens";
    assert !templatePlanSucceeds "value={{nix-seal:undeclared}}";
    assert
      !templatePlanSucceeds {
        content = "{{nix-seal:nix-access-tokens}}";
        placeholders.unused = "pending";
      };
    assert
      !templatePlanSucceeds {
        content = "{{nix-seal:nix-access-tokens}}";
        phase = "services";
      };
    assert !templatePlanSucceeds "{{nix-seal:bad name}}";
    pkgs.runCommand "nix-seal-native-authoring"
      {
        nativeBuildInputs = [
          pkgs.jq
          self.packages.${system}.nix-seal
        ];
      }
      (
        (import ./../lib/render-text.nix) ./scripts/check-native-authoring.sh {
          native_planFile = native.planFile;
          native_bootstrapPlanFile = native.bootstrapPlanFile;
          filter2 = ./scripts/native-authoring-bootstrap-plan.jq;
          filter1 = ./scripts/native-authoring-ready-plan.jq;
        }
      );
  plan-v2 =
    assert
      (builtins.fromJSON (
        self.lib.mkPlan {
          inherit identities approvalPolicies;
          targets.${targetId} = target;
          secrets.${secretId} = {
            inherit source;
            consumers = [ targetId ];
            administrators = [ "administrator" ];
            approvalPolicy = "release";
            runtime = {
              owner = "root";
              group = "root";
              mode = "0400";
            };
          };
          repositoryRoot = ../../.;
        }
      )).schema == "nix-seal.plan.v2";
    pkgs.runCommand "nix-seal-plan-v2" { } "touch $out";
  module-cache-discovery =
    pkgs.runCommand "nix-seal-module-cache-discovery" { nativeBuildInputs = [ pkgs.jq ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-module-cache-discovery.sh {
          configuration_config_nixSeal_activationSpec = configuration.config.nixSeal.activationSpec;
          filter1 = ./scripts/activation-cache-discovery.jq;
        }
      );
  scoped-target-and-administrator-projection =
    assert scopedConfiguration.config.nixSeal.targetId == "host/nixos/fixture";
    assert scopedConfiguration.config.nixSeal.secretScope == "hosts/nixos/fixture";
    assert
      scopedConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/hosts/nixos/fixture/nix-access-tokens";
    assert
      scopedConfiguration.config.nixSeal.secrets."nix-access-tokens".source
      == "secrets/alice/hosts/nixos/fixture/nix-access-tokens.age";
    pkgs.runCommand "nix-seal-scoped-target-and-administrator-projection" { } "touch $out";
  configurable-secret-directories =
    let
      custom = customDirectoryConfiguration.config.nixSeal;
      shared = sharedDirectoryConfiguration.config.nixSeal;
      home = sharedHomeConfiguration.config.nixSeal;
      original = scopedConfiguration.config.nixSeal;
    in
    assert custom.secrets."nix-access-tokens".source == "hosts/shared/nix-access-tokens.age";
    assert shared.secrets."nix-access-tokens".source == "modules/shared/nix-access-tokens.age";
    assert home.secrets."nix-access-tokens".source == shared.secrets."nix-access-tokens".source;
    assert custom.secrets."nix-access-tokens".id == original.secrets."nix-access-tokens".id;
    assert custom.secrets."nix-access-tokens".path == original.secrets."nix-access-tokens".path;
    assert home.secrets."nix-access-tokens".id != shared.secrets."nix-access-tokens".id;
    assert
      explicitSourceConfiguration.config.nixSeal.secrets."nix-access-tokens".source
      == "hosts/shared/nix-access-tokens.age";
    assert lib.all
      (
        directory:
        !(builtins.tryEval
          (scopedConfiguration.extendModules { modules = [ { nixSeal.secretDirectory = directory; } ]; })
          .config.nixSeal.secretDirectory
        ).success
      )
      [
        ""
        "/tmp/secrets"
        "../secrets"
        "hosts/../secrets"
        "hosts//shared"
        "hosts/./shared"
        "hosts/shared/"
      ];
    pkgs.runCommand "nix-seal-configurable-secret-directories" { nativeBuildInputs = [ pkgs.jq ]; } (
      (import ./../lib/render-text.nix) ./scripts/check-configurable-secret-directories.sh {
        custom_planFile = custom.planFile;
        shared_planFile = shared.planFile;
        home_planFile = home.planFile;
      }
    );
  scoped-plan-administrator-projection =
    pkgs.runCommand "nix-seal-scoped-plan-administrator-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-scoped-administrator-projection.sh {
          scopedConfiguration_config_nixSeal_planFile = scopedConfiguration.config.nixSeal.planFile;
          filter1 = ./scripts/scoped-administrator-projection.jq;
        }
      );
  bootstrap-state-is-inferred-from-ciphertext-existence =
    assert bootstrapConfiguration.config.nixSeal.bootstrapPlanFile != null;
    pkgs.runCommand "nix-seal-bootstrap-state-is-inferred-from-ciphertext-existence"
      { nativeBuildInputs = [ pkgs.jq ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-inferred-bootstrap-state.sh {
          bootstrapConfiguration_config_nixSeal_planFile = bootstrapConfiguration.config.nixSeal.planFile;
          bootstrapConfiguration_config_nixSeal_bootstrapPlanFile =
            bootstrapConfiguration.config.nixSeal.bootstrapPlanFile;
          filter2 = ./scripts/bootstrap-create-plan.jq;
          filter1 = ./scripts/bootstrap-ready-plan.jq;
        }
      );
  literal-service-arguments =
    assert lib.all (
      command: lib.hasInfix encodedIdentity command
    ) configuration.config.systemd.services.nix-seal-activate.serviceConfig.ExecStart;
    assert
      !pkgs.stdenv.hostPlatform.isLinux
      || (
        lib.hasInfix encodedIdentity (
          builtins.head (
            lib.toList standaloneHomeConfiguration.config.systemd.user.services.nix-seal-activation.Service.ExecStart
          )
        )
        && lib.hasSuffix ''"%t/nix-seal"'' (
          builtins.head (
            lib.toList standaloneHomeConfiguration.config.systemd.user.services.nix-seal-activation.Service.ExecStart
          )
        )
        && lib.hasSuffix ''"%t/nix-seal/services"'' (
          builtins.head (
            lib.toList standaloneHomeConfiguration.config.systemd.user.services.nix-seal-services.Service.ExecStart
          )
        )
      );
    assert
      (import ../modules/support.nix { inherit lib pkgs; }).groupCredentials [
        {
          unit = "alpha.service";
          name = "one";
          path = "/run/one";
        }
        {
          unit = "beta.service";
          name = "two";
          path = "/run/two";
        }
        {
          unit = "alpha.service";
          name = "three";
          path = "/run/three";
        }
      ] == {
        alpha = [
          "one:/run/one"
          "three:/run/three"
        ];
        beta = [ "two:/run/two" ];
      };
    pkgs.runCommand "nix-seal-literal-service-arguments" { } "touch $out";
  derived-home-target =
    assert lib.hasInfix "homeConfigurations.tester@fixture"
      standaloneHomeConfiguration.config.home.activation.nixSealReadiness.data;
    assert lib.hasInfix "--default-configuration"
      standaloneHomeConfiguration.config.home.activation.nixSealReadiness.data;
    assert lib.hasInfix "${
      if pkgs.stdenv.hostPlatform.isDarwin then "darwinConfigurations" else "nixosConfigurations"
    }.fixture-host" integratedHomeConfiguration.config.home.activation.nixSealReadiness.data;
    assert lib.hasInfix "--default-configuration"
      integratedHomeConfiguration.config.home.activation.nixSealReadiness.data;
    assert standaloneHomeConfiguration.config.nixSeal.targetId == "home/tester/fixture";
    assert standaloneHomeConfiguration.config.nixSeal.secretScope == "users/tester";
    assert
      standaloneHomeConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/users/tester/nix-access-tokens";
    assert
      standaloneHomeConfiguration.config.nixSeal.secrets."nix-access-tokens".source
      == "secrets/alice/users/tester/nix-access-tokens.age";
    assert
      lib.any (
        warning:
        lib.hasInfix "standalone Home Manager target for tester on Linux" warning
        && lib.hasInfix "$XDG_RUNTIME_DIR/nix-seal" warning
      ) standaloneHomeConfiguration.config.warnings == pkgs.stdenv.hostPlatform.isLinux;
    pkgs.runCommand "nix-seal-derived-home-target" { } "touch $out";
  home-launch-agent-domains =
    assert
      !pkgs.stdenv.hostPlatform.isDarwin
      || (
        let
          home = standaloneHomeConfiguration.config;
          overridden = standaloneHomeConfiguration.extendModules {
            modules = [ { launchd.agents.nix-seal-services.domain = "user"; } ];
          };
        in
        home.launchd.agents.nix-seal-activation.domain == "gui"
        && home.launchd.agents.nix-seal-services.domain == "gui"
        && overridden.config.launchd.agents.nix-seal-services.domain == "user"
      );
    pkgs.runCommand "nix-seal-home-launch-agent-domains" { } "touch $out";
  home-service-activation-order =
    assert builtins.elem "nixSeal"
      standaloneHomeConfiguration.config.home.activation.nixSealServices.after;
    assert
      builtins.elem "setupLaunchAgents" standaloneHomeConfiguration.config.home.activation.nixSealServices.after
      == pkgs.stdenv.hostPlatform.isDarwin;
    pkgs.runCommand "nix-seal-home-service-activation-order" { } "touch $out";
  embedded-home-runtime-environment =
    let
      integrated =
        volatile:
        standaloneHomeConfiguration.extendModules {
          specialArgs.osConfig.nixSeal = {
            enable = true;
            linux.volatileRuntime.enable = volatile;
          };
        };
      exercise =
        volatile:
        let
          home = (integrated volatile).config;
        in
        (import ./../lib/render-text.nix) ./scripts/exercise-embedded-home-runtime.sh {
          home_home_activation_nixSeal_data = home.home.activation.nixSeal.data;
          pkgs_coreutils = pkgs.coreutils;
          home_home_activation_nixSealServices_data = home.home.activation.nixSealServices.data;
        };
    in
    pkgs.runCommand "nix-seal-embedded-home-runtime-environment" { } (
      (import ../lib/render-text.nix) ./scripts/check-embedded-home-runtime.sh {
        lib_optionalString_pkgs_stdenv_hostPlatform_isLinux_exercise =
          lib.optionalString pkgs.stdenv.hostPlatform.isLinux
            (
              (import ./../lib/render-text.nix) ./scripts/check-home-runtime-environment.sh {
                exercise_true = exercise true;
                exercise_false = exercise false;
                standaloneHomeConfiguration_config_home_activation_nixSeal_d =
                  standaloneHomeConfiguration.config.home.activation.nixSeal.data;
              }
            );
      }
    );
  home-dry-activation = pkgs.runCommand "nix-seal-home-dry-activation" { } (
    (import ../lib/render-text.nix) ./scripts/check-home-dry-activation.sh {
      standaloneHomeConfiguration_config_home_activation_nixSeal_d =
        standaloneHomeConfiguration.config.home.activation.nixSeal.data;
      standaloneHomeConfiguration_config_home_activation_nixSealSe =
        standaloneHomeConfiguration.config.home.activation.nixSealServices.data;
    }
  );
  runtime-mountpoint =
    pkgs.runCommand "nix-seal-runtime-mountpoint"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        activation = configuration.config.system.activationScripts.nixSealRuntime.text;
      }
      (
        (import ../lib/render-text.nix) ./scripts/check-runtime-mountpoint.sh {
          pkgs_replaceVars_scripts_module_evaluation_check_py_py_pkgs_ =
            pkgs.replaceVars ./scripts/check_runtime_mountpoint.py
              {
                mountProbe = pkgs.replaceVars ./scripts/mount_probe.py { pkgs_python3 = pkgs.python3; };
                pkgs_util_linux = pkgs.util-linux;
                lib_getExe_configuration_config_nixSeal_package = lib.getExe configuration.config.nixSeal.package;
                pkgs_bash = pkgs.bash;
              };
        }
      );
  service-credential-policy-projection =
    pkgs.runCommand "nix-seal-service-credential-policy-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      (
        (import ./../lib/render-text.nix) ./scripts/check-service-credential-policy.sh {
          standaloneHomeConfiguration_config_nixSeal_planFile =
            standaloneHomeConfiguration.config.nixSeal.planFile;
          filter1 = pkgs.writeText "service-credential-restart-policy.jq" (
            (import ../lib/render-text.nix) ./scripts/service-credential-restart-policy.jq {
              if_pkgs_stdenv_hostPlatform_isLinux_then_example_service_els =
                if pkgs.stdenv.hostPlatform.isLinux then "[\"example.service\"]" else "[]";
            }
          );
        }
      );
  explicit-scope-overrides =
    assert overrideConfiguration.config.nixSeal.targetId == "host/custom";
    assert overrideConfiguration.config.nixSeal.secretScope == "systems/custom";
    assert
      overrideConfiguration.config.nixSeal.secrets."nix-access-tokens".id
      == "alice/systems/custom/nix-access-tokens";
    pkgs.runCommand "nix-seal-explicit-scope-overrides" { } "touch $out";
  legacy-explicit-identity-mode =
    assert configuration.config.nixSeal.administrator == null;
    assert configuration.config.nixSeal.secrets.${secretId}.id == secretId;
    pkgs.runCommand "nix-seal-legacy-explicit-identity-mode" { } "touch $out";
}
