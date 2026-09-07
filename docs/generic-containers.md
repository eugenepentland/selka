# Generic containers

Buffers and pools accept explicit type parameters with the same declaration-scoped
contracts as records. Backing elements must guarantee `copy`; this excludes owned
values and pending result obligations, including in unused declarations.

```text
buffer Vector<T:copy>:T;
pool Store<T:copy>(Id):T;
result Open<T:copy>{ok:Vector<T>,err:i64}
result PoolOpen<T:copy>{ok:Store<T>,err:i64}
result Insert<T:copy>{ok:Id<T>,err:i64}
```

`Id<i64>` and `Id<bool>` are different nominal handle types. Specializations retain
allocator provenance, generation checks, automatic owner cleanup, and bounded
specialization work. Generic operation bodies are checked before instantiation;
an invalid unused body cannot hide behind an uncalled template. Allocation and
reserve remain explicit; appending does not silently grow capacity. Mutation,
allocation, and pool access preserve existing typed result contracts.

`std_collections` provides `Vector<T:copy>`, `Created<T:copy>`, `Status`,
`vector(heap, capacity)` and `filled(heap, count, value)`. Functions require explicit
arguments, e.g. `std_collections::filled::<i64>(heap, 8u64, 0)`.

The same module provides allocation-free slice algorithms:

| Function | Contract | Result |
| --- | --- | --- |
| `find<T:equality>(&[]T, T)` | Linear search | First index, or `-1` |
| `contains<T:equality>(&[]T, T)` | Linear search | Membership |
| `reverse<T:copy>(&mut[]T)` | In-place reversal | `0` |
| `sort<T:integer>(&mut[]T)` | Stable ascending insertion sort, quadratic work | `0` |
| `lower_bound<T:integer>(&[]T, T)` | Input already ascending | First index whose element is not less, or length |

Borrow a buffer's initialized range to use these algorithms. Empty slices are
valid. Sorting intentionally suits small application worklists; it is not a claim
of optimal large-input sorting. Owned elements, arbitrary ordering callbacks, and implicit growth remain separate
language additions.

## Bounded maps, sets and queues

`std_map` supplies `Map<K:equality,V:copy>` with create/put/get/remove.
`std_set` supplies `Set<T:equality>` with create/insert/contains/remove.
`std_queue` supplies `Queue<T:copy>` with create/push/pop.

Creation takes an explicit allocator and `u64` capacity and returns a typed result.
Operations transfer the owner and return it in a record on every path; extract the
copyable status/payload with `read_field`, then recover the owner with `take_field`.
Full insertions preserve existing content. Map replacement and set deduplication
succeed even when capacity is full. Removal reclaims capacity. A map removal uses
swap-with-last and does not preserve iteration order; a queue removes in FIFO order.
Lookup/removal and map/set insertion are linear; queue push is constant time and
pop shifts the remaining elements in linear time. All operations are `noalloc`.

Map put reports `PutStatus.inserted`, `.replaced`, or `.full`; get/remove return
`Value<V>.none` or `.some(value)`. Set mutations return `changed` and `full` flags;
contains returns `present`. Queue push returns `accepted`; pop returns `Item<T>`.
Records always contain the live owner, so rejecting an insertion cannot lose it.
An example exercising unrelated nominal keys, replacement, full insertion,
deduplication, deletion, and FIFO removal lives in
[`src/stdlib/tests/bounded.my`](../src/stdlib/tests/bounded.my).

## Whole-owner references

Helpers can accept `&Vector<T>` for length/capacity/element inspection and
`&mut Vector<T>` for writes, append, resize and explicit reserve. Pools have the
same shared/exclusive operation rules. `read_field` can inspect a copyable field
through `&Holder<T>` even when the record also owns a buffer. Whole-reference
forwarding and declared `from` returns preserve the existing lifetime rules.

```text
fn append<T:copy>(values:&mut Vector<T>, value:T)->Status noalloc {
    return append_buffer<Status>(values,value);
}
```

Create the active reference with `borrow mut values as view { ... }`. Moving,
destroying or directly mutating its owner while it is borrowed rejects. A shared
reference cannot mutate. `read_ref` cannot duplicate ownership; `take_field`
cannot extract ownership through a reference. Borrow a complete owner before any
partial move. Result-bearing values still transfer their must-handle obligation
by value; references cannot bypass it.

Borrow element slices directly from the original buffer in a separate lexical
scope. Deriving a slice through a whole-buffer reference is deliberately rejected;
the current reference representation does not yet express the necessary nested
backing lease. Thus reserve cannot invalidate a live element slice. Shared
inspection of resource-bearing records adds no destructor effects; exclusive
references conservatively include the cleanup effects of replacing their value.
See [`examples/owner-references.my`](../examples/owner-references.my).
