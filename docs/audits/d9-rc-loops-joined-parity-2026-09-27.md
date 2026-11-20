# Combined loop parity and schematic diagnostic

The frozen `49c6ca07` Debug compiler completes all 30 non-Lox programs on both
actual backends with correct output. This measures the combined dictionary-loop
and read-list version improvements alongside the previously joined readiness,
named-record and read-only helper changes. All 13 Lox workloads per backend are
excluded, so these results cannot establish full Stage 4 acceptance.

Compiler SHA256: `49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`. Accepted GC remains
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.

## Results

The requirements remain geomean at most 1.0, every program at most 1.3, and
lower median peak RSS. Memory values are KiB.

| Backend | Instruction geomean | Maximum ratio | Rows within 1.3 | GC median RSS | RC median RSS | RSS ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| qbe | 2.433636 | 15.954549 | 8/30 | 6996 | 5334 | 0.762436 |
| llvm | 2.800243 | 23.923112 | 9/30 | 6996 | 5204 | 0.743854 |

| Program | QBE instructions/GC | LLVM instructions/GC |
| --- | ---: | ---: |
| parity/suite/binary_trees | 3.430422 | 3.591853 |
| parity/suite/fannkuch_redux | 1.744177 | 1.017981 |
| parity/suite/knucleotide | 5.909806 | 6.723749 |
| parity/suite/mandelbrot | 1.000009 | 0.957261 |
| parity/suite/matmul | 3.009733 | 1.908876 |
| parity/suite/nbody | 1.441951 | 2.219689 |
| parity/suite/raytrace | 1.436238 | 1.954539 |
| parity/suite/sieve | 2.963576 | 3.513824 |
| parity/suite/sort_builtin | 1.740339 | 1.473463 |
| parity/suite/sort_quick | 1.798547 | 2.451135 |
| parity/suite/sort_records | 4.588636 | 6.219844 |
| parity/suite/spectral_norm | 2.015151 | 2.269182 |
| parity/suite/text_ops | 3.577111 | 3.207487 |
| parity/lib/scan_count | 1.018089 | 1.013201 |
| parity/lib/scan_replace | 1.026225 | 1.020601 |
| parity/lib/scan_split | 2.338469 | 2.023285 |
| parity/micro/alloc_churn | 2.309110 | 2.512923 |
| parity/micro/bytes_scan | 3.554239 | 12.666139 |
| parity/micro/calls | 1.000016 | 1.000048 |
| parity/micro/dict_count | 1.481220 | 1.461059 |
| parity/micro/fib | 1.000017 | 1.000028 |
| parity/micro/float_loop | 1.079375 | 1.000153 |
| parity/micro/intloop | 1.000022 | 1.000040 |
| parity/micro/list_append_sum | 1.902061 | 2.301126 |
| parity/micro/list_records | 3.870779 | 9.011837 |
| parity/micro/records | 1.000015 | 1.000044 |
| parity/micro/str_build | 6.009368 | 8.435395 |
| schematic/fixture | 15.897826 | 23.923112 |
| schematic/changed-net | 15.954549 | 23.901989 |
| schematic/changed-value | 15.903957 | 23.900753 |

## Method and limits

All 56 RC guest builds use the immutable Debug compiler; LLVM guests use O3
and full LTO. The mandated workloads, sizes, output checks and accepted GC
binaries are unchanged. Each row has separate output checks and three
interleaved GC/RC instruction observations plus three peak-RSS observations
per side, pinned to CPU2. The archive preserves raw counters, counter running
fractions, manifests, commands, hashes and explicit MYLANG environment overrides.
The independent verifier reparses those receipts and recomputes every median
and summary. All 360 instruction observations ran at 100%; all 360 separate RSS
observations passed. It verifies the exact selected corpus against accepted GC
and all 112 native manifests, including actual LLVM O3/full-LTO selection.
Documentation coverage and whole-tree Guardian (88 checks) pass.

Later isolated agent results are not multiplied into this combined table.
The ordinary runtime remains GC and full 43-program acceptance remains open.

[Raw evidence](../../experiments/d9-rc-loops-joined-parity-20260927/README.md).
