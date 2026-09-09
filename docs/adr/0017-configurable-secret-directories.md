# ADR 0017: Configure ciphertext storage independently of secret identity

Status: accepted

Scoped modules previously derived every default source as
`secrets/<administrator>/<scope>/<name>.age`. Applications can instead keep
ciphertext beside their home, host, or shared configuration.

`secretDirectory` selects the default repository-relative directory for a
target. Its default preserves the existing layout. `sharedSecretDirectory`
defaults to `secrets/<administrator>/shared`; a secret opts in with
`shared = true`. An explicit source remains authoritative. Legacy unscoped
declarations continue to require an explicit source.

The directory options use the existing restricted relative-path vocabulary.
This change does not alter canonical secret IDs, template IDs, runtime paths,
recipients, ownership, cache verification, or the plan format. Two targets may
reference the same ciphertext while retaining different identities and signed
access policies. The sharing flag does not add consumers or recipients.

Source paths are already bound into signed plan metadata. Relocating ciphertext
therefore requires fresh plans and target artifacts before deployment, even
when the canonical ciphertext hash is unchanged. Existing installed cache
entries remain valid for older generations and must be retained for rollback.
