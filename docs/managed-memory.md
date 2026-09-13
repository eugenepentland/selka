# Managed application collections

Ordinary dynamic lists now allocate on a tracing heap without allocator parameters,
move operations, or collection borrow scopes. This is the first GC-default
application subset; explicit owned buffers, pools, arenas, and resource cleanup
remain available with their existing contracts.

```rust
fn main() -> i64 {
    let values: List<i64> = []
    let alias = values
    alias.push(42)
    return values[0]
}
```

A list assignment or function argument copies a shared reference. `let` prevents
rebinding but permits mutation of the referenced list. Appending grows capacity
automatically. Reading returns a value snapshot, including shared references in
its fields; it never exposes an interior pointer into growable storage. Independent
containers require explicit construction and copying of their elements.

Use `List<Node>` for application collections and `let nodes: List<Node> = []`
for an empty list. Read with `nodes[index]`, write with `nodes[index] = value`,
append with `nodes.push(value)`, and count with `nodes.len()`. These operations
currently use a named local or parameter as their receiver. An empty literal needs
an expected list type from an annotation, return type, or parameter.

The earlier named `list Nodes: Node;` declaration and
`new_list<Nodes>(initial_capacity)` construction remain supported. Capacity is a reserve hint, not a fixed
limit. `len_list`, `read_list`, `append_list`, and `write_list` operate directly on
list values; mutations return `unit`. Invalid indices trap with `R_LIST_BOUNDS`.
Allocation failure terminates the execution with cleanup, rather than returning a
recoverable collection result. Keep application cardinality checks where input
limits are part of its contract.

List elements can be ordinary copyable values, records, and other managed lists.
Recursive graphs through list references are supported:

```text
struct Node { value: i64, children: List<Node> }
```

Records retain value semantics. This release does not introduce `ref struct`, a
Unicode string object, capturing closures, or managed hash maps. Byte literals
and existing byte/text APIs keep their previous behavior. Owned resources, allocator/provider capabilities, and
must-handle results cannot be hidden inside freely aliased lists. Explicit buffers
and pools cannot contain managed references, including references nested inside
records or arrays. Managed interior borrows are not supported. Host invocation,
JSON encoding of managed graphs, and native C emission reject unsupported managed
boundaries; ordinary scalar host calls from managed applications still work.

## Collection and allocation contracts

Each VM execution owns a single-threaded, nonmoving tracing heap. Managed objects
have stable identities. VM locals, operands, intermediate values, and retained
aggregate snapshots maintain reference counts used for root discovery. Collection
subtracts edges internal to the managed graph (including aggregate wrappers),
marks reachable objects, and reclaims unreachable cycles. Dead edges are released
before any dead object header is freed. These counts protect temporary roots;
reference counting alone is not the reclamation algorithm.

Automatic collection runs at managed allocation safepoints according to a simple
object-count threshold. This prototype is not a tuned latency or byte-budget
policy. Host allocators still determine total memory availability. Explicit-buffer
slot quotas do not count managed list storage. VM `memory.gc.statistics` reports
created, reclaimed-during-collection, live/peak objects, live capacity slots, and
collection counts; final teardown zeroes live counts separately from reclamation.

Managed construction and append carry the transitive `managed_allocation` effect.
`nogc` excludes that effect; `noalloc` excludes both managed and explicit guest
backing allocation. Neither promises zero host allocation for value representation
or VM bookkeeping. Reads and fixed-slot writes are permitted under either bound.
Managed allocation remains managed inside an `arena` block; the ambient arena
never redirects it. Managed mutation is not a promise of purity or exclusive access.

`mylang run-project examples/gc-default/main.my --gc-stress` collects at every
managed construction/append safepoint. It should print `142`. Stress mode is a
rooting correctness check, not a performance mode. See the
[schematic instructions](../experiments/schematic/README.md) for the real migrated
application and normal/stress SVG comparison.
