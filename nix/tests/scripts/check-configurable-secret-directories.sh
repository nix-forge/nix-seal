# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
jq -e '.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].source == "hosts/shared/nix-access-tokens.age"' @custom_planFile@ >/dev/null
jq -e '.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].consumers == ["host/nixos/fixture"]' @shared_planFile@ >/dev/null
jq -e '.secrets["alice/users/tester/nix-access-tokens"].consumers == ["home/tester/fixture"]' @home_planFile@ >/dev/null
touch "$out"
