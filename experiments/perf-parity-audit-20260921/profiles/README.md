# Self-PC profiles of the retained SVG and s-expression benchmark binaries

Fresh userspace profiles of two already-built mylang executables, so the parity
audit can say where the remaining time goes. Nothing here rebuilds the compiler
or touches `src/`; every binary is taken as it was already on disk and its
output hash is checked on every run.

## Why a userspace sampler

`/proc/sys/kernel/perf_event_paranoid` is `4` on this host, so `perf` cannot
open a hardware or software event at all. The instrument is therefore the
repository's `LD_PRELOAD` SIGPROF sampler,
`experiments/svg-slowdown-20260921/sample.c`: a constructor arms `ITIMER_PROF`,
and the handler records the interrupted `RIP` relative to the main executable's
`dl_iterate_phdr` load base. Consequences, all of which the JSON restates:

- **Self PC only.** No stacks, so a callee's cost stays on the callee.
- **No hardware counters.** Sample shares are shares of *CPU time*, not cycles,
  and no wall-time claim is made from a profiled run.
- **Shared libraries are invisible.** A sample taken in `libc.so` or `ld.so` is
  counted in `samples` but has no address inside the executable, so it lands in
  `outside_main_executable`. In the LLVM builds that is where `memcpy`,
  `memset` and `malloc` go. The QBE build statically links Zig's compiler-rt,
  so the same work shows up as the `libc` class *inside* the binary instead.
- **LTO folds callees into callers.** A sample inside an inlined guest function
  is attributed to the surviving outer symbol. 70 of the SVG build's 124
  manifest functions and 33 of the s-expression build's 101 still have their
  own symbol; the rest were inlined away.
- **1 ms granularity.** Linux evaluates POSIX CPU timers on the tick, and this
  kernel is `CONFIG_HZ=1000`, so the sampler's 500 µs request yields at best one
  sample per millisecond of process CPU time.

### `sample_dense.c`

The repository sampler sets its first expiration to `500 + pid % 1500` µs of CPU
time, which is fine for a 30–80 ms run and wrong for the SVG run, which is about
2 ms of CPU: up to the first 2 ms would go unsampled, and the phases that run
last would be over-weighted by exactly the amount of the prefix that is missed.
`sample_dense.c` is a copy of that file with one changed line (marked
`AUDIT CHANGE`) putting the first expiration inside the first tick,
`20 + pid % 960` µs. Everything else — handler, hashing, output format — is
byte-identical, and the original file is untouched. The retained profiles use
the dense sampler; `svg-o3-lto-repo-sampler.json` repeats the SVG target with
the unmodified repository sampler so the difference is on the record.

## Targets

| name | binary | workload |
| --- | --- | --- |
| `svg-o3-lto` | `.tmp/svg-gap-fixes-20260921/gc-lto` | schematic renderer, `fixture` project, GC policy, LLVM -O3 + LTO, emitted with `--drop-step-checks --drop-frame-checks` |
| `sexpr-o3-lto-census` | `.tmp/perf-audit-20260921/sexpr-o3-lto` | `input8.sexp` census |
| `sexpr-o3-lto-render` | `.tmp/perf-audit-20260921/sexpr-o3-lto` | `input8.sexp --render` |
| `sexpr-qbe-census` | `.tmp/perf-audit-20260921/sexpr-qbe` | `input8.sexp` census, production QBE backend |
| `sexpr-qbe-render` | `.tmp/perf-audit-20260921/sexpr-qbe` | `input8.sexp --render`, production QBE backend |

`.tmp/svg-gap-fixes-20260921/mylang-o3-lto` does not exist; the GC/LTO/no-step-
accounting arm in that directory is `gc-lto`. The older
`.tmp/full-svg-benchmark-20260921/mylang-o3-lto` is a pre-bulk-IO build (its
`.declared` list has no `io::read_block`/`io::write_block`) and takes about 60 ms
against `gc-lto`'s 7 ms for the same fixture, so it was not profiled.

Each SVG run is checked against
`experiments/svg-gap-fixes-20260921/qualification.json`'s recorded fixture hash,
`68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`, before,
during and after profiling. Each s-expression run is checked against the md5 of
the first unprofiled run of the same workload; for `input8.sexp` those are
`aa9d2fdaca105bfb6c19d7b427b4da7d` (census) and
`f96e951ea7d9fa54c4d2ca91abd44c8a` (render), and they were stable across every
one of the 600 profiled runs. The same binaries reproduce the recorded
`input.sexp` digests `786bfad41c27a724b8ca5cc9fc87dc39` and
`f37748d59ff77d52fe027f012ed74dcf`.

## Reproduction

```bash
cd /home/epentland/ai/canopy/mylang

# SVG: 16000 runs, dense sampler (the retained svg-o3-lto.json)
python3 experiments/perf-parity-audit-20260921/profiles/profile.py \
    --count 16000 --sampler dense --target svg-o3-lto

# the four s-expression workloads, interleaved, 600 rounds each
python3 experiments/perf-parity-audit-20260921/profiles/profile.py \
    --count 600 --sampler dense \
    --target sexpr-o3-lto-census --target sexpr-o3-lto-render \
    --target sexpr-qbe-census --target sexpr-qbe-render

# the same SVG target through the unmodified repository sampler
python3 experiments/perf-parity-audit-20260921/profiles/profile.py \
    --count 8000 --sampler repo --label=-repo-sampler --target svg-o3-lto

# rewrite the JSON from raw samples already collected, without re-running
python3 experiments/perf-parity-audit-20260921/profiles/profile.py --aggregate
```

Every run is pinned with `taskset -c 6`, and `LD_PRELOAD` is injected through
`/usr/bin/env` *after* `taskset` so the sampler loads into the target and not
into `taskset` (an inherited CPU timer can otherwise fire after `exec` has reset
the handler). Targets are interleaved in a seeded shuffle (`SEED = 20260921`) so
no arm owns a particular stretch of machine state.

Runs take about 3 minutes for the SVG target and about 3 minutes for the four
s-expression workloads.

## Layout

- `profile.py` — runs and aggregates; adapted from the sampling half of
  `experiments/svg-gap-audit-20260921/audit.py`, which is left untouched.
- `sample_dense.c` — the one-line-changed copy of the repository sampler.
- `svg-o3-lto.json`, `sexpr-o3-lto-census.json`, `sexpr-o3-lto-render.json`,
  `sexpr-qbe-census.json`, `sexpr-qbe-render.json` — per-function counts, class
  totals, the 15 hottest instruction addresses and disassembly around the top 5.
- `svg-o3-lto-repo-sampler.json` — the SVG target through the unmodified
  repository sampler, for the method comparison.
- `summary.md` — the tables and what the hot addresses mean.
- Raw sample files stay under `.tmp/perf-audit-20260921/profiles/`.

## How a symbol is classified

`guest` comes from the build manifest, which maps each `myl_f_<hash>` symbol to
its source-level name. `runtime-c` and `host-provider` come from the C (and Zig)
sources the build published next to its object cache, scanned for definitions:
`nm` cannot read the LTO builds' archives, which hold LLVM bitcode, and the QBE
backend's archive is one amalgamated `runtime.o`, so neither gives a per-file
symbol map. Names the host provider object (`native-schematic.o`) defines
outrank same-named runtime statics. `libc` covers `memcpy`/`memset`/… and Zig's
`compiler_rt.*`, which only appear inside the QBE build.
