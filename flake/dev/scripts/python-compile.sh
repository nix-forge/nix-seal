#!@bash@
# shellcheck shell=bash
set -euo pipefail

cache_directory="$(@mktemp@ -d)"
trap '@rm@ -rf "$cache_directory"' EXIT

# py_compile intentionally writes bytecode even when Python is invoked with
# -B. Redirect it to a private temporary cache so hooks never dirty the tree.
PYTHONPYCACHEPREFIX="$cache_directory" @python@ -m py_compile nix/tests/scripts/runtime-vm-test.py
