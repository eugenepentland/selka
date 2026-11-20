# Arena stores are linear again: each allocation carries its region — 2026-09-22

**Headline.** Every store of a managed reference inside `with arena()` runs the
region barrier. The barrier asked `myl_native_arena_region` for the depth of the
stored value and the depth of the container. That function searched the heap's
whole list of arena chunks on every call. A phase that keeps N objects holds
O(N) chunks, so filling a list was O(N²). Now every arena allocation carries the
same two-word header as a tracing-heap object. The header's mark word records an
arena flag, the owning depth and the element count. The barrier, the collector,
`escape` and element lookup read the depth with one load.

The results (loaded machine, CPU 10):

- **The repro scales linearly.** 2M stores take 2.01× the time of 1M, where they
  took 3.58×. 4M takes 2.04× the time of 2M, where it took 5.34×. At 2M the time
  drops from 1146 ms to 174 ms.
- **`knucleotide_arena` beats the collecting `knucleotide`.** The paired ratio is
  0.926× [0.911, 0.982]. Before the fix the arena version took 1.99× as long as
  the collecting one. It is now 2.1× faster than its own before, 0.471×
  [0.460, 0.485].
- **`binary_trees_arena` is slightly faster:** 0.978× [0.965, 0.994] of before.
- **The collecting programs are unchanged:** `knucleotide` 1.000×, `binary_trees`
  0.963×, both inside their intervals.

Branch `fix/arena-region-lookup` from `base/parity-20260922` (`bbabfc85`). This
is the arena half of item 6.10 and the first bug of §4.9 in the
[performance parity plan](performance-parity-plan-2026-09-22.md). Raw timings
are in
[`results/wave0/`](../../experiments/perf-parity-plan-20260922/results/wave0/):
`arena-store-scaling.json` and `arena-region-lookup-bench.json`.

## What was wrong

A SIGPROF profile of `suite/repro/arena_store_quadratic.my` (2M stores, LLVM O3
without LTO so runtime functions keep their names, base compiler `install-a3`)
puts **83.6%** of samples in `myl_native_arena_region`. A profile of an
arena-wrapped `knucleotide` puts 43.0% there. So the audit's analysis holds, with
one correction.

An arena object does not add a chunk-list entry. It adds a 24-byte side record
next to its payload, and chunks hold up to 1 MiB each. The 2M-string phase peaks
at 144 MB, which is roughly 140 chunks. `new_chunk` pushes each new chunk onto
the head of `heap->arena_chunks`. The list that receives every store was
allocated first, so its chunk sits at the tail. `containing()` therefore walked
every chunk on every store. Growth of the list's backing and dictionary index
sizing took the same walk. The collector's `mark()` took it too, for every
pointer traced while an arena was open. `myl_native_object_element` added a
binary search over the side records.

## The fix

**Layout.** An arena allocation is now a 16-aligned `myl_native_object` header
followed by its payload, the same layout a tracing-heap slot has. It replaces
the 24-byte side record. The header's word 1 is the element descriptor. Word 0
is laid out as follows ([`src/native_heap.h`](../../src/native_heap.h)):

| bits | tracing-heap object | arena allocation |
|---|---|---|
| 0–1 | mark, immortal | always 0 |
| 2–39 | element count | element count (at most 2^38 − 1) |
| 40–61 | element count | owning depth (at most 4,194,303) |
| 62 | always 0 (the count is capped at 2^60 − 1) | `MYL_NATIVE_OBJECT_ARENA` |
| 63 | free-slot tag | always 0 |

**Lookups.** `myl_native_header_region(payload)` is one load and a bit test. It
is a `static inline` in the header, so `reach()` in the barrier inlines it even
in QBE builds. `myl_native_object_region`, `_element` and `_immortal` read the
header for every kind of payload. `mark()` folds the arena test into the flag
test it already made. `myl_native_heap_extend` and `myl_native_heap_release`
refuse an arena payload by its flag. The arena scan during collection
(`myl_native_arena_trace`) walks each chunk's headers in allocation order. It no
longer walks side records.

