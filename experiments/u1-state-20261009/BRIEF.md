You are implementing lane **U1 ("uniqueness and state")** of mylang's runtime-parity plan, in the new compiler core. Work autonomously to the lane exit, then stop and report. A second agent is implementing lane F2 ("index facts") in parallel in another worktree. Stay inside your owned areas (below).

## Where everything is

- **Your worktree** (locked, yours alone): `/home/epentland/ai/canopy/mylang-worktrees/claude-vk-vp3`, branch `claude/u1-state`, based on `main` `35df839be`. That base is the new core with the copy-elimination waves, wave PM's check counters, and lanes F1 (aliasing and overflow facts) and S1 (substring views). The worktree was reused from lane S1, so it has warm build caches; treat anything under `.mylang-cache/` and `.tmp/` as stale.

  Do all work and builds here. Read other worktrees only.
- **Read first:**
  1. `CLAUDE.md`.
  2. The plan, `docs/audits/runtime-parity-plan-2026-10-08.md`: §8 (the finalized lanes; authoritative for your lever, exit and ownership) and §6 (gates).
  3. Wave PM's report, `experiments/parity-measure-20261008/REPORT.md`:
     - the counterfactual attribution (`unique` and `norc` columns: nbody, str_build, the Lox cells);
     - "Where mylang's extra instructions go" (nbody, str_build, the Lox VM);
     - the Lox VM step ladder and the str_build ladder;
     - PM-4 lever 7.
  4. The ladders: `experiments/parity-measure-20261008/ladders/loxvm.c` and `str_build.c`.
     - loxvm rung 3 hoists the uniqueness tests, rung 5 keeps the frame in registers, and rung 6 keeps `stack_top` in a register.
     - str_build rung 1 hoists the uniqueness test, and rung 2 keeps `len` and `cap` in registers with a typed store.
  5. The wall-time confirmations on CPU 10. Both are on branch `claude/fu-x`, not in your base:
     - `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/REPORT.md` (str_build and nbody);
     - `.../parity-confirm-20261009/lox/` (the Lox VM ladder).
  6. The integration that just landed, `experiments/fs-x-20261009/REPORT.md`, especially "Run 1 found a regression": a newly enabled loop clone made LLVM turn conditional moves into mispredicted branches. Measure the rows (below).
  7. `docs/tooling/counters.md`: `--counters` builds, `mylang cost ENTRY --counters FILE.json`, and the `unique_test` and retain/release kinds.
  8. The code:
     - `src/core/own.zig`: uniqueness tests, copy-on-write, `staticallyUnique`, `exclusiveChildren`, and the shared-row fix NEW-CORE-ROW-COW-1/-2, which you must keep;
     - `src/core/emit_llvm.zig`: list push and append, byte-buffer append, `listSet`/`listSetField`, the `is_unique` emission;
     - `src/core/promote.zig`: the existing stack promotion of lists;
     - `src/core/stores.zig`: CE2-A's dead, sunk and narrowed element stores;
     - `src/core/emit_homes.zig`.
     - The Lox VM is `ports/mylang/vm.my` (`run`, `read_byte`) and `heap.my` (`push`, `pop`, `peek`) in the Lox copy.

## The measured bounds (wall time, CPU 10, current `main`)

| target | what | wall ÷ today | today ÷ Zig ReleaseSafe |
|---|---|---:|---:|
| Lox VM step loop | ladder rung 3 (uniqueness tests hoisted); rung 5 (frame in registers); rung 6 (`stack_top` in a register) | rung 5 0.54, rung 6 0.50 of rung 0 (rung 0 is 0.95 of mylang) | 2.31 |
| nbody | `is_unique` always true (`cf.py` `unique`) | 0.78 | 1.79 → 1.33 |
| str_build | ladder rung 1 (test hoisted) 0.88; rung 2 (`len`/`cap` in registers) 0.75 of rung 0 | **rung 0 itself is 0.61 of mylang** | 1.79 |

**str_build's biggest gap is not in the ladder.** The C transcription of today's code (rung 0) already runs 39% faster than mylang, at 1.05× Zig ReleaseSafe. PM's hypotheses are realloc growth placement and L1 misses: 2.65 per thousand instructions, against 0.11 for Zig. Find that gap first.

PM's per-dispatch counters for the Lox VM: 1.6 uniqueness tests per dispatch. The frame record is spilled, with `ip` written back each dispatch, and `rt.stack_top` lives in memory.

## Your work, in this order (measure after each step)

