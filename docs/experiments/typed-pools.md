# C/D: typed-handle pool foundation

Status: backend implemented in `src/typed_pool.zig`; [source declarations and
operations](source-pools.md) now integrate it with the compiler and VM. [Checked arena backing](region-backing.md) also integrates with the runtime.
Source arena scopes remain pending. This experiment does not complete C or D.

## Identity and storage

`Handle(Tag)` gives each nominal host tag a distinct handle type independently
of its payload layout, allowing recursive graph edges. Each handle records pool
identity, slot index, and generation. Pool identities are unique across payload
specializations; foreign, closed, removed, out-of-bounds, and stale handles are
rejected before payload access. Pool identity exhaustion fails instead of wrapping.
An exhausted slot generation retires that slot permanently.

`Pool(Tag, T)` supports reserve, insert, snapshot get, replace, remove, clear, and
idempotent deinitialization. Removed slots are reused with new generations.
`clear` releases live payloads and invalidates their handles while retaining the
slot allocation. Graph edges are inert IDs, so cycles do not retain graph nodes.
Payloads release in descending slot order during clear, not acquisition order.
This is not the external-resource completion or cleanup-order contract.

No pointer or borrow into movable slot storage escapes. Reads return snapshots
under the configured retain/release hooks. Plain copyable values use default
hooks; immutable guest aggregates use `Value.retain` and `Value.release`.
Callers release retained snapshots with the same policy. Hooks must be non-failing
and must not reenter the pool. Initialized pools must not be copied, and their
allocator must remain valid until all retained payloads are released. This API is
not a concurrent container or an ownership model for move-only source resources.

## Failure and cost

Registry growth happens before an inserted value is retained. Failed growth
preserves existing IDs, values, and input ownership. Replacement retains the new
value before releasing the old value, permitting self-replacement safely.
After reserve, plain-value insertion within the reserved slot capacity, reads,
replacement, removal, and clear do not allocate. Hooks may have their own costs.

The configured limit bounds issued slots, including permanently retired slots.
It is not an exact byte budget: backing capacity can overreserve, and payloads or
retained snapshots can own additional allocations. Insert/get/replace/remove are
constant-time apart from allocation and hooks; clear scans all issued slots.
Cumulative insertion/removal counters saturate.

## Acceptance evidence

`src/typed_pool_test.zig` and the identity test in `src/typed_pool.zig` cover:

- Distinct nominal categories, foreign instances and payload specializations,
  closed/reinitialized stores, invalid indices, and generation exhaustion.
- Traversing a cyclic graph, removing a node, reusing its slot, rejecting the
  stale edge, and explicitly repairing the edge to the replacement node.
- Repeated clear preserving capacity while invalidating old handles.
- Reserved operations with allocation disabled, failed registry growth preserving
  the graph, and failed insert/invalid mutation preserving payload ownership.
- Immutable guest snapshots surviving replacement and clear, with every allocation
  failure exercised and testing-allocator leak checks.
- 10,000 graph creation/clear cycles within 4 KiB live allocation and zero bytes
  remaining after deinitialization.

[Source acceptance](source-pools.md) now covers nominal guest handle diagnostics,
recoverable pool errors, source ownership/effects, and graph programs through the CLI.
Nested source arena experiments must still establish escape rules and backing
allocation behavior. Host generic pool tests alone do not establish those language guarantees.

`value_allocator` optionally selects the allocator passed to release hooks, separate
from registry storage. Set it before insertion; release returned snapshots with that
same value allocator. This supports parent-owned values in arena-backed registries.
