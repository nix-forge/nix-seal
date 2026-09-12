#!/usr/bin/env bash
# Regression probes use a fresh random candidate outside the scanned tree.
set -euo pipefail
scanner=$1
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir "$root/store"
head -c 32 /dev/urandom | base64 >"$root/candidate"

expect_failure() {
  if bash "$scanner" "$@"; then
    echo "Store scanner accepted a match or invalid input" >&2
    exit 1
  fi
}

# Empty and clean trees succeed; dangling symlinks are not regular files.
bash "$scanner" "$root/store" "$root/candidate"
ln -s store "$root/linked-store"
expect_failure "$root/linked-store" "$root/candidate"
chmod 000 "$root/candidate"
test ! -r "$root/candidate"
expect_failure "$root/store" "$root/candidate"
chmod 600 "$root/candidate"
printf 'unrelated content\n' >"$root/store/clean"
expect_failure "$root/store/clean" "$root/candidate"
ln -s missing "$root/store/dangling"
bash "$scanner" "$root/store" "$root/candidate"

# Binary files and names with whitespace must not conceal the candidate.
printf '\0' >"$root/store/binary file"
cat "$root/candidate" >>"$root/store/binary file"
expect_failure "$root/store" "$root/candidate"
rm "$root/store/binary file"

# Enough matching filenames to overflow the old grep -q pipeline's buffer.
for number in $(seq 1 3000); do
  cp "$root/candidate" "$root/store/match-$number"
done
expect_failure "$root/store" "$root/candidate"
expect_failure "$root/missing" "$root/candidate"
expect_failure "$root/store" "$root/absent-candidate"

# Test read failures as the unprivileged Nix builder, never silently skip them.
rm -r "$root/store"
mkdir "$root/store"
touch "$root/store/unreadable"
chmod 000 "$root/store/unreadable"
test ! -r "$root/store/unreadable"
expect_failure "$root/store" "$root/candidate"
