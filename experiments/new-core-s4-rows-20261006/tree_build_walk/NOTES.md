# tree_build_walk (recursive values)

Status: `rows.py build` + `verify` PASS for all five arms (old core `--release`, new core release, Rust,
Zig ReleaseSafe, Go) at all five probes, each checksum equal to `oracle.py`. Extra cross-check: 25 random
`(size 2..300, iterations 1..30, seed 1..1000000)` triples plus `(100000,2,999999)`, `(5,1500,1000000)`,
`(1009,3,1)`, `(1010,3,2)` for both cases, all arms equal to the oracle (no mismatch). Invalid arguments (size 1, iterations 0, seed 0 and
1000001, non-numeric, missing or extra argument, a negative seed, a number past i64, and for the references a
wrong case name) exit 2 with empty stdout and stderr in every arm.

`case.json` iterations come from `rows.py calibrate` (three runs: 4096 -> 268, 272, 282; 64 -> 13002, 12913,
12952). The saved values are the 272 and 12952 runs. At those counts Zig took 70-97 ms at size 4096 and 44-48 ms at
size 64 on CPU 12 while other agents were building, so the 4096 count lands above the ~40 ms target; one
iteration has a different cost than a steady-state one, which the calibrate step extrapolates from.

## Idioms

| arm | tree | allocation and release |
|---|---|---|
| mylang `row.my` | `union Tree: leaf, node(left: Tree, value: int, right: Tree)`, built with `Tree.leaf` / `Tree.node(...)`, read with `match` | the compiler boxes the recursive edges; the tree is freed when `batch_result` returns (reference counts) |
| Rust | `enum Tree { Leaf, Node(Box<Node>) }` with `struct Node { left: Tree, value: i64, right: Tree }` | one `Box` per internal node; dropped at the end of the batch iteration |
| Zig | `struct Node { left: ?*Node, value: i64, right: ?*Node }`, null is Leaf | `std.heap.c_allocator.create`, explicit recursive `destroy` after each batch; `errdefer destroy` on the build path |
| Go | `type node struct { left *node; value int64; right *node }`, nil is Leaf | the garbage collector (no `GOMAXPROCS` call in the program; the harness pins to one CPU so Go runs with one P) |

The traversal and construction order is the contract's: `build` makes the left subtree, then the right, then
the node; `walk` adds `(depth+1)*v` first, then left, then right.

## Decisions the contract left open

**Rust enum shape.** The contract says "`enum` with `Box`". The most literal enum,
`Node(Box<Tree>, i64, Box<Tree>)`, boxes the `Leaf` child too, so a tree of SIZE nodes makes 2*SIZE+1
allocations, against SIZE for the Zig/Go ports and the mylang new core (checked in `new.ll`: a leaf is a null
pointer and `myl_core_box_new(24)` is called once per node). I wrote
`enum Tree { Leaf, Node(Box<Node>) }`: still an enum with a Box and still "Leaf or Node(left, value, right)",
but `Leaf` costs no allocation (the Box niche makes `Tree` one pointer), so all five arms do one allocation per
internal node. The literal form is kept as `alt_box_per_leaf.rs` (not built by `rows.py`; same checksum). On
CPU 12 at `4096 200 7`, best of five: Rust (as shipped) 44.3 ms, `alt_box_per_leaf.rs` 92.3 ms, so the choice
matters about 2x. If the coordinator prefers the literal form it is a drop-in replacement for `main.rs`.

**Zig allocation.** `c_allocator.create(Node)` per node, `destroy` per node, nothing batched, no arena.

**Go release.** Garbage from batch k is collected when the GC runs, not at the end of batch k; any tree still
unfreed at the end of timing is not charged. This is the language's mechanism and is inside the contract
("Go `std` only").

**Allocator is part of the arm, not the program.** Rust and Zig use libc `malloc`/`free` (24-byte nodes). The
mylang new-core runtime allocates a box as a 32-byte header plus the 24-byte payload from its own per-size-class
free lists (64 KiB chunks, single-threaded; `src/core/runtime/core_rt.c`). That is built into the language
runtime, so mylang cannot use another allocator; read the ratio against Rust/Zig as codegen plus allocator.
(CPU 12, noisy, not a measurement: new core ~31 ms, Rust ~44 ms, Zig ~49 ms, Go ~35 ms, old core ~112 ms at
`4096 200 7`.)

**Oracle.** `oracle.py` is the literal `build`/`walk` over nested tuples. A batch depends on its number only
through `(seed + batch) % 1009` (that is the only way `base` enters), so each distinct residue is built and
walked once and reused; this keeps `(17, 999983, 31)` at 0.1 s instead of minutes. It is a cache over the
contract formula, not a different formula.

**mylang header.** `module row` (the file is `row.my`; same convention as `module row_list_append`).
`row.my` is not `mylang fmt --check` clean, and neither is the template `test/core/row_list_append.my`
(the formatter wants one blank line after the extern and one between defs instead of two); I kept the
template's spacing.

## Findings

- New core: no refusal. `mylang-core coverage` reports every row function `ok`; `new-core-refusal.txt` is not
  written.
- No wrong answer in any arm.
- Old core: accepts `row.my` without changes (`mylang check` clean). Nothing awkward or unnatural was needed:
  the recursive union is written the way `tests/lang/recursive_values.my` writes `Expr`. Observation only
  (not investigated): the old core `--release` binary is about 3.5x slower than the new core here.
- Rows.py: no bug blocked this case. The calibrate step overshoots for this case as described above.
