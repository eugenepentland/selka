You are implementing lane **F1 ("aliasing and overflow facts")** of mylang's runtime-parity plan, in the new compiler core. Work autonomously to the lane exit, then stop and report. A second agent is implementing lane S1 ("substring views") in parallel in another worktree. Stay inside your owned areas (below).

## Where everything is

- **Your worktree** (locked, yours alone): `/home/epentland/ai/canopy/mylang-worktrees/claude-ce2-results`, branch `claude/f1-facts`, based on `main` `cafe7fea7`. That base is the new core with both copy-elimination waves (CE, CE2) and wave PM's check counters. The worktree was reused from an earlier lane, so it has warm build caches; treat anything under `.mylang-cache/` as stale.

  Do all work and builds here. Read other worktrees only.
- **Read first:**
  1. `CLAUDE.md`.
  2. The plan, `docs/audits/runtime-parity-plan-2026-10-08.md`: §8 (the finalized lanes; authoritative for your levers, exit and ownership) and §6 (gates).
  3. Wave PM's report, `experiments/parity-measure-20261008/REPORT.md`: "Counterfactual attribution", "Where mylang's extra instructions go" (matmul, bytes_scan, sieve, calls), the matmul ladder, and PM-4 levers 1 and 4.
  4. The wall-time confirmation, `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/experiments/parity-confirm-20261009/REPORT.md` (commit `e1e9600a5`, not in your base).
  5. `docs/tooling/counters.md`: `--counters` builds, `mylang cost ENTRY --counters FILE.json`, and the new check kinds (`bounds_check`, `overflow_check`, ...).
  6. The code: `src/core/emit_llvm.zig` (the TBAA tags `tbaa_count`/`tbaa_header`/`tbaa_data` and `tbaa_metadata` near line 199, every `tbaa_data` access, `trapBegin`, the arithmetic lowering), `src/core/facts.zig` (intervals, counted loops, reductions, `mark`, `Sabotage`), `src/core/elements.zig`, `src/core/stores.zig`, `src/core/own.zig`.

## The measured bounds (PM, then confirmed as wall time on CPU 10)

| program | lever | cycles ÷ today (PM) | wall ÷ today (CPU 10) | today ÷ Zig ReleaseSafe | after |
|---|---|---:|---:|---:|---:|
| matmul | element data tagged by scalar type (`cf.py` variant `tbaa`) | 0.11 | 0.137 | 2.59 | 0.36 |
| bytes_scan | overflow traps never taken (`overflow`) | 0.29 | 0.368 | 1.08 | 0.40 |
| sieve | overflow traps never taken (`overflow`) | 0.74 | 0.768 | 1.15 | 0.88 |
| calls | floor-mod fix-up in `step` removed by hand | 0.94 | — | 1.07 | 1.00 |

## Your work, in this order (measure after each step)

1. **TBAA by element type.** Today one `myl.data` tag covers every element access, so in matmul a float store into `c[i]`'s row may alias `b[k]`'s row-pointer slot. LLVM then reloads b's row pointer, its length and c's row per element, and can neither hoist the check nor vectorize.
   - Tag element data by its scalar type (for example `myl.data.double`, `.i64`, `.ptr`, `.i8`) as children of `myl.data`.
   - **Union payloads, and any access that copies an aggregate or element as integer words, keep the generic `myl.data` tag.** Those accesses alias every child.
   - **Write down the soundness argument in the report.** List every access to element data in the emitter and the runtime, and the tag each uses. Cover these cases:
     - a block freed and its memory reused for another element type;
     - records stored inline in list elements: field access at an offset, against whole-record copies;
     - bytes and text data;
     - dictionary entries;
     - the runtime's C code, and whether any of it reaches the guest module as LLVM (LTO or inlining) rather than as an opaque call.

     If a case can't be made sound, use the generic tag for it.
   - PM's `tbaa` variant in `experiments/parity-measure-20261008/tools/cf.py` is a text-edit counterfactual, output-checked but not proven. Read its `edit` function for what it changed.
