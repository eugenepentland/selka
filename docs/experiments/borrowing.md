# B: guest memory identity and borrowing

Status: the memory registry and dynamic borrow rules are implemented and tested
in `src/memory.zig`. Guest reference/slice syntax, static borrow/lifetime checking,
and VM instruction integration remain pending. This is a backend foundation,
not a completed language borrow checker. A1/A2 value semantics remain intact.

## Implemented memory model

A `Store` owns homogeneous buffers of existing guest `Value`s. Creating a buffer
retains its input values; reads return retained snapshots, and writes retain the
replacement before releasing the old value. Nested immutable records, arrays,
variants, and domains retain their established value behavior. All values in a
store use its runtime allocator. The store is owned by one VM execution thread;
it is not a concurrent memory model.

An allocation handle contains a store identity and a slot/generation token.
Borrow handles identify entries in a separate lease registry. The lease registry
owns the allocation identity, narrowed start/length, shared/exclusive permission,
and parent/child relation. Client-visible handles contain no host address or
editable bounds/permission fields. Access resolves these identities anew, so
registry growth never leaves a guest handle pointing into an old host buffer.

Each new store receives a process-unique monotonic identity. Allocation and lease
slots are recycled with incremented generations. Exhausted generations retire
instead of wrapping; store identity exhaustion is an explicit error. Ended,
destroyed, foreign-store, and closed-store handles are rejected. These handles
are internal VM identities, not cryptographic capabilities or an untrusted
serialization format.

## Implemented access and lifetime rules

Root borrows lock the entire allocation, even when their visible range is empty
or disjoint from another view. Multiple shared roots may coexist. An exclusive
root conflicts with every other root. Owners may read while shared roots exist,
but cannot write or destroy borrowed storage. An exclusive root also blocks
owner reads. Writes require exact element type and live exclusive access.

Views have half-open bounds represented by start and length. Bounds checks use
subtraction to avoid overflow. Empty views may begin at the allocation's end,
but have no valid element access. Maximum host indices and overflowing requested
ranges fail before accessing storage. Future VM instructions must also reject
negative guest indices before converting them to the unsigned backend index.

A reborrow narrows a live parent's bounds and cannot increase permissions.
Shared parents can have multiple shared children and remain readable. An exclusive
parent is suspended while its child is active, whether that child is shared or
exclusive. Shared children may further branch; exclusive reborrowing follows one
active child chain at a time. This conservative rule avoids overlapping mutable
access while retaining useful nested slice views.

Parents cannot end before their children. Ending a child restores its parent's
access; ending a root unlocks the allocation. A stale alias to an ended lease
never becomes valid when its slot is reused. Normal destruction refuses active
borrows. Final store cleanup releases all remaining buffers and lease metadata
even when execution aborts with outstanding leases.

Copying a backend token does not acquire an independent loan. The source checker
and VM value representation still need to enforce exclusive-reference move/copy
rules and lexical lifetime restrictions. Allocation-owner uniqueness and general
resource transfer remain later work; runtime stale-handle checks alone are not
an ownership type system.

## Failure and storage behavior

A failed buffer/lease allocation leaves existing values and locks unchanged.
Locks and parent child-counts are committed only after successful registry
insertion. Reborrow insertion can relocate the lease registry, so parent metadata
is resolved again by token before committing the relationship.

Repeated create/borrow/end/destroy cycles reuse registry slots. Metadata grows
with peak concurrent registrations rather than cumulative operations, apart
from generation-exhausted retired slots. Buffer storage is released on normal
destruction and on final cleanup. Lifetime operations and cleanup do not allocate.

## Evidence

`src/memory_test.zig` and the registry's internal exhaustion test cover:

- shared/exclusive conflicts, owner access while borrowed, and destruction rules;
- exact element types, empty/bounded views, and maximum/overflowing indices;
- nested exclusive suspension, shared reborrows, permission escalation rejection,
  and child-before-parent lifetime ordering;
- stale allocation/lease tokens after slot reuse, foreign stores, closed stores,
  generation retirement, and store-identity exhaustion;
- retained aggregate snapshots surviving writes and owner destruction;
- allocation-failure cleanup and failed-borrow rollback without stranded locks;
- 10,000 allocation/reborrow cycles under a 4 KiB live allocation cap, using one
  allocation slot and two lease slots and ending with zero live bytes.

The full suite passes 133/133 tests in Debug and ReleaseFast (114 core, 19 CLI)
on Guardian's `0.17.0-dev.1683+5ceec001b` snapshot. These new tests exercise the
backend API directly; existing CLI fixtures do not claim guest borrow coverage.
Formatting and whitespace checks pass. Guardian gates were not exercised.

## Remaining B acceptance

Next, connect this registry to VM reference values/instructions and source
shared/exclusive reference and slice types. Establish restricted lexical lifetime
rules, checked reborrowing, parameter behavior, and diagnostics with declaration
and use locations. Demonstrate common read/mutate helpers, reject escaping locals
and conflicting accesses, and test actual CLI programs. Preserve cleanup on
returns, loops, guest traps, and host allocation failures. Do not mark B complete
until those end-to-end tests pass.
