# ADR 0014: Delegated pending-secret creation

Status: accepted

`secret create` remains an administrator or recovery operation. A target key
can receive a deployment artifact but must not decrypt or replace canonical
repository ciphertext.

For a declared `pending = true` secret, nix-seal permits one create-only
operation through a short-lived capability signed by a dedicated public
`authorizer` identity. The capability binds the bootstrap-plan hash, secret ID,
source, derived recipient-set hash, plaintext SHA-256 commitment, byte limit,
validity window, and nonce. The command derives all write policy from the
bootstrap plan, accepts plaintext only from standard input, rejects an existing
destination, and records the consumed capability. It has no age identity and
cannot reveal, replace, rekey, provision, or activate a secret.

Pending secrets appear only in the distinct bootstrap-create plan with the
all-zero ciphertext hash sentinel. Normal plans and activation documents omit
them. After creation, the operator sets `pending = false`; the normal plan then
binds the real ciphertext hash and resumes ordinary provisioning.

The authorizer role is separate from artifact approval. Offline bearer
capabilities cannot support immediate global revocation, so expiry is limited
to 15 minutes and single-use receipt storage is mandatory.
