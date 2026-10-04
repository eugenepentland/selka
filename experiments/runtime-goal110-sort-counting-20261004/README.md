# Counted-sort inverse gather candidate

Production commit: `2a49da2960ad76471cbf2764c068d724cb9c5121`.
**Rejected for integration by the coordinator after the bounded screen.**
The paired run found no material LLVM record-sort gain and QBE regressions.
The source and correctness evidence are retained; this version receives no
normal confirmations and does not replace integrated goal dashboard rows.
Only `src/native_collections.c` changes production behavior. The frozen ports,
contracts, key evaluation code, plain sorter, admission/refusal limits, RC
wrapper, allocation calls and request sizes remain unchanged. This evidence
uses a Debug host compiler with ordinary ReleaseFast LLVM O3/LTO and QBE
guests. A ReleaseFast host receipt and normal independent goal sessions remain
necessary before acceptance.

The isolated six-arm screen used CPU 2, the ordinary timing lock, five measured
rounds and one warmup, with unchanged size/seed/calibration rules. It completed
240 measured samples and 720 qualifications from 02:32:53 to 02:34:05 UTC.
LLVM/current-fastest medians were 2.3546/1.2514 for record sorts and
1.6870/1.0117 for integer sorts (small/large). A subsequent paired session used
the saved Debug-host production `730a86e6` control and Debug-host `2a49da29`
candidate, both ordinary backends, the screen's exact plans, randomized
within-round order, CPU 2 and the same lock. It completed 160 measured samples
and 32 warmups from 02:35:45 to 02:36:06 UTC. All guest timing ended before any
bootstrap or report replay.

| Case / size | LLVM after/before | Paired 95% interval | QBE after/before | Paired 95% interval |
|---|---:|---|---:|---|
| sort_records / small | 1.05734 | 0.98859–1.15360 | 1.08249 | 1.07939–1.09326 |
| sort_records / large | 1.01499 | 0.95240–1.07861 | 1.02335 | 1.02069–1.02893 |
| sort_int / small | 1.01658 | 1.01496–1.02369 | 0.97507 | 0.97228–0.97896 |
| sort_int / large | 0.99938 | 0.99551–1.01091 | 0.99204 | 0.98132–0.99784 |
| mutate_nested / small | 0.99836 | 0.99257–1.01425 | 0.99159 | 0.97201–0.99741 |
| mutate_nested / large | 0.98883 | 0.98045–0.99739 | 1.02492 | 1.00889–1.04002 |
| list_append / small | 1.06140 | 1.05819–1.07469 | 0.98381 | 0.98050–0.98535 |
| list_append / large | 0.98900 | 0.97983–0.99201 | 0.99659 | 0.98858–1.00012 |

The wide LLVM record-sort intervals leave the exact effect uncertain. They
support no improvement claim. Both QBE record-sort medians increased, and the
small LLVM list-append control also increased despite no source change to that
path. This may involve code layout or remaining run variability; no causal
claim is established. Five-round exploratory intervals are not independent
goal confirmations and have no multiple-comparison correction.

The first skip-build timing invocation omitted the reference reuse options
and was correctly refused as an incompatible identity before measurements.
Its log is retained. The successful invocation used the exact original build
options; no manifest, raw report or source was changed to bypass the check.

The old counted-sort path assigns a stable destination per source element,
then rotates forward with a held element and a swap temporary. Each nonclosing
cycle step transfers the whole element three times. The candidate preserves
each low 32-bit destination while writing the inverse source index into its
high 32-bit lane, compacts that lane in place, then calls the existing gather
cycle. Each nonclosing step transfers the whole element once. Counting already
requires `count <= UINT32_MAX` and `span < count`, so every index fits the lane.
Every destination is unique, every high lane is initialized, and forward
compaction reads wide element `i` before writing narrow element `i`. The
existing two-element temporary reservation remains unchanged; sorted copies
keep their original stable forward scatter.

`static-source.json` and its replay helper bind these invariants to exact
committed bytes. `static-binary.json` and its helper pin the saved baseline and
new LLVM ELF. The actual counting path writes inverse lanes and passes
`shift=32` to `keyed_permute`; its 24-byte nonclosing gather contains one full
element transfer. The listed keyed-sort symbols occupy 8,271 baseline bytes
and 7,126 candidate bytes; collections `.text` occupies 292,002 and 290,866
bytes respectively. These are static observations, with different host
compiler modes recorded, and do not establish a runtime speedup.

