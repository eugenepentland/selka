# Cache Wave 2 qualification

This work integrates the Selka cache planner from `c3107e4cf` with `main` at
`e9011d9c6513f63ae02881d0cfc8258c668e6b5e`, then implements the second wave of
`docs/audits/selka-toolchain-cache-plan-2026-10-10.md`.

## Integration baseline

The integration preserves main's packed stage storage, deferred Core lowering,
recursive test replay, allocation-warning replay, live-source formatting gate,
and embedded-source migration checks. The conflict resolutions retain the
planner binding before all replay paths and adapt to main's report-plus-warnings
replay result. The qualified integration is merge commit `ed76d2a9c`.

An added regression compares exact warning bytes across cold file execution,
file replay, directory replay, forced directory execution, and a change to only
the planner artifact. The focused regression passed. The first full gate found
an embedded receipt test still passing the replay struct to the JSON parser;
the assertion now reads its `report` field. The corrected full gate passed:
83/83 steps, 2,512 executed Zig tests, 2,233 shard skips, all guest language,
value-semantics and ported suites in Debug and Release, and all 88 Guardian
checks. The merge commit hook also passed all 88 whole-tree Guardian checks.

The command was `zig build test fmt-check -j2 -Dcore-shards=2 -Dtest-shards=2
--maxrss 8589934592 --summary all`, through `scripts/build-slot.sh gate` with
the pinned toolchain. After a ten-minute queue and confirming about 19 GiB
available memory and low load, this run used `MYLANG_GATE_SLOTS=2` to admit a
second gate; the other worktree was not interrupted. The reduced shard count
made the run slow. Full output: `wave1-main-full-gate-final.log` in the local
validation directory.

Builds use the repository's existing pinned Zig, per-worktree caches, on-disk
temporary files, and the shared build/gate admission slots. The ReleaseFast
integration baseline is installed separately under
`.mylang-cache/cache-wave2-validation/baseline/` before Wave 2 changes.

The exact baseline install passed 12/12 build steps and 88/88 diff-scoped
Guardian checks (`baseline-build-qualified.log`). SHA-256 identities:

- Host: `079ee95624c5a2ff0eabd83ebaad590e7ab8e70e4b20d8eba6c939e097c4cce1`.
- Cache planner: `f3f8876939b2e02c4fc0c06faba035251766237b11975ba737056f685184ee4b`.

## Reproducible workloads

`qualify.py` retains command lines, JSON reports, stderr, GNU time output, keys,
and normalized verdicts for an edit/revert matrix with independent forced
execution. Shadow mode additionally requires an independent eager-lowering key
oracle inside the same invocation, avoiding differences in planner/environment
identity between separately configured runs.

`benchmark.py` uses source-only copies of current-syntax EDA and Lox directory
workloads. It also generates exactly 191,416 and 510,436 physical lines of
reachable private call chains: 31,985/85,293 functions and 248/662 test roots,
respectively, with chains capped at 256 functions. Each module has two
overlapping roots; a same-line edit at the head leaves the tail root unaffected.
This exercises within-module key reuse as well as whole-report directory reuse.
Each batch remains small; the separate 100,000-node component qualification
checks large individual graphs. These synthetic workloads
are distinct from the existing EDA replicas of those sizes, which have no
`test_*` roots. The original external checkouts remain untouched.

Baseline and candidate use the same source paths and separate compiler/native
caches. Each measured edit uses a new value; edited outputs are never prewarmed
or copied from another variant. Corpus edits insert a line and therefore include source-position invalidation;
synthetic edits preserve lines. Zlib is the production storage policy; raw
storage is a diagnostic comparison. The existing conservative environment
identity includes the compression setting, so cross-encoding verdicts agree
while keys are compared to their same-identity shadow oracle. GNU time peak RSS is the largest individual
process RSS, not a sum over concurrently running processes. Cache-size walks
are outside the timed commands.

Initial harness smoke checks passed 36 qualification invocations and 27 tiny
benchmark invocations using the integration baseline. Those runs establish
harness behavior only; they are not Wave 2 correctness or performance evidence.

