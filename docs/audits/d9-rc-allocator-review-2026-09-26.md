# D9 RC allocator and iterative-release review

This is a design-only review of the joined stage-3 runtime, coordinated with
the owner/hold/pin and compiler-action contract reviews. No RC implementation
or performance claim is made. Stage-3 acceptance remains a prerequisite.

## Allocation representation

The proposed 32-byte RC prefix can preserve the existing common header:
owners at payload minus 32, holds at minus 24, mark/count/flags at minus 16,
descriptor at minus 8. Keep the 16-byte GC, arena, and literal headers distinct.
Every retain, release, hold, and uniqueness operation must check the common
immortal/arena flags before accessing a prefix that those objects do not have.
Resolve GC versus RC at the artifact/heap boundary; the common flags do not
make arbitrary GC heap pointers into valid RC pointers.

The following allocator decisions must be frozen with that layout:

- Preserve 16-byte payload alignment and checked extent arithmetic. Both
  allocation and growth currently compute `16 + element->size * count`.
  RC heap paths need their full allocation prefix in size-class selection,
  overflow checks, large-object allocation, zeroing, budget charge, and free.
  Arena traversal and immortal literals retain their own extents.
- `qbe_alloc.zig` embeds header size, class strides, field offsets, fresh mark
  values, and heap-window offsets. A common-header-compatible prefix does not
  make its allocation fast path compatible automatically. The RC branch must
  initialize owner/hold state, and its slow path and inline path must agree.
- Choose allocator metadata and immediate slot reuse explicitly.
  `native_heap.c::myl_native_heap_release` currently searches the entire
  segment list, then leaves a freed slab slot unavailable until a later sweep.
  That deliberately rare GC helper is not a suitable RC deallocator. RC needs
  bounded allocation lookup, reusable free slots, and accounting when a slab
  or large reservation becomes empty. Removing collections cannot leave the
  old sweep as the only way to recover space.
- `myl_native_heap_extend` may `realloc` an oversized reservation. Its RC
  counterpart must preserve count/state/accounting and must not move an
  allocation still named by a lifetime hold or an interior address. A legal
  mutation with such a capture needs a stabilized or retired backing path,
  rather than rejecting a previously supported source operation.
- Count overflow must fail before publishing a new owner or hold; it must not
  wrap into zero. Reused slots must initialize all count/state words. Deferred
  destruction queues, allocator metadata, and retained retired storage must
  remain charged to the same heap budget.

Size-class effects should be measured, not approximated as 16 bytes per
language value. With the current class table, an 8-byte box body moves from a
32-byte allocation to 48 bytes, and a 72-byte list header from 96 to 112 bytes.
The dictionary header currently fills the 320-byte class; an extra 16-byte
prefix moves that allocation to the 384-byte class. These are layout-derived
costs if those classes are retained, not measured RC RSS results.

## Physical edges and metadata lifetime

A tracing scan is a reachability graph, not a ready-made RC ownership graph.
The proposed contract should assign ownership exactly once to each live
logical element, key, value, box field, and backing allocation. Duplicate
header aliases, unused capacity, dead dictionary entries, cached probe keys,
and interior view addresses are not additional value owners.

The coordinated proposal is for collection headers to own their live logical
element edges while backing blocks own raw storage. A dictionary's private
entry-list header is storage bookkeeping, not a second owner of every key and
value. This makes the descriptor problem explicit: currently `entry_type`,
`entry_fields`, and `entry_scan` live inside the dictionary, and both the
entry-list's `element` and its backing allocation's descriptor borrow that
metadata. If an RC backing can outlive its dictionary, it needs a stable raw
allocation descriptor/extent; it cannot keep a dangling entry descriptor.
Any remaining independently surviving descriptor user needs independent
metadata lifetime. Giving backing a counted pointer back to its dictionary
would create a runtime cycle and is not a solution for acyclic RC.

Current list backing headers record capacity, not initialized length. Growth
copies live elements and abandons old storage to GC; dictionary deletion may
leave dead entry bytes until compaction. RC growth, replacement, pop, clear,
and compaction must transfer or release logical edges once and leave stale
bytes non-owning. A generic capacity-wide release plus header-level element
release would double-count them.

