"""Exercise runtime mount vm with the NixOS test driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable
    from contextlib import AbstractContextManager

    from test_driver.machine import QemuMachine

    # The test driver injects nodes and lifecycle functions at execution.
    machine: QemuMachine = cast("QemuMachine", None)
    start_all: Callable[[], None] = cast("Callable[[], None]", None)
    subtest: Callable[[str], AbstractContextManager[None]] = cast(
        "Callable[[str], AbstractContextManager[None]]", None
    )

start_all()
machine.wait_for_unit("multi-user.target")
machine.succeed("useradd -m tester")

with subtest("embedded activation reaches a user manager without a login or fixed UID"):
    machine.succeed("systemctl start home-manager-tester.service")

with subtest("repeated activation preserves Git identity and the mount"):
    machine.succeed("/etc/nix-seal-runtime-activation")
    machine.succeed("bash /etc/nix-seal-runtime-users")
    machine.succeed("install -d -m 0700 /run/nix-seal/users/tester/current")
    machine.succeed(
        "printf '[user]\\nname = Test Author\\nemail = test@example.invalid\\n' > /run/nix-seal/users/tester/current/gitconfig"
    )
    machine.succeed(
        "GIT_CONFIG_GLOBAL=/run/nix-seal/users/tester/current/gitconfig git var GIT_AUTHOR_IDENT >/dev/null"
    )
    mount_before = machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal")
    machine.succeed("/etc/nix-seal-runtime-activation")
    machine.succeed(
        "GIT_CONFIG_GLOBAL=/run/nix-seal/users/tester/current/gitconfig git var GIT_AUTHOR_IDENT >/dev/null"
    )
    assert (
        machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal") == mount_before
    )

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
    machine.succeed(
        "rmdir /run/nix-seal/users/tester /run/nix-seal/users /run/nix-seal/system"
    )
    machine.succeed("env DRY_ACTIVATE=1 /etc/nix-seal-runtime-activation")
    machine.succeed("test ! -e /run/nix-seal/system")

with subtest("unsafe existing mounts fail without being hidden"):
    machine.succeed("mount -o remount,exec /run/nix-seal")
    mount_before = machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal")
    machine.fail("/etc/nix-seal-runtime-activation")
    assert (
        machine.succeed("findmnt -rn -o ID --mountpoint /run/nix-seal") == mount_before
    )
