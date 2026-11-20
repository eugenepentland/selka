# Parity benchmarks rerun on the merged compiler — 2026-09-21

Rerun of every benchmark in
[performance-parity-audit-2026-09-21.md](performance-parity-audit-2026-09-21.md)
on `perf/lever-search` at `a1a5e609`, the merge of the three defect fixes
(`PY-DICT-2` hash-indexed dictionaries, `QBE-ARRAYWRITE-1` in-place fixed-array
writes, `ARENA-MANAGED-10` arena chunk reuse). The pre-merge binaries were kept
and timed in the same batches as the new ones, so every before/after pair is a
within-batch comparison. The machine was quiet this time (load average 0.3–2.1
at each phase). Raw samples, harness copies and the chain log are under
[`experiments/perf-parity-audit-20260921/results/merged`](../../experiments/perf-parity-audit-20260921/results/merged/),
[`micro/results-merged.md`](../../experiments/perf-parity-audit-20260921/micro/results-merged.md)
and [`svg-rerun/`](../../experiments/perf-parity-audit-20260921/svg-rerun/).

**Headline.** The three cliffs are closed: a dictionary with 10,000 keys is
500× faster, a per-scope arena is 4–7× faster and now beats the collecting heap,
and the schematic render dropped 14%. Real workloads are still not at parity:
the schematic is **2.06× Zig and 1.84× Rust** (was 2.39× and 2.13× in this batch),
and the parser is unchanged at **1.8–3.0× Zig** because it touches none of the
three defects. Nothing in the measured set is now worse than about 4× Zig on
the LLVM arm, where before a dictionary-indexed program could be hundreds of
times off. What remains is the audit's structural list, in the same order.

## Schematic SVG renderer

Same harness as the production gap-fixes batch (11 arms × 3 inputs × 31
rounds, CPU 6, exact SVG hash on every run, 256 MiB budget), with the pre-merge
production arms as the before arms. LLVM O3 + LTO throughout. Medians, ms:

| arm | fixture | changed net | changed value |
|---|---:|---:|---:|
| Zig port, ReleaseFast | 1.292 | 1.311 | 1.298 |
| Rust port, O3 | 1.451 | 1.487 | 1.455 |
| Go port | 1.877 | 1.837 | 1.910 |
| mylang GC, before | 3.087 | 3.051 | 3.095 |
| mylang GC, **after** | **2.666** | **2.680** | **2.634** |
| mylang arena, before | 3.047 | 3.013 | 3.013 |
| mylang arena, after | 2.738 | 2.744 | 2.755 |
| mylang GC with tool limits, before | 7.936 | 7.819 | 7.875 |
| mylang GC with tool limits, after | 7.573 | 7.559 | 7.561 |

Paired ratios on the fixture (95% bootstrap intervals): after/before GC
**0.864** [0.843, 0.882]; arena 0.899 [0.872, 0.924]; bounded 0.954 [0.937,
0.963]. Against the ports: GC after is **2.06× Zig** [2.00, 2.15], **1.84× Rust**
[1.79, 1.87], 1.42× Go. The other two inputs agree within 0.03×. The saving is
the `io::flush` staging loop's whole-array copies, 0.42 ms of the 3.09 ms; the
audit's profile had put that loop at 42.5% of samples and the isolated probe at
0.55–0.60 ms, so the profile over-attributed somewhat and the probe was right.
Subtracting each side's empty-program floor (below), the compute-only gap went
from about 3.7× to about 3.0× Zig.

## S-expression parser and printer

21 rounds on CPU 6, both compilers' arms in one batch. Medians, ms, with the
ratio to Zig ReleaseFast:

| workload | Zig fast | Zig safe | QBE before | QBE after | LLVM O3 after | O3 + LTO before | O3 + LTO after |
|---|---:|---:|---:|---:|---:|---:|---:|
| census 927 KB | 1.98 | 2.14 | 4.46 (2.25×) | 4.63 (2.34×) | 3.71 (1.87×) | 3.49 (1.76×) | 3.57 (1.80×) |
| render 927 KB | 2.53 | 2.70 | 8.48 (3.36×) | 8.38 (3.31×) | 6.42 (2.54×) | 6.07 (2.40×) | 6.01 (2.38×) |
| census 7.42 MB | 13.29 | 14.67 | 38.03 (2.86×) | 37.68 (2.83×) | 29.85 (2.25×) | 28.62 (2.16×) | 28.49 (2.15×) |
| render 7.42 MB | 17.00 | 18.60 | 69.05 (4.07×) | 68.88 (4.05×) | 53.59 (3.15×) | 50.64 (2.98×) | 50.44 (2.97×) |

Unchanged: every before/after interval overlaps. The parser has no
dictionaries, no fixed arrays and no per-scope arenas, so none of the three
fixes touches its path. This is the honest control for the batch.

## Matched micro-kernels

The full suite rebuilt and rerun with `run.py` on CPU 6 (15 rounds). The
"before" column is the audit's suite, which ran on a loaded machine, so only
the large movements are meaningful across the two columns; the after column is
one quiet batch. Ratios to Zig ReleaseFast:

