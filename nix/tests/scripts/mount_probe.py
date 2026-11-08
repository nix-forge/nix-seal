#!@pkgs_python3@/bin/python3
"""Model the mount and mountpoint commands for a disposable fixture."""

import pathlib
import sys

root = pathlib.Path(sys.argv[-1])
if sys.argv[1] == "--quiet":
    sys.exit(0 if pathlib.Path("mounted").exists() else 1)
if not root.is_dir():
    sys.exit("mount point does not exist")
pathlib.Path("mounted").touch()
with pathlib.Path("events").open("a", encoding="utf-8") as output:
    output.write("mount\n")
