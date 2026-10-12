# Performance handoff after benchmark deferral

Support7 reduced managed allocation counts and observed managed peaks in all nine parallel cases. Six other exact-sized cases retained the same allocation counts, allocation bytes and peaks. Three completed runtime comparisons recorded lower medians, with overlapping results for record unpacking. No final-revision runtime, RSS or compile-speed claim is supported.

The user changed the endpoint to a green full verification gate and deferred further performance work. No additional benchmarks were run for this report. The coordinator owns the gate result; this report does not assert that the gate passed. Earlier scheduling documents describe the superseded measurement plan.

Artifact identities are fixed as follows:

| Artifact | Source revision | Compiler SHA-256 | Host compiler / guest mode |
| --- | --- | --- | --- |
| C0 | `fbfcaa7a923186a8e773c3760f81c10aa345a432` | `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a` | Debug / Release |
| Support7 | `bed11cf3bf3102ffec44487e431a1573fdf02ad5` | `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef` | ReleaseFast / Release |

Both runtime arms use uninstrumented Release guests. The host compiler optimization differs; these are guest runtime comparisons, not compiler-speed comparisons. [C0 installation](C0-installation.json) and [Support7 installation](raw/Support7-artifacts/installation.json) pin the full layouts. C0 contains historical seed-built components; Support7 contains actual checked-owned components. Neither this package evidence nor these performance results qualify later revisions. Guest/source/helper hashes are in the [runtime raw records](raw/Support7-runtime-initial3/results.json), [guest manifest](raw/Support7-artifacts/guests.json) and [application manifest](raw/Support7-artifacts/apps.json).

Each completed runtime case used two warmup pairs and nine measured alternating pairs on CPU10 of the same i7-12700H host, with exact outputs checked. Wall time includes process launch/wait, excludes admission wait, and uses separate uninstrumented binaries. All samples, including warmups, remain in the raw records. Values below are milliseconds; ranges are measured minima/maxima, not confidence intervals.

| Case | C0 median [range] ms | Support7 median [range] ms | Median change | Paired S7/C0 ratio median [range] |
| --- | ---: | ---: | ---: | ---: |
| array | 310.611 [306.993, 313.889] | 302.566 [299.632, 304.408] | -2.59% | 0.9734 [0.9648, 0.9860] |
| object | 316.188 [312.972, 320.526] | 302.066 [298.124, 303.447] | -4.47% | 0.9591 [0.9358, 0.9680] |
| record | 173.003 [167.604, 177.388] | 169.327 [167.593, 175.243] | -2.12% | 0.9869 [0.9493, 1.0386] |

Array and object observations support a modest workload-specific reduction at Support7. Record ranges overlap and paired ratios cross 1, so its lower median is not a firm improvement claim. None of the three triggers the predeclared 5% slowdown review. These measurements do not establish parallel-map or application throughput improvements.

The fifteen exact-sized managed comparisons below use the same qualified native replay adapter on both arms: `counted-release-native-replay-v2`, commit `7b10b6b6f9205993b7f6bdd73be34e32b4ab93ea`. It links each compiler's archived LLVM against that compiler's verified runtime and numeric object. All thirty primary executions passed output/status checks, strict zero-RC event audits, zero managed exit-live checks and LLVM/symbol audits. Support7 also passed the normal compiler path for all fifteen inputs. These whole-program observations are separate from the original 30-case and expanded census.

| Exact input case | C0 allocations | S7 allocations | C0 allocation bytes | S7 allocation bytes | C0 managed peak B | S7 managed peak B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| array | 12,001,554 | 12,001,554 | 1,280,151,792 | 1,280,151,792 | 75,408 | 75,408 |
| object | 12,002,200 | 12,002,200 | 1,280,196,480 | 1,280,196,480 | 90,264 | 90,264 |
| record | 21,000,000 | 21,000,000 | 2,496,000,000 | 2,496,000,000 | 1,536 | 1,536 |
| parallel_cheap_1 | 101,318,666 | 393,226 | 7,949,257,096 | 567,282,056 | 103,096 | 17,144 |
| parallel_cheap_2 | 25,329,674 | 442,378 | 1,987,316,104 | 163,711,368 | 103,096 | 18,096 |
| parallel_cheap_8 | 12,664,842 | 827,402 | 993,659,272 | 123,275,656 | 103,160 | 21,552 |
| parallel_expensive_1 | 786,762 | 202 | 60,900,232 | 4,211,592 | 1,643,112 | 262,904 |
| parallel_expensive_2 | 786,762 | 874 | 60,900,232 | 4,256,392 | 1,643,048 | 247,488 |
| parallel_expensive_8 | 786,762 | 3,242 | 60,900,232 | 4,424,328 | 1,643,112 | 251,568 |
| a06_word_count | 13,113,602 | 13,113,602 | 891,555,328 | 891,555,328 | 99,152 | 99,152 |
| a06_nested_json | 3,403,682 | 3,403,682 | 266,812,928 | 266,812,928 | 828,184 | 828,184 |
| a06_file_processing | 2,464,352 | 2,464,352 | 185,360,528 | 185,360,528 | 49,680 | 49,680 |
| a06_parallel_t1 | 62,842 | 31,842 | 4,664,128 | 2,443,328 | 65,976 | 27,320 |
| a06_parallel_t2 | 62,842 | 32,922 | 4,664,128 | 2,513,408 | 56,312 | 26,032 |
| a06_parallel_t8 | 62,842 | 35,882 | 4,664,128 | 2,715,648 | 51,576 | 28,592 |

