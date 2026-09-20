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

`main` requires signed-off commits, passing required checks, the merge queue,
and no force pushes. With one maintainer, GitHub requires no independent
approval; the maintainer may use AI review and authorize an agent to merge.
Security-critical changes still need a documented maintainer decision, an ADR
where required, and independent review when another qualified maintainer is
available. See the [organization review policy](https://github.com/nix-forge/.github/blob/main/GOVERNANCE.md#solo-maintainer-review-and-automation).
Releases follow SemVer. CLI, plan, artifact, plugin protocol,
and module compatibility are versioned independently where necessary.
Deprecations remain for at least one minor release.

The project will not describe itself as production-ready before the 1.0 audit
gate. Sponsorship or employment does not grant an exception to security policy.
