# Explicit list snapshots

This prototype adds `.snapshot()` to the main-derived single-owner experiment.
Assignment still moves lists, calls borrow them, and `.copy()` eagerly duplicates
list storage, including nested lists. `.snapshot()` preserves another logical
value by sharing storage and copying on a later write. Both versions may be
mutated independently, including through nested lists and record fields.
No ownership or lifetime annotations are needed.

```mylang
mut rows = [[1, 2], [3]]
mut saved = rows.snapshot()
rows[0].append(4)
saved[1].append(5)
# rows is [[1, 2, 4], [3]]; saved is [[1, 2], [3, 5]].
```

The flag remains `--experimental-single-owner`. In ordinary language mode,
`.snapshot()` has the existing list `.copy()` behavior. The experimental eager
copy behavior and source move/borrow restrictions remain opt-in.

## Try it

From `/home/epentland/ai/canopy/mylang-borrow-stack-20261010`:

```sh
python3 experiments/shared-snapshot-20261011/try.py nested_copy x x x x
python3 experiments/shared-snapshot-20261011/try.py --eager nested_copy x x x x
python3 experiments/shared-snapshot-20261011/try.py both_versions
```

The first two commands print the same result using different storage strategies.
Add `--default` before the sample name for ordinary language semantics. The
wrapper accepts sample names or source paths; `--eager` selects paired sample
names from `eager/`. Large samples need at least one argument.

Rebuild and reproduce the measurements:

```sh
scripts/build-slot.sh build /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig build install --prefix .tmp/shared-snapshot-20261011/candidate
scripts/build-slot.sh build python3 experiments/shared-snapshot-20261011/compare.py --compiler .tmp/shared-snapshot-20261011/candidate/bin/mylang --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig --output .tmp/shared-snapshot-20261011/measurements
```

The measured compiler SHA-256 is
`a02b4b1c34b6d52977a544245e832c896f5a00645182987f3fd217d5ee08483c`.
Work remains on `codex/borrow-call-stack-20261010`, based on main at
`1d202d41bfff888ee91354f706cb74e860dc4b94`, using the Core/LLVM backend.

## Results

These are **peak managed bytes**, including startup/teardown, at the larger
input (`n=11`). Allocation and copy counts exclude startup/teardown. They are
managed-storage counters, not process RSS or elapsed-time measurements.

| Workload | Eager `.copy()` | `.snapshot()` | Peak change | Allocations before → after |
| --- | ---: | ---: | ---: | ---: |
| [Nested lists, mutate one child](samples/nested_copy.my) | 159,312 | 89,008 | **44.1% less** | 2,202 → 1,103 |
| [Read-only second version](samples/unused_snapshot.my) | 224,032 | 135,960 | **39.3% less** | 7 → 6 |
| [Append after saving a large list](samples/snapshot.my) | 224,032 | 312,016 | **39.3% more** | 7 → 7 |

The nested workload copies only the outer pointer array and the changed child:
**2 copies / 8,824 bytes**, versus **1,100 copies / 26,400 bytes** for eager
duplication. Sharing brings back **1,100 runtime retains and 2,200 runtime
releases**, plus one executed uniqueness test; eager copies had none of those.
The read-only workload eliminates its second allocation and all copying. The
optimizer also removes its RC traffic because neither version is mutated.

The append workload is worse because eager copying leaves the original growing
list's spare capacity intact. With a snapshot, the write copies to a buffer
without that spare capacity, then grows it. It executes one extra reallocation
(8 versus 7), three uniqueness checks, one Core retain and three Core releases.
Changing the spelling everywhere is therefore not an across-the-board win.

The smaller input (`n=4`) shows the same direction: nested lists use 44.0% less
peak memory, the read-only case 49.2% less, and the large append case 49.1% more.
No runtime speedup is claimed.

Additional paired cases at `n=11`:

