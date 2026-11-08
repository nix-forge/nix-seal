# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp -R @docs@ docs
cp -R @site@ site
chmod -R u+w docs
mkdocs build --config-file site/mkdocs.yml --site-dir "$out" --strict
test -s "$out/index.html"
test -s "$out/search/search_index.json"
