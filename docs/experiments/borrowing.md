# B: guest memory identity and borrowing

Status: the memory registry, scoped source references, static access checking,
and VM borrow instructions are implemented. Shared/exclusive reference parameters are also implemented. Bounded slices and
returned-reference lifetime contracts remain pending. B is not complete. A1/A2 value semantics remain intact.

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

Copying a backend token does not acquire an independent loan. Scoped source
references cannot be copied, stored, or returned; calls may explicitly reborrow
them into reference parameters. The checker resolves
reference names separately from ordinary values and enforces lexical scope. Allocation-owner uniqueness and general
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

## Scoped source references

```text
fn main() -> i64 {
    let mut count = 1;
    borrow mut count as edit {
        write_ref(edit, read_ref(edit) + 2);
        borrow edit as view {
            return read_ref(view);
        }
    }
}
```

`borrow owner as name { ... }` creates a shared reference; `borrow mut owner as
name { ... }` creates an exclusive reference. The owner must be a named local or
an active reference. Exclusive root borrowing requires a mutable local. Borrowing
covers the whole local value. `read_ref(name)` returns a value snapshot;
`write_ref(name, value);` replaces the whole value and requires exclusive access
and an exact type match. Aggregate writes preserve previously copied snapshots.
These operations preserve domain privacy and nominal type distinctions.

The source checker rejects owner writes during any root borrow, owner reads
during exclusive borrowing, conflicting roots, shared-to-exclusive escalation,
use of suspended exclusive parents, escaping names, and reference copies. Borrow
names cannot shadow active bindings. Sibling scopes may reuse a name. Shared
parents remain readable while shared children are active. Diagnostics retain
borrow declaration locations for conflicts.

The VM promotes a borrowed local into a generation-checked one-element cell.
Reads, assignments, and repeated match payload bindings subsequently use that
cell. Promotion lasts until function return; registry slots are reused across
calls. Normal scope exit ends a lease; early returns evaluate their result then
end active leases from child to parent before releasing locals. Guest traps and
host allocation failures release the entire execution store. References are
frame metadata, not ordinary guest values.

The scoped-reference tests cover scalar and aggregate access, nested reborrows,
conditional returns, calls, loops, match payload reuse, duplicate identity, CLI
diagnostics/disassembly, and allocation-failure cleanup. A 10,000-update source
loop fits within 8 KiB of live runtime allocation. Every instruction-budget trap
boundary in a nested aggregate/call example releases all storage. Mutated internal
bytecode checks missing/repeated borrow operations and conflicting owner reads;
these failures produce guest traps and release storage.

The full suite passes 155/155 tests in Debug and ReleaseFast (134 core, 21 CLI)
on Guardian's `0.17.0-dev.1683+5ceec001b` snapshot. The editable
`examples/references.my` program returns 23. Guardian gates were not exercised.

## Reference parameters and call lifetimes

```text
fn add(target: &mut i64, amount: i64) -> i64 {
    write_ref(target, read_ref(target) + amount);
    return read_ref(target);
}

fn inspect(target: &i64) -> i64 {
    return read_ref(target);
}
```

A parameter may be `&T` (shared) or `&mut T` (exclusive). Its argument must be an
active scoped reference or another reference parameter, with exactly matching
underlying type. Ordinary locals require an explicit surrounding `borrow` scope.
Reference and value parameters may interleave. References remain separate from
ordinary values and cannot be placed in records, arrays, or value locals.

Value arguments evaluate in source order before the call acquires its temporary
reference loans. A nested helper in a value argument therefore finishes and
restores the caller's reference before the outer helper begins. Reference names
do not evaluate a value or acquire a loan at their textual argument position.
The call then reborrows its reference arguments in parameter order. An exclusive
caller reference suspends for the duration of the callee; callee cleanup ends all
parameter loans before returning. Forwarding, recursion, early returns, and
nested scoped reborrows use the same child-before-parent ordering.

Shared references can supply shared parameters multiple times. The conservative
single-child rule for an exclusive reference also applies to calls: it cannot
supply two simultaneous parameter loans, even when both parameters are shared.
Create a scoped shared child first to obtain shared fan-out. Two distinct owners
can supply two exclusive parameters. Shared references cannot supply exclusive
parameters. Conflicts identify the earlier reference declaration.

Parameters may read or replace whole records, arrays, variants, or domains while
preserving value snapshots and private representation checks. A reference to an
array is currently a reference to its entire fixed-size value, not a slice.
Complete declarative conversions retain their single value-parameter contract.
Unused reference parameters get ordinary unused-binding warnings; reads, writes,
reborrows, and forwarding count as uses.

VM calls transfer ordinary values into their declared local slots and acquire
reference parameters separately. Bytecode validation checks parameter modes,
reference metadata, call arity/types/permissions, and prevents treating a
reference parameter as a value local. The runtime independently rejects inactive
or conflicting loans. Failed call setup, including failure after acquiring an
earlier parameter loan, is terminal and releases all execution storage.

Tests cover mixed arguments, multiple owners, shared fan-out, recursive forwarding,
value argument evaluation order, permissions/alias errors, nominal privacy,
unused-parameter warnings, malformed bytecode, and allocation failures. A loop
makes 10,000 mutating helper calls within 16 KiB live runtime allocation; instruction
and frame budget traps release every allocation. The editable
`examples/reference-parameters.my` example returns 19.

## Remaining B acceptance

Add bounded slices, indexing, and narrowed reborrows while preserving immutable
aggregate snapshots. Returned references require an explicit restricted lifetime
contract; local references must never escape. Test these through actual CLI
programs, allocation failures, normal returns, and traps before marking B complete.
