# C: checked region backing for buffers and pools

Implemented the runtime storage and lifetime foundation for nested source arena
scopes. Source `arena` syntax and static escape checking are **not implemented yet**.
This milestone also makes existing source pools use arena backing when executed
with `run --memory=arena`, alongside buffers.

## Shared backing and authority

`memory.Store.beginRegion(parent)` derives an allocator capability with execution
identity and a generational region ID. `endRegion(capability)` rejects active child
regions or retained backing users without changing storage. On success it destroys
arena chunks and invalidates the capability. Copies of ended capabilities remain
invalid after registry-slot reuse. Root capabilities cannot be ended as a region;
capabilities from other stores reject. The default limit is 256 issued region slots,
configurable through `memory.Limits.max_regions`; ended slots reuse generations,
and exhausted generations retire as in the typed-pool registry.

Regions have stable heap-allocated arena metadata. Each arena obtains independent
chunks from the execution allocator. Parent/child links constrain lifetime rather
than placing a child's chunks inside its parent's arena. Region metadata and the
registry use the execution allocator and remain bounded across repeated scope use.

`createAuthorized(capability, element, values, capacity)` allocates buffer backing
from the selected region while retaining node values through the execution allocator.
Every cell records its backing allocator and region lease. Growth and destruction
use that original allocator. The VM checks that `reserve_buffer` receives the same
region authority as the owner; an unrelated allocator cannot change its lifetime.
All regions still share the existing buffer quotas and ownership/borrow registry.

`pool_runtime.Runtime.acquireAuthorized` uses the same backing lease mechanism.
Pool owner wrappers and retained values use the execution allocator; registry entries
use the selected arena. `typed_pool.Pool.value_allocator` separates the allocator
passed to value-release hooks from the registry allocator. Replacing or clearing a
pool must never free parent-allocated node snapshots through an arena allocator.
Existing parent-only callers can keep using `Runtime.acquire`.

Backing leases count buffers, pools, and trusted embedding users, including
zero-capacity owners. Failed allocation/acquisition returns the lease. Normal owner
cleanup releases storage before returning its lease. Region closure therefore cannot
free storage beneath an owned buffer, pool, or active buffer borrow. Snapshot values
and inert graph IDs retain their existing independent lifetime semantics.

## Reset and teardown

Execution-arena reset now rejects live root pool backing leases before clearing any
buffers. This is separate from its existing live-borrow preflight. The rejection
leaves buffer identities and contents intact. Explicit nested regions own independent
chunks; a Store reset still invalidates all buffer cells but does not end their region
capabilities or reset those separate chunks.

Store/Arena teardown requires external pool owners and embedding backing leases to
have released first. It can then unwind buffer cells and borrows, release retained
values, and free region chunks. The VM already destroys locals/operands before its
memory store. Stable snapshots still require their execution allocator to outlive them.
The new manager API is an embedding/backend contract, not an untrusted guest API.

## Evidence and next source work

`src/regions_test.zig` covers nested buffer/pool backing, snapshot retention across
region end, every allocation failure, copied/foreign/stale capabilities, shared region
slot limits, live-borrow and live-pool closure rejection, transactional execution-arena
reset rejection, parent-only value release during clear, zero-capacity owners, and
10,000 mixed buffer/pool region cycles under 16 KiB live runtime allocation. The
existing actual CLI pool fixture runs in both general and arena modes.

The next source step must express lexical arena boundaries, track allocator/owner
provenance through wrappers and helpers, reject outward assignment/return/borrow
escapes, and close regions after ownership cleanup on normal exit, propagation,
return, and traps. Dynamic lifetime checks remain necessary alongside those static
rules. No source-level arena acceptance or completion of track C is claimed here.
