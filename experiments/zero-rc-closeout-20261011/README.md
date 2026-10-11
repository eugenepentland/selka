# Zero-RC library and source-task closeout

This extends the opt-in zero-RC prototype on the main-derived
`codex/borrow-call-stack-20261010` branch. The closeout adds ownership-compatible
standard libraries and source-level `parallel.map`. It does not change the
default memory-management mode or merge the prototype into main.

Qualification is complete: **907 Core tests, 101 selected frontend tests and
88 whole-tree Guardian checks pass**. All 10 selected library fixtures now run
in zero-RC mode, up from 3 in the previous survey. The program matrices and
parallel stress runs also pass. The allocation tradeoff is recorded below.

## Source API

```text
import parallel

func render(value: int) -> str:
    return "item-" + str(value)

func main(out: Stream) -> int:
    const input = [1, 2, 3]
    const output = parallel.map(input, render)
    out.print(input[0], output[0])
    return 0
```

Build with `--experimental-zero-rc`. Map borrows the input until every task has
joined and returns independent owned results in input order. Callbacks take one
read-only parameter; returning borrowed managed input requires `.copy()`.
Nested maps, empty input, error enums and discarded results use the same rules.
No lifetime names or ownership annotations are needed.

The prototype does not expose detached tasks, escaping handles or closure
captures, and does not admit Unit elements. Ordinary RC builds use a sequential
implementation of the same API. Tiny callbacks are poor performance benchmarks:
this initial implementation creates capture, task and result storage per item.

## Library and compiler changes

- `.copy()` supports records, enums, options, fixed arrays and generic values.
  In zero-RC mode it duplicates owned children; scalar copies preserve the value.
  Resources and move-only values remain noncopyable.
- Strings, paths, sorting, pools, random selection/shuffling and JSON explicitly
  copy borrowed values when returning or storing independent owners. Native keyed
  sorting consumes independent source/key storage in zero-RC builds.
- Recursive list/dictionary copies use the existing finite descriptor graph and
  a runtime worklist, avoiding unbounded compiler expansion for recursive types.
- The ownership pass and LLVM emitter agree that zero-RC `str.encode()` creates
  independent bytes. The previous mismatch could destroy borrowed JSON keys;
  a dynamic-string regression now exercises both debug and optimized execution.
- Indexed writes reserve their owner while arguments are evaluated, allowing
  generated bounds reads while still rejecting overlapping mutation or moves.

Eight of the ten library fixture sources are unchanged. The pool fixture uses
an explicit copy for its independent alias and binds a handle before mutating
the pool. The random fixture explicitly copies generator state. The standard
library implementations themselves are migrated. These are selected fixture
results, not a claim that every library API is supported.

## Memory tradeoff

The migrated library fixtures all pass in zero-RC mode. This is a support and
correctness milestone, not an allocation reduction. Explicit copies increase
allocation traffic, especially for JSON's nested managed results. Eliminating
unnecessary copies at owned result/`try` boundaries is a useful next experiment.

The following release-mode comparison uses the same candidate compiler in both
modes. RC runs the original fixture sources; zero-RC runs the two adaptations
described above. Both use the migrated library implementations. Cumulative bytes
include growth; they are distinct from peak live bytes. [Raw measurements](memory.json).

| Fixture | Allocations RC → zero-RC | Cumulative managed bytes RC → zero-RC | Peak managed bytes RC → zero-RC |
| --- | ---: | ---: | ---: |
| byte_builder | 71 → 93 | 353,384 → 355,048 | 331,256 → 331,256 |
| codecs | 127 → 185 | 26,448 → 31,632 | 1,704 → 1,896 |
| integer_extrema | 0 → 0 | 0 → 0 | 0 → 0 |
| json | 446 → 2,559 | 32,032 → 173,376 | 9,792 → 8,096 |
| math | 0 → 0 | 0 → 0 | 0 → 0 |
| path | 94 → 130 | 5,856 → 8,160 | 544 → 704 |
| pool | 63 → 67 | 4,704 → 4,960 | 1,216 → 1,280 |
| sort | 23 → 42 | 1,888 → 3,200 | 352 → 576 |
| strings | 95 → 112 | 6,304 → 7,392 | 288 → 352 |
| time_random | 19 → 19 | 1,216 → 1,216 | 288 → 288 |

