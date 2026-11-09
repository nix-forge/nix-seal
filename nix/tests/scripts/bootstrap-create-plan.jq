.schema == "nix-seal.bootstrap-create-plan.v1" and
  (.identities | has("alice/bootstrap-authorizer")) and
  (.secrets | keys == ["alice/hosts/nixos/fixture/first-token"]) and
  .secrets["alice/hosts/nixos/fixture/first-token"].source
  == "secrets/alice/hosts/nixos/fixture/first-token.age" and
  .secrets["alice/hosts/nixos/fixture/first-token"].sourceCiphertextHash
  == "0000000000000000000000000000000000000000000000000000000000000000"
