# Peak memory on allocation-heavy programs, and the collector leftovers — 2026-09-23

Parity leftovers lane `perf/memory-footprint`, from `base/parity-leftovers`
(`160a2d08`), with the integration commit `6a1a9c4d` merged in before the final
measurements and gate. Items 1–6 of the lane brief; the memory target of
[the parity plan](performance-parity-plan-2026-09-22.md) (§1, §3.4) is peak
RSS ≤ 1.5× Zig, with no loss of time.

> **Follow-up (branch `perf/memory-footprint-2`, see the last section).** The
> first merge (`cfc940bf`) made `lib/scan_split` 1.29× slower. Two of the
> changes below cost it: the tighter collection trigger (item 2) and returning
> spare pages to the host (item 4). Both are withdrawn; `GC-TRIGGER-1` no longer
> exists. The tables in this header and in *Measurements* are the first merge's;
> the follow-up section has the numbers that ship: text_ops peaks at 38.5 MB and
> knucleotide at 27.9 MB instead of 34.2 and 25.5, and every program is within
> 3% of its pre-lane time except `sieve`, a code-layout effect (see there).

**Status: done, gated.** Peak RSS against the integration base (`6a1a9c4d`, the
branch this lane merges into):

| program | RSS before (w4) | RSS integration | RSS this branch | Zig | this / Zig |
|---|---:|---:|---:|---:|---:|
| binary_trees | 29.1 MB | 29.1 MB | **16.1 MB** | 4.6 MB | 3.5× |
| knucleotide | 61.6 MB | 28.6 MB | **25.5 MB** | 9.5 MB | 2.7× |
| text_ops | 34.8 MB | 44.0 MB | **34.2 MB** | 7.8 MB | 4.4× |
| sort_records | 41.4 MB | 41.5 MB | **41.0 MB** | 15.8 MB | 2.6× |
| matmul_tuned | 19.1 MB | 19.1 MB | 14.5 MB | 6.1 MB | 2.4× |
| matmul | 12.5 MB | 12.4 MB | 10.4 MB | 6.1 MB | 1.7× |
| knucleotide_arena | 90.6 MB | 90.6 MB | 82.9 MB | 9.5 MB | 8.7× |

"Before (w4)" is the lane brief's before-arm compiler (`install-w4`, the same
binaries as `160a2d08` for these programs). knucleotide's drop from 61.6 to
28.6 MB between w4 and the integration base is the text/dictionary lane's range
keys, not this lane; text_ops' rise from 34.8 to 44.0 MB there is a phase effect
of the old trigger (see *Where the bytes go*). This lane's contribution is the
integration → this branch column.

**The 1.5× target is not reached on any of the four, and cannot be by the
collector.** Each program's floor is set by its object sizes and by the
language's copy semantics (next section); the lane moved all four toward it and
binary_trees most of the way.

**Time:** no program is slower than the integration base beyond noise
(paired CPU ratios, 11 rounds, CPU 8, table in *Measurements*). binary_trees
runs in 0.88× the integration base's CPU time and **0.48× Zig's**.

## Where the bytes go

