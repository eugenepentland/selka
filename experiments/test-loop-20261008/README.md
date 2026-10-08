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
