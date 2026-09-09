# ADR 0023: Public template values

Status: accepted

Public configuration such as SSH verification keys should have one declaration
and be reusable in file-based templates alongside encrypted fields.

Each template accepts `publicValues`, an attribute set of strings bound to
`{{public:name}}` markers. The Nix frontend resolves these at evaluation and
passes the resulting public source to the existing plan compiler. The existing
`{{nix-seal:name}}` markers remain unresolved until secret rendering. The source
option retains the original file; read-only `renderedSource` exposes the public
result. Templates without public substitution retain their source path.

Bindings must exactly match public marker names. Substitution is one pass and
literal, with no destination-language escaping. Public values cannot contain
or introduce reserved markers, including across replacement boundaries. The
frontend limits public names to 256 and computes the expanded size before
allocating output, retaining the 2 MiB public-template limit. Secret marker
occurrences must remain unchanged.

Public values and the resulting text are Nix-store metadata. This feature does
not accept private inputs, add recipients, declare secret fields, or change
phase and ownership policy. It changes no Rust schema or rendering protocol;
the compiled plan binds the generated source through the existing rules.