The extended integration-baseline qualification then passed 123 matrix
invocations in shadow mode, nine nonempty allocation-warning comparisons, and
two deterministic concurrent-edit trials. Signature/default argument, record
layout, declared and actual effects, embedded bytes, recursive cycle creation
and splitting, generated-parameter invariants, and providers are included.
Concurrent edits returned `SourceChanged`, printed no success report, and
published no success receipt or manifest; each subsequent failing revision
matched forced execution. Metadata corruption was explicitly disabled because
this baseline has no Wave 2 metadata. Evidence lives under
`.mylang-cache/cache-wave2-validation/extended-baseline-qualification-final/`.

## Results

The implementation persists canonical pre-pass function digests and complete
call/reference edges using validated deferred-lowering receipts. Stable logical
identities are remapped into each current discovery revision; ambiguous facts
fall back to complete lowering. Graph generations retain forward/reverse edges,
recursive groups and exact test-key candidates. The version-two Selka component
approves reuse through reverse propagation and preserves the existing ordered
root and sorted non-root hash contribution. Cached recursive groups are checked
for connectivity in both directions and an acyclic quotient before reuse.

The final Debug/raw and ReleaseFast/zlib shadow matrices each passed 99 CLI
invocations: 86 main edit/corruption/forced comparisons, four selected private-edit
checks, six nonempty warning comparisons and three concurrent-edit checks.
Corrupting 65 metadata files and removing the complete test-key metadata directory
both recovered the original keys without admitting a stale passing result.
The combined three-test closure recomputed one function's facts, reused seven,
restored zero raw bodies, executed two affected tests and reused the unaffected
test's exact original key. Earlier source-movement qualification deliberately
inserted a line and invalidated all six facts of that selected closure;
source-position and catalog proofs remain conservative.

The ReleaseFast candidate host SHA-256 is
`92dd45fc92a79bca7eb2f273ec9ffdf6cac454526302b521b5bf33b88e0bc8c6`;
its cache-plan v2 component is
`ae849b2a65b47130b80d03cf2e7575572934c66179a5232e2d81e766bd635e78`.
`qualification-summary.json` retains exact identities and representative work
counters; full local evidence is in `wave2-debug-raw-final/` and
`wave2-release-zlib-final/` under the validation directory.

Focused qualification passed 32 incremental protocol/reference tests and 25
producer/graph tests. The latter includes an exhaustive allocation-failure
sweep of graph publication. Review caught and fixed partial-publication
allocation cleanup, eager-lowering work undercounting, and counting unsuccessful
cache writes as completed writes. It also identified coherently malformed
recursive-group indexes; actual native-component regressions cover recovery
from merged unrelated groups and split cycles.

Native component qualification also passed 408 version-two cold/retained/warm
batches, recovery from three coherent invalid recursive-group partitions, 13
malformed version-two frames, 102 legacy graph cases and 21 malformed legacy
frames. A 100,000-node retained chain required zero closure work when every key
was reusable; index admission remained linear (700,000 node and 599,994 edge
visits). Those work counts are qualification, not end-to-end speed measurements.

The final full gate passed 104/104 steps, 2,543 executed Zig tests and 23,246
shard skips, all guest suites, formatting and component qualification, and all
88 Guardian checks. It used `zig build test fmt-check -j6 --maxrss 8589934592
--summary all` through the gate admission wrapper. Paired measurements follow.

The full gate exposed an existing packed-stage catalog slowdown after repeated
compiler generations in its disposable unit-test cache. `stage_pack.scanPack`
rejects foreign-identity packs before reading their records, but repeated
refreshes reopen those headers. After proving the running compiler's store
identity, 2,571 packs from exactly two rejected older identities were moved to
a separate qualification archive. Current packs, journals and sequence were
untouched; the gate then completed. This was qualification-cache maintenance,
not a production cache change or benchmark preparation. The measured variants
start with separate empty caches. General stage-store generation partitioning
and catalog compaction remain follow-ups.

## Paired measurements

All 318 benchmark/oracle invocations passed: 138 EDA/Lox invocations,
69 at each synthetic size, and 42 independent-addition checks. Runs used the
same ReleaseFast artifacts, CPUs 2 and 10 and four directory workers. Gate
locks prevented overlapping full gates. Cold and immediate no-op entries have
one sample; edit entries are medians of three fresh values. These small samples
describe this machine and fixture, not a statistical latency guarantee.