Byte views are an important exception to pointer-shaped intuition:
`native_bytes.c` stores an interior address in `storage` and the canonical
backing allocation in `work.owner`. The latter is the owning edge. A mutable
buffer's `work.owner` is instead an alias/marker for its already-owned backing
after snapshot publication. Do not retain both aliases, derive a managed
header from a view's interior `storage`, or reuse the list's drop-link fields
as a generic RC queue: those fields already carry live backing information.
Text views likewise retain their canonical text owner.

An interior receiver capture must hold its logical ancestors and the exact
required leaves/backing, not raw bytes alone. If a callback replaces the
parent, a retained backing's bytes do not by themselves retain the child
values they name. Coordinate the finite receiver capture with the scoped-pin
contract so those leaves remain usable at zero ordinary owners. Existing
growth and compaction behavior must remain supported through stabilization.

## Iterative destruction and failure

The two owner/hold words can be repurposed as intrusive work-link and cursor
storage only after both counts reach zero and an explicit DYING state has
been installed. A release must enqueue that transition once, forbid
resurrection, preserve the common descriptor/count/extent until final free,
and keep queued memory unavailable to the allocator. Restore pin state before
the last hold release, which may trigger this transition.

A link and cursor are not, alone, a proof of a complete destructor. The
contract must define how a cursor resumes direct-edge traversal across
records, arrays, active variants, and collections without restarting scans or
recursing one native frame per heap node. Generated direct-edge release plans
or a bounded inline-descriptor traversal can support an allocation-free heap
worklist. Million-node chains and broad shared DAGs must both have bounded
host-stack use and linear work in the released edges. Release at the memory
limit cannot depend on allocating a larger queue.

If embedded metadata remains, parent destruction needs a continuation that
keeps it alive until every descriptor-dependent child finishes. Simply
enqueueing children and freeing the parent is invalid. Merely postponing the
parent until its immediate child is visited is also insufficient if that
child remains alive through another owner or hold. The raw-backing ownership
proposal avoids this dependency only when all such users follow it.

Constructors currently rely on GC to reclaim partial allocations:
`myl_native_list_new`, `myl_native_list_clone_at`,
`myl_native_dictionary_new`, and `myl_native_dictionary_clone_at` can return
NULL after creating a header or backing. RC producers need one owned result
on success and explicit rollback of initialized edges on failure, with the
source unchanged. Zeroed managed fields and an initialized-edge boundary must
make partial destruction valid. Raw uninitialized byte blocks are never
interpreted as value edges. Region escape has the same requirement for its
source-to-clone map, partial clones, and already-outer shared values.

Arena allocations retain the 16-byte header in this proposal. Region close
must enumerate each logical heap edge once before recycling chunks; it cannot
blindly reuse `arena_trace` over all allocations and also destroy collection
elements from their headers. Receiver scopes targeting that arena must unwind
first. Region escape must establish clone edges once, preserve DAG sharing,
and roll back without releasing the still-live source or double-releasing an
outer value.

Finally, immediate RC reuse changes weak-cache invalidation. Dictionary span
probe misses currently compare `heap->collections` before trusting a cached
pointer identity. Free/reuse needs an explicit equivalent epoch or cache
invalidation rule; eliminating GC while leaving that epoch unchanged can
reuse a stale absence answer. Define wrap behavior too. Unique resource drop
hooks remain separate from ordinary shared-value release, with explicit
reentrancy and exactly-once cleanup rules.

## Validation obligations for implementation

The eventual implementation needs layout assertions, allocation/growth/failure
checks at class boundaries, immortal and arena prefix checks, forced allocator
reuse, partial-constructor rollback, held retired backing, byte/text views,
dead dictionary entries, and dictionary destruction under a retained receiver.
Run million-deep chains and wide DAGs at a memory ceiling, with count/edge
invariants and final live-allocation accounting. Include arena-to-heap edges,
nested scope unwinding, and span-cache pointer reuse. These checks supplement
the full correctness, performance, and RSS gates; this review ran no RC code.