Traced from per-collection logs (a temporary `MYL_HEAP_TRACE` build; before
and after bytes, kept-young and old bytes, segments per size class, pool and
spare counts). The process itself costs about 2.4 MB (mandelbrot's RSS).

- **binary_trees.** A node is 16 bytes of header and 16 of payload (32). The
  stretch tree, 2^18 nodes, is 8 MiB live at its peak, and the long-lived tree
  4 MiB. Before this lane every minor collection promoted the tree under
  construction (the 2.1 M promotions the alloc-gc audit counted), so the old
  generation filled with dead trees until a full collection: peak heap 26 MB,
  RSS 29 MB. With aging nothing is promoted but the long-lived tree: peak heap
  13.5 MB (old 5 MiB + a 4 MiB young interval + the tree a minor collection
  keeps young). The floor with 32-byte nodes is about the stretch tree plus a
  young interval plus the process: ~13–14 MB, 3× Zig. **1.5× Zig (6.9 MB) is
  below the stretch tree's own 8.4 MB**; see item 6 for what a smaller header
  would buy.
- **knucleotide.** About 137 k distinct 12- and 18-octet keys at 64 bytes each
  (16 header + 24 text header + payload, rounded) = 8.7 MB, the dictionary's
  entries and index ~5 MB, the 1 M-pointer `parts` list during `generate`
  (8 MB), and the previous `frequencies` dictionary, which is old garbage until
  a full collection. The old trigger let that garbage reach 2× the last full
  collection's live bytes plus 4 MiB, and then let the heap grow by another
  young interval of half a live figure that included the garbage (13.6 MB at
  the worst point) before the full collection ran.
- **text_ops.** 200 k lines of ~15 octets at 64 bytes each (12.8 MB) plus the
  list (1.6 MB), the joined text (4 MB), the rewritten text (4 MB) and the
  young interval (half of ~18 MB live). The big risk is phase timing: the
  f-string list (14 MB) dies right after `join`, and whether a full collection
  runs before the split refills the heap decided 34.8 MB (w4) against 44.0 MB
  (integration) under the old trigger.
- **sort_records.** 1 M records inline in the list storage (16 MB), the key
  list (8 MB, reused as the counting sort's destination) and the sorted copy
  (16 MB): 40 MB with no garbage at all — five collections in the whole run.
  `sorted()` returns a copy while Zig sorts in place (15.8 MB), so this program's
  floor is 2.5× Zig without a change to the language or the standard library.

## What changed

### 1. Aging (`GC-AGING-1`)

A minor collection promotes a young object only the second time it finds it
reachable. The state is one more bitmap per segment, `ages`, one bit per
16-byte granule like the mark bits (512 bytes per 64 KiB segment):

- **Marking.** A young object marked for the first time in a minor collection
  gets its age bit set and keeps header bit 0 (the store barrier's "old" flag)
  clear; an object whose age bit is already set is promoted — bit 0 set, age
  bit cleared. While a collection marks, a set age bit on a *marked* object
  therefore means "kept young by this collection" and on an unmarked one
  "survived the last minor collection".
- **Sweep.** Holes are built from the mark bits first, so a kept object is
  not reclaimed; then `ages &= marks; marks &= ~ages` for the segment, so every
  kept object is unmarked (young) again and every dead or promoted object's age
  bit is gone. A segment holding a kept object stays dirty, so the next minor
  collection sweeps it. Only promotion counts toward the full threshold
  (`old_bytes` excludes `young_bytes`).
- **Promotion through an old object.** The rescan set and the remembered
  bodies are traced with aging set to *promote*: a young object stored into an
  old list, dictionary or class body is promoted at once — the old container
  keeps it, and aging it would only trace it twice. Without this, text_ops and
  knucleotide traced every stored key and line twice.
- **Remembering.** The one soundness obligation aging adds: a promoted object
  that references an object the same collection keeps young is an old → young
  edge no barrier reported. For a rescanned object (list, dictionary, view)
  nothing is needed. A promoted `class` body is listed as remembered, exactly as
  if the barrier had fired; a remembered body whose scan finds a kept-young
  child stays listed. `mark` records the edge (`young_edge`) when it meets an
  already-marked object whose age bit is set, or keeps a new one young.
  Listed bodies keep bit 0 clear after the sweep, as the barrier leaves them,
  and the pre-pass of the next minor collection deduplicates the list.
- A full collection clears every age bit with the mark bits and promotes every
  survivor. `--gc-stress` now runs a full collection every third collection
  (it alternated), so two minor collections — keep, then promote — run between
  full ones at every allocation.

A bug found on the way and fixed: promotion through an old reference first
left the age bit set, so the sweep unmarked the promoted object again and it
was retraced by every minor collection — `matmul_tuned` took 1.7× the CPU time.
Aging is now three-state (off / keep / promote); a C test reaches a kept-young
object through an old record's rescan and fails on the earlier commit.

**Effect:** binary_trees peak RSS 29.1 → 16.1 MB and 0.88× the CPU time. Its
collection trace goes from 5 full collections and a 26 MB peak heap to one full
collection (the first, at 1 MiB) and 13.5 MB; a C model of the program against
the runtime,
[`probes/memory-footprint/binary_trees_sim.c`](../../experiments/perf-parity-plan-20260922/probes/memory-footprint/binary_trees_sim.c),
shows the same (29.5 → 16.1 MB RSS).

### 2. Collection triggers (`GC-TRIGGER-1`, withdrawn in the follow-up)

Three changes to `schedule`, all about garbage in the old generation:

- the full threshold is 1.5× the bytes the last full collection kept plus
  4 MiB (it was 2×);
- the minor collection whose promotions reach the threshold makes the next
  allocation collect fully (it waited another young interval);
- while minor collections keep promoting, the next one runs no later than the
  threshold (or 4 MiB past the live bytes, if that is later), so a young
  interval sized from garbage-inflated live bytes cannot carry the heap far
  past the threshold first.

The young interval itself is unchanged: half the live bytes, at least 4 MiB. A
smaller one is the obvious RSS lever and it is not free — every minor collection
rescans every old list and dictionary (no card marking), so text_ops' 200 k-line
list is traced once per 4 MiB of garbage; a fixed 4 MiB interval cost text_ops
19% and knucleotide 3–5% CPU in the policy grid below.

**Policy grid.** Measured with a temporary build whose policy knobs came from the
environment (grid of 11–15 interleaved rounds, CPU 8; the two
`memory-footprint-policy-*-experimental.json` result files are the bench.py
runs of the two finalists on that build, before the age-bit fix):

| policy (peak RSS, MB) | binary_trees | knucleotide | text_ops | CPU cost |
|---|---:|---:|---:|---|
| old trigger (2×, wait a young interval) | 16.1 | 27.9 | 38.5 | reference |
| + full at once when promotion reaches the threshold | 16.4 | 41.9 † | 55.4 † | text_ops +12% † |
| + 1.5× threshold only | 16.1 | 49.2 † | 53.9 † | text_ops +8% † |
| young interval fixed at 4 MiB | 15.7 | 38–50 † | 30–43 † | text_ops +19–24%, knucleotide +3–5% |
| young interval capped by the last full collection's live bytes | 15.7 | 48.0 † | 46.5 † | not timed alone |
| **shipped: 1.5×, full at once, cap while promoting** | **16.1** | **25.5** | **34.2** | text_ops +4.8% against the old trigger on this branch, still 0.98× the integration base |

† measured before the text/dictionary merge (knucleotide then peaked at 55 MB
under the old trigger), with the same code otherwise. text_ops' peak moves by
±10 MB with any change to *when* the full collection runs relative to the death
of its f-string list, which is why most single-knob changes looked worse on it:
only the combination that bounds the overshoot by construction is consistently
lower. The shipped policy gives back 4.8% of text_ops' CPU that aging and the
other changes had won (0.95× → 0.98× the integration base) for 4.3 MB of RSS.

### 3. Clearing only what must be cleared (`GC-NOZERO-1`)

- `myl_native_heap_alloc_block` — the storage of every `str` built at run time
  — no longer clears a reused slot: its caller writes every octet it reads
  before the next safepoint (every `myl_native_text_build` caller was checked,
  and the text hash reads exactly `bytes` octets), and its PLAIN descriptor
  keeps the collector out. Arena blocks still come from zeroed chunks.
- Constructor-filled class bodies were already covered: the inline path zeroes
  the payload and LLVM deletes the stores the constructor shadows. A class body
  above 256 bytes still goes through the runtime and is cleared, because it is
  traced.
- Fresh pool segments are no longer `memset`: pools are anonymous mappings
  (next item), which read as zero, so the page faults happen on first use
  rather than in the allocator.

The time effect is inside the noise on its own (text_ops' allocation profile is
dominated by the split itself).

### 4. Spare segments and returning memory (`GC-SPARE-1`)

- A bitmap segment a sweep leaves empty (other than its class's current bump
  segment) is unlinked from its class and becomes a **spare**, which any class
  takes before a new mapping is made. Before, an empty segment stayed in its
  class forever, so the peak was the sum of every class's own peak — a phase
  change from 48- to 64-byte objects (text_ops' split fields against its lines,
  knucleotide's short against long keys) needed fresh memory. A resident spare
  is stale: its header is cleared, `stale` is set and every slot handed out from
  it is cleared like a reused hole's. knucleotide (before the text merge):
  59.2 → 55.0 MB from spares alone.
- **Returning pages.** A full collection `madvise(MADV_DONTNEED)`s the spares
  that stayed unused since the previous full collection (a low-water mark of
  the spare list). The first version released every spare above the next young
  interval after each collection; it lowered no peak in the suite and cost
  text_ops 3% in page faults, because text_ops frees a phase's storage and
  refills it at once. Released spares read as zero and are fresh again.
  Neither form lowers *peak* RSS on these programs — the peak is reached with
  the heap full — so this is for steady-state RSS after a phase shrinks.
- Pools are now 2 MiB-aligned private anonymous mappings (map 4 MiB, unmap the
  unaligned head and tail) instead of `aligned_alloc`, which is what makes
  `madvise` well defined and gives the pool table below its 2 MiB regions.
- Rescan entries whose object was released are dropped when a minor collection
  finds them unmarked, so no rescan or remembered entry can point into a
  segment that became a spare. Spares are restricted to bitmap segments: a
  large-class slab has another size and alignment (the first version made that
  mistake and knucleotide crashed).

### 5. Arena scope close and outer-depth lookup (`ARENA-CHUNKS-1`)

`arena_chunks` is now one list per depth (`arena_chunks[d]`, newest first,
`arena_depths` in use). An allocation at depth *d* — the innermost or an outer
one — takes the head of list *d*; closing a scope frees lists from the top
down to its depth, so it costs the chunks it frees; the collector's arena scan
walks every depth. The escape copier and region checks never walked the list,
so `native_regions.c` (the checker-bugs lane's file) is untouched.

[`probes/memory-footprint/arena_scope_sim.c`](../../experiments/perf-parity-plan-20260922/probes/memory-footprint/arena_scope_sim.c)
opens and closes a one-allocation inner scope under an outer arena:

| outer chunks | before | after |
|---:|---:|---:|
| 6 | 49 ns | 49 ns |
| 104 | 1,939 ns | 49 ns |
| 997 | 45,169 ns | 51 ns |

A C test replaces the outer depth's list with an unmapped address while inner
scopes allocate and close 100 times (and the inner list while the outer depth
allocates), so any walk of another depth's chunks would crash.

### 6. Header size — analysis only

A two-word header costs 16 bytes per object. With an 8-byte header and 8-byte
size-class granularity (payloads aligned to 8, not `max_align_t`):

| program | objects that dominate the peak | per-object bytes 16 B → 8 B header | estimated peak RSS |
|---|---|---|---:|
| binary_trees | 2^18 nodes | 32 → 24 | 16.1 → ~12.5 MB (2.7× Zig) |
| knucleotide | ~137 k keys | 64 → 48/56 | 25.5 → ~23.5 MB |
| text_ops | ~400 k short texts | 64 → 48 | 34.2 → ~29 MB |
| sort_records | none (records are inline) | — | unchanged |

It is not contained, so it was not implemented. The mark word holds the flags,
the element count (up to 2^60) and, in an arena, the depth; the second word is
the descriptor pointer. One word would need a descriptor index plus a narrow
count, with a separate header for large objects — and the two-word layout is
read by generated inline allocation, the store barrier, frozen literal blocks
in the image, arena headers, the escape copier, printing, equality and codecs.
A cheaper step toward the same bytes is the text lane's 24-byte `str` header
(length, octets, flags, hash), which could be 16.

### Also: address-classified marking (`GC-POOLSET-1`)

`mark` read every child's header to learn whether it was large, arena or
immortal before it could consult a bitmap, so a minor collection's rescan of
old lists and dictionaries took a cache miss per reference into the old
generation (the alloc-gc audit's leftover). The heap now records every pool's
2 MiB region in a small open-addressed table, fronted by a 128-entry
direct-mapped cache; a reference into a pool is decided by its mark and age
bits alone, and only a newly marked object's header is read.
[`probes/memory-footprint/rescan_sim.c`](../../experiments/perf-parity-plan-20260922/probes/memory-footprint/rescan_sim.c)
(one old list, many minor collections):

| references | layout | header read (before) | pool table (after) |
|---:|---|---:|---:|
| 200 k | allocation order | 2.1 ns | 1.75 ns |
| 200 k | shuffled | 4.4 ns | 2.25 ns |
| 2 M | shuffled | 16.5 ns | 3.9 ns |

### Also: a partial mark could be swept

The worklist-reservation failure check ran before the drain loop, so a push
refused *during* the drain left a reachable object unmarked and the sweep freed
it. The check now follows the drain. Only reachable under host OOM of the
worklist.

## Measurements

`bench.py`, 11 rounds, fresh processes pinned to CPU 8, arms shuffled per round,
three mylang arms: this branch (`my`), the integration base `6a1a9c4d`
(`integ`, the coordinator's `install-loops`) and the brief's `install-w4`
(`before`). Load average 1.7–3.1 (another lane's benchmark ran on CPU 2).
Raw rounds: [`results/leftovers/memory-footprint-suite.json`](../../experiments/perf-parity-plan-20260922/results/leftovers/memory-footprint-suite.json);
the same run without the trigger change:
[`memory-footprint-suite-no-trigger.json`](../../experiments/perf-parity-plan-20260922/results/leftovers/memory-footprint-suite-no-trigger.json).
Paired CPU-time ratios with 95% bootstrap intervals, this branch against the
integration base:

| program | CPU this / integration | 95% interval | ms this | ms integration | × Zig (CPU) |
|---|---:|---|---:|---:|---:|
| binary_trees | **0.879** | [0.874, 0.884] | 102.2 | 116.1 | 0.48 |
| binary_trees_arena | 0.961 | [0.958, 0.973] | 164.4 | 170.8 | 0.78 |
| knucleotide | 0.998 | [0.992, 1.014] | 141.2 | 140.9 | 1.50 |
| knucleotide_arena | 0.968 | [0.965, 0.976] | 290.8 | 300.6 | 3.10 |
| knucleotide_tuned | 1.004 | [0.999, 1.014] | 129.3 | 128.4 | 1.38 |
| text_ops | 0.982 | [0.965, 0.987] | 92.9 | 94.6 | 3.77 |
| text_ops_tuned | 0.974 | [0.964, 1.010] | 16.1 | 16.4 | 0.65 |
| sort_records | 0.992 | [0.985, 0.996] | 29.2 | 29.4 | 0.28 |
| sort_records_keyed | 1.011 | [0.957, 1.025] | 38.0 | 37.8 | 0.36 |
| sort_records_sorted | 0.997 | [0.990, 1.011] | 28.9 | 29.0 | 0.27 |
| fannkuch_redux | 1.005 | [0.974, 1.012] | 223.8 | 222.6 | 1.17 |
| fannkuch_redux_array | 1.020 | [1.006, 1.064] | 175.5 | 165.6 | 0.92 |
| fannkuch_redux_tuned | 0.998 | [0.993, 1.082] | 183.0 | 184.3 | 0.96 |
| mandelbrot | 1.002 | [1.000, 1.024] | 118.0 | 117.9 | 1.02 |
| matmul | 0.978 | [0.963, 0.982] | 149.1 | 153.9 | 3.65 |
| matmul_flat | 0.984 | [0.975, 1.002] | 110.4 | 109.6 | 2.70 |
| matmul_tuned | 0.961 | [0.947, 0.972] | 173.2 | 179.5 | 4.24 |
| nbody | 0.996 | [0.980, 1.020] | 278.6 | 274.4 | 2.06 |
| nbody_class | 0.999 | [0.984, 1.015] | 224.4 | 228.2 | 1.66 |
| raytrace | 1.009 | [0.975, 1.027] | 109.7 | 105.9 | 1.42 |
| raytrace_tuned | 0.987 | [0.935, 1.009] | 93.3 | 97.9 | 1.21 |
| sieve | 1.013 | [0.980, 1.038] | 94.1 | 92.8 | 1.73 |
| sieve_tuned | 1.018 | [0.955, 1.053] | 89.9 | 90.4 | 1.65 |
| sort_builtin | 1.002 | [0.994, 1.007] | 98.3 | 98.4 | 0.51 |
| sort_quick | 0.988 | [0.961, 1.001] | 216.8 | 219.1 | 1.29 |
| spectral_norm | 0.982 | [0.973, 0.991] | 185.9 | 188.9 | 1.23 |
| spectral_norm_tuned | 0.979 | [0.962, 0.989] | 154.2 | 159.0 | 1.02 |

`fannkuch_redux_array` (1.020 [1.006, 1.064]) allocates nothing in its hot loop
and was 1.008 [1.004, 1.013] in the run before the trigger change, which does
not touch it; I read it as layout noise of the shared LTO runtime. Every other
interval contains 1.0 or lies below it. Against the w4 arm, the differences
larger than a few percent (knucleotide 0.44×, spectral_norm 0.74×,
fannkuch_redux_tuned 1.08×, raytrace 0.94×) are the other merged lanes, and
match the integration arm's own ratios.

## Tests

- `tests/native_heap_test.c` (spec-case comments): `aging_test` (kept once,
  promoted the second time, a brief object reclaimed young, full collection
  promotes all), `aging_edges_test` (a promoted cell body with a kept-young
  child is remembered until the child is promoted; a young object reached only
  through a remembered body is promoted at once),
  `aging_through_old_references_test` (fails on the commit before the age-bit
  fix), `spare_test` (cross-class reuse without a new pool, stale slots
  cleared, idle spares released after two full collections), `block_reuse_test`
  (a block keeps its stale octets, an ordinary allocation from the same storage
  is zero), `trigger_test` (threshold, cap while promoting, full at once).
  `remembered_cell_test` is unchanged and still passes.
- `tests/native_arena_chunks_test.c`: `per_depth_chunks` (the poisoned-list
  scaling check above); `header_regions` adapted to the per-depth array.
- `tests/lang/gc_footprint.my`: one `# spec:` test per new bullet
  (`GC-AGING-1`, `GC-TRIGGER-1` (withdrawn in the follow-up), `GC-SPARE-1`, `GC-NOZERO-1`, `GC-POOLSET-1`,
  `ARENA-CHUNKS-1`) plus a `GC-AGING-1` case; `gc_generations.my`'s comment
  updated for the new stress pattern.
- `mylang test tests/lang`: 569 passed; with `--gc-stress`: 569 passed.
- `scripts/test_native_memory.py` suites under UBSan and under ASan + UBSan
  (`MYLANG_TEST_ASAN=1`): all pass except `native_print`, which fails on the
  base as well (`native_print_test.c:58`, `1e100` is expected to be
  unprintable) and is untouched here.

## Gate

Against the coordinator's logs of the integration base (`loops-*.log`, commit
`6a1a9c4d`), with `gate_diff.py`, on this branch's head:

- `zig build test`: 77/77 steps, 0 failures (base 1); **no new failures**. The
  one cleared is the known flake "guest benchmarks write a candidate and
  enforce an approved baseline immutably".
- `zig build test-qbe`: 308/308, no failures; **no new failures**.
- `test-qbe-build`, `test-schematic`, `test-byte-io`, `fmt-check`: green, no
  new failures. Guardian (every build and the commit hook, whole tree): 88
  checks passed.
- `mylang test tests/lang` and `--gc-stress`: 569 passed each.
- Native C suites under UBSan and ASan + UBSan: pass (`native_print` excepted,
  failing identically on the base).

## What is left

- **Card marking for runtime lists and dictionaries.** Every minor collection
  rescans every old list and dictionary in full, which is what makes a small
  young interval expensive (text_ops +19% at a fixed 4 MiB). With a barrier on
  list stores the young interval could shrink to the 4 MiB floor for every
  program: binary_trees ~15.7 MB, text_ops ~30 MB, knucleotide ~24 MB in the
  grid. It needs the list-store lowering and the runtime's writes together.
- **Object sizes.** binary_trees' and text_ops' floors are object sizes: the
  two-word header (item 6) and the 24-byte text header. sort_records' floor is
  `sorted()`'s copy (an in-place `list.sort` by key would halve it).
- **Aging depth.** One survived minor collection is enough for these programs;
  a structure alive across exactly two young intervals is still promoted. A
  second age bit would cost another 512 bytes per segment.

## Follow-up: the scan_split regression (`perf/memory-footprint-2`)

The coordinator's batch after the merge: `lib/scan_split` took 169.7 ms with
this lane (`install-mem`, `cfc940bf`) against 129.0 ms before it
(`install-loops`, `6a1a9c4d`), and `bench-parity` flagged it at 4.44× Zig
against a 3.48× threshold. The suite and micro-kernels in my own measurements
did not include `lib/`.

**The cause.** scan_split splits a 4 MB text three times into about 2.5 M short
`str` pieces kept in lists while each loop runs, so its live set is large and
grows in steps, and every minor collection rescans those old lists (no card
marking). A/B of each change on the `cfc940bf` runtime, one binary with each
change switchable from the environment (paired CPU time against
`install-loops`, 9 rounds, CPU 8):

| change switched off | scan_split / pre-lane |
|---|---:|
| none (as merged) | 1.307–1.314 |
| aging | 1.309 |
| clearing text blocks restored | 1.348 |
| pool-classified marking | 1.369 |
| spare segments | 1.253 |
| page return of idle spares | 1.238 |
| tighter trigger (back to 2× + 4 MiB) | 1.140 |
| trigger and page return | **0.955** |
| trigger, page return and spares | 0.964 |
| everything (the pre-lane collector) | 0.992 |

- **The trigger** doubled the collections: 14 full and 29 minor against 6 and
  13. Full collections that ran as soon as promotion reached the 1.5×
  threshold found nothing to free (the old generation was growing with live
  pieces, not garbage), and the cap on the young interval while promoting
  added minor collections, each rescanning the old piece lists.
- **The page return** released spares between two full collections that the
  next phase refilled at once: 25% more page faults (24.7 k against 19.7 k).

**Nothing in between worked.** Every variant of the trigger (1.5× alone, full at
once alone, the cap alone, the cap bounded below by twice the bytes the last
minor rescanned, a threshold that grows at 2× after a full collection that
freed less than a quarter of the heap) kept scan_split 5–15% slower. Every
variant of the page return (idle spares only, idle spares above the next young
interval, all spares above it) cost it 9–19%, and none lowered a peak. So the
trigger is back to 2× the last full collection's live bytes plus 4 MiB, and a
spare keeps its pages. What that gives back, against `cfc940bf`: text_ops'
peak 34.2 → 38.5 MB and knucleotide's 25.5 → 27.9 MB (both still below the
pre-lane 43.9 and 28.5 MB), and knucleotide_arena 82.7 → 89.9 MB (pre-lane
90.6). binary_trees keeps 16.2 MB. scan_split's peak goes back to 65.0 MB
(64.4 before the lane, 51.6 with it).

**Measurements.** `bench.py` over `bench/parity/{suite,lib,micro}`, 9 rounds,
CPU 8, arms `my` (this branch, `25e438ec`), `loops` (`install-loops`) and `mem`
(`install-mem`), load average 1.1–2.9. Raw rounds:
[`results/leftovers/memory-footprint-2-parity.json`](../../experiments/perf-parity-plan-20260922/results/leftovers/memory-footprint-2-parity.json).
Paired CPU-time ratios with 95% bootstrap intervals and peak RSS:

| program | vs pre-lane | vs `cfc940bf` | RSS pre-lane | RSS `cfc940bf` | RSS now | Zig |
|---|---|---|---:|---:|---:|---:|
| **scan_split** | **0.960** [0.955, 0.965] | **0.735** [0.729, 0.739] | 64.4 | 51.6 | 65.0 | 4.4 |
| scan_count | 0.999 [0.992, 1.014] | 0.995 | 7.2 | 7.1 | 7.0 | 4.4 |
| scan_replace | 1.001 [0.995, 1.010] | 0.984 | 11.4 | 11.4 | 11.3 | 15.3 |
| binary_trees | 0.876 [0.868, 0.882] | 0.996 | 29.1 | 16.1 | 16.2 | 4.4 |
| binary_trees_arena | 0.999 [0.991, 1.003] | 0.999 | 11.7 | 11.5 | 11.5 | 4.4 |
| knucleotide | 1.001 [0.988, 1.009] | 0.991 | 28.5 | 25.5 | 27.9 | 9.4 |
| knucleotide_arena | 1.000 [0.995, 1.005] | 1.038 | 90.6 | 82.7 | 89.9 | 9.4 |
| knucleotide_tuned | 0.985 [0.980, 0.995] | 0.989 | 26.3 | 25.8 | 25.7 | 9.4 |
| text_ops | 0.947 [0.943, 0.952] | 0.972 | 43.9 | 34.2 | 38.5 | 7.8 |
| text_ops_tuned | 0.983 [0.978, 1.024] | 1.000 | 10.7 | 10.2 | 10.2 | 7.8 |
| sort_records | 0.991 [0.977, 1.001] | 0.997 | 41.4 | 40.9 | 41.0 | 15.6 |
| sort_records_keyed | 1.009 [0.973, 1.041] | 1.014 | 26.3 | 25.8 | 25.8 | 15.6 |
| sort_records_sorted | 0.993 [0.982, 1.001] | 0.995 | 41.3 | 40.9 | 40.9 | 15.6 |
| fannkuch_redux | 0.954 [0.950, 0.958] | 0.997 | 2.6 | 2.4 | 2.4 | 2.0 |
| fannkuch_redux_array | 0.980 [0.978, 0.989] | 0.995 | 2.7 | 2.5 | 2.3 | 2.0 |
| fannkuch_redux_tuned | 0.995 [0.994, 0.999] | 0.994 | 2.6 | 2.4 | 2.4 | 2.0 |
| mandelbrot | 0.999 [0.994, 1.001] | 0.998 | 2.7 | 2.6 | 2.4 | 2.0 |
| matmul | 0.987 [0.981, 0.990] | 1.003 | 12.4 | 10.4 | 10.4 | 6.1 |
| matmul_flat | 0.985 [0.976, 0.992] | 1.010 | 9.1 | 8.4 | 8.6 | 6.1 |
| matmul_tuned | 1.002 [0.992, 1.011] | 1.006 | 19.1 | 14.4 | 14.4 | 6.1 |
| nbody | 0.995 [0.990, 1.006] | 0.994 | 2.6 | 2.5 | 2.4 | 2.0 |
| nbody_class | 1.001 [0.999, 1.002] | 1.001 | 2.5 | 2.5 | 2.5 | 2.0 |
| raytrace | 0.997 [0.992, 1.000] | 0.997 | 2.4 | 2.4 | 2.5 | 2.0 |
| raytrace_tuned | 0.995 [0.990, 1.001] | 0.996 | 2.4 | 2.5 | 2.4 | 2.0 |
| sieve | 1.044 [1.035, 1.050] | 1.046 | 21.6 | 21.4 | 21.5 | 19.4 |
| sieve_tuned | 1.018 [1.013, 1.025] | 1.013 | 21.4 | 21.4 | 21.6 | 19.4 |
| sort_builtin | 1.002 [0.988, 1.014] | 1.003 | 26.0 | 25.5 | 25.5 | 15.7 |
| sort_quick | 1.000 [0.997, 1.004] | 1.000 | 18.5 | 18.1 | 18.0 | 15.8 |
| spectral_norm | 1.001 [0.993, 1.007] | 0.990 | 3.0 | 3.0 | 3.0 | 2.0 |
| spectral_norm_tuned | 1.004 [1.001, 1.010] | 1.003 | 3.0 | 3.0 | 3.0 | 2.0 |
| alloc_churn | 1.008 [1.001, 1.014] | 1.009 | 6.6 | 6.6 | 6.6 | 2.0 |
| alloc_churn_arena | 0.996 [0.992, 1.002] | 0.990 | 2.3 | 2.4 | 2.4 | 2.0 |
| bytes_scan | 0.984 [0.943, 1.046] | 0.986 | 11.3 | 10.8 | 10.8 | 8.3 |
| bytes_scan_wrapping | 0.999 [0.966, 1.009] | 0.998 | 11.1 | 10.8 | 10.8 | 8.3 |
| calls | 0.999 [0.994, 1.000] | 0.999 | 2.3 | 2.3 | 2.5 | 2.0 |
| dict_count | 0.978 [0.955, 0.984] | 0.972 | 3.0 | 2.7 | 2.7 | 2.0 |
| fib | 0.997 [0.995, 1.007] | 0.997 | 2.3 | 2.4 | 2.4 | 2.0 |
| float_loop | 1.001 [0.988, 1.003] | 0.999 | 2.4 | 2.5 | 2.4 | 2.0 |
| intloop | 1.003 [0.997, 1.004] | 1.002 | 2.4 | 2.3 | 2.3 | 2.0 |
| list_append_sum | 1.015 [0.988, 1.033] | 1.015 | 125.3 | 125.0 | 125.0 | 122.3 |
| list_records | 0.994 [0.978, 1.032] | 1.026 | 64.3 | 63.8 | 63.8 | 61.2 |
| list_records_wrapping | 0.999 [0.989, 1.015] | 0.999 | 64.3 | 63.8 | 63.8 | 61.2 |
| records | 1.001 [0.997, 1.009] | 1.000 | 2.5 | 2.4 | 2.5 | 2.0 |
| str_build | 0.985 [0.967, 1.001] | 0.986 | 125.4 | 125.0 | 125.0 | 122.3 |

**sieve (1.044 against pre-lane) is code layout, not collection.** sieve runs
exactly one collection (the first, at 1 MiB, with nothing live), under every
policy. A 21-round rerun gives 1.035 against both `loops` and `mem` (whose
sieve runs identically). The `cfc940bf` runtime with its trigger and page
return switched on and off from the environment, one binary, gives 1.000,
1.004, 1.001 and 1.000 for the four combinations, so the policy the follow-up
changes does not reach sieve's time; the difference between the `mem` and
this branch's binaries is the runtime code LTO lays out next to the hot guest
loop (42 lines of disassembly). `list_records` (1.026 against `mem`) reran at
1.010 [0.995, 1.025] against pre-lane and 1.003 against `mem`.

**Gate** (`gate_diff.py` against the coordinator's `mem-*.log`, all green):
`zig build test` 77/77 steps, 0 failures; `test-qbe` 308/308; `test-qbe-build`,
`test-schematic`, `test-byte-io`, `fmt-check` green — **no new failures**
anywhere. `mylang test tests/lang` 569 passed, 569 under `--gc-stress`; the
native C suites pass under UBSan and ASan + UBSan (`native_print` excepted, as
before).
