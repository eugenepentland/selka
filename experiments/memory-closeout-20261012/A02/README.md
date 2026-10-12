# A02 capacity and allocation boundaries

The production change checks allocation arithmetic before allocating, rounding,
or copying. The existing eight-slot initial list growth and doubling policies
are retained. Smaller initial capacities help singleton trees but substantially
increase work for short lists with several elements. No shrinking on return,
new implicit copy, or ownership fallback was introduced.

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (C0).
Safety implementation: `ac4e945c5`.

## Allocation-size correctness

The C0 native boundary probes exposed three failures:

| Request | C0 result | Fixed result |
| --- | --- | --- |
| `list_new_slow(2^61, 8)` | Product wraps; succeeds with capacity zero | Existing out-of-memory exit |
| Payload `SIZE_MAX - 31` | Header addition wraps; SIGSEGV | Existing out-of-memory exit |
| Full list with capacity `INT64_MAX` | Signed doubling overflows; invalid-free abort | Existing out-of-memory exit |

These are native runtime ABI probes, not a claim that ordinary source can
materialize an exabyte list. The guards also cover negative arguments,
alignment rounding, terminated storage, and byte-buffer reallocation. Unit
elements with size zero remain valid. The existing test memory-budget error
is preserved.

The registered `A02 capacity` Core test passed 22 native executions: an ordinary
growth/snapshot/cleanup scenario and ten boundary scenarios in each of the
zero-RC and legacy control runtimes. A07 reviewed and approved the guards. The
commit's precommit Guardian gate passed all 88 checks. See
[validation](safety-validation.json), [source hashes](safety-source-sha256.json),
and [C0 failure records](overflow-before.json). The final integrated compiler
must rerun this registered test and the full verification coordinator.

## Controlled policy comparison

`capacity.py` reconstructs the exact C0 runtime from Git and applies small
in-memory experimental changes. Every variant is compiled with the same pinned
Zig, zero-RC ABI, fixture, optimization, and runtime instrumentation. Production
counter insertion anchors are used with exact-once checks. Separate plain
binaries supply timings and RSS. Symbol audits reject retain/release/share
helpers. These experiments compare runtime policies; they are not final compiler
qualification or compiler-only speedup claims.

The retained-small-list model keeps sixty lists of 24-byte elements live at
once, as the nested JSON workload keeps its per-level list owners live. It
does not run the parser or recursive ownership lowering. A03's distinct
`owned-payload/json_nested` guest case supplies the actual 60-level JSON × 1,000
C0/final reproduction, with expected output `121000`.

| Workload | Initial/growth policy | Final length/capacity | Allocations | Reallocations | Cumulative allocated bytes | Peak managed bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 60 singleton lists × 20,000 | Current 8 / 2× | 60 / 480 total | 2,400,000 | 0 | 307,200,000 | 13,472 |
| Same | Start 1 / 2× | 60 / 60 total | 2,400,000 | 0 | 115,200,000 | 3,872 |
| Same | Start 4 / 2× | 60 / 240 total | 2,400,000 | 0 | 192,000,000 | 7,712 |
| 60 five-element lists × 20,000 | Current | 300 / 480 total | 2,400,000 | 0 | 307,200,000 | 13,472 |
| Same | Start 1 | 300 / 480 total | 6,000,000 | 0 | 652,800,000 | 13,568 |
| Same | Start 4 | 300 / 480 total | 3,600,000 | 0 | 460,800,000 | 13,568 |
| Million-element append × 20 | Current | 1,000,000 / 1,048,576 | 120 | 260 | 167,799,376 | 8,392,696 |
| Same | Start 1 | 1,000,000 / 1,048,576 | 140 | 260 | 167,800,656 | 8,392,696 |
| Same | 1.5× growth | 1,000,000 / 1,215,486 | 180 | 440 | 194,535,712 | 9,727,992 |
| Clear/reuse million-element list × 20 | Current | 1,000,000 / 1,048,576 | 6 | 13 | 8,393,784 | 8,392,664 |
| Repeated three-element replacement × 1,000,000 | Current | 3 / 8 | 2,000,000 | 0 | 128,000,000 | 128 |
| Same | Start 1 | 3 / 4 | 2,000,000 | 0 | 96,000,000 | 96 |
| Million-byte buffer + independent snapshot × 20 | Current | 1,000,001 / 1,048,576 | 200 | 200 | 41,007,424 | 2,056,112 |
| Same, existing reserve hint | Current | 1,000,001 / 1,048,576 | 80 | 0 | 40,982,464 | 2,056,112 |

Cumulative bytes are allocation bytes plus reallocation growth. Peak is measured
live managed storage, never subtracted or treated as traffic. All 28 counted
variant/workload executions preserved their expected checksums, recorded zero
runtime RC events, and ended with zero managed bytes live. Native allocator
chunks, process infrastructure, and counter metadata are not fully represented
by managed peak. The native fixture explicitly frees its list models and checks
the runtime live-block count as well.

