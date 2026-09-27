# Stage 4 scalar-loop readiness reuse: read-only proposal

This proposes a bounded compiler change, not an implemented optimization. The
runtime query remains unchanged. A deliberately unchecked private QBE diagnostic
shows that repeated readiness validation is a material remaining cost even when
actual RC traffic is nearly absent. Root approved that diagnostic only; production
implementation requires review of the boundary below.

## Attribution and limit of the evidence

The immutable type-fact candidate `c71d4046` / Debug compiler `2db0563a…` has these
full-workload counts: scalar append has one O acquisition, one H acquisition, one
uniqueness check and ten heap allocations total; sieve has one O, one H, six
uniqueness checks and two allocations. Repeated ownership increments do not
explain their remaining 4.25× / 5.08× QBE instruction costs versus accepted GC.

The room append path calls `myl_rc_list_plain_ready` for every scalar append that
fits. Even a repeat-cache hit validates heap/state, pending deaths, the actual
native element kind/width, table capacity, current slot bounds/key/kind, and the
binding's zero-edge flat plan. The QBE assembly has two out-of-line helper calls;
LLVM inlines this validation. This is real runtime admission, not redundant
work that may simply be removed without a proof.

On **private copies** of the immutable QBE production/counting binaries, the
six bytes at the query's function entry were replaced with `mov eax,1; ret`.
Original files remain unchanged. Capacity, generation, scalar store, growth and
all other paths remain intact, but all admission checks are deliberately absent.
This diagnostic is unsafe for general use. It is not an optimization, fallback
implementation, correctness result or Stage 4 acceptance measurement.

| QBE workload | Original instructions | Constant-ready diagnostic | Diagnostic/original | Original/GC | Diagnostic/GC |
|---|---:|---:|---:|---:|---:|
| Full scalar append | 2,518,576,834 | 1,414,578,310 | 0.561658 | 4.252234× | 2.388300× |
| Full sieve | 4,180,750,676 | 2,800,750,541 | 0.669916 | 5.084233× | 3.406007× |

These are alternating median-three runs on CPU3, all twelve raw instruction
observations at 100% event running. Outputs and separate counted executions
match. The original/copy hashes, exact byte offsets and bytes are archived in
[the diagnostic bundle](../../experiments/d9-rc-scalar-readiness-audit-20260927/README.md).
The GC denominators are the same archival completed-row references as the
[type-fact report](d9-rc-native-type-facts-2026-09-27.md), not fresh interleaved GC.
Removing the query's work alone cannot meet the gate. The diagnostic also omits
its private repeat-cache hint writes; a real candidate must be measured rather
than adopting this ratio as its predicted result. There is no corresponding LLVM
binary patch: the query is inlined, so only assembly inspection supports that
backend's current attribution.

## Proposed proof and operation boundary

Reuse only a **successful actual admission**, not a static assumption about type
or a count-free shape. The function remains in canonical RC lowering; no new C
ABI, cached heap pointer, global state or changed runtime query is proposed.

Initial admission is deliberately lazy. A per-certified-loop/root flag begins
invalid. At the first real room-append point, after the normal scalar evaluation,
COW and capacity/generation checks, the existing query executes. A successful
answer authorizes reuse only inside the proven interval. If the flag is invalid
or the query refuses, use the complete current path. Zero-iteration loops and
traps before the first append therefore perform no new query.

Every slow append invalidates the flag **before** its runtime call. A later room
append must re-run the actual query; do not refresh eagerly after the slow call.
This retains exact call/step ordering and handles cold registration, growth,
custom allocation hooks, callbacks, reentrant registration and queued deaths
without carrying a cached result across them. A refused query likewise reaches
the original slow append and leaves the flag invalid.

Between successful admission and reuse, the certificate must prove all of:

- One stable canonical named ordinary owner slot and exact managed-list header.
  Reuse the final physical loop-entry uniqueness proof and exact source-role
  proof, not merely semantic liveness or a type-wide `mayHold` answer. The root
  cannot be moved, rebound, pattern-written, aliased into writable storage or
  accessed through caller/ref/projected storage in the interval.
- Builtin plain scalar element, width1/2/4/8, with no O/H/unique contents. The
  actual runtime query still validates the registered binding and empty queue.
  All metadata consulted by that answer is immutable for the header lifetime.
