"""Exercise the generated configuration with the NixOS VM driver."""

from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from test_driver.machine import QemuMachine

    machine: QemuMachine = cast("QemuMachine", None)
    from collections.abc import Callable

    start_all: Callable[[], None] = cast("Callable[[], None]", None)

start_all()
machine.wait_for_unit("multi-user.target")
machine.succeed("systemctl start nix-seal-argument-probe.service")

machine.succeed("nix-seal-runtime-scenario")
