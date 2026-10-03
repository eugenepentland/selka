The expanded baseline is complete: **40 cases (35 microbenchmarks and five application workloads), six configurations, 7,200 timed samples**. All exact checksum checks and the independent evidence verifier passed. The suite was implemented with Sol 6.1 agents.

Compiler/runtime source is pinned to main `6df58b02554401f9d37564cceffd14277a835ae1`; benchmark code was frozen at `b725360f5f86ac67bc405db9407ae51c332a9931`. This change adds benchmark code and evidence only.

[Full timing table](baseline_main_20261003.md) · [Raw baseline](baseline_main_20261003.json) · [Validation receipt](validation.json) · [Suite methodology](../README.md) · [Coverage inventory](../coverage.json)

Application times below are median **microseconds per complete large-fixture execution**, lower is better. Inputs contain 256 fixture entries or evaluator iterations as specified in each contract. These are different workloads; their times should not be averaged into a language score.

| Application | MyLang LLVM | MyLang QBE | Rust | Go | Zig Safe | Zig Fast |
|---|---:|---:|---:|---:|---:|---:|
| packet_decode | 1.64 | 8.29 | 0.79 | 1.95 | 1.34 | 0.66 |
| word_count | 21.14 | 28.54 | 3.89 | 9.96 | 3.13 | 2.47 |
| csv_aggregate | 396.75 | 577.14 | 68.71 | 82.81 | 66.52 | 53.31 |
| json_transform | 3091.02 | 4157.30 | 124.23 | 543.44 | 230.41 | 187.25 |
| lox_eval | 75.79 | 82.98 | 10.66 | 12.64 | 30.53 | 29.79 |

Paired median runtime ratios against Go on those same large inputs:

| Application | MyLang LLVM / Go | MyLang QBE / Go |
|---|---:|---:|
| packet_decode | 0.85× | 4.15× |
| word_count | 2.12× | 2.86× |
| csv_aggregate | 4.79× | 6.98× |
| json_transform | 5.54× | 7.40× |
| lox_eval | 6.02× | 6.55× |

LLVM is faster than Go in this packet fixture, while the four other application fixtures expose substantial remaining work. Ratios above are medians of paired rounds and need not equal the ratio of the displayed medians. Full paired bootstrap intervals and all 15 samples per case/size/configuration are retained.

The most actionable initial microbenchmark gaps are below. These indicate where to investigate; the benchmarks alone do not establish a compiler/runtime root cause.

| Large microbenchmark | LLVM / Go | QBE / Go |
|---|---:|---:|
| call_direct | 2.40× | 14.53× |
| option_handle | 1.93× | 10.76× |
| result_propagate | 1.89× | 8.77× |
| record_update | 1.97× | 10.50× |
| dict_update | 2.25× | 2.92× |
| set_dedup | 3.21× | 4.25× |
| string_split | 3.26× | 4.02× |
| int_format | 3.98× | 5.18× |
| tagged_stack | 4.15× | 5.25× |

Allocation and ownership need special interpretation. `alloc_short` permits normal allocation elimination; the fastest large pilot was only 46 microseconds while the slowest arm approached one second. Treat its extreme ratios as optimization/ownership evidence, not a reliable isolated allocator ranking. `alloc_retained` supplies a complementary workload whose results remain live. Shared and nested snapshots favor MyLang relative to Go here, under the documented native copy-on-write versus explicit clone contracts.

Other LLVM wins include byte scans, string search, integer parsing, and these native sorting fixtures. Sorting algorithms and native JSON libraries differ across languages, so those rows measure the selected libraries and workload as well as generated code. In particular, Go uses `sort.Slice`/`sort.SliceStable`; its generic `slices.Sort`/`slices.SortStableFunc` APIs could produce different results. The Lox case is the documented execution-only bytecode subset, not a full Lox implementation.

Measurement and validation limits:

- All 80 case/size plans used all six configurations, three warmups, 15 measured rounds, and one separate RSS execution per configuration. There were 720 edge qualification probes and 354 calibration pilots. No samples or outliers were dropped.
- Thirty-seven plans missed the fastest-arm 50 ms calibration target: six iteration caps, one pilot limit, and 30 with the saved reason `slowest_arm_budget`. That last label also covers stopping when the computed growth is below 5%, including cases already near 50 ms; it does not mean all 30 hit the one-second budget. Raw fastest/slowest pilot durations and target flags are authoritative.
- CPU 2 was pinned on an i7-12700H; its sibling averaged 0.51% busy. The governor was `powersave` with `intel_pstate`; frequency was not fixed and the machine was not reserved exclusively. No runner interference warnings were emitted.
- These are optimized default target policies, with different instruction sets: MyLang LLVM and Zig use host-derived features, Rust uses its portable default, Go uses GOAMD64=v1, and QBE uses amd64_sysv. MyLang checks and reference counting, Go GC, and Zig ReleaseSafe behavior remain enabled as appropriate.
- Main, QBE, native-build, and formatting gates passed using cached test verdicts. The 14 harness/profile tests passed. The source commit passed all 88 Guardian checks; detailed receipts and hashes are in validation.json.

The eight requested operation areas are all represented. A percentage of everyday software execution cannot be inferred from this inventory; the separate profiles below assess only these five application fixtures.
Separate CPU profiles completed for all 30 application/configuration pairs with valid guest outputs and unchanged artifacts. **None establishes the 80% target.** Captures contained 242–359 samples each; every raw trace reported throttling. Conservative symbol rules linked 0–25% of the captured samples to named primitives. That is incomplete attribution, not evidence that the suite covers only 0–25% of these programs.

[Raw profile summary](profiles/profiles.json) retains symbol groups, primitive rules, diagnostics, hashes, and compressed perf data/sample/event traces for each execution. Percentages below describe the captured samples only; throttling prevents the intended coverage claim.

| Application | LLVM mapped | QBE mapped | Rust mapped | Go mapped | Zig Safe mapped | Zig Fast mapped |
|---|---:|---:|---:|---:|---:|---:|
| packet_decode | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| word_count | 14.5% | 17.0% | 0.0% | 8.3% | 0.0% | 0.0% |
| csv_aggregate | 8.1% | 8.6% | 8.5% | 25.0% | 4.3% | 3.4% |
| json_transform | 3.7% | 7.3% | 3.3% | 4.7% | 0.4% | 0.0% |
| lox_eval | 5.5% | 6.1% | 0.0% | 0.0% | 0.0% | 0.0% |

The unresolved samples still provide investigation leads: MyLang CSV/JSON spend many captured samples in `myl_native_equal` and `leaf`; word counting exposes dictionary probing/capture helpers; the Lox subset concentrates in the evaluator and ownership/list helpers. These are sampled associations, not causal diagnoses. Inlined application functions stay uncredited rather than being automatically assigned to broad operation families.

To substantiate an 80% claim, the next coverage study needs reliable sampling without throttling, source/inline-aware attribution, and representative real application inputs. This baseline supplies the operation inventory and reproducible comparisons; it does not establish a universal distribution of everyday work.
