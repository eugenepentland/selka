# C: buffer operations and checked views

Status: buffer queries, mutations, shared/exclusive slices, slice parameters, and
returned views are implemented. External resources, allocator/external capabilities,
transitive effects, and arenas/pools remain pending. C is not complete.

## Operations

For a buffer binding `b`, `len_buffer(b)` returns initialized length and
`capacity_buffer(b)` returns reserved element slots, both as u64.
`read_buffer(b, index)` returns a retained element snapshot. It traps with
`R_BUFFER_BOUNDS` for a negative or uninitialized/out-of-range index.
These operations inspect the existing owner without consuming it.

Mutations require a live `let mut` buffer binding and an explicit declared status
type with `ok: bool` and `err: i64` payloads:

```text
result Status { ok: bool, err: i64 }

acknowledge append_buffer<Status>(b, value);
acknowledge resize_buffer<Status>(b, length, fill);
acknowledge write_buffer<Status>(b, index, value);
acknowledge reserve_buffer<Status>(b, capacity);
```

A successful operation returns `ok(true)`, including a successful no-op. The status
must be handled, forwarded, propagated with `try`, or explicitly acknowledged.
Acknowledgement deliberately ignores an error; programs that depend on success
should match or propagate it. The owner remains available after either outcome.

| Operation | Behavior | Backing storage |
| --- | --- | --- |
| `append_buffer` | Add one element, requiring spare capacity | Does not grow |
| `resize_buffer` | Fill newly initialized elements or release a removed tail | Does not grow |
| `write_buffer` | Replace one initialized element | Does not grow |
| `reserve_buffer` | Ensure capacity, preserving length and contents | May allocate |

Status error `1` means a reserve capacity/quota violation; `2` means insufficient
reserved capacity for append/resize; `3` means an invalid write index or a negative/
unrepresentable resize length. Failed recoverable edits preserve contents, length,
and capacity. Host allocation failure remains a terminal host error. These numeric
error contracts are provisional pending the capability/error abstraction work.

Value arguments evaluate in source order before owner access. The owner must still
be available afterward; an argument that consumes it causes a source error. Values
and fill expressions require the exact element type. Integer index/length/capacity
arguments retain signedness and width until checked before host index conversion.
Reads preserve snapshots across later writes, resizing, growth, or owner destruction.

The backing-storage distinction above is not a whole-VM no-allocation guarantee.
Result wrappers, expression evaluation, and VM bookkeeping may allocate. Transitive
language effect checking has not been implemented.

## Borrowed views

```text
borrow mut b[0..len_buffer(b)] as values {
    write_slice(values, 0, 7);
}
```

Buffer slices use the existing half-open range syntax and slice operations. Bounds
refer to initialized length, never spare capacity. Empty buffers admit `[0..0]`.
Shared slices permit owner reads and shared fan-out. Exclusive slices block owner
reads. Any active slice blocks owner movement, replacement, destruction, mutation,
and reserve, including capacity-preserving reserve calls. Exclusive parents suspend
while a child loan is active. Disjoint ranges still conflict over the whole buffer.

Helpers accepting `&[]T` or `&mut []T` accept slices from buffers and fixed arrays.
Nested reborrows, recursive forwarding, and returned slices with `from parameter`
contracts preserve element types, offsets, bounds, and permissions. A buffer local
cannot escape by returning a view derived from it. Whole-buffer references and
references to wrappers containing owners remain unsupported; use element slices.

The VM distinguishes direct buffer elements from immutable fixed-array values.
Buffer slice writes replace one element without cloning the entire buffer. Fixed
array writes retain their existing snapshot semantics and immediate-array copy cost.
The shared memory registry enforces whole-allocation locks and stale-lease checks.
Calls and returned views carry their storage representation with the loan, including
zero-length loans. No host address is exposed to the program.

## Acceptance

`src/buffers_test.zig` covers mutation/query results, capacity/bounds failures,
exact element types, uninitialized storage, use after argument consumption,
retained aggregate snapshots, invalid emission metadata, and exact discovery.
Borrow cases cover mixed array/buffer helpers, narrowed returned views, empty
slices, shared-move rejection, growth conflicts, suspension, and local-view escape.
A propagated mutation error ends direct loans before releasing their owners.

Allocation-failure sweeps and instruction-boundary traps cover both mutation and
nested returned-view programs. A program performs 10,000 writes through returned
views with one live owned allocation and 16 KiB live runtime storage, then releases
all storage. The buffer-view example and actual CLI fixture return 19; CLI checks
also reject moving a shared-borrowed owner.

Debug and ReleaseFast pass 240 tests (213 core, 27 actual CLI); formatting and
whitespace checks pass. Discovery is `exact-v15`, retaining operation kind, owner
binding identity, arguments, and result types. Capability/effect enforcement and
external-resource acquisition are next; arenas/pools and all other unfinished
roadmap tracks remain in scope.
