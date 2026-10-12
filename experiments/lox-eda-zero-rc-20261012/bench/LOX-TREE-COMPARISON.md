# Full Lox tree comparison

All 13 full tree-interpreter workloads completed across seven arms with matching output oracles. Ratios below are geometric means over all 13 cases; no VM or bytecode subset is included.

| Arm | Complete cases | Wall / original RC | Wall / migrated RC | Largest case-median peak RSS (MiB) |
|---|---:|---:|---:|---:|
| mylang-original-rc | 13/13 | 1.000 | 1.019 | 46.453 |
| mylang-migrated-rc | 13/13 | 0.981 | 1.000 | 46.629 |
| mylang-zero-rc | 13/13 | 2.322 | 2.366 | 95.992 |
| zig-fast | 13/13 | 0.551 | 0.562 | 35.344 |
| zig-safe | 13/13 | 0.905 | 0.922 | 41.602 |
| rust | 13/13 | 0.721 | 0.735 | 40.559 |
| go | 13/13 | 0.741 | 0.755 | 73.078 |

| Reference | Historical Oct9 mylang / reference | Current zero-RC / freshly rerun reference |
|---|---:|---:|
| zig-fast | 1.623 | 4.213 |
| zig-safe | 1.007 | 2.565 |
| rust | 1.263 | 3.220 |
| go | 1.249 | 3.134 |

Each current arm has two warmups, nine alternating uninstrumented wall samples and three separate GNU-time child peak-RSS samples, on CPU 8 with a recorded 120-second guest deadline. Whole CLI launch/startup is included; no tree arm failed or was censored. Per-case medians and ranges are in lox-tree-per-case.csv; raw samples, input and binary identities and receipt hashes are preserved in lox-tree-runtime-summary.json.

Original RC uses the modern original application source. Migrated RC and checked zero-RC share the same migrated source, so their ratio isolates memory-mode behavior on that source, including explicit snapshot copies. This result does not describe the separate VM engine. Managed allocation and RC counters are measured separately; child RSS is not cumulative allocation or managed peak.

The three mylang arms were built with compiler source e2893d2707cbe057a09abf94e04c4b12d16b7b8b, compiler SHA256 6e7938a14ad4abc46b76c149ef12551b170f6c7e6f462beec2f81db18d40a83d. The final integration gate later rebuilt the compiler to SHA256 8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa with unchanged production source bytes; benchmark guests were not rebuilt or relabeled.

Existing Zig/Rust/Go executables were copied, hashed and freshly rerun, not rebuilt in this session. Historical Oct9 measurements used CPU 10 and different compiler/source/artifact identities. Their group ratios and per-case values are context, not isolated compiler improvements; old receipts do not establish identical reference executable identities. The full 60-cell aggregator remains separate and requires all 26 Lox and 34 EDA cells.