2. **No store-back of an unchanged element pointer.** `c[i][j] = …` stores c's row pointer back into `c` after every element.
   - When the row was already unique and so its pointer did not change, the store-back is redundant. Emit it only on the path where copy-on-write replaced the row, or where the pointer can otherwise change.
   - Check the matmul inner loop's LLVM before and after: one float load, one fma or mul+add, one store per element, and vectorized.
   - CE2-A's `src/core/stores.zig` (dead, sunk and narrowed element stores) is the nearest existing machinery.
3. **Overflow facts.** Extend `src/core/facts.zig` so that `mark` proves these overflow checks:
   - **A counter that grows by at most a bounded step per iteration**, including conditionally (`if data[i] == 109: count += 1`). It stays within `init + trips × step`, where `trips` is bounded by the loop's range or a list or bytes length (`max_list_length`). Targets:
     - bytes_scan:17 (`count += 1` inside `for i in range(size)`, with `count += pass_index` in the outer loop);
     - sieve:21 (`count += 1` under `for flag in flags: if flag:`).
   - **A loop variable bounded by its loop condition.** For sieve:16, `while j <= n: …; j = j + i`, where `j ≤ n` on entry to the body and `i` is bounded. Use the branch-edge refinement the intervals already have, and make sure widening does not lose it.
   - **Floor-mod ranges into callees.** `calls`'s `step(a, b) = (a + b) % 1000003` keeps Python's floor-mod fix-up because `a + b` may be negative. When every call site passes non-negative arguments, the fix-up is dead. Use whichever of interprocedural argument ranges or specialization is simpler and sound.
   - **Every new fact must stay checkable** by the existing fact verification (`--verify` in `qualify_merge`) and by the `Sabotage` tests: a deliberately wrong fact must be caught.

If a step can't be made sound, revert it, keep the others, and say why.

**Exit** (plan §8, F1):
- matmul ≤ 0.4× Zig ReleaseSafe; bytes_scan ≤ 0.4×; sieve ≤ 0.9×; calls ≤ 1.02×. Measure these yourself as cycles; see "Measuring".
- `overflow_check` count 0 at bytes_scan:17 and at sieve:16 and :21 (counting builds).
- Nothing else slower than 1.03× in instructions or cycles beyond noise. That covers every parity program, 4 Lox cells and 2 EDA designs.
- Every gate below passes.

## Ownership

**You own:**
- TBAA metadata and tags in `emit_llvm.zig`, and every element access's tag;
- the store-back in element-store emission: `listSet` and `list_set_field` in `emit_llvm.zig`/`elements.zig`, and `stores.zig`;
- `facts.zig`, and the check emission that consumes its facts;
- integer arithmetic lowering, including floor division and modulo.

**S1 owns:**
- string slicing and substring lowering;
- dictionary lookup and insert with text keys: `emit_dict.zig`, `emit_dict_span.zig`, `fuse_dict.zig`;
- `str_view`;
- the runtime's string and dictionary functions.

If you must touch one of their functions, make the smallest change you can and list it in your report. Don't edit `src/` outside `src/core/`. The runtime's C files are `src/core/runtime/*.c`; read them for the soundness argument, and edit them only if essential.

## Measuring (counts and cycles on your own CPU; the coordinator measures wall time on CPU 10 later)

- **Your measurement CPU is 8.** Use `taskset -c 8` and interleave the arms; PM's `tools/pstat.py` and `tools/cf.py` take `--cpu`. The machine is shared, so cycles are only comparable inside one interleaved run. Instruction counts are exact.
- **Reference binaries** (Zig ReleaseSafe/ReleaseFast, Rust with and without overflow checks): `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/parity/work/bin/<program>.<arm>`, with arms listed in `../arms.json`. Read-only; copy them if you need them elsewhere.
- **Programs:**
  - `bench/parity/suite/{matmul,sieve}.my`;
  - `bench/parity/micro/bytes_scan.my`;
  - `bench/parity/micro/calls.my`;
  - and all other parity programs for the no-regression check.
