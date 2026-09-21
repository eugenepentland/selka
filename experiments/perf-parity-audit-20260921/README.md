# Performance parity audit, 2026-09-21: evidence

Evidence for [`docs/audits/performance-parity-audit-2026-09-21.md`](../../docs/audits/performance-parity-audit-2026-09-21.md).
Nothing under `src/` was changed; binaries and caches live under the gitignored
`.tmp/perf-audit-20260921/`.

| directory | contents |
|---|---|
| `micro/` | eleven matched mylang/Zig kernels, `run.py` (builds every arm, checks stdout identity, times interleaved), `results.json`, `results.md` with per-kernel matching notes |
| `profiles/` | `profile.py` (adapted from `experiments/svg-gap-audit-20260921`), `sample_dense.c` (the repository sampler with an immediate first tick), per-function JSON for the schematic and parser binaries, `summary.md` |
| `probes/` | `bench.py` (interleaved timing helper), `fib.my`/`fib.zig`, `mulloop.my`/`mulloop.zig`, `empty.my`/`empty.zig`, `dict_scaling.my` (substitute `K`), `replace_loop.my`, and the IL patchers `patch_frames.py` and `patch_mul.py` |
| `results/` | raw samples: `sexpr-prelim-loaded.json` (parser batch, loaded machine), `fib-prelim-loaded.json`, `mulloop-prelim-loaded.json`, `startup.json` (loaded), `dict-scaling.json`, `replace-loop.json`, `build-times.txt`; `quiet/{sexpr,fib,mul,startup}.json` are the quiet re-runs the report quotes |

## Reproduce

All commands from the repository root with a built `zig-out/bin/mylang`.

Parser arms and batch (the Zig comparators are the ones
`experiments/zig-parity-20260921` built; inputs from `.tmp/runtime-audit-20260919`):

```sh
zig-out/bin/mylang build experiments/sexpr-port/main.my --project --mode ReleaseFast --keep-symbols \
  --cache-dir .tmp/perf-audit-20260921/cache-qbe -o .tmp/perf-audit-20260921/sexpr-qbe
zig-out/bin/mylang build experiments/sexpr-port/main.my --project --mode ReleaseFast --keep-symbols \
  --backend llvm --llvm-opt 3 --cache-dir .tmp/perf-audit-20260921/cache-llvm -o .tmp/perf-audit-20260921/sexpr-o3
zig-out/bin/mylang build experiments/sexpr-port/main.my --project --mode ReleaseFast --keep-symbols \
  --backend llvm --llvm-opt 3 --lto --cache-dir .tmp/perf-audit-20260921/cache-llvm -o .tmp/perf-audit-20260921/sexpr-o3-lto
python3 experiments/llvm-backend/measure.py --work .tmp/perf-audit-20260921/measure \
  --input .tmp/runtime-audit-20260919 --rounds 21 --warmups 3 --cpu 6 --sink null --no-counters \
  --binary zig=.tmp/zig-parity-20260921/install/bin/zig-bench \
  --binary zig-safe=.tmp/zig-parity-20260921/install-safe/bin/zig-bench \
  --binary qbe=.tmp/perf-audit-20260921/sexpr-qbe --binary o3=.tmp/perf-audit-20260921/sexpr-o3 \
  --binary o3-lto=.tmp/perf-audit-20260921/sexpr-o3-lto --reference zig --json OUT.json
```

Counterfactual arms (diagnostic: a patched binary cannot report traps):

```sh
D=.tmp/perf-audit-20260921/frame
zig-out/bin/mylang emit-qbe --drop-step-checks --drop-frame-checks $D/fib.my > $D/fib.json
python3 experiments/perf-parity-audit-20260921/probes/patch_frames.py $D/fib.json $D/fib-FT.json FT
zig-out/bin/mylang build $D/fib.my --manifest-file=$PWD/$D/fib-FT.json -o $D/fib-o3-lto-FT \
  --mode ReleaseFast --backend llvm --llvm-opt 3 --lto --cache-dir $D/cache-llvm-FT
python3 experiments/perf-parity-audit-20260921/probes/bench.py --cpu 8 --rounds 15 \
  zig=$D/fib-zig qbe=$D/fib-qbe o3-lto=$D/fib-o3-lto o3-lto-FT=$D/fib-o3-lto-FT
```

`patch_frames.py` modes: `F` removes the frame record link/unlink and the stack
floor check, `T` the sticky trap test after calls, `P` the position stores.
`patch_mul.py` removes the 128-bit overflow computation after each 64-bit `mul`.

Micro suite and profiles: see `micro/README.md` and `profiles/README.md`.

Build-time probe (`results/build-times.txt`): copy `experiments/sexpr-port` to a
scratch directory, build cold and unchanged on each backend, insert one
statement into `sexpr/printer.my`, rebuild with `--report`.

## Machine state

i7-12700H, Linux, `perf_event_paranoid=4` (no hardware counters). The first
pass of every batch ran while other sessions executed `zig build test` and this
audit's subagents built their arms (load average 7–20); `results/*-loaded.json`
keep those samples. The parser, fib, multiply and start-up batches were re-run at
load average 2 (`results/quiet/`), and the report quotes those. The micro suite,
dictionary and replace-loop probes have only the loaded pass; the report quotes
their within-batch ratios only.
