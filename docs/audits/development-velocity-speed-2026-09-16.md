# Compilation and test speed baseline — 2026-09-16

## Main results

The ReleaseFast host compiler checks the ordinary 10k-line fixture without
caching in **59 ms**, versus **616 ms** with the Debug host compiler. This is
the clearest immediately available speed improvement in the measured setup.

Caching still has substantial overhead. The same ReleaseFast 10k fixture takes
**2.17 seconds to check and populate an empty cache**, and **127 ms after a
private edit**, even though only two bodies are checked. At 100k lines, a private
edit takes **1.06 seconds** and checks every body because retention is bypassed.

The 10k native test takes **109 seconds on its first build**, **294 ms for an
unchanged cached result**, and **1.18 seconds after a helper edit**. On a separate
fixed source tree, selecting 32 cached tests takes **1.81 seconds**, with no test
executions. Repeated preparation remains a measurable cost.

These measurements cover the current code snapshot. They do not establish the
before/after effect of the C1R/C2/P1 implementation commits.

## Provenance and method

- Source checkout: `a1b48b3c` on `codex/velocity-integration`. Changes after code
  gate `88691e7b` are documentation only.
- Executables: pinned copies of the existing `final-release` and `final-debug`
  cold-gate worktree installations at `88691e7b3c5d6dea0a05e82ffadb375bd865981f`.
  No compiler rebuild or Guardian gate was part of this measurement run.
- Release compiler identity:
  `5e12ed92e4e4a43a8c45ca09ad1f5c431170c0f8499220a74c18a26f61044918`.
- Debug compiler identity:
  `3c2bb209b69eb9829ead395093f08bd8a8034f3efdef93d410ab5b3fc03c7110`.
- Machine: Intel i7-12700H, 20 logical CPUs, 30 GiB RAM, Linux x86_64. This is a
  shared machine. Commands ran sequentially; compiler build modes were measured
  in separate batches. These are local baselines rather than an isolated-machine
  release qualification.
- Reused `scripts/profile_large_project.py` for generators, process measurement,
  work-report parsing, and nearest-rank percentiles. Source fixtures and caches
  are in an independent scratch directory recorded in the JSON.
- Time includes process startup through exit. Check runs request `--report`;
  native tests request `--json`; direct native builds request `--report`.
- Checks: five no-cache samples, three empty-cache samples, five unchanged
  samples, and 20 unique private edits after warm-up. An unchanged check can
  reuse a whole-project verdict; it is not evidence that bodies were relocated.
- Native 10k tests: one first-build sample, 20 unchanged samples, five forced
  runs, and 20 helper edits. Prototype builds: one first-build sample and five
  unchanged/edit samples. Test-count comparisons: five samples per count.
- The host compiler is ReleaseFast except for the explicit Debug comparison.
  Native guest builds use Debug mode, matching the development workflow.
- “Cold” means an empty **mylang** cache. OS page caches, Zig's global cache, and
  installed runtime archives remain available. First native builds are single
  observations and have no useful latency distribution.
- RSS is direct-child `wait4` peak memory. Native build descendants are excluded,
  and the harness's fork/exec overhead is included; it is not whole-system memory.

All recorded timed commands exited successfully. There are 198 meaningful check
samples, 20 excluded control samples described below, and 73 native samples.

## Check latency

All values are milliseconds. Latency columns are medians; edit p95 uses 20 samples.

| Workload | Source lines / files | Fresh `--no-cache` | Empty-cache check | Unchanged check | Private edit | Edit p95 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Ordinary 10k | 9,935 / 66 | 59.4 | 2,172.4 | 17.5 | 126.8 | 181.9 |
| Ordinary 100k | 100,943 / 66 | 943.6 | 1,164.9 | 101.0 | 1,058.2 | 1,527.1 |
| Managed/generic 10k | 10,022 / 68 | 81.4 | 1,835.4 | 12.7 | 218.5 | 230.3 |
| Self-host prototype entry | 720 / 3 in directory | 4.6 | 6.8 | 2.4 | 9.9 | 12.7 |
| Maintained schematic | 2,186 / 14 in directory | 24.3 | 47.7 | 5.3 | 21.1 | 42.0 |

Directory source inventories include files that an entry may not import and
exclude bundled standard-library source. Body counters below describe the
actual checked graph.

### Work performed after edits

| Workload | Bodies checked | Bodies reused | Specializations instantiated |
| --- | ---: | ---: | ---: |
| Ordinary 10k | 2 | 3,137 | 0 |
| Ordinary 100k | 33,475 | 0 | 0 |
| Managed/generic 10k | 194 | 2,562 | 128 |
| Self-host prototype | 3 | 19 | 0 |
| Schematic | 1 | 114 | 0 |

Ordinary/managed fixtures change one helper body with a unique literal per
sample. The prototype edit changes the `line_count` literal in the compiled
`bench.my` entry. The schematic edit adds a private helper in a reachable module.

The maintained harness originally selected the prototype directory's largest
file, `parser.my`, which `bench.my` does not import. Its approximately 2.4 ms
result was an irrelevant-edit control. Those samples remain in the raw data as
`unreachable_file_edit_control`; the table uses the corrected 20 entry-body edits.

The 100k result is consistent with the 16 MiB all-or-nothing semantic retention
policy in `src/main.zig:1796` and `src/semantic_cache.zig:442`. No ordinary bodies
reuse at that size. Its edit p95 remains above the plan's 500 ms objective.