`benchmark-summary.json` preserves every phase, sample values, process CPU/RSS,
work counters, retained bytes/files and source/result identities. Raw stdout,
stderr and timing files remain in the local validation directories. The figures
below are command wall times; gate-lock occupancy was not separately measured.

| Workload | Edit | Baseline s | Wave 2 zlib s | Wave 2 raw s | Peak RSS MiB, baseline → zlib |
| --- | --- | ---: | ---: | ---: | ---: |
| EDA (310 tests) | private | 1.561 | 1.606 | 1.595 | 247.1 → 246.9 |
| EDA (310 tests) | helper | 0.574 | 0.638 | 0.638 | 146.0 → 118.7 |
| EDA (310 tests) | three-file | 1.829 | 1.924 | 1.885 | 249.5 → 255.4 |
| Lox (65 tests) | private | 0.414 | 0.437 | 0.472 | 88.1 → 86.5 |
| Lox (65 tests) | helper | 0.415 | 0.421 | 0.423 | 98.1 → 99.3 |
| Lox (65 tests) | three-file | 0.660 | 0.675 | 0.666 | 100.6 → 98.6 |
| 191k synthetic (248 tests) | private | 0.150 | 0.171 | 0.174 | 58.1 → 58.1 |
| 191k synthetic (248 tests) | helper | 3.484 | 4.426 | 4.341 | 266.5 → 267.0 |
| 191k synthetic (248 tests) | three-file | 3.528 | 4.502 | 4.415 | 269.2 → 268.6 |
| 510k synthetic (662 tests) | private | 0.287 | 0.341 | 0.325 | 58.1 → 58.1 |
| 510k synthetic (662 tests) | helper | 12.528 | 17.458 | 17.262 | 661.4 → 661.4 |
| 510k synthetic (662 tests) | three-file | 12.432 | 17.061 | 17.237 | 661.4 → 661.5 |

| Workload | Cold seconds, baseline → zlib | Immediate no-op seconds, baseline → zlib |
| --- | ---: | ---: |
| EDA (310 tests) | 19.066 → 19.411 | 0.131 → 0.140 |
| Lox (65 tests) | 9.976 → 10.013 | 0.050 → 0.040 |
| 191k synthetic (248 tests) | 17.808 → 19.349 | 0.083 → 0.111 |
| 510k synthetic (662 tests) | 36.504 → 43.175 | 0.226 → 0.273 |

**This wave is not an end-to-end speed improvement on these workloads.**
Zlib edit medians are about 1–39% slower; a few measurements differ by only
milliseconds and need more sampling before interpreting small differences.
Reverting the shared-helper edit costs 1.273 → 2.171 seconds at 191k lines
and 6.376 → 11.334 seconds at 510k even though every test verdict is cached.
Peak memory is mostly unchanged; the populated EDA helper case drops from
146.0 to 118.7 MiB. Raw storage does not remove the large-workload regression.

For the 510k helper sample zero, process-tree CPU rises from 22.41 to 31.64
seconds. Candidate per-group intervals sum to 18.22 seconds in cached lowering
setup and 14.02 in planner calls, versus 0.93 in fact admission and 0.007 in final
key hashing. Those overlapping wall intervals are diagnostic attribution, not
isolated CPU measurements. Profile lowering setup, repeated catalog proofs and
component invocation before optimizing digest hashing further.

The large private-edit cases plan one test and reuse the other test key inside
the edited module. Sample zero conservatively computes all 259 facts after the
discovery transition; subsequent samples compute one and reuse 258, with zero
raw-body restores. Shared-helper edits at 191k compute 124 facts and reuse
31,984; at 510k they compute 331 and reuse 85,292. These are per-root counts:
the shared function has a separately validated contribution in each root.
All affected helper tests still replan and execute, as required.

Independent additions preserve every existing cold key: one new test executes
beside 248/662 cached tests. Both sizes perform the same key work: two fresh
facts on the first addition, then one fresh and one reused, one planned test
and zero raw-body restores. Candidate zlib medians are 0.133/0.301 seconds
versus baseline 0.119/0.257; directory validation remains size-dependent.

