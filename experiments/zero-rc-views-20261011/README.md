# Stage 2: borrowed text and byte views

The experimental zero-RC mode now supports `TextView` and `ByteView`, with local
lifetime checking and a returned-view relationship derived from the function's
single immutable view input. The backend extends the backing owner's liveness
through every derived view; it does not retain the owner or rely on inlining.
Normal owned substrings and `.copy()` remain available when independence matters.

```text
func segment(source: TextView, start: int) -> TextView:
    return source.borrow(start, start + 3)

func main(out: Stream) -> int:
    mut text = "aλz" + str(7)
    const full = text.borrow(0, len(text))
    const part = segment(full, 1)
    out.print(part)             # λz7, without a substring allocation
    const saved = part.copy()  # owns independent storage
    text += "!"
    out.print(saved)
    # out.print(part)          # compile error: owner changed
    return 0
```

Use `.borrow(start, end)` on strings, bytes, mutable byte buffers, or other
views. Text indices count Unicode scalars, byte indices count octets. Negative
endpoints and clamping follow existing slice semantics. Byte indexing returns a
scalar. Text indexing returns an owned character and can allocate for non-ASCII
characters. `.copy()` returns an owned `str` or `bytes`.

## Measured allocation results

Compared with the frozen Stage 1 compiler:

| Workload | Stage 1 allocations | Stage 2 allocations | Cumulative allocated bytes avoided |
| --- | ---: | ---: | ---: |
| 10,000 text slices | 10,013 | 13 | 640,000 |
| 10,000 byte slices | 10,017 | 17 | 640,000 |
| Census text slice, input 4 | 9 | 8 | 64 |
| Census text slice, input 11 | 16 | 15 | 64 |

These are complete-execution managed allocation counters, including arguments
and cleanup. Peak managed bytes were unchanged: 992 for the repeated text case,
928 for bytes, and 448/992 for the two census inputs. Cumulative allocation is
allocator traffic, not simultaneous resident memory. Process RSS is measured
separately by the performance harness.

The repeated workloads request a 16-octet substring each iteration. Avoiding
10,000 such materializations avoids 160,000 payload bytes being copied, derived
from the operation and sample size. The frozen Stage 1 runtime does **not**
attribute all substring copies to its copy-byte counters, so this is not a
reported counter delta. The allocation counts and bytes above are measured.

All 27 previously supported census cases retain their outputs. Still **20/27**
allocate within the workload, because views do not eliminate construction or
growth of the owning values. All complete executions report zero RC and no live
managed bytes at exit. The borrow-only sample additionally reports zero workload
allocations/reallocations at 0, 4,000, and 11,000 slices in all five configurations.
A native regression test creates 10,000 Unicode views with zero managed allocations
in the entire execution, in both unoptimized and verified release builds.

Only census [26_text_slice.my](migrated/26_text_slice.my) changes in this stage.
It takes an explicit view and computes its result before replacing the owner.
The original version deliberately discarded the owner first and therefore needed
an independent substring. Earlier Stage 1/list migrations remain in use; no
original samples or frozen Stage 1 evidence are replaced.

[results.json](results.json) contains 330 census executions and 55 additional
paired/borrow-only executions across release, unoptimized, optimized debug,
verified release, and release without facts. Each emitted module passes the
zero-RC structural guard; runtime count reads retain the Stage 1 abort tripwire.

## Runtime and compilation

Uninstrumented release runs, with equal output, give the following medians:

| Case | Iterations | Stage 1 | Stage 2 | Elapsed change |
| --- | ---: | ---: | ---: | ---: |
| Short text | 5,000,000 | 234.8 ms | 436.8 ms | **+86.0%** |
| Bytes | 5,000,000 | 133.6 ms | 67.2 ms | **−49.7%** |
| Text from a 2,310-octet owner | 500,000 | 29.7 ms | 51.9 ms | **+74.8%** |

These are nine alternating paired repetitions after two warmups, pinned to CPU 2
on a shared host. The ranges and individual observations are in
[performance.json](performance.json). Median RSS was 2,060 KiB in every lane;
that is not evidence of a process-memory reduction. Text views reduce allocator
traffic but currently cost more execution time in these tests. They should remain
experimental. Cheap text metadata and fewer scanning/helper calls are the next
performance work; these do not require more sophisticated lifetime inference.

