# C: owned-buffer runtime foundation

Status: backend implemented. [Source buffer acquisition and ownership](owned-buffers.md)
now integrate move checking and partial-construction cleanup into the language.
[Buffer operations/views](buffer-operations.md) are also implemented. External resources, capabilities/effects, and arenas/pools
remain pending. C is not complete.

## Ownership and storage

`memory.Store` reuses the allocation and lease registries established by B.
`createWithCapacity` retains homogeneous ordinary Value snapshots, recording
initialized length separately from reserved capacity. Reads, writes, and borrows
cannot expose spare slots. Buffer elements do not yet contain resource owners.

`transfer` consumes an allocation identity by advancing its generation without
allocating or copying its contents. Every alias of the old handle becomes stale.
Active borrows reject transfer. Generation exhaustion returns an error while
leaving the current owner valid; destroying an exhausted slot retires it instead
of wrapping into an old identity. A copied backend handle is an access alias,
not an independent owner. Source move checking is still required.

`reserve` allocates new backing storage and transfers the initialized values only
after allocation succeeds. Failed growth preserves contents, capacity, identity,
and accounting. It refuses active borrows, including requests requiring no growth.
`appendWithinCapacity` and `resizeWithinCapacity` never allocate; growth beyond
capacity returns `NoCapacity`. Shrinking releases initialized values in reverse
order. Snapshot reads remain valid after reserve, shrink, transfer, or cleanup.

Limits bound capacity per buffer, total reserved element slots, and live allocation
count. `CapacityLimit` is distinct from host `OutOfMemory` and `NoCapacity`. These
are slot quotas, not total-byte bounds: registry storage, nested aggregate values,
and transient old/new backing storage during reserve are additional costs. Runtime
statistics count live allocations/capacity, successful creations, transfers, and
releases; cumulative counters saturate. These backend errors are not yet guest
recoverable result values.

## Partial acquisition and cleanup

`owned_scope.Scope` owns registered allocations until release or transfer.
Acquisition/adoption and cross-scope moves reserve cleanup-record storage before
consuming ownership, so metadata allocation failure leaves the previous owner
valid. `adopt`, `take`, and `moveTo` all invalidate the old access identity.
Cross-store moves are rejected. Registered owners must be transferred through the
Scope API rather than directly rekeyed through Store.

Normal `release` and reverse-order `rollback` refuse live borrows. If rollback
releases B then encounters a borrowed A, B stays removed; ending A's loan permits
retry without double release. Rollback performs no allocation.

Terminal `deinit` handles partial acquisition, host failure, or traps by invalidating
all loans for each registered allocation before releasing it. This includes nested
reborrows while preserving loans to unrelated allocations. Loan invalidation scans
the lease registry per owner; it is not a constant-time operation. Scope metadata
is then freed. Repeated deinitialization is harmless. Store must outlive its scopes;
neither initialized Store nor Scope may be copied. No user-defined destructors or
external-resource cleanup effects exist at this checkpoint.

## Acceptance evidence

`src/owned_scope_test.zig` and the generation test in `src/memory.zig` cover:

- Stale identities, borrowed transfer/growth rejection, and generation exhaustion.
- Initialized bounds, exact element types, capacity exhaustion, and quota recovery.
- Acquire A, fail acquiring B, release A exactly once; successful transfer survives
  scope cleanup. Also acquire A/B, reject C, release B first, and retry borrowed A.
- Adoption, taking, cross-scope/self moves, and foreign-store rejection.
- Failed reserve and destination metadata allocation preserving the original owner.
- Successful reserved edits, transfer, destruction, and nonempty rollback with an
  allocator configured to reject every allocation.
- Nested aggregate snapshots surviving growth, shrink, moves, and terminal unwind.
- Every allocation failure through aggregate acquisition, growth, scope moves, and
  nested borrowing, with testing-allocator leak checks.
- 10,000 acquisition/move/borrow/cleanup cycles within 16 KiB live allocation and
  zero live bytes after final cleanup.

The full Debug and ReleaseFast suites pass 211 tests (186 core, 25 actual CLI).
The CLI count is unchanged because this checkpoint adds no source syntax.

## Integration progress

[Source ownership and acquisition](owned-buffers.md) now implement buffer types,
move semantics, wrappers, fallible guest acquisition, and lexical/early-return
cleanup through the typed representation and VM. The remaining integration adds
allocator/external capabilities, transitive effects
including cleanup, and arenas/pools.
