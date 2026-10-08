# EDA benchmark stage 1 (`eda-sch`) on mylang's new core, 2026-10-08

This run measures the stage-1 EDA port, the KiCad schematic and netlist exporter with 34 golden designs, in four languages. The four are mylang (new compiler core), Zig, Go and Rust. All four ran under one protocol, in one session, on one machine. The run also times each port's optimized program on the 34 designs, which had never been measured before.

## Summary

- **Correctness:** the new-core mylang port reproduces all 34 goldens byte for byte, in debug and in `--release` builds, and all 310 of its tests pass. The Zig, Go and Rust ports also give 34/34 and pass their own test suites.
- **Development loop after a one-line edit:**
  - check: mylang is the fastest of the four (0.22–0.28 s);
  - build: 0.71–0.82 s, level with Zig and Rust; Go is faster;
  - test: mylang is the slowest (3.8–7.1 s against 1.2–2.2 s);
  - cold build: 12.5 s (Go 5.4 s, Rust 3.3 s, Zig 133 s).
- **Against the old core:**
  - cold build 79 s → 12.5 s;
  - check 6.5 s → 0.28 s;
  - test 31 s → 4.9 s;
  - cold-build peak RSS 2.9 GiB → 295 MiB.
- **Program runtime, optimized builds over all 34 designs:**
  - mylang `--release` takes **1.82× as long as Zig ReleaseFast** (geometric mean of per-design ratios). Against the others it is 1.67× Zig ReleaseSafe, 1.65× Rust and **0.67× Go**.
  - Summed over the designs: mylang 1.59 s, Zig ReleaseFast 0.81 s, Rust 0.89 s, Go 2.18 s.
  - Per design, mylang takes 1.5× to 3.3× Zig's time. The outliers are the largest flat design and the designs with PCB data.
  - Peak memory: mylang 53 MiB, Zig 80 MiB, Rust 44 MiB, Go 70 MiB.

## Inputs and protocol

- **Compiler:** `~/.cache/mylang/bench-newcore-5a6b501d/bin/mylang`, a ReleaseFast build of mylang `main` 5a6b501d6 (sha256 prefix dce72f99ac4dd773), used as given.
- **eda-bench:**
  - Worktree `eda-bench-wt/claude-eda-bench-newcore`, branch `claude/eda-bench-newcore` at 0008fbc (local only), created from `claude/s4-eda-newcore` 7e938b6.
  - Its `zig/`, `go/`, `rust/` and `golden/` match `main` af8cf03. The 2026-09-24 runs used the same ports.
- **Harness entries:**
  - `[mylang-new]`: debug build, `mylang check`, `mylang test src --jobs 4`.
  - `[mylang-new-release]`: `build --release`.
  - The map files are symlinks to `mylang.toml`.
- **Toolchains:** zig 0.17.0-dev.1683+5ceec001b, go 1.27.0, rustc/cargo 1.98.1 (`--offline`).
- **Machine:** i7-12700H, 20 logical CPUs, `powersave` governor, shared with other agents.
- **Caches:** all caches and `TMPDIR` on disk under `<worktree>/.cache`.
- **Build, check and test timing:**
  - `bench.py time <lang> --stage 1 --repeat 3` for zig, go, rust and mylang-new, back to back, 08:00–08:28 UTC.
  - Each run held `flock bench-compile.lock` and ran under `build-slot.sh build --` on CPUs 0, 1, 4–9 and 12–19.
  - Untimed preparation was done first.
  - One-minute load average before → after each run:
    - zig 5.0 → 9.3
    - go 9.3 → 14.2
    - rust 14.2 → 4.7
    - mylang-new 4.7 → 9.2