- The admitted success span contains only closed scalar operations and direct
  same-root length/read/write/append operations whose lowering has no callback,
  allocation, ownership publication/release, scope transition or hidden helper
  effect. Known bounds/arithmetic failures still trap at their original point;
  they do not resume with a stale flag. Initially refuse unrelated managed roots,
  unknown calls, managed aggregate producers, semantic SHARE, captures or COW
  detachment inside the loop. Any permitted slow append is an explicit cache
  invalidation boundary.
- Every CFG entry reaches flag initialization, and every use reaches a successful
  query without an invalidating operation. Refuse external interior entries,
  uncertain backedges, overlapping/nested candidates that cannot preserve this
  induction, or any possible cleanup/publication between producer and use.
  Keep the existing bounded function/loop scan limits; proof refusal preserves
  current lowering.

The death queue is empty when admission succeeds. Direct scalar stores and
arithmetic cannot enqueue a death or invoke a finalizer. If the loop is itself
inside finalizer guest reentry, no outer drain resumes during that closed span;
initial admission still refuses a nonempty pending queue. Every potentially
allocating/callback-bearing slow path invalidates before reentry. Thus this
proposal does not relax the per-operation queue check generally: it proves that
its answer cannot change between selected operations, then checks again after
any operation that could change it.

## Checks and accounting that remain per operation

Capture the evaluated scalar before writes, as today. Read the current list
length, capacity and generation each time; keep room and generation-overflow
checks and the exact existing slow fallback. Do not cache backing addresses,
length/capacity, generations, region or allocation budget. Growth still uses the
receiver's real region, current capacity/overflow/limit checks and allocator;
no pre-sizing, reserve widening or amortized-budget assumption is allowed.
Uniqueness stays at the already-proved entry, with all original guards and
fallback checks; this slice does not infer O/H state or remove physical holds.

Bounds, arithmetic, logical steps, source locations, trap cleanup and partial
allocation behavior remain. A small cache word, if emitted, must use the existing
accounted frame-storage machinery for both stack and heap frames. It may not be
an unaccounted `alloc` or overlap live operand, pending, scope or journal storage.
Exact hook/storage choice is a review item, not justification to change the
ownership-frame ABI or ratchet.

## Decisive controls before retention

Positive controls: scalar widths and domains, repeated and zero-iteration loops,
multiple room spans separated by actual growth, cold element registration,
heap/inherited-arena receiver, aliasing scalar RHS, and later real iteration H
semantics. Demonstrate lazy query placement in emitted code and unchanged
step/trap behavior before the first append.

Negative controls: any callback or unknown helper in the loop; owner publication,
cleanup or extra root mutation; actual H/LOAN inputs; ref/caller/projected roots;
managed/unique/zero-sized element types; alternate entries; arena transitions;
semantic snapshot/history; ambiguous nested loop authority. Refused cases must
keep the old per-operation query.

Runtime/embedding controls: queued finalizer at initial admission; reentrant guest
with pending sibling deaths; slow growth that registers metadata or queues work;
custom allocator failure; generation maximum; byte-budget and region refusal;
finalizers observing the scalar/list length at unchanged boundaries. The flag
must be invalid on every return from an intervening slow operation, successful
or otherwise; no proof may depend on production allocator hooks alone.

Measure unchanged full append and sieve on actual QBE and LLVM O3/full LTO with
an immutable matched compiler pair, exact output/counters and median-three
instructions. Include alloc_churn, Lox and schematic controls. Keep the deliberately
unchecked diagnostic separate. The remaining GC gap must be reported even if
this bounded candidate wins.

## Deferred Lox runtime direction

The type-cache after-profile still has approximately 10.7% QBE sample weight in
`walk`, 6.3% in `visit`, and substantial native loan/unloan and descriptor work.
One ordinary variant transfer can seed/clear active edges, visit/acquire them,
then later walk them again for unloan. Existing flat plans refuse variants.
A root-variant active-arm plan could remove repeated structural traversal, but
needs all-arm unique validation, global depth/refusal equivalence, exact leaf
order/duplicate rollback, dynamic finalizer checks, valid tag handling and one
final drain. It is not authorized or implemented here.

The adjacent-switch compiler candidate removes 37 whole Object loans, including
hot string/property/frame sites, while preserving selected-arm retain and list
writes. Its joined dynamic results must precede prioritizing a general variant
runtime plan; old Object sampling alone would overstate the remaining opportunity.