- **Lox and EDA:**
  - Lox: copy `/home/epentland/ai/canopy/mylang-worktrees/claude-copy-elim/.mylang-cache/lox` into your `.mylang-cache/lox`, without its `.tmp/`, then create `.tmp/lox-bench/tmp` in your worktree root; the harness looks for it.
  - EDA: copy `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang` into `.mylang-cache/eda-src`.
  - `experiments/ce2-x-20261008/tools/` shows how CE2-X built and ran them; PM's `experiments/parity-measure-20261008/tools/prof.sh` shows its 4 Lox cells and 2 EDA designs.
- **Report:** before and after instructions and cycles, ratios against Zig ReleaseSafe for the four exit programs, the check counters at the named sites, and the matmul inner loop's LLVM after.

## Gates (every one must pass on your final commit; run them before declaring the exit)

A wrong answer is never acceptable.
1. **Build and repository gates:** `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
2. **Conformance** against the frozen S5 references, debug and release, with leak and fact verification: **1518/0/0**.
   - Run `python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence <a fresh directory inside experiments/>`.
   - Never reuse an evidence basename: a reused name crashes on a stale `.mylang-cache/s5/integration-qualify/<name>/tmp`.
   - Move that evidence under your evidence directory afterwards.
3. **Frozen fuzz 9×50:** `experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new <a copy of your Debug zig-out/bin/mylang> --cases 50 --evidence <dir below experiments/> --jobs 3`. All 9 kinds must PASS. It needs a clean tracked tree.
4. **Lox:**
   - `python3 harness/lox_bench.py conformance --binary <your plain release lox binary> --engine both --stress -j 4` from your Lox copy: **974/974**;
   - the port's own tests, `mylang test .` in `ports/mylang`: **65/65**.
5. **EDA:**
   - all 34 cases' outputs byte-identical to the goldens;
   - `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir <yours>` in your `eda-src`: **310/310**.
6. **Parity:** every program's output equals its `.expected`.
7. **Counting:** counting on and off give the same output on every program you count.

**Every transformation needs regression tests,** including adversarial ones:
- **TBAA:**
  - a list of records whose element is copied whole and then a field is read;
  - a union-typed list;
  - a list of floats and a list of lists in one loop;
  - memory freed and reused for another element type inside one function;
  - nested lists that alias by value semantics, as in `b = a; b[0][0] = 1.0`.
- **Store-back:**
  - the row shared, so copy-on-write must replace it and store the new pointer;
  - the row replaced inside the loop;
  - aliasing rows, as in `c[0] = c[1]`, then writing one of them;
  - `break` and early return.
- **Overflow:**
  - counters near `max`;
  - a step that is not bounded;
  - a loop whose condition changes in the body;
  - negative arguments at one call site of the modulo callee;
  - a wrong fact injected through `Sabotage` and caught.

Put them in `test/core/*.my` and/or the core's Zig tests.

**Guardian rules:**
- every behavioural line under `src/` needs a test with `// spec: TAG` and a `SPEC.md` bullet; use `NEW-CORE-F1-*`;
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
- **Caches and `TMPDIR`** stay on disk inside your worktree, never in `/tmp`. Disk is tight, so delete scratch you no longer need.
- **Never end your turn to wait for background work.** The harness treats a turn that ends while you wait as the end of your run. Run long steps in the foreground, with a timeout of up to 600000 ms, and split anything longer into parts.
- **Never kill processes by pattern** (`pkill -f`). Kill only PIDs you started.
- **Evidence** goes in `experiments/f1-facts-20261009/`: logs, before/after JSON (gzipped if large), and scripts. Keep it under 10 MB.
- **Commits:** one per step on `claude/f1-facts`, with messages ending in `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree or branch.
- **Stop and report** if:
  - a wrong answer cannot be fixed;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside your change;
  - you would need more than a minimal change in S1's areas.
- **Your final reply** must contain the full report:
  - each step's commit;
  - the TBAA soundness argument, access by access;
  - before and after instructions and cycles, with ratios against Zig ReleaseSafe for matmul, bytes_scan, sieve and calls;
  - the no-regression table: every parity program, the Lox cells and the EDA designs;
  - the check counters at the named sites;
  - every gate receipt;
  - any touches in S1's areas;
  - remaining limits.

  Also write `experiments/f1-facts-20261009/REPORT.md`. If the tool refuses the file, the reply is enough.
