.schema == "nix-seal.activation.v2" and
  .artifactCacheRoot == "/var/lib/nix-seal/cache/v1" and
  (.artifacts | length) == 1 and
  (.artifacts[0] | has("ciphertext") | not) and
  (.artifacts[0] | has("envelope") | not)