**Decision:** retain the current policy. Starting with one slot reduces singleton
retained storage, but five-element lists require 2.5× as many allocations and
2.125× the allocation traffic with no peak reduction. Starting with four has
the same tradeoff at a smaller magnitude. The 1.5× policy adds reallocations and
does not guarantee a smaller final capacity at a particular length. Existing
reserve hints avoid the repeated byte-buffer growth when a final size is known.
This is a rejected performance experiment, not a claimed production saving.

## Runtime and RSS limits

The first admitted window selected allowed CPU 0, used two warmup groups and
nine alternating measured groups, and completed singleton, append, and reuse
cases before being stopped to release the build queue. Its baseline singleton
range was 39.5–763.8 ms. The four policies' broad overlapping ranges do not
support speedup or slowdown conclusions. A09 observed heavy load on CPU 0's
sibling. The shared build-slot budget changed during this window, so the old
one-slot wrapper is also a stated isolation limitation.

A second window on CPU 10, with the fresh two-slot environment, completed all
nine samples of the five-element case for all four policies in 27 seconds.
It was still noisy: current-policy range 65.1–1,136.2 ms, start-one range
90.0–1,650.3 ms. The counted matrix overlapped the first 0.5 seconds of the first
warmup; the timing binaries themselves were uninstrumented. No ratio is used
to justify the decision.

A09 subsequently reported that Guardian commit `4a700cb52` finished at
00:46:58 UTC, inside that 00:46:43–00:47:10 window. The hook's admission was
not established in the retained metadata; possible interference is therefore
an additional limitation, without changing the no-speedup conclusion.

Raw RSS is GNU `time` maximum RSS for each native process, in KiB; it excludes
compilation and child-process build memory. These small-list variants retain
the allocator's 64-KiB chunk and showed similar roughly 1.9–2.1-MiB process RSS
in the preliminary singleton samples despite different managed peaks. That is
not evidence for an RSS saving. All samples, ranges, artifact hashes, complete
allocation counters, and exact commands are retained under [raw](raw/).
The [capacity archive](capacity-archive.json) pins all 60 raw files, verifies
the available 16 plain/counted binary identities and reconstructs their runtime
source hashes from C0 plus the recorded policy. Historical build-time harness
hashes are preserved separately from the later checkpoint-enabled harness;
their exact earlier Python source was not separately archived.

Runtime/RSS completion for the remaining native cases and final guest-path
requalification belong to the coordinated A09 schedule; no C0 native timing
is relabeled as a final compiler measurement.

## Reproduction

Source the shared development environment in this worktree. The harness defaults
to the pinned C0 revision; an explicit `--revision` selects another committed
runtime. Use a new output directory instead of overwriting evidence.

```sh
scripts/build-slot.sh build python3 -B experiments/memory-closeout-20261012/A02/capacity.py build --output .tmp/memory-closeout/A02/reproduce
python3 -B experiments/memory-closeout-20261012/A02/capacity.py measure --output .tmp/memory-closeout/A02/reproduce
scripts/build-slot.sh timing python3 -B experiments/memory-closeout-20261012/A02/capacity.py timing --output .tmp/memory-closeout/A02/reproduce --cpu 10 --cases nested5
scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter='A02 capacity' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Choose an allowed, measured CPU on the actual machine. Finish counting runs
before requesting timing admission. Timing windows may select one case at a
time to avoid holding up independent compiler work.

## Managed list mutation follow-up

`insert`, `reverse`, indexed `pop`, and `remove` now operate on zero-RC lists of managed children. Insert appends the new owner and rotates it into place; indexed removal rotates the selected owner to the final slot and uses the existing pop transfer/destruction path. Reverse swaps slots. The consuming runtime helpers preserve the list header, capacity, layout descriptor and every child owner, with bounded byte scratch and no allocation or deep copies. Ordinary RC lowering is unchanged at this stage. A07 reviewed the complete helper and lowering path.

The registered `A02 list methods` test passes release, unoptimized debug, verified release, optimized debug, and release without facts. Every mode checks 100 nested-list, wide-record and recursive-union trials (output `500`), independent snapshots, clamped insertion, discarded pop, removed-child cleanup and four failure paths. Counted runs have zero exit-live bytes, clean RC symbols/LLVM, and exact indexed-pop error metadata for -3/2, 2/2 and 0/0. `remove` of a missing element reports `R_LIST_VALUE`. Exact compiler, source, binary and LLVM hashes and complete counter/trap results are in `raw/list-methods/`. No runtime-speed or RSS claim is made for this API completion.

The test uses a read-only equality helper for nested comparisons: direct nested-list equality followed by mutation currently produces an unrelated ownership phi retain. A07 received the full IR reproducer at `.tmp/memory-closeout/A02/list-methods-ir.txt`; this remains a separate support issue, not a passed general equality claim.