1. **str_build's transcription gap.** Find why mylang's str_build is 39% slower than its own C transcription: the runtime's growth policy and realloc, the untyped 8-byte `llvm.memmove` that keeps `len` in memory, or alignment. Fix what is in the core or the runtime. Then hoist the per-append uniqueness test.
2. **Uniqueness tests hoisted out of loops.** When a loop updates a list or record in place, and nothing in the loop can share it, test once before the loop instead of on every update.
   - Nothing may share it through a copy, a retain, a store into another value, a call that may retain it, or a function value.
   - Copying once if shared makes it unique for the rest of the loop.
   - Targets: nbody's per-pair test, str_build's per-append test, and the Lox VM's `rt.stack`/`rt.frames` tests in the dispatch loop.
   - The shared-row rule (NEW-CORE-ROW-COW-1/-2, `exclusiveChildren`) must stay correct: an element read out and kept is a second owner.
3. **Loop-carried state in registers.** Keep scalar state that a loop reads and writes through memory in SSA values across iterations. Write it back before every exit, every call that may read it, and every trap that can be observed:
   - a list's or buffer's `len`/`cap` while appending;
   - the Lox VM's `frame` (a record local, stored back into `rt.frames`) and `rt.stack_top` (a field of the `mut` runtime record).

   Check what CE2-A's narrowed stores (`stores.zig`) already do for `frame`, and build on it.
4. **If time remains:** loxvm rung 7, ADD/LESS operands read once.

If a step can't be made safe, revert it, keep the others, and say why.

**Exit** (plan §8, U1):
- `unique_test` once per loop, not per iteration, in nbody and str_build (counting builds).
- nbody ≤ 1.35× Zig ReleaseSafe; str_build ≤ 1.0×.
- Lox VM step loop ≤ 0.85× today's cycles.
- Nothing else slower than 1.03× in instructions or cycles beyond noise. That covers every parity program, the 6 Lox cells, the 2 EDA designs and **all 46 rows at both sizes**.
- Every gate below passes.

## Ownership

