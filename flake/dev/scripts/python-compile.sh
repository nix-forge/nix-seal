#!@bash@
# shellcheck shell=bash
set -euo pipefail

cache_directory="$(@mktemp@ -d)"
trap '@rm@ -rf "$cache_directory"' EXIT

# py_compile intentionally writes bytecode even when Python is invoked with
# -B. Redirect it to a private temporary cache so hooks never dirty the tree.
git ls-files -z -- '*.py' >"$cache_directory/files"
mapfile -d '' -t files <"$cache_directory/files"
if ((${#files[@]})); then
  PYTHONPYCACHEPREFIX="$cache_directory" @python@ -m py_compile "${files[@]}"
fi
