# C: arena backing and checked region reset

Status: backend implemented in `src/arena.zig` and `src/memory.zig`. Guest arena
syntax, scoped allocator grants, source escape checks, and VM integration remain
pending. This experiment does not complete the arena language feature or track C.

## Region lifetime

An Arena owns a memory Store and Zig arena allocator. Initialize it at its final
address and never copy or move it: the Store's backing allocator points into its
owning Arena. The runtime parent allocator must outlive all retained snapshots.

Buffer backing uses the arena. Memory/lease registries and retained aggregate
payloads use the parent runtime allocator. Buffer creation and growth retain the
existing type, quota, allocation-identity, and borrow checks. Arena backing can
accumulate replaced or individually destroyed buffers until the next reset; live
buffer capacity is therefore not a bound on the arena's physical allocation.

Normal reset first checks every live allocation for outstanding shared or
exclusive borrows. Nested, suspended, and empty loans also prevent reset. A borrow
conflict returns before any allocation changes, so the whole region remains usable.
After preflight, reset removes every live allocation, advances its generation (or
retires exhausted slots), releases its initialized payloads, and frees its buffer
storage. The arena then resets its backing. Old allocation IDs cannot revive when
slots are reused. Ended lease IDs remain expired through registry reuse.

Reset preserves the memory identity, allocator grant, limits, cumulative statistics,
and registry capacity. A grant authorizes allocation in the next cycle, not access
to an old allocation. Independent arenas keep independent identities and loans.
Retained immutable snapshots remain valid because their payload allocation belongs
to the runtime parent, not the resettable backing.

Terminal deinitialization releases live cells even with outstanding loans, then
frees both registries and backing. Closed-store checks invalidate all prior handles
and allocator grants. Repeated deinitialization is harmless.

## Reset cost and retention

The memory Store's checked reset performs no allocation. It scans issued cell slots
before releasing live values in descending slot order. Element release runs in
reverse element order. This is not the external-resource acquisition-order cleanup
contract; the supported payload contract remains ordinary retained values.

Arena reset accepts Zig's `free_all`, `retain_capacity`, or `retain_with_limit` mode.
The returned boolean reports backing-capacity retention success only. Even when
retention returns false, reset has invalidated all old owners and completed; the
arena remains usable. Retention may invoke the parent allocator, so reset with
retention is not an unconditional no-allocation operation. A preheated scalar
cycle can reuse both backing and registry capacity without further allocation.

`free_all` releases arena backing, while registry capacity remains until final
Store deinitialization. Retained snapshots and registry capacity are additional
costs outside backing-retention limits. Slot quotas remain logical live-buffer
quotas, not physical-byte guarantees.

## Acceptance evidence

`src/arena_test.zig` covers all-or-nothing rejection with nested/empty borrows,
mutation after rejected reset, stale allocation/lease IDs after reuse, allocator
authority across cycles, quota recovery, terminal cleanup with active loans,
retained snapshots after reset/destruction, and every allocation failure through
aggregate creation, buffer allocation, growth, and cleanup. It also covers normal
Store reset with allocation disabled and two independent arenas.

A preheated region loop runs with subsequent host allocation disabled. Another
10,000-cycle fixture creates and grows buffers, resets, checks stale handles, and
fits within 16 KiB live parent allocation, returning to zero after cleanup. These
are measured fixture bounds, not a general memory or performance guarantee.

Source integration must still define scoped arena acquisition, move/escape rules,
allocator forwarding, checked reset results, cleanup/effect behavior, and real
source programs through the CLI. Pool payloads do not yet use this arena route.
