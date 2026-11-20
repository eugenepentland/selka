# Joined entry/operand performance diagnostic

Frozen compiler source `4e5c0cd638e55b86ef0d99112872e02ae41dbe89`, Debug SHA256 `52bff2acf09f3d0ef3739c707ea7e570c789d26cbc938b6a0a5615fed5133738`.
This measures the unchanged 30 non-Lox programs plus full Lox VM binary_trees N10. It excludes twelve Lox programs and cannot establish final 43-program acceptance. The accepted GC compiler and all native executables retain their original hashes.

## Current result

| Set | Backend | Instruction geomean RC/GC | Worst row | Rows <=1.3 | Median peak RSS GC / RC (KiB) |
| --- | --- | ---: | ---: | ---: | ---: |
| 30 programs | qbe | 2.252288 | 11.154345 | 9/30 | 7002 / 5330 |
| 30 programs | llvm | 2.478538 | 16.596880 | 10/30 | 7084 / 5220 |
| 31 programs | qbe | 2.417467 | 20.205200 | 9/31 | 7224 / 6552 |
| 31 programs | llvm | 2.693842 | 32.784654 | 10/31 | 7388 / 6616 |

The whole 43-program goal remains geomean <=1.0, every row <=1.3 and lower median RSS. A subset meeting one component does not discharge that goal.

## Historical 30-program comparison

The earlier 49c 30-program diagnostic used CPU 2; this run uses CPU 11. These historical medians are shown separately from the paired current-vs-accepted GC measurements. No older RC compiler or binary was rebuilt.

| Backend | Prior 30-program geomean | Current 30-program geomean | Current / prior geomean |
| --- | ---: | ---: | ---: |
| qbe | 2.433636 | 2.252288 | 0.925483 |
| llvm | 2.800243 | 2.478538 | 0.885115 |

## Per-program instruction ratios

Each row is the median retired instruction count from three runs, independently paired with accepted GC on CPU 11. All 372 current instruction observations have one active instruction event at 100% running. There are 372 separate peak-RSS observations, exact stdout/SVG checks, and 62 separately built count-balanced executions. All 31 complete counter dictionaries agree between backends. Actual LLVM manifests require O3 and full LTO. The 116 RC guest builds are slot-controlled and use an isolated new cache/TMPDIR.

| Program | QBE RC/GC | LLVM RC/GC | Further QBE reduction to 1.3 | Further LLVM reduction to 1.3 |
| --- | ---: | ---: | ---: | ---: |
| parity/suite/binary_trees | 3.430422 | 3.591852 | 62.10% | 63.81% |
| parity/suite/fannkuch_redux | 1.744177 | 1.017982 | 25.47% | 0.00% |
| parity/suite/knucleotide | 6.113849 | 6.655516 | 78.74% | 80.47% |
| parity/suite/mandelbrot | 1.000009 | 0.957261 | 0.00% | 0.00% |
| parity/suite/matmul | 3.009715 | 1.935412 | 56.81% | 32.83% |
| parity/suite/nbody | 1.441951 | 2.219689 | 9.84% | 41.43% |
| parity/suite/raytrace | 1.436238 | 1.954539 | 9.49% | 33.49% |
| parity/suite/sieve | 2.963575 | 3.513824 | 56.13% | 63.00% |
| parity/suite/sort_builtin | 1.740339 | 1.473463 | 25.30% | 11.77% |
| parity/suite/sort_quick | 1.798547 | 2.451135 | 27.72% | 46.96% |
| parity/suite/sort_records | 4.588636 | 6.324675 | 71.67% | 79.45% |
| parity/suite/spectral_norm | 2.015151 | 2.269182 | 35.49% | 42.71% |
| parity/suite/text_ops | 3.600721 | 3.188044 | 63.90% | 59.22% |
| parity/lib/scan_count | 1.018016 | 1.013246 | 0.00% | 0.00% |
| parity/lib/scan_replace | 1.026225 | 1.020601 | 0.00% | 0.00% |
| parity/lib/scan_split | 2.338461 | 2.023286 | 44.41% | 35.75% |
| parity/micro/alloc_churn | 2.302574 | 2.525228 | 43.54% | 48.52% |
| parity/micro/bytes_scan | 1.105132 | 1.075882 | 0.00% | 0.00% |
| parity/micro/calls | 1.000016 | 1.000048 | 0.00% | 0.00% |
| parity/micro/dict_count | 1.312029 | 1.325034 | 0.92% | 1.89% |
| parity/micro/fib | 1.000017 | 1.000028 | 0.00% | 0.00% |
| parity/micro/float_loop | 1.079375 | 1.000153 | 0.00% | 0.00% |
| parity/micro/intloop | 1.000022 | 1.000040 | 0.00% | 0.00% |
| parity/micro/list_append_sum | 1.902062 | 2.301126 | 31.65% | 43.51% |
| parity/micro/list_records | 3.870787 | 8.857745 | 66.42% | 85.32% |
| parity/micro/records | 1.000015 | 1.000044 | 0.00% | 0.00% |
| parity/micro/str_build | 6.009368 | 8.435394 | 78.37% | 84.59% |
| schematic/fixture | 11.117453 | 16.539573 | 88.31% | 92.14% |
| schematic/changed-net | 11.142961 | 16.580257 | 88.33% | 92.16% |
| schematic/changed-value | 11.154345 | 16.596880 | 88.35% | 92.17% |
| lox/vm/binary_trees | 20.205200 | 32.784654 | 93.57% | 96.03% |

Counts, per-side medians, raw perf strings, manifests, run environments limited to MYLANG overrides, source/input hashes and exact commands remain in the compressed archive. `verify.py --live` rechecks immutable live hashes. No defaults or production compiler/runtime files changed in this worktree. Root owns the combined source gates and centralized Guardian feedback.

The frozen source passed the root-owned four-command gate (2,404 main and 458 QBE tests, native build checks and formatting), both forced RC sweeps (1,049 assertions across 179 programs per backend), and all 88 Guardian checks. This evidence-only task did not rerun those gates.

The largest measured gaps remain Lox and schematic. Among the other programs, list_records is 3.87× / 8.86× GC and str_build is 6.01× / 8.44×. Dictionary counting is close to the per-row cap but still needs 0.92% / 1.89% fewer instructions. These measurements prioritize further attribution; they do not establish the cause of a gap.
