# C/D: partial record field moves
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Status: source, checked representation, bytecode, VM, cleanup, and flow checking
implemented. `take_field(owner, field)` transfers one field from an owned or
result-bearing record binding. It works without requiring mutable bindings, just
as whole-value ownership transfer does. Plain copyable records use `read_field`.

```text
let pair = new Pair { first: first_buffer, second: second_buffer, code: 7 };
discard take_field(pair, first);
let second = take_field(pair, second);
return read_field(pair, code);
```

## Ownership and remaining fields

The extracted field transfers immediately, including resource ownership or result
handling obligations. Taking a field does not retain another copy in its parent.
Discarding an extracted resource therefore releases it before subsequent acquisition,
while the parent's remaining fields retain their own ownership.

The checker records moved fields by resolved local and schema field identities.
Taking or otherwise valid copyable-field reading of a missing field fails with
E_FIELD_MOVED. A partially moved record
cannot be copied, passed, returned, projected through ordinary field syntax, or
acknowledged/discarded as a whole; whole-value use fails with E_PARTIAL_MOVE. Remaining
copyable metadata can be inspected with `read_field`, and remaining fields can be
transferred with `take_field`. Existing borrowing and moved-owner checks still apply.

Nested records can be taken intact into a new binding and then partially moved there.
A mutable binding can be replaced with a complete value of the same type, releasing
its remainder and restoring all fields. Individual missing-field reinitialization
is not provided. Arrays, domains, and tagged variants are not record field-take
subjects; match variant payloads first. This keeps existing exhaustive matching and
private-construction rules intact.

## Flow and result obligations

Continuing branches must leave the same field availability, regardless of extraction
order. Loop continuations and short-circuit paths must preserve the expected incoming
state. This extends whole-owner state snapshots rather than inferring ownership from
identifier spelling or runtime reference counts.

Untouched result-bearing fields remain obligations. Transferring one such field does
not acknowledge another; ordinary discard of the extracted result is rejected.
After all result-bearing fields have been transferred/handled, copyable metadata and
owned resources left in the partial record can leave scope normally. Overwriting a
partial record still rejects any remaining unhandled result field. Result propagation
and terminal failures clean up both extracted local owners and the parent remainder.

## Runtime storage and costs

Unique aggregate storage tracks moved slots with a separate bitmap. The first take
allocates bookkeeping before changing ownership. Allocation failure leaves the
aggregate intact. Successful take marks the slot and transfers its existing value
without retaining it. Reads reject moved slots; cleanup skips them and releases
only the remainder, in the existing reverse field order. The bitmap releases with
the parent. Shared aggregates reject destructive extraction, preserving snapshots.
Ordinary immutable updates reject partial aggregate storage.

The checker uses immutable field-state snapshots when branches or expressions need
ownership comparisons; each take copies an array of optional source spans. A present
span records the extraction of that field, while comparisons use only availability.
See [diagnostic provenance](diagnostic-provenance.md) for causal notes and repairs. The runtime bitmap
allocates once per partially moved record. These are host bookkeeping costs, not
guest buffer backing allocations: noalloc retains its existing guest-allocation
meaning. Cleanup effects remain conservatively inferred from owned types. No general
compile-time scalability or zero-host-allocation claim is made for large records.

## Acceptance evidence

`src/partial_fields_test.zig` and `src/resource_source_test.zig` cover:

- Immediate extracted-buffer release under a two-allocation quota, preserved metadata,
  and independent transfer of another field.
- Missing-field/whole-value rejection; differing branch/loop/short-circuit states;
  equal states reached in different orders; complete binding replacement.
- Remaining result obligations, extracted-result handling, overwrite rejection, nested
  record moves, and recoverable propagation with extracted/remainder cleanup.
- Shared aggregate rejection, surviving snapshots, malformed bytecode schemas, and
  repeated runtime extraction rejection with complete cleanup.
- Every allocation failure through buffer and external-resource scenarios, and every
  instruction-budget boundary on both general and arena execution backends.
- External release order 1, 3, 2: first extracted owner immediately, then later spare,
  then the untouched second owner. No completion callback is fabricated.
- 10,000 partial-move/remainder-cleanup cycles within 16 KiB live general-backend
  allocation, with 20,000 created/released buffers and zero live bytes afterward.

Actual CLI tests exercise checks, dumps, both VM memory backends, and consistent
source rejection across analysis/native commands. The formatter corpus now includes
the partial-field fixture. Exact discovery is exact-v25 and distinguishes reads from
takes while normalizing bound names. Native execution still explicitly rejects these
aggregate operations. Source pool/arena integration and generics remain pending.