- **Runtime:**
  - `runtime.py` ran under `flock cpu10.lock`, with the process and its children pinned to CPU 10. Its SMT sibling, CPU 11, is reserved.
  - Each design ran with `equiv`'s exact command, from the repository root.
  - One warm-up round, then 10 timed rounds, interleaved per design, with the binary order rotated each round.
  - Every output of every round was compared with the goldens.
  - Wall time runs from spawn to `wait4`. Peak RSS comes from an extra round under `/usr/bin/time -f %M`.
  - Load 1.9 → 2.1.
  - Binaries:
    - Zig `-Doptimize=ReleaseFast` and `-Doptimize=ReleaseSafe`;
    - Rust `cargo build --release`;
    - Go `go build`;
    - mylang `build --release`.

## Correctness

| check | result |
|---|---|
| `equiv mylang-new` (debug) | 34/34, 5.4 s total run time |
| `equiv mylang-new-release` | 34/34, 2.8 s |
| `equiv` zig / go / rust | 34/34 each |
| `test mylang-new` | 310 passed, 11.1 s |
| `test zig` | ok (280 per the README) |
| `test go` | ok, all packages |
| `test rust` | ok, 293 + 1 passed |
| runtime rounds | every output of every round matched the goldens, for all 5 binaries |

## Build, check and test

All times are wall seconds, the median of 3. Edit rows show leaf / hub / interface, then the median of the three. The 09-24 columns come from the earlier runs:
- `eda-bench/harness/results/time-zig-20260924T130202.json`;
- `eda-bench-wt/go-lead/.../time-go-20260924T141407.json`;
- `eda-bench-wt/rust-lead/.../time-rust-20260924T144750.json`.

The old-core column is the old core's `bench.py time` run of 2026-09-30, `codex-eda-friction-baseline-20260930/.../time-stage1-mylang-20260930T184531.json`, `--repeat 3`.

| step | mylang-new | Zig | Go | Rust | Zig 09-24 | Go 09-24 | Rust 09-24 | mylang old core |
|---|---|---|---|---|---|---|---|---|
| cold | 12.5 | 132.6 | 5.35 | 3.30 | 77.9 | 3.54 | 3.13 | 79.0 |
| clean | 1.50 | 2.08 | 1.18 | 2.95 | 1.32 | 0.82 | 3.18 | 77.4 |
| no-op | 0.01 | 0.03 | 0.07 | 0.02 | 0.02 | 0.05 | 0.02 | 0.03 |
| check | .22/.28/.28 → 0.28 | 1.19/1.15/1.34 → 1.19 | .76/.99/1.10 → 0.99 | 1.62/.55/.71 → 0.71 | 0.68 | 0.70 | 0.56 | 6.48 |
| build | .80/.82/.71 → 0.80 | 1.02/1.10/.95 → 1.02 | .55/.32/.95 → 0.55 | .94/.85/.82 → 0.85 | 0.54 | 0.41 | 0.72 | 1.08 |
| test | 3.81/7.09/4.86 → 4.86 | 2.21/2.20/2.06 → 2.20 | 1.15/1.19/1.87 → 1.19 | 1.67/1.64/1.48 → 1.64 | 1.18 | 0.88 | 1.11 | 30.6/41.4/6.77 → 30.6 |
| cold peak RSS (MiB) | 295 | 1026 | 279 | 473 | 1112 | 291 | 476 | 2920 |

- **Today's machine is slower:** today's Zig, Go and Rust loops are 1.3–1.9× slower than on 09-24, from load and the slot's 16-CPU affinity. Compare languages within today's columns.
- **Why mylang's test step trails:** after the hub edit it reran 122 of 310 tests ("122 passed, 188 cached"), and each affected test module is rebuilt and run as its own native process. A full warm run of all 310 tests takes 10–11 s.
- **mylang cold build:**
  - timed run: 12.5 s, the median of 11.2–14.2 s at load 5–11;
  - a supplementary 5× cold/clean rerun under the same lock: cold 9.86 s (9.05–10.30), clean 1.37 s.
  - An untimed breakdown of the cold build:
    - the program itself: about 1.2 s;
    - building the core runtime into an empty `XDG_CACHE_HOME`: about 3–4 s;
    - Zig's link caches in an empty `ZIG_GLOBAL_CACHE_DIR`: about 3–4 s.
  - S5's 6.84 s cold build did not empty all of these cache layers, so it is not comparable.

