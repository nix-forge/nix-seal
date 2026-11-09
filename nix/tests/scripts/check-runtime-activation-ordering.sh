# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
# shellcheck disable=SC2154
DRY_ACTIVATE=1 @activation@
test ! -e events
DRY_ACTIVATE=0 @activation@
printf '%s\n' mount prepare >expected
cmp expected events
rm events
if DRY_ACTIVATE=0 @failedMount@; then
  echo "Activation continued after a failed mount" >&2
  exit 1
fi
test ! -e events
touch "$out"
