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
      targetName = "fixture";
    };
    modules = [
      self.homeManagerModules.default
      {
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
    pkgs.runCommand "nix-seal-darwin-deployment-readiness" { } ''
      cat > nix-seal <<'EOF'
      #!${pkgs.runtimeShell}
      if [ "$1" = readiness ]; then
        case " $* " in
          *" --deployment "*) ;;
          *) exit 2 ;;
        esac
        echo "check:''${TEST_OWNER:-root}" >> "$PWD/events"
        if [ "''${TEST_OWNER:-root}" = "$FAIL_OWNER" ]; then
          echo "target-local cache lacks verified artifacts" >&2
          exit 1
        fi
      else
        echo runtime >> "$PWD/events"
      fi
      EOF
      cat > sudo <<'EOF'
      #!${pkgs.runtimeShell}
      test "$1" = -H && test "$2" = -u && test "$4" = -- || exit 2
      export TEST_OWNER="$3"
      shift 4
      exec "$@"
      EOF
      chmod +x nix-seal sudo
      export FAIL_OWNER=root
      if ${pkgs.runtimeShell} ${pkgs.writeText "darwin-preactivation" (script integrated)} 2> error; then
        echo "Darwin accepted missing system artifacts" >&2
        exit 1
      fi
      grep -q 'target-local cache lacks verified artifacts' error
      printf 'check:root\ncheck:tester\n' > expected
      diff -u expected events
      export FAIL_OWNER=tester
      : > events
      if ${pkgs.runtimeShell} ${pkgs.writeText "darwin-preactivation" (script integrated)} 2> error; then
        echo "Darwin accepted missing home artifacts" >&2
        exit 1
      fi
      diff -u expected events
      export FAIL_OWNER=none
      : > events
      ${pkgs.runtimeShell} ${pkgs.writeText "darwin-preactivation" (script integrated)}
      printf 'runtime\n' >> expected
      diff -u expected events
      export FAIL_OWNER=tester
      for script in ${pkgs.writeText "darwin-persistent-preactivation" (script persistent)} ${pkgs.writeText "darwin-home-only-preactivation" (script homeOnly)}; do
        : > events
        if ${pkgs.runtimeShell} "$script" 2> error; then
          echo "Darwin skipped readiness without a system volatile runtime" >&2
          exit 1
        fi
        grep -q 'check:tester' events
        if grep -q runtime events; then exit 1; fi
      done
      touch "$out"
    '';
  deployment-readiness =
    let
      integrated = configuration.extendModules {
        specialArgs = {
          configName = "fixture";
          nixSealDefaultConfiguration = "nixosConfigurations.fixture";
        };
        modules = [
          ({ lib, ... }: {
            options.home-manager.users = lib.mkOption {
              type = lib.types.attrs;
              default.tester = standaloneHomeConfiguration.config;
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
      homePreflightScript = pkgs.writeText "home-readiness-preflight" (
        builtins.unsafeDiscardStringContext (
          lib.replaceStrings
            [ (lib.getExe standaloneHomeConfiguration.config.nixSeal.package) ]
            [ ''"$PWD/readiness-probe"'' ]
            standaloneHomeConfiguration.config.home.activation.nixSealReadiness.data
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
      ''
        cat > readiness-probe <<'EOF'
        #!${pkgs.runtimeShell}
        test "$1" = readiness && test "$2" = --spec && test -n "$3" || exit 2
        case " $* " in
          *" --deployment "*) ;;
          *) exit 2 ;;
        esac
        echo "''${TEST_OWNER:-root}" >> "$PWD/events"
        test "''${TEST_OWNER:-root}" != "$FAIL_OWNER"
        EOF
        cat > runuser-probe <<'EOF'
        #!${pkgs.runtimeShell}
        test "$1" = --user && test "$2" = tester && test "$3" = -- || exit 2
        export TEST_OWNER="$2"
        shift 3
        exec "$@"
        EOF
        chmod +x readiness-probe runuser-probe
        grep -q -- '--default-configuration' ${preflightScript}
        if grep -q -- '--default-configuration' ${homePreflightScript}; then
          echo "Standalone Home Manager incorrectly claimed the flake default" >&2
          exit 1
        fi
        printf 'root\ntester\n' > expected
        for owner in root tester; do
          export FAIL_OWNER="$owner"
          : > events
          if ${pkgs.runtimeShell} ${preflightScript} 2> error; then
            echo "Readiness preflight accepted missing $owner artifacts" >&2
            exit 1
          fi
          diff -u expected events
        done
        export FAIL_OWNER=none
        : > events
        ${pkgs.runtimeShell} ${preflightScript}
        diff -u expected events

        : > events
        ${pkgs.runtimeShell} ${homePreflightScript}
        printf 'root\n' > expected-home
        diff -u expected-home events

        jq -e '.schema == "nix-seal.deployment.v1" and (.targets | length) == 2' ${integrated.config.nixSeal.deploymentFile}
        # The host may already have a private cache. Test an absent cache inside
        # the sandbox so readiness diagnoses missing artifacts, not permissions.
        jq --arg cache "$TMPDIR/empty-cache" '.artifactCacheRoot = $cache' \
          ${configuration.config.nixSeal.activationSpecs.activation} > activation.json
        if nix-seal readiness --spec "$PWD/activation.json" \
          --deployment ${configuration.config.nixSeal.deploymentFile} \
          --default-configuration --json > report.json; then
          echo "readiness accepted an unprepared system" >&2
          exit 1
        fi
        jq -e '.ready == false and (.errors | length) == 0 and (.artifacts[0].missing | length) > 0 and (.preparationCommand | contains("prepare --identity")) and (.preparationCommand | contains("--deployment") | not)' report.json
        touch "$out"
      '';
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
      ''
        nix-seal check --nix-plan ${withValues.config.nixSeal.planFile}
        nix-seal template check --plan ${withValues.config.nixSeal.planFile}
        touch $out
      '';
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
      ''
        nix-seal check --nix-plan ${concise.planFile}
        touch $out
      '';
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
      ''
        nix-seal check --nix-plan ${native.planFile}
        nix-seal template check --plan ${native.planFile}
        jq -e '
          (.templates | keys == ["alice/hosts/nixos/native/aliased", "alice/hosts/nixos/native/from-file", "alice/hosts/nixos/native/named", "alice/hosts/nixos/native/ready"]) and
          (.secrets | keys == ["alice/hosts/nixos/native/nix-access-tokens"])
        ' ${native.planFile} >/dev/null
        jq -e '
          (.templates == {}) and
          (.secrets | keys == ["alice/hosts/nixos/native/pending"])
        ' ${native.bootstrapPlanFile} >/dev/null
        touch "$out"
      '';
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
      ''
        jq -e '
          .schema == "nix-seal.activation.v2" and
          .artifactCacheRoot == "/var/lib/nix-seal/cache/v1" and
          (.artifacts | length) == 1 and
          (.artifacts[0] | has("ciphertext") | not) and
          (.artifacts[0] | has("envelope") | not)
        ' ${configuration.config.nixSeal.activationSpec} >/dev/null
        touch "$out"
      '';
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
    pkgs.runCommand "nix-seal-configurable-secret-directories" { nativeBuildInputs = [ pkgs.jq ]; } ''
      jq -e '.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].source == "hosts/shared/nix-access-tokens.age"' ${custom.planFile} >/dev/null
      jq -e '.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].consumers == ["host/nixos/fixture"]' ${shared.planFile} >/dev/null
      jq -e '.secrets["alice/users/tester/nix-access-tokens"].consumers == ["home/tester/fixture"]' ${home.planFile} >/dev/null
      touch "$out"
    '';
  scoped-plan-administrator-projection =
    pkgs.runCommand "nix-seal-scoped-plan-administrator-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          (.identities | has("alice/administrator")) and
          (.identities | has("alice/recovery")) and
          (.identities | has("alice/release")) and
          ((.identities | has("bob/administrator")) | not) and
          (.approvalPolicies | has("alice/release")) and
          (.secrets | has("alice/hosts/nixos/fixture/nix-access-tokens")) and
          (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].administrators == ["alice/administrator", "alice/recovery"]) and
          (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].consumers == ["host/nixos/fixture"])
        ' ${scopedConfiguration.config.nixSeal.planFile} >/dev/null
        touch "$out"
      '';
  bootstrap-state-is-inferred-from-ciphertext-existence =
    assert bootstrapConfiguration.config.nixSeal.bootstrapPlanFile != null;
    pkgs.runCommand "nix-seal-bootstrap-state-is-inferred-from-ciphertext-existence"
      { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          (.secrets | length) == 0 and
          ((.identities | has("alice/bootstrap-authorizer")) | not)
        ' ${bootstrapConfiguration.config.nixSeal.planFile} >/dev/null
        jq -e '
          .schema == "nix-seal.bootstrap-create-plan.v1" and
          (.identities | has("alice/bootstrap-authorizer")) and
          (.secrets | keys == ["alice/hosts/nixos/fixture/first-token"]) and
          .secrets["alice/hosts/nixos/fixture/first-token"].source
          == "secrets/alice/hosts/nixos/fixture/first-token.age" and
          .secrets["alice/hosts/nixos/fixture/first-token"].sourceCiphertextHash
          == "0000000000000000000000000000000000000000000000000000000000000000"
        ' ${bootstrapConfiguration.config.nixSeal.bootstrapPlanFile} >/dev/null
        touch "$out"
      '';
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
        ''
          (
            unset XDG_RUNTIME_DIR
            ${home.home.activation.nixSeal.data}
            test "$XDG_RUNTIME_DIR" = "/run/user/$(${pkgs.coreutils}/bin/id -u)"
            export XDG_RUNTIME_DIR="$TMPDIR/custom-runtime"
            ${home.home.activation.nixSealServices.data}
            test "$XDG_RUNTIME_DIR" = "$TMPDIR/custom-runtime"
          )
        '';
    in
    pkgs.runCommand "nix-seal-embedded-home-runtime-environment" { } ''
      run() { :; }
      ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        ${exercise true}
        ${exercise false}
        if (
          unset XDG_RUNTIME_DIR
          ${standaloneHomeConfiguration.config.home.activation.nixSeal.data}
        ); then
          echo "standalone activation accepted a missing runtime environment" >&2
          exit 1
        fi
      ''}
      touch "$out"
    '';
  home-dry-activation = pkgs.runCommand "nix-seal-home-dry-activation" { } ''
    export DRY_RUN=1
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    run() {
      printf 'skipped\n' >> "$TMPDIR/skipped"
    }
    ${standaloneHomeConfiguration.config.home.activation.nixSeal.data}
    ${standaloneHomeConfiguration.config.home.activation.nixSealServices.data}
    test "$(wc -l < "$TMPDIR/skipped")" -eq 2
    test ! -e "$XDG_RUNTIME_DIR"
    touch "$out"
  '';
  runtime-mountpoint =
    pkgs.runCommand "nix-seal-runtime-mountpoint"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        activation = configuration.config.system.activationScripts.nixSealRuntime.text;
      }
      ''
        python3 <<'PY'
        import os
        import pathlib
        import subprocess

        root = pathlib.Path.cwd() / "runtime"
        mounted = pathlib.Path.cwd() / "mounted"
        events = pathlib.Path.cwd() / "events"
        mock = pathlib.Path.cwd() / "mount-probe"
        mock.write_text("""#!${pkgs.python3}/bin/python3
        import pathlib, sys
        root = pathlib.Path(sys.argv[-1])
        if sys.argv[1] == "--quiet":
            sys.exit(0 if pathlib.Path("mounted").exists() else 1)
        if not root.is_dir():
            sys.exit("mount point does not exist")
        pathlib.Path("mounted").touch()
        with pathlib.Path("events").open("a") as output:
            output.write("mount\\n")
        """)
        mock.chmod(0o700)
        source = pathlib.Path(os.environ["activation"].strip()).read_text()
        source = source.replace("/run/nix-seal", str(root))
        source = source.replace("${pkgs.util-linux}/bin/mountpoint", str(mock))
        source = source.replace("${pkgs.util-linux}/bin/mount", str(mock))
        # Exercise the generated mount logic without materializing any secrets.
        source = source.replace("${lib.getExe configuration.config.nixSeal.package}", "true")
        script = pathlib.Path("activation.sh")
        script.write_text(source)
        subprocess.run(
            ["${pkgs.bash}/bin/bash", str(script)],
            env=dict(os.environ, DRY_ACTIVATE="1"), check=True,
        )
        assert not root.exists() and not mounted.exists()
        subprocess.run(["${pkgs.bash}/bin/bash", str(script)], check=True)
        marker = root / "existing-generation"
        marker.touch()
        subprocess.run(["${pkgs.bash}/bin/bash", str(script)], check=True)
        assert marker.exists()
        assert events.read_text() == "mount\n"
        PY
        touch "$out"
      '';
  service-credential-policy-projection =
    pkgs.runCommand "nix-seal-service-credential-policy-projection" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        jq -e '
          .secrets["alice/users/tester/service-token"].runtime.restartUnits
          == ${if pkgs.stdenv.hostPlatform.isLinux then "[\"example.service\"]" else "[]"}
        ' ${standaloneHomeConfiguration.config.nixSeal.planFile} >/dev/null
        touch "$out"
      '';
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