New guest object counts match the baseline in every compared edit. For the
large private edit they are two on the first transition and one thereafter;
the helper edit retains 124/331 new objects. This wave changes test-key
derivation, not native unit granularity or linker ownership.

| Workload | Baseline cache MiB, cold → end | Zlib cache MiB, cold → end | Raw cache MiB, cold → end |
| --- | ---: | ---: | ---: |
| EDA (310 tests) | 121.8 → 288.6 | 128.4 → 313.7 | 138.6 → 351.5 |
| Lox (65 tests) | 58.9 → 100.9 | 60.2 → 104.9 | 62.0 → 110.7 |
| 191k synthetic (248 tests) | 109.0 → 367.6 | 134.6 → 395.5 | 156.8 → 418.3 |
| 510k synthetic (662 tests) | 213.7 → 900.0 | 282.1 → 973.6 | 341.2 → 1034.0 |

These are complete isolated variant caches, including compiler, native and Zig
cache data, measured before the separate addition matrix. They are not the size
of Wave 2 metadata alone. The final 510k variant contains 21,329 baseline files
versus 25,969 candidate files. Retention/compaction remains a separate concern.

Next priority: reduce total admitted server work and lock-held seconds. Cache
and select full verification actions before admission, revalidate queued input
snapshots, and narrow resource holds while preserving benchmark isolation.
Wave 2 supplies sound facts and keys for that work; the current measurements
do not justify claiming faster gates or rolling it out as a performance win.

### Measurement boundaries

`cache.work` is current-invocation work once per provider group; whole-report
replay does not repeat historical counters. Fresh/reused fact and body counts
describe the production path, not the extra independent shadow oracle. Total
wall time includes that oracle when enabled. The `fallback` fact counter counts
internal fact misses plus complete-fallback events; it is not a count of tests.
Packed storage statistics cover the test-key stores, excluding journal reads,
ordinary metadata and other frontend/native stores. Per-group wall intervals can
overlap during directory execution and are not process CPU totals. Total
bytes hashed, isolated key-derivation CPU time and linker-only time are not yet
instrumented. GNU time provides process-tree CPU totals and maximum individual
process RSS; native-object deltas count newly retained `.o` files. Benchmark records also
split guest `units-v1` objects from fixed runtime objects; these count retained
outputs rather than compiler process invocations.

The runner still validates the complete discovered graph and sends one complete
bounded batch per provider group. Persisted exact keys avoid unaffected closure
derivation; arbitrary closure vectors are not persisted between invocations.
Packed test-key stores are namespaced by canonical source path so each directory
root indexes its own facts. Reopening a single directory-wide store per root
would repeatedly index every other root's records. Provider groups for one source
share its store; cross-root producer sharing is left for a measured follow-up.
Graph chunks contain at most 256 records, with a global million-edge bound;
an individual high-degree row can be large. Producer edge lists are split into
512-edge chunks. Neither scheme promises a lookup reads only its own bytes.
Global semantic validation, current conservative source/type proofs, and
existing native module boundaries remain in force.

### First edit and populated discovery scopes

Directory replay changes the set of files in the shared checked program. The
existing lowering receipt hashes the complete ordered declaration catalog and
source origins, and deferred raw receipts also bind the IR layout. The first
transition from the cold full-directory discovery to a smaller affected subset
therefore misses otherwise unchanged raw/fact records. A later fresh edit of
the same subset can reuse them; no edited output or edited key is prewarmed.
The measurements retain sample zero separately from the medians and subsequent
samples so this admission cost is visible.

For example, EDA's first private edit lowered 3,087 internal functions afresh
and reused none; the next two fresh private edits lowered 17 and reused 3,070.
The shared-helper edit similarly changed from 3,446 fresh internal functions to
one fresh and 3,445 reused. Canonical fact counts also include external/runtime
declarations: 517 fresh private-edit facts include 500 such declarations, not
517 freshly lowered internal bodies. Source-line insertion creates additional
legitimate location-sensitive misses. Narrower directory discovery proofs and
stable cross-root source identities need separate qualification before removing
these costs.
