# Full EDA fresh comparison

All 34 full schematic-export designs completed across seven arms with byte-identical output oracles. Checked zero-RC takes **10.380×** the original-source RC wall time and **10.458×** migrated-source RC wall time (geometric means). Migrated-source RC takes **0.993×** original-source RC wall time. This identifies the memory-mode cost on the same migrated source; it does not justify a speedup claim.

| Arm | Completed designs | Wall time / original RC | Wall time / migrated RC | Largest case-median peak RSS (MiB) |
|---|---:|---:|---:|---:|
| mylang-original-rc | 34/34 | 1.000 | 1.007 | 52.699 |
| mylang-migrated-rc | 34/34 | 0.993 | 1.000 | 52.754 |
| mylang-zero-rc | 34/34 | 10.380 | 10.458 | 88.020 |
| zig-fast | 34/34 | 0.808 | 0.814 | 80.250 |
| zig-safe | 34/34 | 0.887 | 0.893 | 80.125 |
| rust | 34/34 | 0.887 | 0.893 | 44.047 |
| go | 34/34 | 2.086 | 2.102 | 65.051 |

| Reference | Historical Oct9 mylang / reference | Current checked zero-RC / fresh reference |
|---|---:|---:|
| zig-fast | 1.290 | 12.850 |
| zig-safe | 1.166 | 11.707 |
| rust | 1.145 | 11.708 |
| go | 0.474 | 4.976 |

Current measurements use CPU 8, two warmups, nine alternating uninstrumented wall samples, and three separate GNU-time child peak-RSS samples per arm and design. Times include the whole CLI launch and startup. Every guest has a recorded 120-second deadline; no EDA run failed or was censored. Raw samples and identities remain in results/eda-final; eda-per-case.csv retains median/min/max and exact historical context.

The three mylang arms use the same frozen compiler (source e2893d2707cbe057a09abf94e04c4b12d16b7b8b, SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d). Original RC uses the prepared modern original application; migrated RC and checked zero-RC use the same final migrated source. Full 310-test qualification, 170 golden output sets and nine error paths passed. All models, flags, project files and expected outputs match the owner frozen manifests: eda-input-qualification-equality.json records the 34-case equality.

Historical Oct9 data used CPU 10 and different compiler/source/executable identities. Existing Zig/Rust/Go executables were copied, hashed and freshly rerun, rather than rebuilt in this session; historical receipts do not establish identical executable identities. These cross-date columns give context, not isolated compiler improvement. Historical EDA memory uses rss_exact_mib, excluding the launching Python wait4 high-water floor.

The migrated source introduces explicit owned snapshots. Their physical copy and destruction behavior differs between RC and checked zero-RC; separately instrumented allocation and event counters are collected in results/eda-counted. Child RSS is not managed peak or cumulative allocation traffic. release_unique counts direct destruction, not RC retain/release traffic. The reader/printer EDA subset is excluded.

All 102 separately instrumented arm-case runs completed correctly. Every arm exits with zero live managed bytes. Checked zero-RC has zero compiler/runtime/shared retain-release events, zero share marks and zero uniqueness tests; its direct destruction events are reported separately. Its cumulative allocated bytes are 7.051× migrated RC (matched-case geometric mean). Across the 34 independent runs, cumulative allocation totals are 3.119 GB for either RC arm and 24.325 GB for checked zero-RC; these sums are allocation traffic, not simultaneous resident memory. Largest managed peak is 51,415,480 bytes for RC and 86,587,128 bytes for zero-RC. See eda-counted-summary.json for per-case metrics and ranges; eda-counted-summary.json.gz preserves every raw counter.

The later final integration gate rebuilt the compiler executable to SHA256 8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa with unchanged production source bytes. Benchmark guests were already frozen from compiler 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d and were not rebuilt or relabeled.
