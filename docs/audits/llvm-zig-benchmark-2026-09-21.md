# Fresh LLVM O3 versus Zig benchmark

21 September 2026. **Current mylang LLVM O3 takes 1.98–3.16 times as long as
Zig ReleaseFast on the matched EDA S-expression parser/printer benchmark.**
Full LTO does not materially close this gap.

This measures `experiments/sexpr-port`, which implements the EDA reader and
canonical printer. There is no matching Zig implementation of the pilot's
complete three-input validation, placement, routing and SVG contract. These
numbers therefore do not compare the full schematic SVG tool, and the prior
47% SVG improvement must not be applied to these results.

## Runtime

Median elapsed milliseconds, 31 randomized interleaved rounds after three
warmups, all processes pinned to CPU 6:

| Input | Work | Zig ReleaseFast | mylang LLVM O3 | mylang LLVM O3 + LTO | O3 / Zig |
| --- | --- | ---: | ---: | ---: | ---: |
| 927,415 bytes | Parse + census | 1.84 | 3.62 | 3.54 | 1.98× |
| 927,415 bytes | Parse + canonical print | 2.32 | 6.30 | 6.25 | 2.71× |
| 7,419,320 bytes | Parse + census | 13.12 | 29.21 | 29.46 | 2.23× |
| 7,419,320 bytes | Parse + canonical print | 16.50 | 52.14 | 52.45 | 3.16× |

The paired-bootstrap 95% intervals for the O3/Zig ratios are respectively
1.91–2.06, 2.60–2.79, 2.22–2.24 and 3.14–3.18. They describe variation within
this batch, not uncertainty across other machines or workloads. All timing
includes process launch, file reading, parsing, the selected work, output and
shutdown. Compilation is excluded. Timed output goes to `/dev/null`, with warm
file caches. Hardware counters were not collected (`perf_event_paranoid=4`).

The secondary Zig ReleaseSafe comparator measured 2.06, 2.53, 14.24 and 18.19 ms
in the same four cases. On the larger input, mylang O3 therefore still takes
2.05× as long for parse/census and 2.87× for parse/print compared with ReleaseSafe.

## Memory

Separate five-run samples of maximum resident memory on the 7,419,320-byte input:

| Work | Zig ReleaseFast | mylang LLVM O3 | mylang LLVM O3 + LTO |
| --- | ---: | ---: | ---: |
| Parse + census | 16.53 MiB | 29.32 MiB | 29.28 MiB |
| Parse + canonical print | 22.00 MiB | 54.20 MiB | 54.15 MiB |

These are median process peaks from `/usr/bin/time`, including code, runtime and
data; they are not allocation counts or live-heap sizes. The comparison includes
the implementations' memory policies: Zig uses an arena; mylang uses its ordinary
collecting GC. It does not isolate backend code generation from language/runtime
costs. The printer workload has the largest measured runtime and memory gap;
these measurements alone do not establish which functions cause it.

## Configuration and correctness

Both sides were freshly compiled with pinned Zig `0.17.0-dev.1683+5ceec001b`,
using native default targets and no explicit CPU feature override. The vendored
Zig source closure is byte-identical to the sibling EDA checkout at
`2a8d901174255ff8fa3e4840acd35a041e39c9a8`.

Mylang uses the current dirty working tree's installed ReleaseFast compiler,
the new `--backend llvm --llvm-opt 3` path and an optional `--lto` arm. Each build
compiled 101 functions from a fresh object cache and compiled its matching C
runtime from source. Bounds/overflow checks and ordinary collecting GC remain;
the normal ReleaseFast executable policy omits step/frame accounting. No custom
arena, header removal, unchecked-IR rewrite or GC-root removal was used. Zig
ReleaseFast disables its safety checks; the secondary ReleaseSafe build retains
them.

The 927,415-byte input is the real 185,482-byte
`poe-pd-flyback-tps23757.sexp` plus a newline, repeated five times; the larger input
repeats that result eight times. Outputs contain 15,105 and 120,840 nodes.

- All four benchmark workloads have byte-identical census/render output across
  all four implementations, checked before and after timing. Status and stderr
  are checked on every timed invocation.
- All 17 retained rendering goldens pass for all four arms: 136 additional
  render/census executions. Auxiliary census fields agree numerically; integral
  float sums can spell `0` in Zig and `0.0` in mylang. That spelling difference
  does not occur on either timed input.
- This is ordinary execution, not GC-stress qualification. The pre-existing
  S-expression printer GC-stress failures remain documented in the
  [implementation report](schematic-llvm-o3-implementation-2026-09-21.md).

Raw samples, source/binary hashes, build receipts, memory samples, qualification
and reproduction commands are retained in
[`experiments/zig-parity-20260921`](../../experiments/zig-parity-20260921/README.md).
No production source was changed for this benchmark and no Guardian gate was
exercised.
