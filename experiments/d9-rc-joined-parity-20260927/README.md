# Joined parity and schematic diagnostic

The last fully gated source `5b87601297f01810968b9f7ac554c484d5848cca`
finishes all 30 non-Lox programs on both actual backends with correct output.
It still fails the instruction requirements. Median peak RSS is lower than
accepted GC on each backend for this subset. All 13 Lox workloads per backend
are excluded; no whole-corpus acceptance follows from these results.

This source includes scalar record publication, the private scalar descriptor
identity cache, and record-field snapshot correction. It precedes dictionary
tail `3c4251e8`, native type facts `c71d4046`, and adjacent variant-read work.
Its immutable Debug compiler SHA256 is
`f87393b249f45699d63a1f5a81dc47fb59faa41d1396fc8035131d7b2533b120`.
The accepted GC baseline remains unchanged, with compiler SHA256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.

## Results

The thresholds are instruction geomean at most 1.0, every program at most 1.3,
and lower median peak RSS. Memory values below are KiB.

| Backend | Instruction geomean | Maximum instructions/GC | Rows within 1.3 | GC median RSS | RC median RSS | RSS ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| qbe | 2.831332 | 18.707279 | 8/30 | 7058 | 5332 | 0.755455 |
| llvm | 3.283233 | 27.160196 | 9/30 | 7042 | 5248 | 0.745243 |

| Program | QBE instructions/GC | LLVM instructions/GC |
| --- | ---: | ---: |
| parity/suite/binary_trees | 3.431484 | 3.592350 |
| parity/suite/fannkuch_redux | 1.744178 | 1.016337 |
| parity/suite/knucleotide | 9.875874 | 11.367041 |
| parity/suite/mandelbrot | 1.000009 | 0.957261 |
| parity/suite/matmul | 3.015348 | 2.054766 |
| parity/suite/nbody | 1.441951 | 2.219689 |
| parity/suite/raytrace | 1.436238 | 1.954539 |
| parity/suite/sieve | 5.084234 | 7.527071 |
| parity/suite/sort_builtin | 1.740339 | 1.473463 |
| parity/suite/sort_quick | 1.798547 | 2.451135 |
| parity/suite/sort_records | 4.614144 | 6.272260 |
| parity/suite/spectral_norm | 2.015244 | 2.269361 |
| parity/suite/text_ops | 3.555259 | 3.200109 |
| parity/lib/scan_count | 1.017415 | 1.013213 |
| parity/lib/scan_replace | 1.026648 | 1.020591 |
| parity/lib/scan_split | 2.336890 | 2.018173 |
| parity/micro/alloc_churn | 2.634583 | 2.727750 |
| parity/micro/bytes_scan | 3.554239 | 12.666139 |
| parity/micro/calls | 1.000016 | 1.000048 |
| parity/micro/dict_count | 11.857681 | 13.165319 |
| parity/micro/fib | 1.000017 | 1.000028 |
| parity/micro/float_loop | 1.079375 | 1.000152 |
| parity/micro/intloop | 1.000022 | 1.000040 |
| parity/micro/list_append_sum | 4.252236 | 4.964809 |
| parity/micro/list_records | 3.870787 | 8.857745 |
| parity/micro/records | 1.000015 | 1.000044 |
| parity/micro/str_build | 6.009368 | 8.435396 |
| schematic/fixture | 18.582755 | 27.084984 |
| schematic/changed-net | 18.573699 | 27.133961 |
| schematic/changed-value | 18.707279 | 27.160196 |

## Measurement and limits

There are 56 distinct RC guest builds and 60 workload/backend rows. The three
schematic inputs reuse each backend's one binary. Each GC/RC row has an exact
output check, three retired-instruction observations and three separate peak-RSS
observations. Timed stdout is discarded; output is checked separately. Every
instruction observation reports 100% counter running. All workloads, sizes,
accepted GC binaries and input hashes are unchanged. RC guests use ReleaseFast;
actual LLVM builds use O3/full LTO. Measurements run on reserved CPU3.

The driver freezes its compiler, input, accepted baseline and own source hashes;
it also checks all used guest binary hashes before returning. Exit 0 means the
diagnostic executed completely, not that the performance thresholds passed.
The independent verifier reparses raw counter and RSS strings, recomputes all
medians and summaries, and checks the exact selected corpus against the accepted
baseline. Source paths and manifests preserve the actual backend selections.
The archive includes only explicit MYLANG overrides, not unrelated inherited
host environment data.

The run provides a current map of remaining costs: pure scalar and some text
scan rows are near GC, while collection operations and schematic remain above
the cap. It is a diagnostic checkpoint, not a replacement for the required
43-program-per-backend final comparison. Later combined optimizations need
fresh measurements; their isolated gains are not multiplied into this table.

Run `python3 experiments/d9-rc-joined-parity-20260927/verify.py` from the repository root.
