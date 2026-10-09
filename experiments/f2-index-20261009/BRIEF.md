You are implementing lane **F2 ("index facts")** of mylang's runtime-parity plan, in the new compiler core. Work autonomously to the lane exit, then stop and report. A second agent is implementing lane U1 ("uniqueness and state") in parallel in another worktree. Stay inside your owned areas (below).

## Where everything is

- **Your worktree** (locked, yours alone): `/home/epentland/ai/canopy/mylang-worktrees/claude-ce2-results`, branch `claude/f2-index`, based on `main` `35df839be`. That base is the new core with the copy-elimination waves, wave PM's check counters, and lanes F1 (aliasing and overflow facts) and S1 (substring views). The worktree was reused from lane F1, so it has warm build caches; treat anything under `.mylang-cache/` and `.tmp/` as stale.

  Do all work and builds here. Read other worktrees only.
- **Read first:**
  1. `CLAUDE.md`.
  2. The plan, `docs/audits/runtime-parity-plan-2026-10-08.md`: §8 (the finalized lanes; authoritative for your lever, exit and ownership) and §6 (gates).
  3. Wave PM's report, `experiments/parity-measure-20261008/REPORT.md`: the counterfactual attribution (the Lox rows, sort_quick, sieve), "Where mylang's extra instructions go" (the Lox VM, sort_quick, sieve), the Lox VM step ladder, and PM-4 lever 6.
  4. The ladder itself, `experiments/parity-measure-20261008/ladders/loxvm.c`. Rung 0 transcribes what mylang emits per dispatch; rung 2 removes the index checks and the negative-index wraps.
  5. The integration that just landed, `experiments/fs-x-20261009/REPORT.md`, especially "Run 1 found a regression": a newly enabled loop clone made LLVM turn conditional moves into mispredicted branches (binary_search 3.7× slower). The fix, NEW-CORE-FSX-VERSION-1 in `src/core/version.zig`, versions a reduction loop only when its body makes no call and holds no other loop.
  6. Lane F1's report, `experiments/f1-facts-20261009/REPORT.md`: what `facts.zig` now proves, and "Remaining limits" (sieve's leftover checks are yours).
  7. The Lox VM wall-time confirmation, `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/lox/` (on branch `claude/fu-x`, not in your base).
  8. `docs/tooling/counters.md`: `--counters` builds and `mylang cost ENTRY --counters FILE.json`, with the `bounds_check` and `overflow_check` kinds.
  9. The code:
     - `src/core/facts.zig`: intervals, list facts, counted loops, `mark`, `Sabotage`;
     - `src/core/version.zig`: unswitching and versioning;
     - `src/core/emit_llvm.zig`: index lowering in `listGet`/`listSet`/`listSetField`, the negative-index wrap, `trapBegin`;
     - `src/core/passes.zig`.
     - The Lox VM is `ports/mylang/vm.my` and `heap.my` in the Lox copy: `read_byte`, `push`, `pop`, `peek`, `GET_LOCAL`, `SET_LOCAL`.

## The measured bounds