| kernel | QBE before → after | LLVM O3 + LTO before → after |
|---|---:|---:|
| dict_count (1,000 string keys) | 591× → **6.0×** | 329× → **3.2×** |
| alloc_churn, `with arena()` per batch | 18.6× → **4.1×** | 16.4× → **2.2×** |
| alloc_churn, collecting heap | 6.1× → 5.5× | 3.9× → 3.7× |
| intloop | 2.37× → 2.39× | 0.98× → 0.98× |
| records | 2.18× → 2.05× | 1.00× → 0.95× |
| calls | 2.35× → 2.25× | 1.03× → 1.01× |
| fib | 3.91× → 3.81× | 3.60× → 3.56× |
| list_records | 2.29× → 2.22× | 1.97× → 1.91× |
| bytes_scan | 3.57× → 3.77× | 1.50× → 1.74× |
| list_append_sum | 4.42× → 4.31× | 3.27× → 3.18× |
| float_loop | 3.15× → 2.88× | 3.05× → 3.05× |
| str_build | 6.01× → 5.84× | 3.83× → 3.86× |

The arena arm now runs in 149 ms against 248 ms for the same body on the
collecting heap (LLVM), and 276 ms against 375 ms on QBE: arenas beat the GC on
the workload the documentation recommends them for, which was the point of the
fix. The rows outside the top three moved by no more than the difference
between a loaded and a quiet batch.

## Probes

Same probes as the audit, before and after in one batch each, CPU 6.

**Dictionary scaling** (300,000 `counts[key] = counts.get(key, 0) + 1`):

| distinct keys | QBE before → after | LLVM O3 + LTO before → after |
|---:|---:|---:|
| 100 | 166.6 → 16.9 ms | 87.9 → 9.2 ms |
| 1,000 | 1,484 → 20.5 ms | 858 → 11.2 ms |
| 10,000 | 15,507 → **30.4 ms** | 9,307 → **18.9 ms** |

Linear in the key count before, flat after: 10,000 keys costs 1.8× what 100
keys costs, not 93×.

**Replace loop** (49,617 bytes staged through a `[256]u8`): over the 0.92 ms
empty-program floor, QBE 0.61 → 0.17 ms and LLVM 0.49 → **0.03 ms**. The loop
has become free; what is left on QBE is the bounds-checked byte loop itself.

**Unchanged, as expected:** fib(32) 3.0× Zig on both backends before and after
(the call protocol is untouched); the checked-multiply loop 2.30× on QBE and
0.89× on LLVM; the empty program 0.66 ms for Zig against 0.85 ms (QBE) and
0.83 ms (LLVM).

## Where parity stands

| | before the fixes | after | target |
|---|---:|---:|---:|
| scalar loop, records (LLVM) | 0.9–1.0× | 0.95–0.98× | ≤ 1.2× |
| schematic SVG (LLVM, GC) | 2.39× Zig, 2.13× Rust | **2.06× Zig, 1.84× Rust** | ≤ 1.2× |
| parser, small / large render (LLVM) | 2.40× / 2.98× | 2.38× / 2.97× | ≤ 1.2× |
| worst micro-kernel (LLVM) | 329× (dict) | 3.9× (str_build) | ≤ 1.3× |

The fixes removed the asymptotic failures and about a third of the schematic
gap. The rest is the audit's ranked list, unchanged: the LLVM backend as the
release default (a flat 2.2–2.4× on QBE that LLVM has already closed), the
per-call frame protocol (fib 3.6×, priced at 40% of a call-bound program), the
96-byte object header, 4-byte-per-scalar strings and the mark-sweep collector
over `calloc` (str_build, list_append_sum and alloc_churn at 3–4×), runtime fast
paths behind LTO (`find_any`, `buffer_grow_rooted`, list append), and list
elements by reference for the schematic's 128-byte `Pin` copies. Two smaller
items came out of the fix work itself: `frameBytes` over-sizes frames that pass
large `[N]T` parameters (a heap-allocated frame per call, now a separate task),
and array-typed record fields still copy on write.

## Method and limits

- Compiler: `zig-out/bin/mylang` built from `a1a5e609` (sha256 `0c9c4d2b…`);
  the before arms are the binaries the audit built from the pre-merge tree.
  LLVM arms use `--backend llvm --llvm-opt 3` with `--lto`; Zig comparators are
  unchanged from the audit.
- Timing: `probes/bench.py`, `micro/run.py`, `experiments/llvm-backend/measure.py`
  and the copied SVG harness `svg-rerun/run.py` (its repository-root lookup
  adjusted for the deeper directory; otherwise the production batch's script).
  All phases ran sequentially from one chain script on CPU 6 with the machine
  otherwise idle (load average 0.3–2.1, logged per phase in `chain.log`).
- Every timed binary's output was checked: the parser arms against Zig's
  digests, the SVG arms by exact hash on all 1,023 runs plus the ten
  qualification cases normally and under GC stress, and every micro kernel's
  stdout across all its arms.
- The micro suite's before column comes from a loaded batch; treat its
  sub-10% movements as noise. `bytes_scan` moving from 1.50× to 1.74× is that
  noise, not a regression: the kernel's code path is untouched by the merge.