**You own:**
- uniqueness-test placement and hoisting (`own.zig`'s `is_unique` decisions);
- loop-carried state promotion, and any new pass for it;
- list push and append and byte-buffer append emission;
- the runtime's growth and realloc for lists and buffers (`src/core/runtime/*.c`).

**F2 owns:**
- `facts.zig`: index and field ranges;
- bounds-check emission and the negative-index wrap in `emit_llvm.zig`'s index lowering;
- check hoisting and bounds versioning (`version.zig`).

**Shared.** F2's field facts and your promoted state meet at `rt.stack_top`. If you need a change in an F2 function, make the smallest one you can and list it in your report. Don't edit `src/` outside `src/core/`.

## Measuring (counts and cycles on your own CPU; the coordinator measures wall time on CPU 10 later)

- **Your measurement CPU is 6.** Use `taskset -c 6` and interleave the arms. PM's `experiments/parity-measure-20261008/tools/pstat.py`, `cf.py` and `ladder.py` take `--cpu`. Cycles are only comparable inside one interleaved run; instruction counts are exact.
- **Base compiler:** `~/.cache/mylang/main-35df839b/bin/mylang` (ReleaseFast, current `main`). Build yours with `zig build -Doptimize=ReleaseFast --prefix <a directory under ~/.cache/mylang/ named for your commit>`.
- **Reference binaries:**
  - parity: `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/parity/work/bin/<program>.<arm>`;
  - Lox: `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox/.tmp/lox-bench/cache/{zig-release-safe/out-release-safe,zig-release/out-release}/bin/lox` and `rust-release/target/release/lox`.

  All are read-only.
- **Lox scripts:** `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/lox/` holds `step.10000000.lox`, `fib.34.lox`, `string_equality.100000.lox`, `invocation.1500000.lox` and `method_call.500000.lox`. The tree-walker cells are `invocation.150000.lox` and `equality.300000.lox`.
- **Lox and EDA trees:**
  - Lox: copy `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox` into your `.mylang-cache/lox`, without its `.tmp/` and `results/`, then create `.tmp/lox-bench/tmp` in your worktree root.
  - EDA: copy `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang` into `.mylang-cache/eda-src`.
  - Lane F1's tools at `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/f1-facts-20261009/tools/` (`parity.py`, `checks.py`, `lane.py`) build, count and measure all three corpora; copy and adapt them.
- **Rows:**
  1. Build with `python3 experiments/new-core-s4-20261006/integration/measure_all46.py --build-only --mylang <base compiler> --core <your compiler> --bin <a dir in your worktree>`, under `scripts/build-slot.sh build`.
  2. Measure with `python3 /home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/tools/rows_perf.py --bin <that dir> --worktree <your worktree> --cpu 6 --json <out>`.
  3. Explain every row it flags: a real cost, or layout (same instructions, different branch behaviour).

## Gates (every one must pass on your final commit; run them before declaring the exit)

A wrong answer is never acceptable.
1. **Build and repository gates:** `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
2. **Conformance** against the frozen S5 references, debug and release, with leak and fact verification: **1518/0/0**.
   - Run `python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence <a fresh directory inside experiments/>`.
   - Never reuse an evidence basename.
   - Move that evidence under your evidence directory afterwards.
3. **Frozen fuzz 9×50:** `experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new <a copy of your Debug zig-out/bin/mylang> --cases 50 --evidence <dir below experiments/> --jobs 3`. All 9 kinds must PASS. It needs a clean tracked tree.
4. **Lox:**
   - `python3 harness/lox_bench.py conformance --binary <your plain release lox binary> --engine both --stress -j 4` from your Lox copy: **974/974**;
   - the port's own tests, `mylang test .` in `ports/mylang`: **65/65**.
5. **EDA:**
   - all 34 cases' outputs byte-identical to the goldens;
   - `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir <yours>`: **310/310**.
6. **Parity:** every program's output equals its `.expected`.
7. **Counting:** counting on and off give the same output on every program you count. Counts must stay exact; the conformance leak check catches a missed or double release.

**Every transformation needs regression tests,** including adversarial ones:
- **Hoisted tests:**
  - an alias created inside the loop (a copy, `kept = xs[i]`, an append of the list to another list, a store into a record field, a call that retains);
  - an alias created before the loop and dropped inside it;
  - the list replaced or rebound in the loop;
  - nested lists and the shared-row shapes from `test/core/row_cow.my`;
  - function values and recursion.
- **Promoted state:**
  - a call inside the loop that reads or writes the promoted field (through `mut`, or by reading the record);
  - a trap inside the loop, where the state must be observable as Python would leave it;
  - `break`, `continue` and early return;
  - the record copied inside the loop;
  - an exception-free path where the field is never written.
- **Growth:** appending to an empty buffer, crossing capacity boundaries, and a shared buffer appended to (copy-on-write).

Put them in `test/core/*.my` and/or the core's Zig tests.

**Guardian rules:**
- every behavioural line under `src/` needs a test with `// spec: TAG` and a `SPEC.md` bullet; use `NEW-CORE-U1-*`;
- at most 7 struct fields and 6 parameters;
- `///` on every `pub` declaration;
- no import cycles; new files reachable from `guardian.toml` roots;
- no type-size ratchet growth.

## Rules

- **Builds** go through `scripts/build-slot.sh` (see `CLAUDE.md`). The machine is shared with other agents, with at most four build-heavy processes in total.
- **CPUs:**
  - never run heavy work on CPUs 2, 3, 10 or 11 (use `taskset -c 0,1,4-9,12-19` for runs);
  - take perf measurements only on CPU 6;
  - never take wall time on CPU 10.
- **Caches and `TMPDIR`** stay on disk inside your worktree, never in `/tmp`. Delete scratch you no longer need.
- **Never end your turn to wait for background work.** The harness treats a turn that ends while you wait as the end of your run. Run long steps in the foreground, with a timeout of up to 600000 ms, and split anything longer into parts.
- **Never kill processes by pattern** (`pkill -f`). Kill only PIDs you started.
- **Evidence** goes in `experiments/u1-state-20261009/`: logs, before/after JSON (gzipped if large), and scripts. Keep it under 10 MB.
- **Commits:** one per step on `claude/u1-state`, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree or branch.
- **Stop and report** if:
  - a wrong answer cannot be fixed;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside your change;
  - you would need more than a minimal change in F2's areas.
- **Your final reply** must contain the full report:
  - each step's commit;
  - what made str_build slower than its transcription, and what fixed it;
  - why each hoisted test and each promoted value is safe;
  - before and after instructions, cycles and counters (`unique_test`, retains and releases);
  - ratios against Zig ReleaseSafe for nbody and str_build;
  - the Lox step cell against today;
  - the no-regression table: parity, Lox, EDA and the 46 rows;
  - every gate receipt;
  - any touches in F2's areas;
  - remaining limits.

  Also try to write `experiments/u1-state-20261009/REPORT.md`. If the tool refuses the file, the reply is enough.