Cheap-map allocation counts fell by 99.61%, 98.25% and 93.47% at 1/2/8 workers on their respective matched inputs. Expensive-map counts fell by 99.97%, 99.89% and 99.59%; the application prime-map counts fell by 49.33%, 47.61% and 42.90%. These are managed-allocation reductions, with runtime and RSS for these cases deferred.

[Machine-readable handoff](final-performance-handoff.json) and the [full paired comparison](raw/size-aligned-Support7-native-replay-v2/comparison-C0.json) retain reallocations, growth bytes, copy traffic, direct drops, per-input/source hashes and binary identities separately. Allocation bytes above exclude separately recorded reallocation growth; managed peaks are live-storage observations, not traffic and not RSS. Multiworker peaks can vary across repeated executions. Output storage and temporary chunk-result storage remain allocated.

The array/object cases perform four million lookups over 128 siblings; record performs one million unpacks. Cheap-map cases use 513 inputs and 65,536/16,384/8,192 repetitions for 1/2/8 workers. Those differing repetition counts prohibit comparing raw totals across worker rows. Expensive-map cases use 8,193 inputs, 32 maps and 2,048 arithmetic iterations per callback. Application repetitions are word-count 200, nested JSON 80, file-processing 150 and parallel primes 40. Both arms use identical source/helpers, inputs, worker counts and affinity within each row. Exact checksums and dataset hashes are preserved in the [runtime manifest](calibrated-manifest.json) and [application manifest](calibrated-applications-manifest.json).

C0 undercounted descriptor-driven list copies. The later instrumentation fix increases some copy-event/byte fields without a corresponding allocation increase; those telemetry changes are not savings or regressions by themselves. The eight original normal C0 counted builds failed at native-link staging. [Their failures](raw/size-aligned-C0/results.json), archived LLVM, the older v1 replay and the ReleaseFast extractor failure remain intact. The v2 paired replay uses the same adapter in both arms and does not patch the frozen baseline compiler.

A separate smaller JSON library fixture exposed a Support7 regression: release allocations rose 538 → 541 and allocation bytes 38,720 → 38,912, with the 9,952-byte peak unchanged. The cause was three temporary byte slices in `json::read_literal` after a conservative lifetime safety repair. The later private read-only helper refactor, integrated as `d01f772cd0cfa823a9ec6a8838aaf5c4856710b4`, recovered those three allocations under the **same Support7 compiler**: 541 → 538 and 38,912 → 38,720 in release, verified release and optimized debug. Release without facts recovered the same three allocations; unoptimized debug was unchanged. All peaks stayed unchanged. [A04's controlled source comparison](../A04/json-literal-view/comparison.json) and [qualification report](../A04/json-literal-view/README.md) preserve twelve native lanes and exact source/compiler identities. This is a source-refactor allocation result, not a final-installation, timing or RSS result; the larger nested-JSON application row above remains unchanged.

Existing list/buffer growth policy was retained. Smaller initial capacities reduce the singleton-list peak but add growth/allocation work for common small lists; measured runtime ranges were too noisy for a throughput claim. The controlled [replacement](raw/capacity-replacement-long.json), [buffer](raw/capacity-buffer-long.json) and [reserve](raw/capacity-reserved-long.json) observations remain separate from this compiler comparison. No capacity-policy speed or RSS saving is claimed.

Work deferred by the revised endpoint:

- Runtime: 3/15 cases and 66/330 launches completed. The remaining twelve map/application cases (264 launches) were not measured against Support7. The fourth timing window was canceled before admission; no guest sample was interrupted.
- RSS: 0/90 planned valid guest launches completed. [Old pilot RSS](raw/rss-qualification/invalid-pilots.json) was contaminated by Python launcher high-water and is invalid. The [corrected GNU-time child-rusage method](raw/rss-qualification/README.md) passed controlled small/large-child and parent-memory tests, but was not used for a final guest comparison.
- Compile scaling: A08 retains 45 accepted C0 ReleaseFast calls across nine cells, five parser-limit refusals at match depth 128 and ten native-link failures for modules 16/64. Four further native cells were not attempted after that baseline defect. The planned 80 candidate calls and twelve paired source/Core-only diagnostic calls remain unmeasured. No matched compiler-speed ratio exists.
- Later revisions: the eventual green-gate revision and any default/retirement changes have no runtime, RSS or compile-speed measurements in this report. The separately labelled JSON source-refactor counter experiment does not qualify that final installation. Do not relabel these Support7 results as final-revision evidence.

The preserved C0 compilation baseline uses ReleaseFast compiler SHA-256 `78ac31605c7505c7cb330d41bdf2d3a232043e032f487e599f454b3bc6f2bd37`, with the [complete baseline manifest](C0-releasefast-installation.json). Admission delays and correctness-harness command times are scheduling evidence only. They are not cold-build benchmarks.

Report validation recomputed runtime summaries from the preserved samples, checked all fifteen paired counter rows and hashed the referenced evidence. Historical raw records were not changed. The accompanying JSON lists those report hashes and all deferred case IDs.
