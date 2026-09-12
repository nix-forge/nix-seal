#!/usr/bin/env bash
# Scan regular files without exposing the candidate in argv or diagnostics.
set -euo pipefail

directory=$1
candidate=$2
test -s "$candidate"
test -r "$candidate"
test -d "$directory"
test ! -L "$directory"

# Consume all grep output. Under pipefail, piping into grep -q can turn a
# detected match into SIGPIPE and accidentally accept the scan. grep status 1
# is the only successful outcome here; matches and read errors both fail.
# find -exec ... + propagates any failed batch as a nonzero find exit status.
find "$directory" -type f -exec bash -c '
  candidate=$1
  shift
  status=0
  grep -a -l -F -f "$candidate" -- "$@" >/dev/null || status=$?
  test "$status" -eq 1
' bash "$candidate" {} +