Positive text endpoints now scan only the required prefix. Negative endpoints
still count scalars to normalize the range, and `len(TextView)` scans the view.
The initial complete-owner scan and its measured performance are preserved in
[performance-initial.json](performance-initial.json); the final candidate contains
the bounded scan. The frozen initial executable has a separate artifact path.

Cold language-cache builds took 181–216 ms after versus 192–233 ms before. Warm
executable-cache builds took 18–20 ms versus 21–23 ms. Lowering, optimization, and
emission totaled 12–15 ms after versus 11–14 ms before; frontend build work was
7–22 ms versus 7–22 ms. Native compilation/linking dominated. These are single
cold/warm pairs with shared Zig/runtime caches and variable host load, so no
compile-time improvement is established. See
[compile-timings.json](compile-timings.json) for complete phase reports.

Validation includes 877 Core tests, 409 relevant frontend tests, and a final
43-test ownership/zero-RC regression run after the final view changes. All 385
counted executions passed the [strict RC/leak audit](candidate-audit.json), and
[CLI boundaries](boundaries.json) cover five refused programs and eight located
bounds traps. All 88 whole-tree Guardian checks passed. The
[validation manifest](validation.json) records ordering, tool/source hashes and
raw log hashes. The final compiler SHA-256 is
`94033136a95aa40d57e6fa43d545afcaab1d9da3de38b1b420b642942a03c1e3`.

## Boundaries and tradeoffs

View bindings and parameters are immutable. A function returning a view has
exactly one view parameter and no `mut` parameters. The return must derive from
that view input. Other scalar and ordinary borrowed inputs are allowed.

Views cannot be stored in aggregates or used in callback signatures. Conditional
expression bindings of views are refused; a helper can instead return from
separate branches. A loop cannot invalidate a view created outside the loop,
even if that view has no later read. Creating new views inside each iteration is
supported. These conservative restrictions avoid lifetime-name syntax and a
whole-program alias analysis.

Supported operations are borrowing/reslicing, length, indexing, copying and text
printing. Direct view iteration and other collection methods remain unsupported.
Printing a byte view or converting it to another owning type requires an explicit
copy. Existing bytes `.view()` retains its old meaning and is rejected by zero-RC
mode; it is not an alias for this API. Unsupported shapes never fall back to RC.

A view keeps its entire backing allocation alive. Copying a small substring can
therefore have a lower peak when its very large owner could otherwise be freed.
This first representation stores a pointer and byte length. Text length and
Unicode range normalization scan UTF-8; repeated slicing of a large text view can
be slower than using cached metadata on an owned string. Byte views have constant
time range normalization. Zero allocations do not establish a runtime speedup.

## Reproduce

The final candidate is installed separately from the frozen Stage 1 baseline:

```sh
export ZIG=/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
export MYLANG_ZIG="$ZIG"
.tmp/zero-rc-views-20261011/candidate/bin/mylang run \
  experiments/zero-rc-views-20261011/samples/borrowed_text.my --experimental-zero-rc

python3 experiments/zero-rc-views-20261011/measure.py \
  --compiler .tmp/zero-rc-views-20261011/candidate/bin/mylang \
  --before .tmp/zero-rc-20261011/candidate/bin/mylang --zig "$ZIG" \
  --output .tmp/zero-rc-views-20261011/measurements-final
```

`benchmark.py` accepts the same arguments and measures five million slices (500,000 for the larger text owner),
9 alternating paired repetitions after two warmups, with counters and leak
instrumentation disabled. It pins runs to CPU 2; the host remains shared.
`boundaries.py` accepts `--compiler`, `--zig`, and `--output` and checks CLI refusals
and invalid-index traps. Compiler `check` validates ownership; `build` also checks
runtime/backend support. Both experimental ownership modes still bypass
per-function optimization caches.

The next planned stage is remaining containers: dictionaries/sets, owned unions
and recursive boxes. That expands supported coverage; it is separate from
optimizing text-view metadata or eliminating dynamic allocation altogether.
