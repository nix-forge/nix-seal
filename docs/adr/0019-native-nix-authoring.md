# ADR 0019: Native Nix authoring defaults

Status: accepted

Consumers should not need migration inventories or a configuration framework to
declare canonical secrets and public templates. The Nix modules accept a direct
administrator catalog, derive native target and cache defaults, and derive a
ciphertext source for unscoped declarations as well as scoped ones. Explicit
sources and framework metadata retain precedence. This extends ADR 0017's
directory defaults to unscoped declarations, which previously required sources.

A template accepts public text, a Nix path, or its existing option set.
Placeholders default to same-named declared secrets. Explicit mappings and
encodings remain authoritative. The frontend validates the public grammar,
references, and phase constraints even when a caller exports only the plan.
It never declares a secret from a placeholder or copies a template's runtime
permissions onto its fields. The compiled plan and runtime grammar are unchanged.

Declared missing sources remain exclusively in the bootstrap-create plan.
Their dependent templates are reported as pending and omitted from activation.
Bootstrap plans contain no templates because template outputs are not canonical
creation destinations. Completing the fields makes a template available at the
next evaluation. Unknown references fail evaluation rather than becoming pending.

Bootstrap completion accepts unambiguous local secret names and explicit hidden
terminal input. Resolution precedes private input; the possession challenge
binds the resolved canonical ID. Authorization, create-only transactions, and
the 64 KiB limit retain ADR 0014's rules. Non-interactive stdin remains the
default. No new cryptographic format or permission grant is introduced.

Migration inventories may remain as one-time import records in consuming
repositories. They do not participate in normal declaration or activation.
Applications retain ownership of service selection and format-specific policy.
