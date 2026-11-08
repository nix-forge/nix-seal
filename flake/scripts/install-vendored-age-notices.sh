# shellcheck shell=bash
# The Rust builder supplies these variables; run from the package source root.
# shellcheck disable=SC2154
for license in LICENSE-MIT LICENSE-APACHE; do
  install -Dm644 "$src/vendor/$license" "$out/share/licenses/$pname/age/$license"
done
install -Dm644 "$src/vendor/README.md" "$out/share/licenses/$pname/age/MODIFICATIONS.md"