**Barrier shortcut.** `myl_native_region_check` accepts a store at once when the
container already lives in the innermost open arena. No live object is younger
than that arena, so the value's depth cannot exceed the container's, and the
answer is the one the full check would give. This is the common case: a list or
dictionary filled in the scope that made it.

**Why it stays sound.**

- *Nested arenas.* Each allocation records the depth it was made at, including
  `alloc_at` for backing that grows in an older container's region.
- *Escape copies.* Clones are allocated while `region_depth` is lowered, so their
  headers carry the enclosing depth. `ensure()` compares header depths.
- *Bulk release and chunk reuse.* Headers live inside the `used` prefix that
  reuse already zeroes, so a reused chunk is still byte-identical to a fresh
  one.
- *The collector.* It never marks, queues or sweeps a flagged payload. The scan
  of arena contents keeps GC objects alive as before.
- *Interior pointers.* The header read assumes every managed pointer the runtime
  follows is an object's start. The collector already relied on that for every
  non-arena pointer. Byte views record their backing block, not a mid-block
  address, for the same reason.
- *Traps.* The barrier traps exactly where it did.

The header bounds are new failure points: an arena allocation of 2^38 or more
elements, a scope opened at depth 4,194,303, and a tracing-heap allocation of
2^60 or more elements are all refused as allocation failures. None is reachable
in practice: element counts are bounded by memory and nesting by the native
stack. The tracing-heap cap also closes an old edge: a zero-size-element
allocation of 2^61 or more elements used to overflow into the free-slot tag.

**Spec and docs.** The new bullet `[ARENA-MANAGED-11]` states the contract. Two
existing bullets were edited to stay true. `[ARENA-MANAGED-8]` no longer says
"compact side descriptors and no per-object GC header". `[ARENA-MANAGED-10]`
now says that reuse zeroes the headers and payloads rather than "its side
records". [`docs/arenas.md`](../arenas.md) now describes the header, the linear
store cost, the barrier shortcut and the bounds.

## Measurements

The machine was loaded (load average 5.5–9.4 during the runs, other agents
building). Every binary ran pinned to CPU 10. The before arm is the base
compiler `install-a3`; the after arm is a ReleaseFast build of this branch.

**Scaling.** `results/wave0/arena_scaling.py` builds the repro at three sizes
with both compilers and times all six binaries shuffled in each of 7 rounds.
The table shows medians.

| stores | before | after | before growth | after growth |
|---|---|---|---|---|
| 1M | 320 ms | 87 ms | | |
| 2M | 1146 ms | 174 ms | 3.58× | 2.01× |
| 4M | 6122 ms | 356 ms | 5.34× | 2.04× |

Peak RSS at 2M falls from 144 MB to 128 MB, because each allocation's 16-byte
header replaces a 24-byte side record. After the fix, the barrier functions are
3.3% of the repro's samples.

**Suite.** `bench.py knucleotide binary_trees --arms my my-arena --cf before`
ran 11 interleaved rounds. The new `suite/knucleotide_arena.my` prints
byte-identical output to `knucleotide.my`; each counting phase runs inside its
own `with arena()`. Ratios are paired per round, from
`results/wave0/paired.py`.

| comparison | wall ratio [95%] | medians |
|---|---|---|
| `knucleotide_arena` after / `knucleotide` after | **0.926 [0.911, 0.982]** | 806 / 875 ms |
| `knucleotide_arena` after / before | 0.471 [0.460, 0.485] | 806 / 1741 ms |
| `knucleotide` after / before | 1.000 [0.985, 1.051] | 875 / 875 ms |
| `binary_trees_arena` after / before | **0.978 [0.965, 0.994]** | 607 / 613 ms |
| `binary_trees` after / before | 0.963 [0.945, 1.013] | 894 / 923 ms |
| `binary_trees_arena` after / `binary_trees` after | 0.650 [0.638, 0.663] | 607 / 894 ms |

Against `zig-fast` in the same batch, the ratios and peak RSS are:

| program | before | after | peak RSS before | peak RSS after |
|---|---|---|---|---|
| `knucleotide_arena` | 10.36× | 4.90× | 99.5 MB | 92.4 MB |
| `knucleotide` | 5.31× | 5.32× | 78.3 MB | 78.3 MB |
| `binary_trees_arena` | 1.31× | 1.29× | 18.9 MB | 17.8 MB |
| `binary_trees` | 2.04× | 1.98× | 51.7 MB | 51.7 MB |

Acceptance: store cost is linear (2M ≈ 2× 1M). The arena-wrapped `knucleotide`
is no slower than the collecting one; it is 7% faster. `binary_trees_arena` is
no slower than before; it is 2% faster.

## Tests

- **C, [`tests/native_arena_chunks_test.c`](../../tests/native_arena_chunks_test.c)**,
  run by `zig build test`, `test-qbe` and `test-native-heap`:
  - `header_regions` allocates 4096 objects over several chunks in two nested
    arenas. It then detaches `heap->arena_chunks` and checks every region,
    element and immortality answer for arena, tracing-heap and frozen payloads.
    This is the deterministic scaling check: no lookup consults the chunk list,
    so none can depend on its length. It fails on the base.
  - `barrier_by_header` covers the shortcut and every older and younger
    container and value pairing.
  - `scan_across_chunks` checks that a GC object referenced only from the first
    and the last of 3000 arena slots survives a collection.
  - `header_bounds` checks the three count and depth bounds.

  The whole native suite also passes under `-fsanitize=undefined` and under
  `-fsanitize=address` (`scripts/test_native_memory.py`, `MYLANG_TEST_ASAN=1`).
- **Zig, [`src/arena_managed_test.zig`](../../src/arena_managed_test.zig).** The
  `ARENA-MANAGED-11` test checks that the barrier still traps `R_ARENA_ESCAPE` in
  two cases once the arena spans thousands of allocations: a depth-2 value
  stored into a depth-1 container, and an arena value stored into a collected
  container. It also checks the accepted stores at the same scale. All 35 arena
  unit tests pass.
- **Guest, [`tests/lang/arena_regions.my`](../../tests/lang/arena_regions.my)**,
  with five tests under `--gc-stress`, so every allocation also walks every
  header:
  - thousands of arena strings in one arena list;
  - collected values stored into arena lists and dictionaries;
  - an older arena's values in a younger container;
  - records holding arena text;
  - `escape` of a list that spans several chunks.

  The existing `arena_managed.my` and `arena_scopes.my` still pass.

No guest scaling test was written, because under `--gc-stress` every arena
allocation collects and scans the whole arena, which is quadratic by design.
The detached-chunk-list test stands in for it.

## Gate

Each full-gate step ran on the branch and was compared with the base logs using
`gate/gate_diff.py`:

- `zig build test`: 47 failing test names on the base and 47 on the branch,
  none new and none cleared. The build summary shows 19 failed steps against
  the base's 18. The added unit test shifts tests between the 12 shards, so the
  same 46 failures now fall into 12 shards instead of 11.
- `zig build test-qbe`: 2 failures on the base and 2 on the branch, none new.
- `zig build test-qbe-build`: 30 of 30 steps pass.
- `zig build fmt-check` passes, and Guardian passes all 88 checks.

## What is left

- **Two chunk-list walks remain, off the per-store path.**
  `myl_native_arena_release` still walks the whole chunk list at every scope
  exit. `myl_native_arena_alloc` still searches it for the current chunk of the
  allocating region. Under a large outer arena, each exit of a short inner scope
  costs O(outer chunks). Keeping the list ordered by depth would make release
  cost proportional to the chunks it frees. The suite does not exercise this
  case.
- **Fresh memory is what the arena variant still pays.** An arena never reuses
  memory within a scope. The retention cache keeps at most 2 MiB, so each
  `knucleotide_arena` phase faults in about 70 MB again. `myl_native_heap_alloc_at`
  also validates its arguments before it dispatches to the arena. Neither cost is
  quadratic.
- **`knucleotide` is still about 5× Zig on either heap.** The dictionary and
  text items in wave 0 (items 2 and 3) and §5.4 are what remain for it.