**Lox VM per dispatch today** (PM's counters): about 7 bounds checks, 7 overflow checks and 1.6 uniqueness tests.
- Every index the core cannot prove ≥ 0 pays Python's negative-index wrap as well as its check.
- `stack_top`, `ip`, `base` and `frame_count` are record fields, so today's SSA facts know nothing about them.

**Cycles, on current `main`, CPU 8** (`cf.py`, `bounds` and `checks` = those traps never taken):

| cell | bounds | checks |
|---|---:|---:|
| vm/string_equality | **0.71** | 0.70 |
| vm/fib | 0.86 | 0.82 |
| vm/invocation | 0.87 | 0.80 |
| step loop | 0.84 | 0.97 (non-monotonic; see PM) |

Ladder rung 2 (index checks and wraps removed) is 0.744 of rung 0. sort_quick: bounds 0.93 (PM). sieve: the `flags[j]` checks (46 M) and the `for flag in flags` checks (20 M) remain after F1.

**Positions today, CPU 10 wall time ÷ Zig ReleaseSafe:**
- sort_quick 1.10 (225 against 205 ms);
- sieve 0.86;
- Lox VM about 1.96 (geomean of 13 cells).

## Your work, in this order (measure after each step)

1. **No negative-index wrap for an index proven ≥ 0, and fewer bounds checks for indexes proven below the length.**
   - Extend what the facts prove for list and bytes indexes: an index derived from a value already proven in range of the same SSA list, `for x in xs` iteration indexes, `j <= n` against a list built with length `n + 1`, and counted loops over `len(xs)` that do not change `xs`'s length.
   - Start with sieve (`flags[j]`, `for flag in flags`) and the obvious loop shapes in sort_quick.
2. **Field ranges.** A whole-program, per-field interval for integer record fields: the hull of every value stored to that field, from construction, field stores, `mut` writes through callees, and element stores of records.
   - It is sound only if every write is seen. Records are values, so a write is either in the module or impossible. Indirect calls and `extern` functions cannot write guest record fields; check this, and say so in the report.
   - With it, `rt.stack_top >= 0`, `frame.ip >= 0`, `frame.base >= 0` and `rt.frame_count >= 1` become facts. The wraps go, and `stack_top - 1 - d` with `d >= 0` from a byte becomes a non-negative index whose only remaining check is the upper bound.
   - Every field fact must be checkable by verify mode (`--verify-facts` asserts it at each load) and must have a `Sabotage` probe that verify catches.
3. **Check hoisting and loop versioning for bounds**, where a loop indexes a list whose length does not change in the loop.
   - Prefer hoisting a single range check before the loop, which needs no clone, over versioning.
   - When a clone is unavoidable, follow NEW-CORE-FSX-VERSION-1's lesson: clone only small, flat bodies. Measure the rows (below) before and after.
4. **If time remains:** the Lox VM's remaining per-dispatch checks. Report which ones are left and why.

If a step can't be made sound, revert it, keep the others, and say why.

**Exit** (plan §8, F2):
- Lox VM bounds checks ≤ 2 per dispatch (counting build of the step cell; about 7 today).
- vm/string_equality ≤ 0.80× today's cycles.
- sort_quick ≤ 1.0× Zig ReleaseSafe.
- No negative-index wrap on an index proven ≥ 0.
- Nothing else slower than 1.03× in instructions or cycles beyond noise. That covers every parity program, the 6 Lox cells, the 2 EDA designs and **all 46 rows at both sizes**.
- Every gate below passes.

## Ownership

**You own:**
- `facts.zig`: index and field facts;
- bounds-check emission and the negative-index wrap in `emit_llvm.zig`'s index lowering;
- check hoisting and bounds versioning: `version.zig` and any new pass you add.

**U1 owns:**
- uniqueness-test placement (`own.zig`'s `is_unique` decisions and their hoisting);
- loop-carried state promotion (keeping `len`/`cap`, the VM frame and `rt.stack_top` in registers across iterations), and any new pass for it;
- list append and push emission;
- str_build's buffer growth.

**Shared.** U1's promoted state and your field facts meet at `rt.stack_top`. If you need a change in a U1 function, make the smallest one you can and list it in your report. Don't edit `src/` outside `src/core/`.

## Measuring (counts and cycles on your own CPU; the coordinator measures wall time on CPU 10 later)

- **Your measurement CPU is 8.** Use `taskset -c 8` and interleave the arms. PM's `experiments/parity-measure-20261008/tools/pstat.py` and `cf.py` take `--cpu`. Cycles are only comparable inside one interleaved run; instruction counts are exact.
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
  2. Measure with `python3 /home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/tools/rows_perf.py --bin <that dir> --worktree <your worktree> --cpu 8 --json <out>`.
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
7. **Counting:** counting on and off give the same output on every program you count.

**Every transformation needs regression tests,** including adversarial ones. Each must keep the right answer and trap where it must:
- negative indexes that must still wrap;
- an index that is ≥ 0 on one path only;
- a list whose length changes in the loop (append, pop, rebinding, a `mut` callee);
- a field written negative somewhere far away, through a `mut` callee, an element store, or a record copied and then changed;
- field facts across recursion and across function values;
- out-of-range indexes that must still trap with the same trap and location;
- `break`, `continue` and early return around hoisted checks;
- a `Sabotage` probe for each new fact kind, caught by verify.

Put them in `test/core/*.my` and/or the core's Zig tests.

**Guardian rules:**
- every behavioural line under `src/` needs a test with `// spec: TAG` and a `SPEC.md` bullet; use `NEW-CORE-F2-*`;
- at most 7 struct fields and 6 parameters;
- `///` on every `pub` declaration;
- no import cycles; new files reachable from `guardian.toml` roots;
- no type-size ratchet growth.

## Rules

- **Builds** go through `scripts/build-slot.sh` (see `CLAUDE.md`). The machine is shared with other agents, with at most four build-heavy processes in total.
- **CPUs:**
  - never run heavy work on CPUs 2, 3, 10 or 11 (use `taskset -c 0,1,4-9,12-19` for runs);
  - take perf measurements only on CPU 8;
  - never take wall time on CPU 10.
- **Caches and `TMPDIR`** stay on disk inside your worktree, never in `/tmp`. Delete scratch you no longer need.
- **Never end your turn to wait for background work.** The harness treats a turn that ends while you wait as the end of your run. Run long steps in the foreground, with a timeout of up to 600000 ms, and split anything longer into parts.
- **Never kill processes by pattern** (`pkill -f`). Kill only PIDs you started.
- **Evidence** goes in `experiments/f2-index-20261009/`: logs, before/after JSON (gzipped if large), and scripts. Keep it under 10 MB.
- **Commits:** one per step on `claude/f2-index`, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree or branch.
- **Stop and report** if:
  - a wrong answer cannot be fixed;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside your change;
  - you would need more than a minimal change in U1's areas.
- **Your final reply** must contain the full report:
  - each step's commit;
  - the soundness argument for field ranges, write by write;
  - before and after instructions, cycles and check counters: per dispatch on the Lox step cell, and per site on sieve and sort_quick;
  - ratios against Zig ReleaseSafe for sort_quick and sieve;
  - the no-regression table: parity, Lox, EDA and the 46 rows;
  - every gate receipt;
  - any touches in U1's areas;
  - remaining limits.

  Also try to write `experiments/f2-index-20261009/REPORT.md`. If the tool refuses the file, the reply is enough.