## Program runtime

| binary | total of 34 per-design medians | geomean vs Zig ReleaseFast | peak RSS | median-design RSS |
|---|---|---|---|---|
| Zig ReleaseFast | 0.814 s | 1.000 | 80.2 MiB | 35.0 MiB |
| Zig ReleaseSafe | 0.889 s | 1.089 | 80.2 MiB | 35.2 MiB |
| Rust `--release` | 0.890 s | 1.105 | 44.0 MiB | 9.4 MiB |
| Go `go build` | 2.185 s | 2.713 | 70.2 MiB | 20.9 MiB |
| mylang `--release` | 1.593 s | 1.823 | 53.2 MiB | 11.8 MiB |

- **mylang ÷ each:** Zig ReleaseFast 1.823, Zig ReleaseSafe 1.674, Rust 1.651, Go 0.672.
- **Per design against Zig ReleaseFast:** 1.52× to 3.28×, median 1.74×.
- **Slowest mylang designs:**
  - rds3+flat: 198 ms, 3.28× Zig
  - rds3: 113 ms, 2.03×
  - cyclops-digital-pcb: 87 ms, 2.89×
  - labstation: 84 ms, 1.84×
  - straps-base: 82 ms, 2.34×
  - cyclops-kband-pcb: 56 ms, 2.35×
- **Memory** (geometric mean of per-design RSS): mylang uses 0.42× Zig's, 1.21× Rust's and 0.58× Go's.
- **Consistency:** a first pass without the exact-RSS round agrees within 2% (1.857 against 1.823).
- **Data:** `results/runtime.json` has every design's samples, CPU time and RSS.

## Lines of code

`bench.py counts`, non-blank lines of mapped files:

| port | lines | test lines |
|---|---|---|
| Zig | 26,486 (slice 26,430) | 6,439 |
| Go | 34,589 | 7,103 |
| Rust | 31,501 | 6,853 |
| mylang | 17,965 | 4,952 |

Most of mylang's lower count is comments the port did not carry over, plus the absence of closing-bracket lines.
- **Comments:** 8% of the mylang port's lines are comments, against 24–27% in the others.
- **Remaining code:** without comments and bracket-only lines, mylang has 1.02× Zig's code lines and 0.95× its tokens.

## Caveats

- **Shared machine:**
  - Load was 2–14 and frequency is not pinned.
  - The four build-timing runs were sequential, not interleaved.
  - Runtime samples vary by a median of 14–19% per design (max−min over median). The two runtime passes agree within 2%.
- **Go is pinned to one CPU.** That gives it `GOMAXPROCS=1`, with its garbage collector on the same CPU, which costs Go more than normal use would.
- **Short runs:** designs take 2–200 ms, so start-up counts. Binary sizes: Zig 8.5 MB, Go 4.0 MB, mylang 1.8 MB, Rust 1.5 MB.
- **RSS floor in the harness:** `bench.py`'s `wait4` RSS has a floor of about 22–25 MiB, the parent's high-water mark before `exec`. The runtime table uses `/usr/bin/time` instead.
- **Relative cache path:** mylang ignores a relative `XDG_CACHE_HOME` and falls back to `~/.cache`.
- **Deviations:**
  - The harness cache is reached through a symlink.
  - `.gitignore` gains `/.cache/` and `/harness/.cache`.
  - The cold/clean supplement and the cold-build breakdown go beyond the planned protocol.

## Files

- `run.sh` (phases `prep`, `time`, `runtime`, `supplement`) and `runtime.py`.
- `results/`: `time-stage1-*.json`, the cold/clean supplement JSON, `runtime.json`, `runtime-first-pass.json`.
- `logs/`: load, time, runtime, prep-test and cold-breakdown logs.

The run was made by a benchmark agent; the coordinator wrote this file from the report the agent returned as text.