The 10k cache population results are consistent with the full-directory scan
after every publication identified in the C2/P1 review. Reusing bodies also costs
more than checking these small synthetic bodies from scratch, so improvements
must be judged by wall time as well as reuse counters. Cache loading, remapping,
and global passes are further profiling targets; this run does not apportion
their individual costs.

### Host compiler build mode

Same ordinary 10k source and workload recipes:

| State | ReleaseFast host | Debug host | Observed ratio |
| --- | ---: | ---: | ---: |
| Fresh no-cache check | 59.4 ms | 616.3 ms | 10.4× |
| Empty-cache check | 2.17 s | 45.12 s | 20.8× |
| Unchanged check | 17.5 ms | 102.8 ms | 5.9× |
| Private edit | 126.8 ms | 1,198.6 ms | 9.5× |

## Native compilation and tests

| Workload/state | Median | p95 | Samples | Work |
| --- | ---: | ---: | ---: | --- |
| Ordinary 10k: first native test | 109.20 s | — | 1 | Compile/build/run one test |
| Ordinary 10k: unchanged test | 294.3 ms | 425.8 ms | 20 | 0 executed, 1 cached |
| Ordinary 10k: forced test | 896.5 ms | — | 5 | 1 executed |
| Ordinary 10k: helper edit + test | 1,176.3 ms | 1,778.7 ms | 20 | 1 executed |
| Prototype: first executable build | 1,063.4 ms | — | 1 | 22 compiled, 0 reused functions |
| Prototype: unchanged executable build | 133.6 ms | — | 5 | 0 compiled, 22 reused functions |
| Prototype: main-body edit + build | 190.2 ms | — | 5 | 1 compiled, 21 reused functions |

The prototype's first build used the installed runtime archive. Its codegen
phase took approximately 989 ms, frontend 24 ms, and link 40 ms. Native object
reuse is working, but unchanged builds still perform frontend and link work.

The ordinary test receipt names 50 dependency functions, while preparation and
native compilation process the entire project. C4's lazy lowering/build scope
addresses this distinction. This measurement does not predict the eventual
speedup.

### Cached-test count scaling

The same source tree contains 32 tests; only the filter changes. Every measured
case already has a valid receipt, and no tests execute.

| Selected cached tests | Median | Samples |
| ---: | ---: | ---: |
| 1 | 47.5 ms | 5 |
| 8 | 378.6 ms | 5 |
| 32 | 1,811.6 ms | 5 |

This quantifies the per-case preparation regression identified as R2. Shared
preparation per provider graph should be restored before adding more caching
layers. R1's whole-snapshot receipt invalidation also still requires correction.

## Recommended performance order

1. **Use the optimized host compiler for routine language checks and builds.**
   Keep compiler Debug validation in its appropriate correctness workflow. The
   measured ReleaseFast executable came from a cold verified installation; the
   known warm compiler-build invalidation issue still needs repair.
2. **Fix C2 cache overhead.** Amortize publication/eviction scans; profile load
   and remapping costs against the no-cache baseline. Fix the retention policy
   that disables all body reuse at 100k. Merely raising the limit before fixing
   publication could expose a much larger quadratic workload.
3. **Restore shared test preparation and selective receipt reuse (R2/R1), then
   complete C4's lazy emission/build path.** This directly targets cached-test
   scaling, affected-test latency, and the cold native test build.
4. **Complete C3 for generic workloads.** The managed fixture instantiates 128
   specializations on each edit. C3 cannot by itself repair the ordinary 100k
   fixture, which has no specializations.
5. **Repeat the same fixtures and correctness controls.** Preserve current
   cold/no-cache acceptance and diagnostics while comparing wall time, actual
   work, and memory. Re-run final S1 qualification after the implementation
   changes; the current 100k feedback objective is not met.

## Remaining plan and self-hosting

After C3/C4, the velocity plan has one named package left: **D2** documentation
and feature reconciliation. Counting closeout work separately gives four items:
D2, final S1 performance evaluation, the productivity trial, and the integration
gate. The current review fixes and invalidation prerequisites are additional
corrective work.

C2/C3/C4 improve the toolchain used to compile and test `.my` compiler sources.
P1 supports implementing compiler phases against checked fake providers. These
are useful foundations for self-hosting, but they do not move the existing
frontend out of Zig or make Zig compilation itself incremental at `.my` body
granularity.

The separate self-hosting plan still calls for production driver/lexer/parser,
resolution, checking, IR/lowering, QBE emission, project/cache integration, and
stage 1/2/3 bootstrap parity before the primary implementation switches. The
current prototype timings measure one entry in the lexer/parser prototype
directory, not a full self-hosted compiler build.

## Evidence and reproduction

- [Raw check samples and provenance](development-velocity-speed-2026-09-16.json)
- [Raw native samples and provenance](development-velocity-speed-native-2026-09-16.json)
- [Check runner snapshot](velocity-speed-2026-09-16/run_checks.py)
- [Corrected prototype edit runner](velocity-speed-2026-09-16/measure_prototype_edit.py)
- [Native runner snapshot](velocity-speed-2026-09-16/run_native.py)

The runner snapshots are the exact local measurement drivers, using the existing
profile harness. Run them in the listed order to recreate the scratch fixtures
and recordings on this workstation. They require the recorded gate worktrees
and toolchain paths and overwrite this report's JSON filenames. For a future
implementation comparison, point their compiler inputs and output filenames at
the new pinned build and a new evidence set.
