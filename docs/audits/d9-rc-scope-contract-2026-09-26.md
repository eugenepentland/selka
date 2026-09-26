# D9 RC owner, hold and receiver-scope contract proposal

This is a design-only proposal for the serial WP-4 interface step. No RC code
or acceptance claim is introduced. Stage-3/default and WP-4pre acceptance
remain prerequisites. It supplements the [readiness inventory](d9-rc-readiness-2026-09-26.md)
and coordinated [allocator review](d9-rc-allocator-review-2026-09-26.md).
The [compiler ABI review](d9-rc-compiler-contract-2026-09-26.md) supplies the
matching action-plan and call conventions.

## Counts and physical edges

An RC heap allocation has ordinary owners O, lifetime holds H, and pin state P.
An owner represents an owning local/result or a live logical container edge.
A hold preserves lifetime without creating a snapshot. Destruction begins only
at O=H=0; a hold never causes COW detachment by itself. A pending receiver can
remain usable at O=0,H>0 after its parent is replaced. Such access requires the
live receiver hold, not an invented ordinary owner. Nested pins restore the
previous state. Immortal and arena allocations are separate representations;
check their common flags before accessing an RC prefix.

Fresh runtime success results carry one already-owned reference. Receiving
that result transfers its token without incrementing. Construction records
initialized edges and aborts them explicitly; no floating-result adoption or
recursive adoption walk. Count overflow fails before publication or count
change; underflow, double release and resurrection of a DYING object are
internal invariant failures. The serial interface must freeze the located
count-limit diagnostic and construction-state representation.

| Component | Owning edges |
| --- | --- |
| List/container header | Live logical elements and its backing allocation |
| Dictionary header | Live keys/values and private storage/bookkeeping |
| Raw backing block | Bytes only |
| Immutable box | Direct managed children |
| Bytes/text view | Canonical backing owner, never an interior address |
| Receiver scope | Explicit holds and journal storage |

Capacity padding, deleted dictionary entries, duplicate bookkeeping pointers
and retired backing bytes are not additional value owners. A dictionary's
private entry-list is storage bookkeeping, not a second owner of keys/values.
This ownership graph is deliberately distinct from the GC reachability graph.

## Proposed entry points

The following names and opaque types are an interface draft, not declarations
already supplied by the runtime. A slot identifies its descriptor, address,
container if any, and destination region. A place describes an already
evaluated receiver and finite projection; it executes no guest expressions.
Status distinguishes success, allocation refusal, count limit and region error.

```c
myl_rc_status myl_rc_new(myl_native_heap *,
    const myl_rc_alloc_request *, void **out);
myl_rc_status myl_rc_value_copy(myl_native_heap *,
    myl_rc_slot *dst, const myl_rc_slot *src);
myl_rc_status myl_rc_value_take(myl_native_heap *,
    myl_rc_slot *dst, myl_rc_slot *src);
myl_rc_status myl_rc_value_replace(myl_native_heap *,
    myl_rc_slot *dst, myl_rc_slot *src, myl_rc_transfer mode);
void myl_rc_value_drop(myl_native_heap *, myl_rc_slot *);
void myl_rc_value_relocate(myl_rc_slot *dst, myl_rc_slot *src);

myl_rc_status myl_rc_hold_acquire(myl_native_heap *,
    void *payload, myl_rc_hold *);
void myl_rc_hold_release(myl_native_heap *, myl_rc_hold *);
void myl_rc_scope_begin(myl_native_heap *, myl_rc_scope *);
myl_rc_status myl_rc_scope_hold(myl_rc_scope *, void *payload);
myl_rc_status myl_rc_scope_pin(myl_rc_scope *, void *payload);
myl_rc_status myl_rc_scope_prepare(myl_rc_scope *, const myl_rc_place *);
void myl_rc_scope_end(myl_rc_scope *);

myl_rc_status myl_rc_unique_owned(myl_native_heap *, myl_rc_slot *);
myl_rc_status myl_rc_unique_borrow(myl_native_heap *,
    const myl_rc_slot *, const myl_rc_scope *, myl_rc_edit *out);
void myl_rc_edit_abort(myl_native_heap *, myl_rc_edit *);
void myl_rc_edit_commit(myl_native_heap *, myl_rc_slot *, myl_rc_edit *);

myl_rc_status myl_rc_region_escape(myl_native_heap *,
    myl_rc_slot *dst, const myl_rc_slot *src);
void myl_rc_arena_close(myl_native_heap *, unsigned depth);
void myl_rc_drain(myl_native_heap *);
```

