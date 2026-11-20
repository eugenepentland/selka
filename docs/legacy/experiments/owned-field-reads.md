# C: non-consuming record field reads
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Status: `read_field(owner, field)` inspects a copyable field without consuming
its record binding. This enables code-dependent retry of completion errors while
retaining their resource. Partial field moves and borrowing owned wrappers remain
pending; ordinary `owner.field` projection keeps its existing consuming semantics.

```text
fn retry(file: File) -> Finish effects(filesystem) {
    match complete_resource<Finish>(file) {
        Finish.ok(done) => { return new Finish.ok(done); },
        Finish.err(failure) => {
            if read_field(failure, code) == 3 {
                return complete_resource<Finish>(failure.resource);
            } else {
                return new Finish.err(failure);
            }
        }
    }
}
```

The owner must be a live named record value binding. The field is a statically
resolved name, not an evaluated string or dynamic index. The selected field must
be ordinary copyable data, including immutable aggregate snapshots or capability
values. Owned values and any nested result-handling obligations cannot be copied
this way. A moved record cannot be inspected. Read counts are recorded for binding
diagnostics, but the record's ownership and result-handling state remain unchanged.
Reading metadata therefore cannot silently handle another field's pending result.

The read is immediate and produces a retained value snapshot. It creates no guest
borrow that escapes the expression. Later owner updates, transfers, or cleanup do
not invalidate the returned snapshot. Shared borrowing of an ordinary record permits
inspection; an active exclusive borrow blocks it. Reference names/parameters require
the existing reference operations instead. Owned-wrapper borrowing is not enabled
by this feature. For nested copyable metadata, read the metadata field and then use
ordinary field projection on that snapshot.

A direct `read_field(source_parameter, field)` in a complete conversion counts as
an explicit use of that source field. Unread fields still require their own use or
named discard. The restricted declarative conversion body continues to use ordinary
`discard source.field` syntax for discard decisions.

Bytecode carries the resolved owner slot, field index, and output type. Validation
rejects wrong shapes, indices, types, references, and attempts to copy owned/result
fields. Runtime reads respect the memory registry's active borrow checks and retain
only the resulting snapshot. The operation adds no effect of its own; existing
conservative ownership-cleanup effects still apply to functions owning external
resource wrappers. Exact discovery is `exact-v20`, preserving owner and field
identities while normalizing binding spelling.

306 tests pass in Debug and ReleaseFast (274 core, 32 actual CLI). Coverage includes
snapshot survival across owned-record updates and transfers, result/owner-copy
rejection, moved-owner rejection, unsatisfied result obligations, shared/exclusive
access, complete-conversion accounting, invalid emitted operands, exact discovery,
and allocation-failure cleanup. The external-resource failure-injection suite now
uses code-dependent retry through `read_field`; all resource cleanup/trap tests
continue to pass. Actual CLI tests cover execution, checking, dumps, and rejection
across commands. Formatting and whitespace checks pass on the pinned Zig snapshot.

[Partial field moves](partial-fields.md) now complement copyable field inspection
with immediate ownership transfer and checked access to remaining fields.
