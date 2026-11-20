# Focused declaration context (internals)

Implementation detail moved out of the user guide, verbatim, under the same headings.

## Source confirmation

The envelope names the exact source identities the answer was assembled from, and
the command re-reads every one of them through the same provider the project was
loaded from before it prints anything.

The command compares the actual held bytes and re-reads through
the loader's embed callback, so a same-length edit or a missing file is stale.
An unavailable callback or unreadable file is a failure to confirm. Partial
answers retain these identities. The `agent-context-v1` envelope is unchanged:
projects without embeds keep their existing fields and snapshot digest; projects
with embeds gain these rows and their digest includes them.

## Budget and omissions

Embedded-file rows are descriptive snapshot detail and can be omitted with the
source rows; `omissions` names `source.embeds` when that happens. Their contribution
to `snapshot_sha256` remains.