`new` returns one owned allocation or NULL. Copy/take initialize an empty
owning destination. Both honor snapshot and pin semantics; take clears its
source only on success. Replace prepares the incoming value before releasing
the previous edge, including self-aliasing cases. Failed publication leaves
source/destination ownership unchanged. Drop clears its owning slot and is
allocation-free. Relocate is an internal, proven movement of the same logical
value, not permission to publish an independent snapshot.

This distinction also applies to consuming collection results: removing the
last ordinary owner of a pinned leaf into a callback result may require copying
the finite pinned path. The original remains O=0,H>0 for its pending mutation.
A last-use classification alone does not authorize bypassing pins.

`unique_borrow` never consumes the parent's owning edge. Its tagged edit
result is either the same borrowed pointer or a fresh owned pointer. The old
parent edge stays intact until commit; abort releases only a fresh token.
Commit of borrowed reuse has no count churn. Commit of a fresh token replaces
the authorized parent edge, then releases the old one. The compiler must prove
the closed edit still owns that slot; it must not resurrect a parent entry a
callback replaced. Captured pending receivers instead remain usable through
their holds. `unique_owned` can consume/replace its input owning token directly.

## Boxes, scopes and cleanup

An unpinned immutable-box transfer retains only the box, in O(1). Materializing
an owned private body acquires its direct managed children and stops at child
boxes. A pinned transfer copies only the finite protected path. Immutable
bytes and collection-free boxes still need RC accounting when COW needsCopy
is false. A scoped projection is a protected borrow, not a new snapshot.

Preparation installs an empty scope on the dynamic cleanup chain before any
fallible work, captures receiver/key/index values once, and protects ancestors
while detaching the selected path. Each journal entry owns a hold and records
prior pin state. Replacement ownership is committed before the previous edge
is released. Bounds and missing-key errors stay at their original evaluation
points; preparation must not move them ahead of callbacks.

An interior capture holds its logical ancestors, exact required backing and
finite candidate leaves/boxes, or uses stable materialized inline storage.
Header holds alone do not preserve backing after growth; backing holds alone
do not preserve children removed by a callback. Legal growth and compaction
remain supported through stabilization. Relocation transfers logical edges
without adding snapshot owners for retired bytes.

On partial preparation failure, release new holds and restore new pins. Already
committed value-equivalent detachments may remain. No clone or journal node
may rely on tracing GC to reclaim it. Normal and error cleanup use this order:

1. Stabilize any escaping result into its required ownership while sources live.
2. Unlink/deactivate the scope so an epilogue cannot reinstall it.
3. Restore all recorded pin states in reverse acquisition order.
4. Release holds and journal storage exactly once; the final hold can destroy.
5. Continue local/resource cleanup and drain newly dead objects.

Empty and partially prepared scopes are closable. Outer scope holds and pins
survive nested cleanup. Scope links have explicit ownership; former root
records/descriptors provide no RC lifetime guarantee.

## Arenas and destruction

Arena allocations retain their distinct header and bulk lifetime initially.
Conservative arena sharing flags may continue governing COW. Every arena-owned
edge into the RC heap acquires ordinary ownership and releases it at replacement
or region close. Arena-to-older-arena references rely on dominance rather than
an RC prefix. Heap/older-region edges into a younger region remain invalid.

A hold never extends a chunk's lifetime. Region close first finishes escape,
unwinds scopes whose lifetimes end there, drops owning locals, and releases
committed logical arena edges exactly once before recycling chunks. Outer
receiver scopes may survive callbacks opening/closing younger arenas. A
replacement clone uses the receiver's required region, not merely the current
active arena. Failed escape leaves source usable and destination empty, rolls
back initialized clones, and preserves source-to-clone DAG sharing.

Release must be allocation-free with bounded native-stack usage. Use an
intrusive dead-object queue or allocator-reserved storage, with an explicit
DYING transition. Direct-edge traversal workspace must exist before objects
requiring it are published. Enumerate owned edges while container metadata is
valid, enqueue newly dead children, then free storage. A million-node chain
must not consume a million native frames.

Dictionary entry/storage descriptors currently borrow dictionary-embedded
metadata. Raw RC backing requires stable allocation metadata; any remaining
independently surviving descriptor user needs independent metadata lifetime.
A parent continuation alone is insufficient when a child survives through a
hold. Do not reuse list.work for queue links: bytes views own backing there,
while a mutable buffer's work.owner is only an alias/snapshot marker.

The allocator review additionally requires immediate-reuse metadata and an
explicit dictionary span-cache reuse epoch. Unique resource cleanup remains
separate from shared-value count changes, with exactly-once and reentrancy
rules. These representation, traversal and error details must be frozen in
the serial step before implementation branches start. No RC validation was
run for this design report.