The new native test links the production runtime normally and wraps only host
scratch `malloc`/`calloc`/`free` while sorting. It checks 1,610 stable cases over
13 element widths (including zero and widths larger than the inline temporary),
both directions, both in-place and sorted-copy paths, integer key widths and
extrema, floating-point adjacent words, signed-zero ties and distinct NaN ties.
An independent stable insertion oracle compares every output byte. All 46,234
permutations through eight positions include fixed points, disjoint cycles,
long cycles and prefetch cursor boundaries. Exact scratch request sizes prove
the counting path ran. Six failure cases refuse every actual scratch request
across large-element/narrow-key in-place and sorted-copy paths, checking
unchanged input/header/output and zero remaining scratch. RC tests retain text
payloads across counted sorts and sorted copies, check owners/header/heap
accounting, and release everything afterward.

Validation completed on this source:

- All 32 native memory suites passed with UBSan.
- Three focused native suites passed optimized UBSan; counting and production
  RC collection suites passed optimized ASan/UBSan.
- The test-input coverage check and input manifest self-test passed.
- All 24 official expanded executables built. All 720 frozen qualification
  cells and 516 additional six-arm correctness holdouts passed, with elapsed
  values discarded and independently replayed from their oracle reports.
- The production commit and official Debug compiler build each passed all 88
  Guardian checks. Existing report-only findings remained nonblocking.

`validation-receipt.json` records exact source/compiler/manifest/binary hashes,
coverage and evidence hashes. Gzip files preserve exact raw bytes and hashes;
the original ignored live manifests and binaries remain available for artifact
replay. This receipt supports the coordinator's review; it is not the final
goal110 `checks-v1` attestation or an acceptance report. Full repository gates
and unseen semantic shapes are not claimed by the bounded checks here.

From this worktree, the executed official commands were:

```bash
scripts/build-slot.sh build env MYLANG_JOBS=2 python3 scripts/test_native_memory.py
python3 benchmarks/runtime/build_compiler.py \
  --source-revision 2a49da2960ad76471cbf2764c068d724cb9c5121 \
  --optimize Debug --work .mylang-cache/goal110-sort-debug \
  --output .mylang-cache/goal110-sort-debug/compiler-receipt.json
python3 benchmarks/runtime/expanded/run.py \
  --candidate-id goal110-sort-2a49da29-debughost-20261004 \
  --compiler-receipt .mylang-cache/goal110-sort-debug/compiler-receipt.json \
  --work .mylang-cache/goal110-sort-debug/runner --build-only \
  --reuse-reference-manifest /home/epentland/ai/canopy/mylang-worktrees/runtime-parity-harness-20261003/.mylang-cache/runtime-candidate-730a86e6-releasefast/runner/manifest.json \
  --expected-reference-manifest-sha256 94ea9f6343133da2fefdcb327458fbb5fcf6d7f099ba29385ebb5b0bd430d721
python3 experiments/runtime-goal110-sort-counting-20261004/qualify.py \
  --manifest .mylang-cache/goal110-sort-debug/runner/manifest.json \
  --output .mylang-cache/goal110-sort-review/qualification.json --cpu 4
python3 benchmarks/runtime/diagnostics/holdouts.py \
  --manifest .mylang-cache/goal110-sort-debug/runner/manifest.json \
  --output .mylang-cache/goal110-sort-review/holdouts.json --cpu 4
```

Replay the existing ignored reports and pinned static evidence without builds:

```bash
python3 experiments/runtime-goal110-sort-counting-20261004/qualify.py \
  --verify .mylang-cache/goal110-sort-review/qualification.json
python3 benchmarks/runtime/diagnostics/holdouts.py \
  --verify .mylang-cache/goal110-sort-review/holdouts.json
python3 experiments/runtime-goal110-sort-counting-20261004/static-source.py
python3 experiments/runtime-goal110-sort-counting-20261004/static-binary.py
```

Archive replay can decompress qualification/holdouts into temporary paths.
Live compiler/asset/source verification still requires the original receipt
paths or an explicit verified relocation; archived hashes prove preservation
of recorded bytes, independently replayed oracle rows prove their contents,
and neither substitutes for an actual new execution.