The task examples allocate 882 / 1,067 managed blocks and 65,200 / 80,208
cumulative managed bytes. Their sequential RC controls allocate 405 / 483 blocks
and 29,392 / 35,248 bytes. The controls have a different execution strategy and
do not establish an isolated cost for removing RC. Batching map work could
reduce the per-element scheduling storage. Task peaks vary with scheduling.

## Program validation

| Suite | Passed executions | Checks |
| --- | ---: | --- |
| Original 48-program matrix | 470 | Five pipelines; expected output, no managed leaks, no RC events, clean LLVM and symbols. |
| 10 selected library fixtures | 50 zero-RC + 10 RC controls | Five zero-RC pipelines; expected result and cleanup. Previous survey supported 3/10. |
| Two source map examples | 30 counted + 6 ThreadSanitizer + 2 sequential RC controls | Five pipelines at 1, 2 and 8 threads; separate sanitizer builds. |
| Source map repetitions | 200 counted + 200 ThreadSanitizer | 100 repetitions of each example in each configuration, at 8 threads. |
| Compile-time refusals | 7 programs | Resource escapes, foreign managed values, borrowed map results and mutable callbacks. |

That is 750 counted zero-RC executions, 206 sanitizer executions and 12 RC
controls. Every counted zero-RC run has no observed language/runtime RC and
zero live managed bytes at exit. The ABI proof independently verifies that the
count member and legacy retain/release/share implementations are absent.

The original census remains **23 allocating workloads out of 30**, with 7
allocating no memory in their measured workload. Program startup can allocate
even for those 7. This closeout extends supported programs, not the allocation
elimination count.

Reports: [regression matrix](regression.json), [library matrix](library.json),
[source task matrix](tasks.json), [stress runs](repetitions.json),
[refusals](boundaries.json), [ABI proof](abi.json).

## Evidence and reproduction

[Validation](validation.json) pins the compiler package, 699 source files,
check logs and evidence hashes. Earlier stage reports and candidate builds are
preserved. Diagnostic `probe.py` output is exploratory and is not counted as
qualification. The first closeout candidate is retained with its known JSON
cleanup failure; the qualified build is **candidate-v2**.

Use the frozen compiler at
`.tmp/zero-rc-closeout-20261011/candidate-v2/bin/mylang` and the Zig toolchain
recorded in validation. Each qualification suite accepts `--compiler`, `--zig`
and `--output`; the build-slot wrapper coordinates shared host resources:

```sh
scripts/build-slot.sh build python3 experiments/zero-rc-closeout-20261011/qualify.py \
  --compiler "$compiler" --zig "$zig" --output "$output/library" --suite library
scripts/build-slot.sh build python3 experiments/zero-rc-closeout-20261011/qualify.py \
  --compiler "$compiler" --zig "$zig" --output "$output/tasks" --suite tasks
scripts/build-slot.sh build python3 experiments/zero-rc-closeout-20261011/qualify.py \
  --compiler "$compiler" --zig "$zig" --output "$output/regression" --suite regression
python3 experiments/zero-rc-closeout-20261011/repeat.py \
  --matrix "$output/tasks" --output "$output/repetitions" --count 100
python3 experiments/zero-rc-closeout-20261011/boundaries.py \
  --compiler "$compiler" --zig "$zig" --output "$output/boundaries"
scripts/build-slot.sh build python3 experiments/zero-rc-closeout-20261011/abi.py \
  --zig "$zig" --output "$output/abi"
```

The five pipelines are release, unoptimized debug, verified release, optimized
debug and release without facts. Counted runs check expected results, no managed
leaks and no language/runtime RC events. The harness also audits emitted LLVM
and executable symbols. ThreadSanitizer runs are separate from counted runs.

Removing RC does not eliminate heap allocation or destruction. The count-free
header remains 32 bytes because of alignment. Managed counters exclude native
metadata, worker stacks, allocator bookkeeping and other raw allocations, so
they do not measure total process memory. No general runtime or compile-time
speedup is claimed by this closeout.
