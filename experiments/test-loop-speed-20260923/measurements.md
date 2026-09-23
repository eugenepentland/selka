# Test-loop measurements, 2026-09-23 (i7-12700H, 20 threads, 30 GB, shared with other agents)

Every run: Debug compiler, private `ZIG_LOCAL_CACHE_DIR`, the machine-wide gate slot,
`/usr/bin/time -v`, `sampler.py` for a step timeline, `rsssampler.py` for per-step
memory. Load is the 1-minute load average at start → end.

## `zig build test`, before (`e54d1bd7`) and after (`devloop/test-loop`)

| run | wall | user CPU | load |
|---|---:|---:|---|
| before (a) clean cache | 253 s | 1185 s | 1.5 → 14.3 |
| before (b) unchanged rerun | 125 s | 719 s | 9.1 → 10.6 |
| before (b) unchanged, under `strace -f` | 145 s | | 15 → 14 |
| before (c) `src/sema.zig` + comment line | 135 s | 774 s | 2.1 → 6.4 |
| before (c) `src/qbe.zig` + comment line | 143 s | 829 s | 10.4 → 6.9 |
| before (c) `src/native_text.c` + comment line | 196 s | 1171 s | 6.9 → 10.5 |
| before (c) `tests/lang/python_core.my` + comment line | 150 s | 984 s | 10.5 → 8.5 |
| before (c) `docs/io.md` + paragraph | 134 s | 684 s | 8.5 → 7.8 |
| after (a) clean cache | 182 s | 1459 s | 10.0 → 21.3 |
| after (a) clean cache, final gate after merging `d18304c1` | 199 s | | 9.2 → 17.2 |
| after (b) unchanged rerun | 5.7 s / 4.7 s | 25 s / 21 s | 20.5 → 8.4, 8.0 → 7.5 |
| after (c) `src/sema.zig` | 114 s | 1002 s | 6.7 → 15.7 |
| after (c) `src/qbe.zig` | 112 s | 955 s | 14.7 → 15.3 |
| after (c) `src/native_text.c` | 161 s | 1438 s | 15.3 → 19.4 |
| after (c) `tests/lang/python_core.my` | 5.1 s | 24 s | 18.0 → 16.8 |
| after (c) `docs/io.md` | 27 s | 339 s | 16.8 → 21.6 |

Every (c) edit is a new line with a unique comment, applied to a warm cache and
reverted afterwards, so each run recompiles exactly what that edit changes.

## Per step, before, clean cache

unit-root compile 34 s (81 s under load 15+) · unit shards 26–60 s · CLI shards
18–31 s · schematic root 50 s · `native_boundary_matrix.py --compiler` 52 s ·
`idiom_probes.py --compiler` 41 s · `mylang test tests/lang --gc-stress` 34 s ·
`mylang doctest .` 20 s · `test_native_memory.py` 12 s · runtime identity 6 s ·
LLVM adapter unit tests 4 s · parser hints 4 s · emit-runtime prebuild 8 s ·
Guardian 1 s · every other step under 1 s.

## Drivers, serial → parallel (same compiler, same load window)

| driver | before | after |
|---|---:|---:|
| `native_boundary_matrix.py --compiler`, warm object cache | 58 s | 9.8 s |
| same, cold | | 15.2 s |
| `idiom_probes.py --compiler`, cold caches | 30.1 s (`--jobs 1`) | 5.6 s |
| `test_native_memory.py` | 10.5 s (`MYLANG_JOBS=1`) | 2.4 s |

## Memory: declared vs used

Peak summed RSS of each step's process tree, clean cache (`rsssampler.py`):
`tests/lang` 2.4 G · doctest 2.3 G (2.8 G standalone) · `tests/guest` 1.3 G ·
boundary 1.3–1.45 G · unit shards 0.28–1.24 G (largest single process 570 M) · CLI
shards 1.1–1.2 G (largest single process 141 M) · schematic root 1.24 G · QBE
compile 1.06 G · emit-runtime 1.0 G · idioms 0.69 G · C suites 0.55 G · parser
hints 0.47 G · Guardian 0.27 G · adapter 0.21 G · self-tests under 60 M.
The whole `zig build test` never exceeded 5.8 G at once.

Full test rerun (`-Dtest-rerun=true`, compiles cached), same loaded window:
old ceilings 136 s; `--maxrss 100G` 81 s; new ceilings 98 s. Later, at load 13–25:
new ceilings 81 s with 12 shards, 75 s with `-Dtest-shards=8`.

## Dispatch serialisation

Sema edit with `--maxrss 60G`: the unit root finished compiling at 54.9 s, 3 of its
12 shards started at 55.9 s and the other 9 at 94.1 s, when the first of those
finished. `std.Io.Threaded` (lib/std/Io/Threaded.zig, `groupAsync`) runs a task
eagerly in the calling thread once `async_limit` (cores − 1) tasks are busy, and
the build runner dispatches a finished step's dependants in a loop in that thread.

## Inner loop, `python3 scripts/affected_tests.py --base HEAD` (load 6–10)

| edit | selection | wall |
|---|---|---:|
| `src/sema.zig` | compiler + 8 guest smoke areas | 13.9 s |
| `src/qbe.zig` | 3 Zig filters → 119 tests over 8 shards (50.6 s), smoke | 57.3 s |
| `src/native_text.c` | native memory + heap suites (15.4 s), 5 text areas | 24.6 s |
| `tests/lang/python_core.my` | that file | 1.0 s |
| `docs/io.md` | its doctest + doc-coverage | 1.9 s |

Focused `qbe_test.test.` after a `src/qbe.zig` edit: `test-units` (one process)
80–92 s; `-fincremental` 80 s; `test-units-sharded -Dtest-shards=8` 45 s.

## Final gate (clean cache, after merging `d18304c1`), against `split-*.log`

| step | this branch | base | gate_diff |
|---|---|---|---|
| `test` | 88/88 steps, 1809/20199 tests, 199 s | 83/83 steps, 1809/20199 | 0 new |
| `test-qbe` | 50/50 steps, 322/322 tests, 62 s | 50/50, 322/322 | 0 new |
| `test-qbe-build` | 32/32 | 32/32 | 0 new |
| `test-byte-io` | 28/28 | 28/28 | 0 new |
| `test-schematic` | 29/29 | 29/29 | 0 new |
| `fmt-check` | 2/2 | 2/2 | 0 new |
