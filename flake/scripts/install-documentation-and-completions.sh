# shellcheck shell=bash
# Build/activation supplies these variables and functions.
# shellcheck disable=SC2154,SC2329
mandoc -Tlint @docs_nix_seal_1@
install -D -m 0644 @docs_nix_seal_1@ "$out/share/man/man1/nix-seal.1"
install -d -m 0755 "$out/share/nix-seal/schemas" "$out/share/nix-seal/completions"
nix-seal schema --kind plan >"$out/share/nix-seal/schemas/plan-v2.json"
nix-seal schema --kind target-policy >"$out/share/nix-seal/schemas/target-policy-v1.json"
nix-seal schema --kind secret-recipients >"$out/share/nix-seal/schemas/secret-recipients-v1.json"
nix-seal schema --kind activation >"$out/share/nix-seal/schemas/activation-v2.json"
nix-seal schema --kind collection >"$out/share/nix-seal/schemas/collection-v1.json"
nix-seal completions bash >"$out/share/nix-seal/completions/nix-seal.bash"
nix-seal completions zsh >"$out/share/nix-seal/completions/_nix-seal"
nix-seal completions fish >"$out/share/nix-seal/completions/nix-seal.fish"
nix-seal completions nushell >"$out/share/nix-seal/completions/nix-seal.nu"
