# D9 joined 43-workload diagnostic — 2026-09-26

**Result: FAIL.** The frozen `5bdd99ea` candidate has instruction-count geometric
means of **1.061944× QBE** and **1.096255× LLVM** against exact `60b668cf`.
The acceptance limits remain ≤1.05× geometric mean and ≤1.30× for every workload.
All 172 baseline/candidate output checks passed.

## Scope and method

The run uses the 27 parity IDs recorded in the original `results.json`, three
schematic fixtures and all 13 Lox VM workloads: 43 keys on each backend. The
later `binary_trees_recursive` addition is excluded. The mandated
`experiments/perf-gc-dict-20260925/scripts/pc.py` supplies build commands, run
arguments, stdout/SVG validation and perf counting, including its historical
tree-calibrated Lox sizes. Each result is the median of three interleaved runs
pinned to CPU 10. Guest builds use ReleaseFast; LLVM uses `-O3` and LTO. The
compiler is Debug, and candidate compilation explicitly enables value semantics.

The candidate compiler SHA-256 is
`ceb38b6e1fb1a23f20d92580b3cd7f07f635f5752311f27d477f9792e388b7d5`.
The exact baseline compiler SHA-256 is
`48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`.
All reused baseline binary hashes match their recorded build metadata. Candidate
source and provider hashes, all binary hashes, raw counters and checks are in
[the raw results](d9-performance43-5bdd99ea.json); full build commands and source
hashes are in [the build records](d9-performance43-5bdd99ea-builds.json).

The Lox source was reproduced using
`docs/audits/d9-stage3d-migrations/apply-lox.sh .tmp-perf43 --optimized` from this
snapshot. It includes compact frames, direct frame loading and tree helper/env
reader changes. This run precedes the pending scoped-pin fix and subsequent
source/compiler optimizations, so it is diagnostic evidence, not final acceptance.

## Aggregate results

| Group | Keys/backend | QBE | LLVM |
| --- | ---: | ---: | ---: |
| Parity | 27 | 1.042969× | 1.031449× |
| Schematic | 3 | 0.920515× | 0.996299× |
| Lox VM | 13 | 1.139432× | 1.271912× |
| Full suite | 43 | 1.061944× | 1.096255× |

## Workloads exceeding 1.30×

| Workload | QBE | LLVM |
| --- | ---: | ---: |
| `parity/suite/binary_trees` | 3.305924× | 2.152965× |
| `lox/vm/binary_trees` | 1.327798× | 1.660148× |
| `lox/vm/closures` | 1.341546× | 1.552496× |
| `lox/vm/method_call` | 1.234636× | 1.512524× |

The parity regression is isolated to recursive boxed binary trees. The other
29 non-VM keys have geometric means of 0.989427× QBE and 1.002005× LLVM.
Lox binary trees, closures and LLVM method calls remain optimization targets.

## Complete ratios

| Workload | QBE | LLVM |
| --- | ---: | ---: |
| `parity/suite/binary_trees` | 3.305924× | 2.152965× |
| `parity/suite/fannkuch_redux` | 1.000000× | 0.997267× |
| `parity/suite/knucleotide` | 1.000001× | 1.002451× |
| `parity/suite/mandelbrot` | 1.000000× | 1.000003× |
| `parity/suite/matmul` | 1.000006× | 1.001724× |
| `parity/suite/nbody` | 1.007021× | 1.007003× |
| `parity/suite/raytrace` | 0.865246× | 1.000001× |
| `parity/suite/sieve` | 1.000002× | 1.000030× |
| `parity/suite/sort_builtin` | 1.000002× | 1.002601× |
| `parity/suite/sort_quick` | 1.077281× | 1.052628× |
| `parity/suite/sort_records` | 1.000006× | 1.000005× |
| `parity/suite/spectral_norm` | 1.000000× | 1.000002× |
| `parity/suite/text_ops` | 1.001001× | 1.004068× |
| `parity/lib/scan_count` | 1.000062× | 1.000050× |
| `parity/lib/scan_replace` | 1.000080× | 1.000115× |
| `parity/lib/scan_split` | 1.000043× | 1.000035× |
| `parity/micro/alloc_churn` | 1.002293× | 1.002571× |
| `parity/micro/bytes_scan` | 1.000002× | 1.000012× |
| `parity/micro/calls` | 1.000001× | 1.000000× |
| `parity/micro/dict_count` | 1.000003× | 0.999991× |
| `parity/micro/fib` | 1.000001× | 1.000000× |
| `parity/micro/float_loop` | 1.000002× | 1.000002× |
| `parity/micro/intloop` | 1.000001× | 1.000000× |
| `parity/micro/list_append_sum` | 1.000003× | 1.000009× |
| `parity/micro/list_records` | 1.000004× | 1.000020× |
| `parity/micro/records` | 1.000001× | 1.000000× |
| `parity/micro/str_build` | 1.000002× | 1.000009× |
| `schematic/fixture` | 0.920483× | 0.996258× |
| `schematic/changed-net` | 0.920580× | 0.996392× |
| `schematic/changed-value` | 0.920483× | 0.996246× |
| `lox/vm/binary_trees` | 1.327798× | 1.660148× |
| `lox/vm/closures` | 1.341546× | 1.552496× |
| `lox/vm/equality` | 1.050664× | 1.194115× |
| `lox/vm/fib` | 1.094324× | 1.154029× |
| `lox/vm/instantiation` | 1.229441× | 1.281206× |
| `lox/vm/invocation` | 1.085804× | 1.159882× |
| `lox/vm/method_call` | 1.234636× | 1.512524× |
| `lox/vm/properties` | 1.066333× | 1.164101× |
| `lox/vm/string_equality` | 1.060943× | 1.103340× |
| `lox/vm/strings` | 1.117432× | 1.208842× |
| `lox/vm/trees` | 1.105330× | 1.255944× |
| `lox/vm/zoo` | 1.074188× | 1.208929× |
| `lox/vm/zoo_batch` | 1.077019× | 1.211500× |
