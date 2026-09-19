# Speed benchmark — mylang port vs the Zig reader

`bench.py` measures compile and execution speed for both implementations and
writes `evidence/bench.json`; `bench_charts.py` renders
`evidence/sexpr-speed-comparison.png`. Reproduction:

```sh
python3 experiments/sexpr-port/bench/bench.py            # ~15 min: 3 compile reps, 25 runs
python3 experiments/sexpr-port/bench/bench.py --quick    # 1 rep, 5 runs
/home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/sexpr-port/bench/bench_charts.py
```

## What is measured

| measurement | definition |
| --- | --- |
| `cold` | fresh project cache **and** fresh toolchain cache — the Zig side gets its own `ZIG_GLOBAL_CACHE_DIR`, so standard-library compilation is charged. |
| `cold_local` | fresh project cache, warm toolchain cache — what a developer sees on a clean checkout. |
| `warm` | nothing changed; both caches valid. |
| `tweak` | `short_list_max_width` 72 → 73 in the printer, rebuilt warm, then reverted (bytes verified). |
| `execute stats` | run the produced binary on the ~1 MiB input and print the node census. |
| `execute render` | same, printing the canonical rendering to `/dev/null`. |

Every compile measurement is the median of `--reps` repetitions; every
execution measurement is the median of `--runs` reps pinned with `taskset` to
one CPU. Raw samples are kept in `bench.json` so the spread is auditable.

## Chart scales

Every axis in both figures is **linear**. The raw values span four orders of
magnitude (0.016 s to 79 s), which a single linear axis cannot show, so the
panels are grouped by magnitude instead of compressed with a log axis: cold
builds, project-cold builds, and warm/incremental builds each get their own
linear panel with a fitted range, and Zig and mylang execution each get their
own. The summary panel plots a speed factor that is always >= 1 (colour marks
the winner) so it is readable on a linear axis too.

## Fairness notes

* **Same toolchain.** Both sides use the `zig` on `PATH`
  (`0.17.0-dev.1683+5ceec001b`), which is also the version mylang pins.
* **Trimmed Zig project.** `zig-bench/` vendors only the sexpr closure; building
  the whole EDA binary would charge the Zig reader for ~200k unrelated lines.
* **Same input, same work.** One ~1 MiB file (the real 185 kB
  `poe-pd-flyback-tps23757` module repeated), parsed by both, then either walked
  once or rendered once.
* **Modes differ by design.** Zig has `ReleaseFast` and `ReleaseSafe`; mylang's
  guest build offers only `ReleaseFast` and `Debug` (`--mode ReleaseSafe` is
  rejected), so the fourth point is mylang `Debug`.
* **Toolchain caches are private** to the run (`/tmp/sexpr-bench`), so a cold
  build cannot silently hit a warm shared cache, and the run does not pollute
  the user's own cache.
* Timings are wall-clock on a shared 20-core machine; `bench.json` records the
  load average at the start, and execution runs are pinned to one CPU. Treat
  sub-10% differences as noise.
