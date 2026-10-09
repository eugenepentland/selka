# A closed arena scope now hands its chunk to the next one — 2026-09-21

**Headline.** `with arena()` used to reserve and zero a fresh 64 KiB chunk on the
first allocation of every scope and return every chunk to the host at scope exit,
so a loop that opened one arena per iteration paid a `calloc` and 64 KiB of
zeroing per iteration. Bulk release now retains a bounded few chunks per heap and
the next scope takes one back instead of calling `calloc`. On the matched
`alloc_churn` kernel — one million batches, each building and folding a
sixteen-element `list[int]` inside `with arena():` — that is **18.5× → 4.7× Zig**
on QBE and **16.5× → 2.5× Zig** on LLVM O3 + LTO, and it turns the arena arm from
**3.1× slower** than the same body on the collecting heap into **1.35× faster**
(QBE) and from 4.3× slower into **1.65× faster** (LLVM). Peak resident memory is
unchanged at 2.4 MB.
This is defect three of the three the
[performance parity audit](performance-parity-audit-2026-09-21.md#3-three-defects-that-are-not-constant-factors)
named. Nothing about the documented guarantees changed: the memory budget still
counts only bytes serving live allocations, a small budget still shrinks chunks,
exhaustion still names the budget, and a reused chunk is byte-identical to a
freshly zero-filled one.

Branch `fix/arena-chunk-reuse` from `base/defects-20260921`. Raw timing samples:
[`arena-chunk-reuse-2026-09-21-probes.json`](arena-chunk-reuse-2026-09-21-probes.json).

## What was wrong

`new_chunk` in [`src/native_arena.c`](../../src/native_arena.c) sized a scope's
first chunk at 64 KiB (`preferred` doubles from there to a 1 MiB ceiling),
`calloc`'d it, and `myl_native_arena_release` `free`'d every chunk of the closing
region. A `with arena():` inside a loop therefore paid one `calloc` plus 64 KiB
of kernel-supplied zeroing per iteration, for a body whose live footprint was a
few hundred bytes. Arenas are exactly the tool
[`docs/arenas.md`](../arenas.md) recommends for repeated temporary work, and on
that workload they lost to the collecting heap by a factor of three.

## What changed

One runtime change, in `src/native_arena.c`, `src/native_arena.h`,
`src/native_heap.c` and `src/native_heap.h`.

- **A bounded per-heap retention cache.** `myl_native_arena_release` now offers
  each released chunk to `cache()` before freeing it. The bound is at most four
  chunks, at most 2 MiB, never a chunk above the 1 MiB ordinary growth ceiling
  (an oversized one-off chunk goes straight back to the host), and never more
  than `heap->limit` itself. The cache is a separate list, `heap->arena_cache`,
  which `containing()` never walks, so region lookup stays a walk of live chunks
  only.
- **Reuse instead of `calloc`.** `new_chunk` asks `uncache()` first. A cached
  chunk qualifies only when it holds at least the request's minimum and no more
  than the size the existing sizing policy would have reserved from the host, and
  the largest qualifying chunk wins because its spare capacity is free.
- **Zero exactly what could be stale.** Payload allocations only ever write
  `data[0 .. used)` — alignment padding between allocations is never touched and
  stays zero from the original `calloc` — and side records occupy the top
  `count * sizeof(Allocation)` bytes. Reuse `memset`s exactly those two ranges,
  which restores a chunk byte-identical to a freshly zero-filled one and by
  induction keeps that true across any number of reuses. The cost is proportional
  to what the previous scope used, not to the chunk size: for the kernel above,
  a few hundred bytes instead of 64 KiB.
- **Give the cache back under pressure.** A `calloc` that fails in either
  `new_chunk` or `myl_native_heap_alloc_at` frees the whole cache and retries
  once, so retained chunks can never be the reason an allocation fails.
  `myl_native_heap_destroy` frees the cache.

The first-chunk sizing policy is unchanged; §"The sizing policy" below says why.

## Accounting decisions

**A retained chunk is charged to nothing.** Release discharges it from
`heap->bytes`, `heap->arena.reserved_bytes` and `heap->arena.chunks_live`
exactly as freeing it did, and reuse charges it again exactly as a fresh
reservation would. Three consequences, all deliberate:

- `--max-memory` keeps its exact meaning: the budget counts the bytes currently
  serving live arena allocations, so `reserved_bytes`, `chunks_live` and
  `peak_reserved_bytes` keep meaning what they meant, and every existing
  assertion that a closed scope leaves `heap.bytes == 0` and
  `chunks_live == 0` still holds unchanged.
- The collection trigger is untouched. `myl_native_heap_collect` computes
  `gc_bytes = heap->bytes - heap->arena.reserved_bytes`; since a retained chunk
  is in neither term, the threshold sees exactly what it saw before.
- Because reuse is capped at the size the sizing policy would itself have
  reserved, a scope can never be charged *more* than it was charged before this
  change. A small budget still shrinks its chunk to the bytes available
  (`bytes = preferred < available ? preferred : available & ~mask`), a chunk
  larger than the remaining budget is simply not a candidate for reuse, and
  the exhaustion path is reached exactly as before, so the trap still names the
  budget rather than the host.

The one thing that is *not* charged is the retained bytes themselves: between
scopes the process can hold up to the bound (2 MiB, and never more than the
budget) above what the budget counts. That is bounded, it is memory the scope had
already been charged for at its peak, it is inside the 256 MiB `RLIMIT_AS`
headroom the budget guard installs, and any host refusal frees it and retries, so
`RLIMIT_AS` stays consistent. Measured peak RSS did not move (below).

**Statistics separate the two sources.** `myl_native_arena_statistics` gains
three fields and its header comment now states the split:

| field | meaning |
|---|---|
| `chunks` | host reservations, as before — a reused chunk does not advance it |
| `reused` (new) | chunks taken back from the cache |
| `cached`, `cached_bytes` (new) | what the cache currently holds |
| `chunks_live`, `reserved_bytes`, `peak_reserved_bytes` | unchanged: only chunks serving live allocations |

No guest module exposes these counters, and the only consumers in the tree are
`tests/native_arena_chunks_test.c` and the C runtime itself.

## Measurements

Kernels `experiments/perf-parity-audit-20260921/micro/alloc_churn_arena.my` and
`alloc_churn.my`, built `--mode ReleaseFast` (LLVM arms `--backend llvm
--llvm-opt 3 --lto`), against `micro/alloc_churn.zig`
(`std.heap.ArenaAllocator` reset per batch) and `micro/alloc_churn_gpa.zig`
(`std.heap.smp_allocator`), both `zig build-exe -O ReleaseFast`. Timing is
`probes/bench.py --cpu 8`: a fresh process per round pinned to one CPU, three
warm-ups, randomized interleaved rounds, medians, with every arm's stdout md5
checked equal before timing (all arms print `999739`).

The machine is shared and two other agents were running gates throughout, so
absolute times move between batches while within-batch ratios do not. The
headline batch below is the one in which the Zig reference landed on its
unloaded floor (64.95 ms, against 64.56 ms measured on the quietest batch of
the morning), so its absolutes are usable; five further batches at load averages
3–23 are in the probes file and agree on every ratio.

**Before and after, same batch, 11 interleaved rounds, load average 23 → 12:**

| arm | median | × Zig arena |
|---|---:|---:|
| Zig `ArenaAllocator`, ReleaseFast | 64.95 ms | 1.00 |
| Zig `smp_allocator`, ReleaseFast | 57.30 ms | 0.88 |
| mylang GC, QBE | 395.29 ms | 6.09 |
| mylang arena, QBE — **before** | 1202.05 ms | 18.51 |
| mylang arena, QBE — **after** | **304.25 ms** | **4.68** |
| mylang arena, LLVM O3 + LTO — **before** | 1070.77 ms | 16.49 |
| mylang arena, LLVM O3 + LTO — **after** | **164.20 ms** | **2.53** |

That is **3.95× faster** on QBE and **6.52× faster** on LLVM O3 + LTO.

**All eight arms in one batch**, 13 interleaved rounds, load average 3.2 at the
start but spiking mid-batch; the `min` column is the usable estimator here and
reproduces the quiet batch above arm for arm:

| arm | min | × Zig arena (min) |
|---|---:|---:|
| Zig `ArenaAllocator` | 65.03 ms | 1.00 |
| Zig `smp_allocator` | 56.76 ms | 0.87 |
| mylang GC, QBE | 371.16 ms | 5.71 |
| mylang GC, LLVM O3 + LTO | 241.50 ms | 3.71 |
| mylang arena, QBE — before | 1151.05 ms | 17.70 |
| mylang arena, QBE — after | 275.71 ms | **4.24** |
| mylang arena, LLVM O3 + LTO — before | 1027.38 ms | 15.80 |
| mylang arena, LLVM O3 + LTO — after | 146.43 ms | **2.25** |

Across the four batches that contain both a before and an after arm the ratios
span 17.2–18.5× → 4.1–4.7× (QBE) and 14.1–16.5× → 1.9–2.5× (LLVM).

**Arena against the collecting heap**, the comparison the arena documentation's
claim rests on, taken within each batch that carries both arms: the arena arm was
3.0–3.9× slower than the same body on the GC heap on QBE and 4.0–4.5× slower on
LLVM; it is now 1.05–1.35× *faster* on QBE and 1.60–1.91× faster on LLVM. The
loose ends of both "after" ranges come from the single most perturbed batch; the
four batches whose Zig reference stayed near its floor agree on 1.30–1.35× (QBE)
and 1.60–1.65× (LLVM).

**Peak resident memory**, `/usr/bin/time -f %M`, `taskset -c 8`, one run each:

| arm | before | after |
|---|---:|---:|
| mylang arena, QBE | 2436 KiB | 2412 KiB |
| mylang arena, LLVM O3 + LTO | 2452 KiB | 2456 KiB |
| mylang GC, QBE | 6748 KiB | — |
| Zig `ArenaAllocator` | — | 2016 KiB |

The cache does not raise peak RSS, which is what the accounting predicts: the
retained chunk is one the scope had already reserved, so the high-water mark is
unchanged.

### The sizing policy

The audit asked whether the 64 KiB first chunk should shrink. With reuse in
place it cannot matter for a loop of scopes — the reservation is paid once per
process, not once per iteration — and the zeroing on reuse is bounded by what the
previous scope used, not by the chunk size. Measured rather than assumed: a build
with the floor lowered from 64 KiB to 4 KiB, timed against the shipped build in
one interleaved batch of 11 rounds at load average 5.2, came out at
288.02 ms against 288.92 ms, a ratio of **1.00**. The probe was reverted; the
sizing policy ships unchanged.

## Tests

Spec bullet **`[ARENA-MANAGED-10]`** appended to the "Managed arenas" section of
`SPEC.md`.

Guest tests, `tests/lang/arena_scopes.my` — run by `zig build test-lang`, which
passes `--gc-stress` to every program, so all four also cover collection under
stress:

| test | tag | what it pins |
|---|---|---|
| `test_a_loop_of_arena_scopes_folds_every_batch_correctly` | `spec: ARENA-MANAGED-10` | 500 scopes fold identically to the same body, and four scopes sum to the unscoped sum |
| `test_nested_arena_scopes_reuse_chunks_without_disturbing_the_outer_one` | `spec-case` | 200 outer scopes each opening three inner scopes; outer values survive inner reuse |
| `test_an_escaped_list_survives_the_scopes_that_reuse_its_chunk` | `spec-case` | an `escape` copy read back after 200 scopes have reused the chunk its scope released |
| `test_a_reused_chunk_hands_out_no_bytes_of_the_previous_scope` | `spec-case` | a scope writing 256 `-1`s followed by a scope reading a fresh list, 100 times |

Zig tests, `src/arena_managed_test.zig`, both `spec-case: ARENA-MANAGED-10`:

- *repeated arena scopes reuse a retained chunk inside a small budget* — 20,000
  scopes under `--max-memory` of 1 MiB complete without a trap (a reused chunk
  charged differently from a fresh one would trap or drift), and a live arena
  list that outgrows the same ceiling still traps `R_MEMORY_BUDGET`.
- *a chunk reused after an escape copy keeps the escaped value* — normally and
  under `--gc-stress`.

C runtime tests, `tests/native_arena_chunks_test.c` (five new cases; the file's
suite is wired into `zig build test`, `test-qbe` and `test-native-heap`, and
`src/native_regions.c` was added to that build module so the escape case links):

- `chunk_reuse_across_scopes` — the second scope's first allocation returns the
  *same address*, `chunks` does not advance while `reused` does, the payload
  reads back all zero, and `bytes`/`reserved_bytes`/`peak_reserved_bytes` are
  exactly what one fresh reservation charged.
- `retention_bound` — six nested scopes release six chunks; the cache keeps four
  and stays under its byte bound.
- `reuse_respects_budget` — a 4096-byte budget: the chunk is shrunk to the
  budget, retained, reused, charged again, and the heap still reports
  `exhausted` with `bytes <= limit`.
- `nested_scope_reuse` — an inner scope's chunk serves the next inner scope while
  the outer scope keeps its chunk, its region tag and its values.
- `reuse_after_escape` — escape into the enclosing region, release, collect under
  stress, then reuse the released chunk and read the escaped value back.

"Destroy frees the cache" is checked by LeakSanitizer rather than by an
assertion, since a C test cannot observe freed storage. `MYLANG_TEST_ASAN=1
python3 scripts/test_native_memory.py` passes all ten suites; a control build
with the `myl_native_arena_reclaim` call removed from
`myl_native_heap_destroy` reports `Direct leak of 1048576 byte(s) in 1 object(s)
... in new_chunk`, so the passing run is evidence and not silence.

## Gate

Commands, all through the cgroup wrapper, on commit `6eab67db`:

| step | result |
|---|---|
| `zig build test --summary all --maxrss 8000000000` | passed, exit 0 — every step `success`, including the sharded `root_test`/`integration` runs, `native-heap-test`, `native-arena-chunks-test`, `test-lang`, `doc-coverage` and `doctest` |
| `zig build test-qbe --summary all` | passed, exit 0 — `test-c-ffi` 45/45, `test-qbe-build` 62/62 + 2/2, `test-golden` 1/1 |
| `zig build test-qbe-build --summary all` | passed, exit 0 |
| `zig build fmt-check` | passed, exit 0 |

The machine was shared with two other agents' gates throughout; no step needed
a rerun and none reported a spawn, errno or temp-directory symptom.

Guardian ran whole-tree as the commit gate: **88/88 checks passed**. The
sanitizer driver (`MYLANG_TEST_ASAN=1 python3 scripts/test_native_memory.py`,
UBSan plus ASan plus LeakSanitizer) passed all ten C suites, and
`zig-out/bin/mylang test tests/lang/arena_scopes.my --gc-stress` passed 4/4.

## Limits

- **The win is measured on one kernel.** `alloc_churn_arena.my` is the workload
  the defect was priced on; it is a loop of scopes whose body allocates a few
  hundred bytes. A program with one long arena scope, or scopes whose bodies
  outgrow a chunk every time, sees the reservation amortized differently and
  gains less. Nothing here was measured on the S-expression parser or the
  schematic renderer, neither of which opens an arena per iteration.
- **Retention is not adaptive.** Four chunks and 2 MiB are constants chosen to
  cover a few levels of nesting without holding a wide scope's reservation. A
  program alternating between scopes of very different sizes can thrash them,
  falling back to the old `calloc`-per-scope cost rather than doing worse.
- **Cross-scope use-after-free is now less likely to be caught dynamically.** A
  chunk that is retained rather than freed will not trip ASan if some future
  runtime bug reads a released arena payload. No such read is reachable today —
  arena escape is a static check and `escape` deep-copies — but the dynamic
  safety net over that specific window is weaker than it was.
- **Peak RSS can exceed the budget by the bound.** Bounded at 2 MiB and at the
  budget itself, well inside the 256 MiB `RLIMIT_AS` headroom, and freed on any
  host refusal; but a host that sizes a container from `--max-memory` alone
  should know the runtime may hold that much more between scopes.
- **Absolute times in the tables are from a shared, loaded machine.** Ratios are
  within-batch and reproduce across six batches; the absolutes should be read as
  the order of magnitude they are.
