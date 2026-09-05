# C: source buffer acquisition and ownership

Status: nominal buffer types, recoverable acquisition, move checking, wrapper
ownership, and source/VM cleanup are implemented. [Buffer operations and checked
views](buffer-operations.md) now add mutation, queries, and borrowed slices. External
resources, capabilities/effects, and arenas/pools remain pending. C is not complete.

## Syntax and acquisition

```text
buffer Numbers: i64;
result Acquired { ok: Numbers, err: i64 }

fn forward(values: Numbers) -> Numbers {
    return values;
}

fn allocate(heap: allocator) -> Acquired {
    let first = try acquire_buffer<Acquired>(heap, 4);
    let second = try acquire_buffer<Acquired>(heap, 8);
    discard first;
    return new Acquired.ok(forward(second));
}
```

`buffer` is contextual at top-level declarations; ordinary bindings can still use
that spelling. A buffer name is nominal even when two buffers have the same element
type. Elements must be ordinary copyable values with no result obligations or
owned resources, including transitively through wrappers. Recursive element/type
cycles are rejected. Ordinary record construction cannot manufacture a buffer.

`acquire_buffer<ResultType>(capability, capacity)` checks explicit allocator authority, evaluates an integer capacity once, and
returns the declared result. Its success payload must be a buffer; the initial
error contract is `i64`. Success creates an empty buffer with the requested reserved
capacity. The recoverable error code `1` means a negative/unrepresentable capacity,
a buffer/total-capacity quota violation, or exhaustion of the live-allocation quota.
It does not convert host allocation failure or guest arithmetic traps into errors.
The `i64` error contract is provisional; named errors belong to the remaining error abstraction work.
[Explicit allocator capabilities](allocator-capabilities.md) are now required.

The embedding VM accepts `Options.memory_limits` with the existing backend quotas.
The CLI currently uses defaults. Quotas count reserved element slots and live
allocations, not all runtime bytes. `memory_statistics`, an optional embedding/test
output, reports final ownership accounting after cleanup; it is not guest syntax.

## Moves and lifetime

Buffers and wrappers containing buffers are move-only. Wrappers include records,
union/result payloads, and nonempty fixed arrays/tables. Passing, assigning,
returning, or otherwise evaluating a move-only local transfers its value and makes
the old binding unavailable. A second use reports `E_OWNED_CONSUMED` at that use,
with the declaration location. Source moves do not clone buffer contents.

The checker requires consistent availability on continuing branches, loop back
edges, and short-circuit paths. An owned-only mismatch reports `E_OWNED_PATH` or
`E_OWNED_LOOP`; result-bearing values retain result-obligation diagnostics. These
checks are conservative even if a runtime condition is constant. A mutable owned
binding may be refilled after a move or replaced, releasing its previous value.
The replacement evaluates before the old value is released, so both acquisitions
may temporarily count against capacity limits.

Unused owned-only values are cleaned up automatically; `discard value;` releases
them explicitly. Fallible results still require matching, forwarding, returning,
or acknowledgement. Ownership does not excuse an unhandled result, and
`acknowledge` remains restricted to result-bearing values.

Projecting a field/element out of a move-only wrapper consumes the whole wrapper
and releases the remaining contents. There is no independent partial-field binding
state yet. Preserving updates consume the old wrapper and transfer preserved
contents into the replacement. Existing result rules still reject projections or
updates that would silently drop result obligations. Whole-buffer and owned-wrapper reference parameters remain unsupported;
[buffer slices](buffer-operations.md) now support shared/exclusive views, slice
parameters, and returned-view contracts. Ordinary value borrowing retains B.

## Runtime cleanup

`MOVE_LOCAL` removes the value from its old VM slot. This also replaces retained
loads for existing result transfers, so handled result payloads are not kept alive
in obsolete locals. `DROP_LOCAL` ends owned lexical bindings at normal block and
match-arm exits; it tolerates an already moved or previously cleaned slot. Returns
release remaining locals in reverse slot order. Error propagation releases
unfinished operands before leaving the function, preserving caller operands.
Execution traps/host failures release operand/local storage and registered memory.
No user-defined destructor or cleanup effect is implemented yet.

The internal resource wrapper consumes the backend allocation handle and owns one
cleanup record. Internal aggregate-construction/projection temporaries may retain
that record; the final release invalidates its views and destroys the allocation.
These implementation references do not permit additional source owners. Resource
wrappers require their Store to remain alive. VM results cannot expose them after
execution because `main` still returns i64.

## Acceptance evidence

`src/buffers_test.zig` covers nominal schemas, acquisition errors, forwarding,
wrappers, use-after-move, branch/loop/short-circuit state, mutable replacement,
lexical/match cleanup, instruction/frame traps, invalid bytecode, and exact discovery.

The partial-construction program acquires A then fails acquiring B under a one-owner
quota, propagates the error, and successfully acquires again in the caller. Its
success case constructs/transfers two owners and releases both. Final statistics
assert one release per successful acquisition. A separate case covers A as an
active local rather than an unfinished constructor operand.

Allocation-failure sweeps cover compilation, resource metadata, result/record
wrappers, and VM execution on both successful and failed partial construction.
A 10,000-iteration source program forwards resources through helpers under a
one-owner quota and 16 KiB live runtime allocation, leaving zero live bytes.

Debug and ReleaseFast both pass 226 tests (200 core, 26 actual CLI). The editable
`examples/buffers.my` and CLI fixture return 21. Dumps show buffer schemas,
`ACQUIRE_BUFFER`, and `MOVE_LOCAL`; all checking commands reject use after move.
Exact duplicate discovery is `exact-v14`, retaining acquisition structure and
move-only type behavior.

[Buffer operations and checked borrowed views](buffer-operations.md) are now implemented.
[Allocator capabilities](allocator-capabilities.md) and transitive allocation bounds
are now implemented. External capabilities and cleanup effects remain next. External-resource
handling, arenas/pools, generics/handles, and other roadmap tracks remain in scope.
