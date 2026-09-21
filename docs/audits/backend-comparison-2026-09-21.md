# Backend comparison, 2026-09-21 — schematic reader/renderer

Re-measured on the integration branch at `8882c22a`. Two figures:

* `figures/backend-comparison-2026-09-21.png` — runtime;
* `figures/backend-incremental-2026-09-21.png` — compile and recompile cost.

## What was measured

One program, `experiments/sexpr-port/main.my`, reading and rendering schematic
S-expression netlists. It is the same benchmark the LLVM qualification used, and
the same entry the Zig reference mirrors.

| arm | backend |
| --- | --- |
| `zig` | `experiments/sexpr-port/zig-bench`, the frozen Zig reference, ReleaseFast |
| `qbe` | mylang through the bundled QBE — the default a user gets |
| `llvm-o2` | mylang through `experiments/llvm-backend/qbe_llvm.py` at `-O2` |
| `llvm-o3` | the same at `-O3` |

**Same work, checked.** All four arms printed byte-identical output on all four
workloads — including the 5,603,400-byte render — so the timings compare the
same computation and not four different ones. `measure.py` records the digest of
the timed stdout per workload and reports one distinct hash for each.

Inputs are the real EDA module repeated: 927,415 bytes and 7,419,320 bytes,
`sha256` recorded in the report. Runtime is a median of 31 rounds after 2
warmups, stdout captured, no `perf` counters. Build figures are medians of 3.

## Runtime (wall ms, median of 31)

| workload | zig | qbe | llvm-o2 | llvm-o3 | qbe ÷ zig | qbe ÷ llvm-o2 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| census 927 KB | 2.01 | 4.84 | 3.90 | 3.92 | 2.40× | 1.24× |
| render 927 KB | 2.63 | 9.98 | 7.99 | 8.00 | 3.79× | 1.25× |
| census 7.42 MB | 13.65 | 38.84 | 31.08 | 31.05 | 2.85× | 1.25× |
| render 7.42 MB | 19.10 | 88.65 | 72.67 | 72.82 | 4.64× | 1.22× |

Two things worth reading off this:

* **LLVM buys about 20–25% of runtime over QBE**, consistently across both
  workloads and both input sizes, and `-O3` is indistinguishable from `-O2`.
* **Rendering is where mylang is furthest behind Zig** (3.8× at 927 KB, 4.6× at
  7.4 MB) while the census is only 2.4–2.9× behind. Render is the
  output-heavy half, so the gap is concentrated in the formatting and printing
  path rather than in parsing.

## Build cost (median of 3, ReleaseFast guest)

| arm | cold (all caches empty) | project-cold (toolchain warm) | warm (nothing changed) | after one-constant change |
| --- | ---: | ---: | ---: | ---: |
| `qbe` | 2.91 s | 2.93 s | 0.161 s | **0.195 s** |
| `llvm-o2` | 12.16 s | 12.20 s | 0.116 s | **0.356 s** |
| `zig` | 73.93 s | 11.98 s | 0.015 s | 11.32 s |

The interesting column is the last one. An edit costs **0.20 s** through QBE and
**0.36 s** through LLVM, against **11.3 s** for the Zig reference — mylang
recompiles only the affected functions and reuses the rest, while the Zig build
recompiles and relinks a much larger closure.

The cost is on the other end: a cold mylang+LLVM build is **4.2× a cold QBE
build** (12.16 s vs 2.91 s), because the translator runs per unit and then clang
compiles each one. `-O2` and `-O3` build in the same time and run at the same
speed here, so `-O2` is the arm to use.

Both mylang arms beat the Zig reference cold by a wide margin (2.91 s and 12.16 s
against 73.93 s), which is the frontend's doing rather than the backend's: the
Zig cold figure includes compiling the whole Zig benchmark and its standard
library closure from an empty global cache.

## Method notes, including two numbers that were wrong first

The compiler under test is the **ReleaseFast** install, not the Debug one
`zig build` leaves behind by default. With the Debug compiler the same series
reports QBE cold at 4.00 s and warm at 0.91 s, which is a property of the host
compiler and not of the backend; `bench/bench_compiler_modes.py` exists in this
repository for exactly that reason. The default Debug install was restored
afterwards.

The Zig arm first reported a cold build of **0.016 s**. That is the *warm* time:
`bench.zig_series` reads its cache roots from that module's `WORK` global, and
when called from this harness that global no longer named the directories it
deletes, so every build found the prefix already installed. The harness now
spells the paths out — and resolves them absolutely, because `zig build` runs
with `cwd=zig-bench` and a relative cache root resolves against *that* directory
while the deletion resolves against the repository root. Both mistakes produced
a plausible-looking no-op rather than an error, which is why the cold figure is
now cross-checked against a standalone build (73.3 s) before being published.

## Reproducing

```console
# inputs: the real EDA module repeated to ~1 MiB and ~8 MiB
python3 experiments/llvm-backend/measure.py \
    --work .mylang-cache/bench/work --input .mylang-cache/bench/input \
    --binary zig=$PWD/.mylang-cache/bench/zb-out/bin/zig-bench \
    --arms qbe,llvm-o2,llvm-o3,zig --no-counters --rounds 31 \
    --json .mylang-cache/bench/measure.json

# build cost; install the compiler ReleaseFast first for a fair reading
python3 experiments/llvm-backend/qualify_incremental.py --rounds 3 \
    --arms qbe,llvm-o2,zig --json .mylang-cache/bench/incremental.json

/home/epentland/ai/canopy/rust-workflow/.venv/bin/python \
    experiments/llvm-backend/backend_charts.py
```

## What this does not establish

* **Not a general backend result.** The workload family is the schematic census
  and render on two input sizes. It says nothing about allocation-heavy,
  floating-point or dictionary-heavy programs.
* **Not a schematic-layout result.** It reads and renders netlists; it does not
  place or route.
* Guest builds are ReleaseFast and the compiler was ReleaseFast; the Debug
  compiler's own timings are not in these figures.
