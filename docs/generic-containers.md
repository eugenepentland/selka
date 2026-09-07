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
of optimal large-input sorting. Maps, sets, queues, owned elements, arbitrary
ordering callbacks, and implicit growth are separate library or language additions.
