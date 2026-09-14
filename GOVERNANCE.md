# Governance

The current maintainer is [@IanHollow](https://github.com/IanHollow).

The maintainer owns release decisions and appoints CODEOWNERS. Decisions favor
interoperability, least privilege, fail-closed behavior, and compatibility over
feature count. Security-sensitive architectural decisions require a public ADR,
two-person review when more maintainers are available, and no unresolved
critical/high findings.

Code collaborators are reviewed before receiving escalated permissions for
protected-branch approval, repository administration, Pages, Actions secrets,
or release automation. The review considers sustained contribution quality,
identity or organizational affiliation where relevant, and the narrowest role
needed. Access is revisited when responsibility changes and removed promptly
when it ends.

`main` should require signed-off commits, review, passing required checks, and
no force pushes. Releases follow SemVer. CLI, plan, artifact, plugin protocol,
and module compatibility are versioned independently where necessary.
Deprecations remain for at least one minor release.

The project will not describe itself as production-ready before the 1.0 audit
gate. Sponsorship or employment does not grant an exception to security policy.
