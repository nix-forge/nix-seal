(.templates | keys == ["alice/hosts/nixos/native/aliased", "alice/hosts/nixos/native/from-file", "alice/hosts/nixos/native/named", "alice/hosts/nixos/native/ready"]) and
  (.secrets | keys == ["alice/hosts/nixos/native/nix-access-tokens"])
