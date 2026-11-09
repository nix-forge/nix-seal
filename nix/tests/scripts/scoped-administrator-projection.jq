(.identities | has("alice/administrator")) and
  (.identities | has("alice/recovery")) and
  (.identities | has("alice/release")) and
  ((.identities | has("bob/administrator")) | not) and
  (.approvalPolicies | has("alice/release")) and
  (.secrets | has("alice/hosts/nixos/fixture/nix-access-tokens")) and
  (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].administrators == ["alice/administrator", "alice/recovery"]) and
  (.secrets["alice/hosts/nixos/fixture/nix-access-tokens"].consumers == ["host/nixos/fixture"])
