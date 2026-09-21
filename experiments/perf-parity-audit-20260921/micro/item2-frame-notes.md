# Item 2 — taking the frame protocol off the call path (working notes)

Branch `perf/roadmap-2-frame-off-call-path`, based on `95f3c080`.

## Baseline (`fib`, `--only fib`, 3 warmups + 15 rounds, CPU 6)

Command:

```bash
export ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-cache-global
python3 experiments/perf-parity-audit-20260921/micro/run.py \
  --only fib --rounds 15 --warmups 3 --cpu 6 \
  --work .tmp/rm2/baseline-work \
  --json .tmp/rm2/results-baseline.json \
  --markdown .tmp/rm2/results-baseline.md
```

Medians (ms), `fib(36)`, 29,860,703 calls:

| arm | median | ratio to `zig-fast` |
| --- | ---: | ---: |
| zig-fast | 35.0 | 1.00× |
| zig-safe | 66.4 | 1.90× |
| mylang-qbe | 132.8 | 3.80× |
| mylang-o3 | 123.0 | 3.52× |
| mylang-o3-lto | 132.8 | 3.80× |

The `ReleaseFast` build drops step accounting and frame accounting
(`src/qbe_build.zig:205-216`), so this is the fast arm the roadmap targets:
a 32-byte native frame record linked through `ctx->active_frame`, a floor
check per non-leaf function, a `ctx->trap` read + branch after every call, and
a position store before each call site (see `mylang emit-qbe
--drop-debug --drop-step-checks --drop-frame-checks fib.my`).

The audit's headline counterfactual (LLVM O3+LTO 17.64 ms -> 11.82 ms without
the record and floor check -> 10.46 ms also without the sticky test) is
`38.7%` / `8.0%` of the as-compiled time. Reproduced here at the same order of
magnitude by scaling to the faster machine would be ~9-10 ms off the LLVM arm.

Absolute times here are ~6x the audit's because this host is shared (load
average ~6 on 20 CPUs) and the kernel is `fib(36)`, not the audit's `fib(32)`.
Ratios are the metric; every arm is pinned to one CPU and interleaved.
