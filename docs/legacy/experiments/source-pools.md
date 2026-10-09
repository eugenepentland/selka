# C/D: source pools and nominal graph handles
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Source pool declarations, allocator-authorized acquisition, owned transfers,
queries, insertion, snapshot reads, replacement, removal, clear, and handle equality
are implemented. This integrates the [typed-pool backend](typed-pools.md).
[Checked region backing](region-backing.md) now supports arena-backed pools.
[Nested source arena scopes](source-arenas.md) are implemented; generics remain pending.

## Types and operations

```text
pool Nodes(NodeId): Node;
union Link { none, some: NodeId }
struct Node { value: i64, next: Link }
result Open { ok: Nodes, err: i64 }
result Insert { ok: NodeId, err: i64 }
result Read { ok: Node, err: i64 }
result Change { ok: bool, err: i64 }
```

The declaration introduces two nominal types. `Nodes` owns a pool and transfers
by value. `NodeId` is an inert, copyable ID. Its type does not traverse the node
layout, so nodes may contain their own handle category, including through arrays,
records, and variants. Actual recursive by-value layouts still reject. Pool elements
must be copyable values without resource ownership or result obligations. Neither
pool owners nor IDs can be forged with record construction, casts, or domain wraps.
Different declarations produce incompatible handle types even with identical elements.

| Expression | Result |
| --- | --- |
| `acquire_pool<Open>(heap, capacity)` | Owned pool or `i64` error |
| `len_pool(nodes)` | Live nodes as `u64` |
| `capacity_pool(nodes)` | Maximum issued registry slots as `u64` |
| `insert_pool<Insert>(nodes, node)` | Nominal handle or `i64` error |
| `read_pool<Read>(nodes, id)` | Independent node snapshot or `i64` error |
| `replace_pool<Change>(nodes, id, node)` | `bool` success or `i64` error |
| `remove_pool<Change>(nodes, id)` | `bool` success or `i64` error |
| `clear_pool(nodes)` | `true` after clearing |

Operations name an available owner binding. Mutations require `let mut`; reads
and queries preserve the owner. The result declaration must match the exact
operation success type and `i64` error type. Handling, propagation, and explicit
acknowledgement use the existing result rules. Whole-owner references are still
unsupported; helpers transfer owners by value and can return them in wrappers.

Handle `==` and `!=` compare pool identity, slot, and generation, with equal nominal
types required. There is no handle arithmetic or ordering. Comparing an expired
ID is safe; equality does not establish that it is still live. Pool identities
never wrap, and exhausted slot generations retire their slots. Removal and clear
invalidate affected IDs. Acquiring another pool of the same source category does
not make old IDs valid. Graph edges do not retain nodes, so cycles do not prevent
cleanup. Reads retain independent immutable snapshots; replacement, removal, and
pool destruction cannot change or invalidate those snapshots.

Acquisition errors: `1` is a capacity/quota failure (including a negative or
unrepresentable capacity); `2` is pool-identity exhaustion. Operation errors:
`1` is an invalid/removed/stale ID, `2` a foreign pool ID, and `3` exhausted slot
capacity. Host allocation failure remains `OutOfMemory` with VM unwinding. No
implicit retry, resize, or node-reference borrowing is provided.

## Allocation, quotas, and cleanup

Acquisition checks the allocator capability's execution identity and reserves
registry capacity up front. It contributes the transitive `allocation` effect.
Insertion, reads, replacement, removal, clear, and owner cleanup do not grow guest
backing storage; they are allowed under `noalloc`. As elsewhere in the VM, that
contract does not prohibit host bookkeeping allocations for result values,
immutable snapshots, frames, or the compiler itself.

`vm.Options.pool_limits` has independent per-execution limits: `max_pools` (64),
`max_pool_slots` (4096), and `max_total_slots` (16384). Copied allocator grants,
helper calls, and distinct pool categories share this ledger. Slots are logical
reserved registry slots, including retired slots, not a physical byte limit or a
live-node quota. Clear retains the reservation; destroying the owner returns it.
Zero-capacity pools still consume the owner quota. Buffer limits remain a separate
resource category. `pool_statistics` reports acquired/released pools and remaining
live owners/reserved slots, including after runtime traps.

Pool registries now follow `--memory=general` or `--memory=arena` alongside buffers.
Owner wrappers and retained node snapshots continue using the VM parent allocator.
[Checked region backing](region-backing.md) specifies separate allocator lifetimes
and reset guards. [Source arena scopes](source-arenas.md) are implemented.

Owner transfers, records, partial field moves, lexical cleanup, early propagation,
and VM unwinding use the existing ownership machinery. Final owner release clears
nodes, frees registry storage, and returns quotas. Pool cleanup cannot recursively
retain graph edges because their IDs contain no owner references.

## Evidence

`examples/pools.my` returns `52` after constructing a cycle, replacing a node while
retaining its earlier snapshot, reusing a removed slot, checking stale/foreign IDs,
and clearing the graph. `src/pools_test.zig` covers that program, all host allocation
failures, every instruction budget up to completion on both memory backends,
nominal/type/ownership rejection, quota sharing/recovery, ID equality after owner
death and slot reuse, allocation effects, partial construction/field moves,
malformed bytecode, and 10,000 aggregate insert/read/remove cycles under 16 KiB live
runtime storage. Backend tests separately cover identity/generation exhaustion.

The actual CLI runs/checks/dumps the graph, validates formatting round trips, and
rejects forged construction consistently across analysis commands. Scalar native
emission reports `E_NATIVE_FEATURE` for pool programs. Exact discovery is
`exact-v28`; pool operations and nominal handle types remain distinct checked facts.
