# D9 WP-4: bounded flat-loan plan (review draft)

This is a separate proposed runtime optimization after plain retain `5237aebc`.
No implementation is included in this draft. The parent requested review by the
collections agent before implementation. The aim is to remove generic native
unique-type, shape, seed and value walkers from small physical loans; semantic
SHARE/publication, pins, clone history and compiler loan elimination are unchanged.

## Admission stronger than the existing flat plan

`flat.count <= 8` alone is insufficient. The current native unique-type walk
rejects a POINTER with `collection_kind == 5` whose native body has a finalizer,
even when the physical pointer is null. Flat admission currently stops at that
pointer and does not inspect the body. Each nonnull loan leaf also checks its
actual payload descriptor for a finalizer. Those are separate obligations.

Proposed private admission adds `unsigned loanable` to `myl_rc_flat`, filling its
current four bytes of tail padding on the supported amd64 ABI. Assert the unchanged
private structure size. No emitted descriptor, heap prefix or public ABI changes.
`flat_build` computes this flag with its existing bounded walk. Initially refuse
all pointer leaves with `collection_kind == 5 && element != NULL`, even when their
body would be copyable. This conservative rule proves the existing native unique
predicate false without depending on registration order or importing body
metadata. Raw RESOURCE/OWNED_BUFFER/OWNED_POOL kinds, H leaves, variants, hooks and
unsupported/deep/wide metadata already refuse flat admission and remain generic.
Limit loan admission to at most eight inline levels so the candidate does not
replace an existing dynamically allocated transfer-stack failure with success.

Nonzero, disjoint slots and an already registered loanable binding may enter the
fast loan copy. Cold metadata, zero-size and overlap/same-address cases retain the
old path and its invariants. For each nonnull payload preserve the dynamic header
and descriptor check, including the immortal exception and finalizer refusal.
Only the common header is read for arena/immortal objects; no RC prefix is inferred
from a non-counted allocation. Pinned values retain exactly their identity and
marks. Arena loans still carry no physical count and remain frame-confined.

Copy inline bytes, clear every admitted pointer offset, then acquire H in the
original shape order with the existing `myl_rc_hold_acquire`. Publish each pointer
only after its H acquisition succeeds. Duplicate leaves therefore perform one
increment per token; a later count-limit failure retains the same acquired-prefix
and rollback counter events as the generic path. Refusal releases that prefix,
clears all destination bytes and returns the same status. Source bytes, ordinary
owner counts, marks and pins remain unchanged. No count-limit preflight shortcut
is proposed. A success or refusal retains the final drain boundary.

## Sibling finalization must remain deferred

Calling public `myl_rc_hold_release` for every flat leaf is incorrect: it drains
immediately, while the generic compound walker keeps nonzero walker depth until
all sibling fields have been cleared/released. An early finalizer could otherwise
observe a later sibling that was still held, or run before a later callback was
queued. The release queue is intrusive LIFO, so order is observable to callbacks.

Factor an internal `myl_rc_hold_edge_release(heap, payload)` from the existing
public hold release: validate the live counted header, decrement H, account it and
enqueue death, without draining. The public API still clears its hold record,
calls this helper and drains exactly as before. Flat unloan clears each pointer
slot then calls this internal helper in the same admitted offset order. After all
leaves, clear the whole inline value and drain once. Count-zero values still clear
and drain. Nested finalizers retain `dead.active`; nothing temporarily changes
that state or fabricates walker frames. The same no-drain helper supports prefix
rollback. This avoids both early callbacks and allocation during release.

## Validation required before keeping the candidate

Add production before/after controls for null finalized managed-box types,
nonnull finalized payloads behind generic pointers, raw unique inline fields,
ordinary versus held shape refusal, duplicate aliases near the H limit, late
failure and exact empty output, ownerless lifetimes, pinned/arena/immortal/null
mixtures, budget exhaustion and cold metadata. Include queued finalizers and
multiple dying siblings whose callbacks observe cleared loan storage and verify
identical queue order, plus reentrant allocation/registration/drop. Validate
counted success and failure traffic, not only the final live-object count.

Run the existing loan/history/contract/arena/hold production sanitizer suites and
actual QBE/LLVM guest controls, then measure a frozen schematic or other observed
loan-heavy workload with matching outputs and counts. Keep the change only if it
removes a material remaining cost. Scalar retain, array metadata admission,
allocator ABI changes and compiler proofs remain separate slices.

Proposed implementation ownership is `native_rc_values.c`, the narrow flat-plan
builder in `native_rc_shapes.c`, the private plan/helper declarations in
`native_rc_internal.h`, the extracted H decrement/enqueue helper in `native_rc.c`
and the production loan fixture. No compiler or generic transfer walker edits are
needed. Peer review and parent agreement are pending.
