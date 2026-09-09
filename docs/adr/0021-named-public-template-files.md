# ADR 0021: Named public template files

Status: accepted

The frontend already derives ciphertext filenames from declared names and a
configurable directory. Public templates need the same convenience without
making a consumer adopt a particular configuration framework or host layout.

`templateDirectory` defaults to the repository-relative directory `templates`.
`templates.<name> = { };` selects `<templateDirectory>/<name>.template`.
An explicit source or inline content retains precedence. The directory and
local name use the existing restricted relative-path and ID rules. A missing
public file fails evaluation with its expected path.

Public template storage defaults to a repository-wide directory because public
syntax can be reused independently of ciphertext access policy. Ciphertext
defaults retain their existing administrator and scope separation. Callers can
override directories once per target or set sources individually, so centralized
and colocated layouts use the same implementation.

No filesystem discovery adds declarations. Public files carry no implicit
consumer or recipient grants, and only declared templates are read. The change
does not alter IDs, signed runtime policy, ciphertext encoding, or the plan
schema. The storage guide documents file-sharing criteria and the requirement
to provision fresh artifacts after ciphertext source paths move.
