{
  inputs,
  self,
  system,
  pkgs,
}:
let
  # Evaluate the real activation module separately so the guest can exercise
  # its mount preparation before the target account exists, without needing
  # production ciphertext or keys.
  fixture = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      ({ lib, ... }: {
        options.home-manager.users = lib.mkOption {
          type = lib.types.attrs;
          default.tester.nixSeal = {
            enable = true;
            secrets.token.restartUnits = [ "example.service" ];
            templates.token = { };
          };
        };
        config = {
          system.stateVersion = "26.05";
          nixSeal = {
            enable = true;
            targetId = "host/test";
            target = {
              kind = "nixOs";
              inherit system;
              identity = "target";
            };
            identities.target = {
              kind = "target";
              public = "age1x2k2hx0rzltg56p4et3yn4a873m6jltk62vmlrs8leamel69kamqf8ycqx";
            };
            identityFile = "/run/keys/unused";
            artifactCacheRoot = "/var/lib/nix-seal/cache/v1";
            repositoryRoot = ../../.;
            secrets.token.source = "nix-seal.example.toml";
          };
        };
      })
    ];
  };
in
pkgs.testers.nixosTest {
  name = "nix-seal-runtime-mount";
  nodes.machine = {
    environment.systemPackages = [ pkgs.git ];
    systemd.services.home-manager-tester.serviceConfig = {
      Type = "oneshot";
      User = "tester";
      ExecStartPre = fixture.config.systemd.services.home-manager-tester.serviceConfig.ExecStartPre;
      ExecStart = pkgs.writeShellScript "check-user-manager" ''
        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
        ${pkgs.systemd}/bin/systemctl --user show-environment >/dev/null
      '';
    };
    virtualisation.fileSystems."/run/nix-seal" = fixture.config.fileSystems."/run/nix-seal";
    environment.etc."nix-seal-runtime-activation".source =
      fixture.config.system.activationScripts.nixSealRuntime.text;
    environment.etc."nix-seal-runtime-users".text =
      fixture.config.system.activationScripts.nixSealRuntimeUsers.text
        or fixture.config.systemd.services.nix-seal-runtime.serviceConfig.ExecStart;
    virtualisation.memorySize = 1024;
    system.stateVersion = "26.05";
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("useradd -m tester")

    with subtest("embedded activation reaches a user manager without a login or fixed UID"):
        machine.succeed("systemctl start home-manager-tester.service")

    with subtest("repeated activation preserves Git identity and the mount"):
        machine.succeed("/etc/nix-seal-runtime-activation")
        machine.succeed("bash /etc/nix-seal-runtime-users")
        machine.succeed("install -d -m 0700 /run/nix-seal/users/tester/current")
        machine.succeed("printf '[user]\\nname = Test Author\\nemail = test@example.invalid\\n' > /run/nix-seal/users/tester/current/gitconfig")
        machine.succeed("GIT_CONFIG_GLOBAL=/run/nix-seal/users/tester/current/gitconfig git var GIT_AUTHOR_IDENT >/dev/null")
        mount_before = machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal")
        machine.succeed("/etc/nix-seal-runtime-activation")
        machine.succeed("GIT_CONFIG_GLOBAL=/run/nix-seal/users/tester/current/gitconfig git var GIT_AUTHOR_IDENT >/dev/null")
        assert machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal") == mount_before

    with subtest("first activation precedes account creation"):
        machine.succeed("systemctl stop user@$(id -u tester).service")
        machine.succeed("userdel tester")
        machine.succeed("umount --all-targets /run/nix-seal")
        machine.succeed("rmdir /run/nix-seal")
        machine.succeed("env DRY_ACTIVATE=1 /etc/nix-seal-runtime-activation")
        machine.succeed("test ! -e /run/nix-seal")
        machine.succeed("/etc/nix-seal-runtime-activation")
        machine.succeed("useradd -m tester")
        machine.succeed("bash /etc/nix-seal-runtime-users")
        machine.succeed("test $(stat -c %u /run/nix-seal/users/tester) = $(id -u tester)")

    with subtest("dry activation makes no changes"):
        machine.succeed("rmdir /run/nix-seal/users/tester /run/nix-seal/users /run/nix-seal/system")
        machine.succeed("env DRY_ACTIVATE=1 /etc/nix-seal-runtime-activation")
        machine.succeed("test ! -e /run/nix-seal/system")

    with subtest("unsafe existing mounts fail without being hidden"):
        machine.succeed("mount -o remount,exec /run/nix-seal")
        mount_before = machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal")
        machine.fail("/etc/nix-seal-runtime-activation")
        assert machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal") == mount_before
  '';
}
