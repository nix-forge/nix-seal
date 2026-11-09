(.secrets | length) == 0 and
  ((.identities | has("alice/bootstrap-authorizer")) | not)
