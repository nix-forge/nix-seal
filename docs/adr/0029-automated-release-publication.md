# ADR 0029: Verify reviewed source before automated release publication

Status: accepted

A separately copied builder digest drifted from the actual reusable workflow
pin, so valid provenance would fail publication. Resolve the single immutable
builder SHA from the tagged release workflow and use that identity for every
subject's attestation verification. Keep the builder independently pinned.

Routine publication uses a version-tag-only release environment without an
additional reviewer prompt. Before publishing, fetch the protected default
branch and require the tagged commit to be its ancestor. Required pull-request
and merge-group checks establish that source history; protected tag creation
selects the release. Invalid tags, missing notes, failed builds, inconsistent
checksums, or mismatched provenance stop publication.

This moves the routine publication approval to reviewed source and protected tag
creation. A compromised repository administrator remains trusted and can change
those controls. This does not replace the independent audit and human assurance
gates for a 1.0 release. It does not change artifact cryptography, package
trust, activation, or secret access. Reverting the workflow and restoring the
environment reviewer restores the previous publication policy.

Regression fixtures execute the publisher's actual ancestry shell block using
reviewed and unreviewed commits and an invalid default-branch ref. Shared CI
checks the single-builder identity and rejects duplicate stale digests.
