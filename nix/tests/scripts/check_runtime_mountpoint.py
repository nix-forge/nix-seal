"""Validate generated artifacts in an isolated build or VM fixture."""

import os
import pathlib
import subprocess

root = pathlib.Path.cwd() / "runtime"
mounted = pathlib.Path.cwd() / "mounted"
events = pathlib.Path.cwd() / "events"
mock = pathlib.Path.cwd() / "mount-probe"
mock.write_text(
    pathlib.Path("@mountProbe@").read_text(encoding="utf-8"), encoding="utf-8"
)
mock.chmod(0o700)
source = pathlib.Path(os.environ["activation"].strip()).read_text(encoding="utf-8")
source = source.replace("/run/nix-seal", str(root))
source = source.replace("@pkgs_util_linux@/bin/mountpoint", str(mock))
source = source.replace("@pkgs_util_linux@/bin/mount", str(mock))
# Exercise the generated mount logic without materializing any secrets.
source = source.replace("@lib_getExe_configuration_config_nixSeal_package@", "true")
script = pathlib.Path("activation.sh")
script.write_text(source, encoding="utf-8")
subprocess.run(
    ["@pkgs_bash@/bin/bash", str(script)],
    env=dict(os.environ, DRY_ACTIVATE="1"),
    check=True,
)
assert not root.exists()
assert not mounted.exists()
subprocess.run(["@pkgs_bash@/bin/bash", str(script)], check=True)
marker = root / "existing-generation"
marker.touch()
subprocess.run(["@pkgs_bash@/bin/bash", str(script)], check=True)
assert marker.exists()
assert events.read_text(encoding="utf-8") == "mount\n"
