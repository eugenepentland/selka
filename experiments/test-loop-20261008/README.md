# Test loop after an edit, 2026-10-08

Evidence for `docs/audits/test-loop-plan-2026-10-08.md` §1 and §6.

- **`probe.sh`** runs EDA's `mylang test src` in a private cache. It applies the harness's edits from `harness/maps/mylang-new.toml`, plus a comment-only edit. `warm` fills the cache; `edit KIND` times one run with the edit applied, reverts it, then times one more run.
  - Environment: `MYLANG` picks the compiler, `PROBE` the cache directory, and `JOBS` the job count (`all` omits `--jobs`).
- **`child.sh`** times the dominant file, `export_kicad_sch_test`, alone after the leaf edit.
- **`stable.sh`** checks that comment-only edits keep every receipt.
- **`matrix.sh`** runs the before/after matrix behind §6, writing `matrix.out`.
  - The two compilers each get their own warm cache.
  - It runs under `flock /run/user/1000/mylang-slots/bench-compile.lock` and `scripts/build-slot.sh build --`.

**Where it ran:**
- **EDA tree:** `eda-bench-wt/claude-eda-bench-newcore`. Its `mylang/` is identical to `claude/s4-eda-newcore` `7e938b6`.
- **Before compiler:** `~/.cache/mylang/bench-newcore-5a6b501d/bin/mylang`.
- **After compiler:** a ReleaseFast build of this branch.

**Not committed:**
- The `perf` profiles, the `strace` timelines and the timing probe of §1. They were taken during the investigation.
- Those numbers come from the session's runs, and the method is in the plan.

**T3b** (§6b of the plan):
- **`keys_differential.py`** runs seeded edits and their reverts in both key modes; the results are in `keys-{eda,lox,lang}.json`.
- **`matrix-t3b.sh`** times the items 1–3 compiler against T3b (`matrix-t3b.out`).
- **`interleave.sh`** is the 5-round interleaved check (`interleave-t3b.out`, taken under outside load).

**Item 4** (§6c of the plan):
- **`batch_differential.py`** runs a corpus with `--force` batched and with `MYLANG_TEST_ISOLATE=1`, then after each seeded break edit (`--breaks N --seed S`), and compares every verdict; the results are in `batch-{eda,lox,lang,core}.json`.
- **`interleave-batch.sh`** is the 5-round interleaved timing of T3b against item 4 (`interleave-batch.out`, load about 6).

**Fast launches, the cache sync and item 5** (§6d and §6e of the plan):
- **`interleave-spawn.sh`, `interleave-nosync.sh`, `interleave-union.sh`, `interleave-final.sh`** are the interleaved timings: item 4 against fast launch; `main` against fast launch plus no cache sync; that against item 5 (3 rounds); `main` against the final branch (5 rounds). Their `.out` files are the results.
- **`batch_differential.py --oracle MYLANG_TEST_CHILDREN`** compares in-process directory runs with one child per root (`union-{eda,lox,lang}.json`, with break edits).
- **`final-keys-*.json` and `final-batch-eda.json`** rerun the T3b and item 4 differentials on the final compiler.

**The benchmark on the merged `main`** (§6f of the plan; `bench-main/`):
- **`bench-main/run.sh prep|time|runtime`** is the morning run's protocol (`experiments/bench-newcore-20261008/eda/run.sh`) with the compiler re-pinned to a ReleaseFast build of `main` `fc31e55bb`.
- **Results:** `bench-main/results/` holds `bench.py time` for Zig, Go, Rust and mylang, and `runtime.json`. The logs are in `bench-main/logs/`.
- **`bench-main/probe-rounds.out`** shows the first-edit against repeated-edit cost.
- **`bench-main/shift.sh`** (results in `bench-main/shift.out`) separates the line shift from the edit. It is the evidence for lever 0 in §8.
