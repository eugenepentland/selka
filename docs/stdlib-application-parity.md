# Library preparation for application comparisons

These reusable modules cover standard-library operations used by the EDA and
workflow planner workloads. Their implementation and migration are preparation,
excluded from timed application development. This is functional workload parity,
not a claim to reproduce the complete Python or Zig APIs.

## Ordering and priority queues

`std_order::Item` holds an `i64` payload (`value`) and two index/length pairs
(`first`, `first_len`, `second`, `second_len`) into a supplied immutable `&[]i64`.
Keys compare lexicographically by the first range, then the second; payloads do
not break ties. Empty second ranges implement single keys. Ranges may hold
ASCII/Unicode scalar values or arbitrary signed integers. No JSON layout or
application identifier rule is built into this module.

- `sort(text, items, base, count) -> bool` sorts that range in place using
  heapsort: O(n log n) comparisons, constant auxiliary space, unstable ties.
  Invalid bounds or key descriptors return false before any mutation.
- `compare(text, left, right) -> i64` returns -1/0/1; `valid(text,item)` checks
  descriptors. Invalid descriptors compare as zero; callers using `compare`
  independently must validate them first.
- `lower_bound(text, items, base, count, needle) -> u64` returns an absolute
  insertion position in a sorted range. Invalid range returns `len_slice(items)`;
  descriptors and needle must be valid. Comparison is O(log n).
- `equal_run_end(text, items, start, end) -> u64` finds the exclusive end of the
  adjacent equal-key run. Subtract start for its frequency. Invalid initial
  bounds/descriptor return start. Together with sorting this provides counting
  and duplicate grouping for composite keys without application sorting loops.
- `heap_push(text, items, count, value) -> bool` adds to an initialized prefix;
  successful callers increment count. Full/invalid-value pushes change nothing.
- `heap_pop(text, items, count, fallback) -> Pop` returns `found`, new `count`,
  and minimum `value`. Empty/invalid count returns false and the fallback without
  mutation. Both heap operations use O(log n) comparisons. All existing heap
  descriptors must remain valid and the same immutable text must be supplied.
  Storage beyond the active count is scratch; neither operation resizes it.

Comparison cost also includes common key prefix lengths. This supports the
workloads' identifier and identifier-pair ordering, equivalent to the needed
`sorted`, `heapq`, `bisect` and `std.mem.sort` behavior. General callback sorting
with borrowed context remains a compiler limitation: callback parameters currently
accept values, not borrowed slices. Descriptor preparation is untimed library
migration; arbitrary user-defined comparator breadth is not claimed.

## Counting, character classes and pairs

`std_counter::add_bytes` increments a `std_hash_bytes::Map<u64>` entry and
`get_bytes` returns zero when absent. Add returns `ok`, `full`, `invalid` or
`overflow`; failure preserves the previous counter. Keys have the existing
256-byte limit; counts are unsigned and bounded. This supplies the frequency
operation used from Python `Counter`, not negative counts or Counter arithmetic.
Composite descriptors can instead use `std_order::equal_run_end` after sorting.

`std_ascii::Class` independently enables lowercase, uppercase, digits,
underscore and hyphen. `matches<T:integer>(text,head,tail,minimum,maximum)` checks
full-slice length and first/subsequent character classes without allocation;
`contains<T>` checks one integer. A lowercase head plus lowercase/digit/_/- tail
and bounds 1..32 gives `[a-z][a-z0-9_-]{0,31}` exactly, including rejection of
non-ASCII values and negative tape integers. This is a character-class primitive,
not a regular-expression engine or Unicode character category implementation.

`std_iter::pairs(n)` returns `Pairs{size,first,second,done}`. Inspect the pair
while not done, then call `next_pair`. It visits each unordered distinct index
pair once in lexicographic order, the operation used from
`itertools.combinations(sequence,2)`. Size below two starts done. Advancement
checks even externally constructed state and avoids u64 overflow. Other
combination sizes and generator protocols are not provided.

## Directed graph readiness

`std_graph::Edge{from,to}` names vertices by zero-based indices. Caller-owned
`&mut []i64` state length defines vertex count. `prepare(state,edges)` validates
all endpoints before mutation, then stores indegrees; duplicate edges count and
are removed independently. It uses O(V+E) work and no allocation.

`ready(state,node)` tests whether a vertex is available. `take_ready` reserves it
once. `complete(state,edges,node)` accepts only reserved vertices, marks completion
and releases outgoing dependencies. It scans E edges per completion. `finished`
is true only after all vertices complete (also for an empty graph). `stalled`
is true when unfinished vertices remain and none are ready or reserved; this
identifies a cycle or its blocked descendants after ready work is exhausted.
It does not report the individual cycle members.

This provides the readiness/done mechanism of Python `graphlib.TopologicalSorter`.
Selection order, execution rounds, duration arithmetic and domain error reporting
remain application decisions. The state and edges must keep their correspondence
from `prepare`: do not directly modify state or change edges mid-run. State -2
means reserved and -1 completed. A completion with an out-of-range endpoint is
rejected before mutation; valid graph state is required for arithmetic invariants.