| Workload | Eager peak bytes | Snapshot peak bytes | Allocations before → after |
| --- | ---: | ---: | ---: |
| [Small saved list then mutation](samples/09_snapshot_mutate.my) | 1,216 | 1,056 | 3 → 2 |
| [Loop history](samples/10_loop_snapshots.my) | 2,176 | 2,048 | 13 → 12 |
| [Record field snapshot](samples/13_record_snapshot.my) | 1,152 | 1,152 | 4 → 4 |
| [Branch-selected borrowed argument](samples/16_branch_alias.my) | 1,024 | 1,024 | 3 → 3 |
| [Return a borrowed record field](samples/19_return_field.my) | 960 | 960 | 2 → 2 |
| [Mutate both nested versions](samples/both_versions.my) | 384 | 384 | 6 → 6 |
| [Mixed list types](samples/mixed_families.my) | 62,624 | 53,824 | 4 → 4 |

All 33 snapshot-free controls (27 census cases plus six focused samples) retain
exactly their previous release-mode memory and RC counters at both inputs.
The census still has **20 programs allocating managed heap storage, 7 with no
observed kernel heap allocation, and 3 unsupported dictionary cases**. This
change reduces duplication in suitable workloads; it does not eliminate runtime
allocation. The 21 numeric/list-only census controls remain free of executed
retains, counted releases, uniqueness checks and runtime RC.

## Deliberately coarse sharing policy

A reachable `.snapshot()` enables RC/COW for its **Core list type throughout
the module**, and recursively for child-list types reachable through records or
fixed arrays. Other list types retain the single-owner guarantee. Core types
are structural, so distinct source record names with the same field layout can
also share a storage policy. There is no per-object sharing analysis or new
runtime object layout.

For example, snapshotting `int[][]` also enables sharing for `int[]`, while
`float[]` can remain exclusive. In the mixed-type sample, the unrelated
`independent.append(8)` executes **one extra uniqueness check** after an `int[]`
snapshot is introduced. `floats.append(8.0)` still executes no uniqueness check
or counted release. The ordinary COW proof can remove overhead where it proves
uniqueness, but that is no longer guaranteed for unrelated lists of the same type.

Cleanup follows the same policy. An exclusive parent may contain shared children:
the compiler directly frees that parent and emits normal releases for its shared
child types. Copying a shared parent is safe because every reachable child-list
type was included in the sharing policy. `.copy()` remains eager even within a
snapshot-enabled family; a counter regression test checks this explicitly.

Existing experimental restrictions remain: dictionaries/sets, recursive owning
types, unions containing lists, partial field moves, and some nested list methods
and evaluation-temporary forms are rejected. A snapshot does not disable source
move, borrow, or mutable-overlap checks. Single-owner builds continue to bypass
persistent Core stage caches.

## Correctness fix and validation

The two-sided nested mutation case exposed an existing COW bug, reproducible with
the frozen previous compiler in ordinary mode. Copying one outer list shares
unchanged children with the original, but the original could still prove those
children unique. Ownership now accounts for parent copies, prospective COW
updates, and escaping parent uses before removing a child's uniqueness test.
The regression passes in both ordinary and experimental modes. Existing tests
still ensure genuinely unshared nested updates need no count test.

- **858 Core tests passed**, including nested writes, record children, callbacks,
  generic snapshots, borrowed returns, a shared child surviving its exclusive parent,
  empty snapshots, pop/clear, move errors, and copy counters.
- **254 relevant frontend tests passed**, covering collections, generics, method
  diagnostics, Python-style syntax and reference tooling.
- **570 program executions passed**: ten paired samples in eager and snapshot
  modes across five build configurations, ordinary mode in release and fact
  verification, plus 33 controls across all five configurations; two inputs each.
- Leak checking was enabled, and every counted run had zero managed bytes live
  at exit. Three unsupported dictionary cases retained their diagnostics.
- All **88 whole-tree Guardian checks passed**. Report-only findings are retained
  in the log; no policy baselines or Guardian feedback logs were changed.

See [all measurements](results.json), [compact counters](summary.csv),
[reproduction harness](compare.py), and [validation manifest](validation.json).
Raw build commands, LLVM, counters and execution output are under
`.tmp/shared-snapshot-20261011/measurements/`. Core site counts and runtime counts
can overlap; their columns must not be added together as a total RC count.
