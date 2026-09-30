# Next work plan (handoff), 2026-09-29

This plan is written to be handed to AI agents that did not see the conversation it came from.
Each work package (WP) says where it starts, what to do, what "done" means and what has
already gone wrong in this area. Read sections 1 to 5 before any WP.

## Closeout status, 2026-09-30

A1–A4 are implemented, integrated and verified on the isolated
`codex/next-closeout-20260929` branch. A5 gate `m17-codex` is green at compiler
source `d8f66585`: all 27 steps pass, including 1,438 fresh guest tests in each
of nine modes and all four Lox combinations. Dev/full corpus outputs match all
86 pairs; every row meets the 1.3x cap and 1% regression limit.

**A5 landed with explicit user approval** ("Yeah fast forward main") on
2026-09-29. `main` fast-forwarded from `6d91f95b` to `80dd5190`; its compiler
source is the gated `d8f66585`. Original checkouts and paused lane worktrees
were not edited. The completed Codex A3/A4 worktrees were removed after
archiving their logs and Guardian ROI receipts; their branches remain.
Details, exact counts, performance rows and Guardian feedback are in
[codex-next-integration-closeout-2026-09-29.md](codex-next-integration-closeout-2026-09-29.md).

**Phase B is implemented and its complete final integration gate is green** on
`codex/next-closeout-20260929`, frozen compiler source `a3e451d7`. All 27 steps
pass: 2,804 selected Zig tests, 505 QBE tests, nine fresh guest sets of 1,486
tests, all four Lox runtime/backend combinations and the native checks. The
29-program / 43-row module corpus and all four runtime module matrices have
identical interfaces, units and executables, with zero fallback or reference
failure. The 100-seed fuzz run has zero RC divergences and the two previously
known GC-stress-only findings remain reported. All 258 dev/full/smoke outputs
match; every dev/full row passes the 1% limit against both approved and explicitly
pinned A5 controls and every 1.3x cap. Smoke retains six reported diagnostic
increases and has zero new cap miss.

The strict final verifier and independent subagent reviews bind source/compiler,
tag/size, all 58 measured binary hashes, fresh test names and retained module
bytes. All final evidence is archived and hash-verified; earlier rejected
checkpoints remain in their historical receipts. Details, exact counts,
performance rows, known findings and Guardian feedback are in
[codex-next-phase-b-closeout-2026-09-30.md](codex-next-phase-b-closeout-2026-09-30.md).

**Phase B landed with explicit user approval** ("Yeah merge it in") on
2026-09-30. Main fast-forwarded from `80dd5190` to `b6aed6cf`; its tested compiler
source is `a3e451d7`. The original dirty checkout was verified unchanged.
Phase C is now authorized to start on the completed compiler work.

Lane receipts are in [python-text-closeout-2026-09-29.md](python-text-closeout-2026-09-29.md),
[wp-b4-tooling-2026-09-29.md](wp-b4-tooling-2026-09-29.md),
[codex-next-runtime-checkpoint-2026-09-29.md](codex-next-runtime-checkpoint-2026-09-29.md)
and [text-runtime-closeout-2026-09-29.md](text-runtime-closeout-2026-09-29.md).
The final module-lane receipts are in
[codex-next-modules-closeout-2026-09-30.md](codex-next-modules-closeout-2026-09-30.md);
the QBE phi fix is in [wp-b3-qbe-phi-2026-09-30.md](wp-b3-qbe-phi-2026-09-30.md).
EDA preparation has a verified test inventory and guide/checker reconciliation.
Phase C begins after the approved Phase B landing. Sections below retain the
original handoff state and requirements.

## 1. Read first

- `CLAUDE.md`: the build, the fast loops, the Guardian rules and the gate. Guardian blocks `zig build` and commits.
- Section 4 of this plan: the rules every WP follows.
- `docs/audits/rc-future-performance-2026-09-28.md`: why the RC runtime has two counts, the ranked future performance work, and the correctness items.
- `docs/audits/rc-perf-closeout-2026-09-27.md`: how the RC runtime reached 1.07x the GC.
- `experiments/rc-perf-20260927/README.md`: the performance harness `quick.py`.
- For WP-B2 only: `git show merge/devspeed-into-main:docs/audits/merge-devspeed-into-main-2026-09-24.md`.
- For WP-C1 only: in `/home/epentland/ai/canopy/eda-bench`, read `PORTING.md`, `mylang/PORTING-MYLANG.md`, `mylang/PLAN.md` and `mylang/GAPS.md`.

## 2. Original handoff state (historical)

The status above records the current closeout. The following snapshots describe
the starting state, so original branch names and gate failures remain auditable.

### Starting `main` = `6d91f95b`

- Reference counting (RC) is the default runtime. On the 43-program corpus it runs at a geomean of 1.07x the tracing GC's instruction count, and every program is at or under 1.3x. `--gc-runtime` selects the GC.
- The language-level copy bugs are fixed:
  - VALUE-SEMANTICS-14: a read-only operand gets a snapshot when a later operand of the same expression writes its root.
  - OWNERSHIP-MUT-RECORD-WRITE-3.
  - MUT-EXCLUSIVE-1: two `mut` arguments of one call must name disjoint places, else `E_MUTATION_OVERLAP`.
- `mylang check` on a file with no `main` type-checks it as a library (CHECK-LIBRARY-2).

### Integration branch `claude/rc-perf` = `1f744a3f`

Worktree: `/home/epentland/ai/canopy/mylang-worktrees/claude-rc-perf`. None of this is on `main`, and the full gate has **not** passed at `1f744a3f` yet. See WP-A1.

| Merged lane (branch) | Spec tags | Effect |
|---|---|---|
| `claude/rc-exit` | RC-EXIT-SKIP-1 | Production RC builds skip the entry frame's drop walk at exit when no resource is live. Small win: schematic -0.2% QBE, -0.5% LLVM. |
| `claude/rc-pins` | COW-PIN-ELIDE-1, VALUE-BUFFER-FRESH-1 | No per-call pin on a `mut` list argument whose callee provably never shares it. This is a whole-program summary in `src/rc_pin_summary.zig`. nbody LLVM 1.26 -> 0.98, sort_quick LLVM 1.28 -> 0.99. |
| `claude/literal-build` | LITERAL-PAYLOAD-1 | A constant `str`/`bytes` literal lowers to one `make_record` with a `payload`. A 16 KB literal built in 174 s before and 0.3 s after. |
| `claude/str-index` | TEXT-INDEX-1..3 | Long non-ASCII `str` gets a lazy position index. Iterating 1 MB with one `é`: 703 s -> 0.12 s. |
| `claude/num-literals` | NUM-LITERAL-1..7 | Python numeric spellings: `0x`/`0o`/`0b`, `1_000`, `.5`, `5.`. Typed unsuffixed constants (`const M: u32 = 4278190080`). Decimal leading zeros (`0755`) rejected. `[0x10]u8` works. |
| hint fix `3e946072` | NUM-LITERAL-4 (sentence added) | Fixes a regression from num-literals, where `x == module.Enum.CASE` in a module with constants failed. See the lesson in section 4. |
| `claude/rc-typeids` | RC-TYPE-ID-1, RC-STARTUP-3, RC-CLASS-TABLE-1 | Dense RC type ids, a static class table and lazy flat plans. Empty-program startup went from 322k to 283k instructions. Otherwise about neutral. |

### Gates on the integration branch

- **Gate m15 on `f5aa3f19`:** green except the Lox port, which is the regression fixed by `3e946072`.
  - `zig build test`: 2566 tests.
  - `test-qbe`: 472 tests.
  - `tests/lang`: 1325 passed across 207 programs, in each of 9 runtime modes.
- **Gate m16 on `1f744a3f`:** started, then stopped when work was paused. Rerun it.

### Branches not yet merged

| Branch (worktree under `mylang-worktrees/`) | State |
|---|---|
| `claude/tool-gaps` `b1a8db99` (`claude-tool-gaps`) | **Done.** Lane gate green: 2543 tests, qbe 471, `tests/lang` default and GC. The Lox port was verified. Spec tags:<br>- IO-FILE-WRITE-LINEAR-1<br>- CAPABILITY-FIELD-METHOD-1 (`ctx.fs.read_file()`)<br>- CLI-INPUT-REFUSED-1<br>- CLI-CACHE-DIR-1<br>- RUN-FLAGS-1<br>- RUN-FRAME-BUDGET-1<br>- PROJECT-LIMITS-1 (`mylang.json` `limits`) |
| `claude/typing` `4d6ffdf7` plus 9 uncommitted files (`claude-typing`) | **Paused mid-work.**<br>- Contains the merged `claude/embed`: EMBED-1..5, `embed_bytes`/`embed_str`.<br>- Also contains the hint fix, cherry-picked.<br>- Committed: DISCARD-NAME-1, OPTION-EQ-1, CONST-METHOD-1.<br>- Uncommitted: float module constants and float-to-integer casts.<br>- Next step: the interface test and the Zig rejection tests. |
| `claude/devspeed-fidelity` `a48b62f5` (`claude-devspeed-fidelity`) | **Paused in its final gate, during the RC fuzz step.** This is stage 1 of the devspeed port. Every port is committed:<br>- PY-CHAIN-1, PY-TEXT-ORDER-1, PY-REPEAT-1, PY-RANGE-STEP-1, PY-FSTRING-SPEC-1/2, PRELUDE-ROUND-2<br>- PY-GATHER-1, PY-GENERATOR-1/2, PRELUDE-KEYS-1, PY-SET-OPS-1<br>- the `mylang fix` producers, MUT-PARAM-8, and part of test-capabilities<br>- the devspeed trial harness<br>- the hint fix, cherry-picked |
| `claude/py-text` (`claude-py-text`) | Worktree only, at `main`, with no commits. Recreate it from the new `main` for WP-B1. |

### Stranded work (stage 2 source)

- `devspeed/module-compile`, `module-schedule`, `module-projects`, `module-nowait`, `module-test` and `module-interface` are per-module incremental builds.
- They are integrated in `devspeed/integration` and `merge/devspeed-into-main` `fbd12a85`. That branch was approved for main on 2026-09-25 but never landed, and `main` is now about 1,050 commits ahead.

### EDA benchmark (`/home/epentland/ai/canopy/eda-bench`, `main` `af8cf03`)

- The Zig, Go and Rust stage-1 ports reproduce all 34 golden cases byte for byte.
- mylang preparation is done:
  - the porting guide, `mylang/PORTING-MYLANG.md`;
  - the lane plan, `mylang/PLAN.md`: four lanes, about 24k mylang lines;
  - harness hooks (`bench.py build|check|test mylang`);
  - support modules, including a Zig-exact float formatter;
  - an S-expression pilot;
  - the gap list, `mylang/GAPS.md`.
- The pinned compiler is `eda-bench-wt/mylang-c523da46` and is outdated. See WP-C1.

## 3. Decisions already made by the user (do not relitigate)

- **Runtime:** RC is the default runtime. A geomean of about 1.07x GC is accepted, with every corpus row at or under 1.3x. The GC stays as the `--gc-runtime` opt-out.
- **Overlapping `mut` arguments** are rejected at compile time (MUT-EXCLUSIVE-1). This is Swift/Rust-style exclusivity, not alias-aware analysis.
- **File embedding** is part of the language: `embed_bytes("path")` and `embed_str("path")`, resolved at compile time. The EDA port embeds its data files this way rather than converting them to literals.
- **Numeric literals** follow Python, including rejecting decimal leading zeros.
- **Rejected by design**, with hints (PARSER-HINT-10): `**`, `<<` and `>>`. Stage 1 respected this; keep it that way.
- **Loop variables:** a `for` variable may not reuse an active local's name, because loop variables are block-scoped (E_SHADOWING). Only `_` is exempt.
- **Stranded devspeed work** lands in two stages:
  - stage 1: Python fidelity and tooling (WP-A4);
  - stage 2: the per-module build chain (WP-B2).
  - On conflicts, current `main`'s explicit design decisions win.
- **EDA port timing:** the mylang port of the EDA benchmark starts after the compiler work lands (WP-C1). Earlier the user said the mylang port waits "until all compiler updates are finished".
- **Nothing is merged to `main` without the user's explicit OK.**

## 4. Common rules (every WP)

### Workspace

- Work in your own git worktree under `/home/epentland/ai/canopy/mylang-worktrees/`, on your own branch. Never edit `/home/epentland/ai/canopy/mylang`: that main checkout holds other sessions' uncommitted work. Never touch another agent's worktree.
- Set these in every shell. Scratch stays inside your worktree; Zig's global cache is one shared directory for every agent. `~/ai` is shared by all agents and has filled up before.
  ```
  export TMPDIR=$WT/.tmp ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
  ```
- Caches:
  - Share only the global cache. Zig locks it per entry, so concurrent builds are safe, and a warm one avoids rebuilding compiler_rt/libc and the `ar rcs` flake below.
  - Never share `ZIG_LOCAL_CACHE_DIR` (`.zig-cache`) between worktrees: Zig's configure cache ignores the build root, and the build refuses a tree it did not configure.
  - Never share a `.mylang-cache` between worktrees running different compilers: each compiler generation evicts the others' objects.
- Reuse worktrees. Before creating one, switch one of your own merged, clean worktrees to your new branch (`git switch -c <branch> main`), so its `.zig-cache` stays warm. When a lane is merged and you will not reuse its worktree, remove it with `git worktree remove <path>`; the branch stays.
- `scripts/prune-caches.sh` runs hourly. A worktree idle for 3 days loses `.zig-cache`, `.mylang-cache`, `zig-out`, and the binaries, objects and `*cache*` folders in its `.tmp*` scratch. Any `.zig-cache` over 15 GiB is deleted while no build is running in it. Keep evidence you need as text (logs, JSON, notes), not in caches or binaries.
- Run every `zig build`, and any heavy `mylang test <dir>`, through `scripts/build-slot.sh build|gate …`. It admits jobs by free slots and memory. At most about 4 build-heavy agents fit on this box.
- Forbidden:
  - bare `git stash`;
  - `pkill` or `killall`;
  - killing any process you did not start;
  - pushing, since there is no remote;
  - merging to `main` without the user's OK.
- No Python in the compiler's build or use path. Python is fine for tests and experiments.
- If a permission check refuses an action, do not work around it; report it. Merging one shared branch into another has been refused for sub-agents before. The integrator (WP-A) does merges.

### Spec and tests

- Guardian needs a behavioural change to carry a `// spec: TAG` (Zig) or `# spec: TAG` (guest) test plus a `- [TAG] …` bullet in `SPEC.md`. Otherwise it fails the build with `change-classification`.
- Guest behaviour tests go in `tests/lang/*.my` as `public def test_*() -> bool`.
- Diagnostics, CLI behaviour and native tests are Zig tests.
- New language features also need a `src/features.json` slug whose doc anchor has a runnable example (`mylang doc-coverage .`).

### Lane gate (before reporting)

Run all of these:
- `zig build`, `test`, `test-qbe`, `test-qbe-build`, `fmt-check`;
- `test-native-memory` and `test-native-heap` if you touched the runtime;
- `mylang test tests/lang --force --jobs 4` under the default runtime and under `--gc-runtime`. Add `--release`, `--rc-runtime=stats` and `--gc-runtime --gc-stress` for runtime or ownership changes;
- `zig build test-rc-fuzz -Dfuzz-seeds=100`, which must show 0 RC divergences. It has known `--gc-stress`-only failures.

**Always build and test the Lox port as well.** The `num-literals` lane passed its own gate but broke every module that compares against a module-qualified enum. Only the Lox port caught it.
- Get the port from `quick.py setup`, which puts it at `.tmp-rc-quick/lox/benchmarks/lox/ports/mylang`. Copy it into your `.tmp` before running.
- Build: `mylang build main.my --project -o X --cache-dir …`.
- Tests: `mylang test . --max-steps=100000000`.
- Driver cases: `mylang test driver_tests.my --cases driver_cases.json --max-steps=100000000`.
- Run all three under the default runtime and `--gc-runtime`.

**Known flake:** with a fresh `ZIG_GLOBAL_CACHE_DIR`, zig prints `ar rcs …` on stderr the first time it builds compiler_rt/libunwind. Two CLI tests that expect empty stderr then fail. The shared global cache above is warm, so this should no longer happen; if it does, rerun before calling it a failure.

### Performance acceptance

- Measure any change that can affect generated code:
  - `python3 experiments/rc-perf-20260927/quick.py setup`
  - `quick.py build --compiler $WT/zig-out/bin/mylang --tag T`
  - `quick.py measure --tag T --size dev`
  - `quick.py compare <baseline>.json <yours>.json`
- `quick.py build --runtime gc` measures the GC side.
- Baselines:
  - `claude-rc-perf/.tmp-rc-quick/results-m14-dev.json` is `main` before this batch.
  - After WP-A1, use that gate's `results-<tag>-dev.json`.
- Rules:
  - No row may get worse by more than 1% on either backend.
  - Every row stays at or under 1.3x.
  - RC output must match GC output on all 86 program/backend pairs; `quick.py` checks this.
  - Explain every row that moves.

### Integration gate

`experiments/rc-perf-20260927/gate.sh TAG` runs:
- the 43-program corpus at dev and smoke size;
- the full zig gate;
- `tests/lang` in 9 runtime modes;
- the Lox port under both runtimes, with and without `--release`.

Results go to `.tmp-gate/TAG/summary.txt`; every step must be 0. It takes about 2 hours, needs a clean tree, and flags "HEAD moved during gate". Don't commit to the branch while it runs.

### Report

Your final report is read by an integrator, not by the user. It must include:
- the branch tip and commits;
- per item: the rule implemented, spec tags, tests, and before/after evidence;
- gate counts;
- the performance table;
- anything skipped, refused or uncertain.

## 5. Order and parallelism

```
Phase A (one integrator agent, serial)
  A1 re-gate claude/rc-perf -> A2 merge tool-gaps -> A3 finish typing -> A4 finish stage 1
  -> A5 merge A3+A4, final gate, user OK, fast-forward main
Phase B (parallel, from the new main)
  B1 Python text surface      B2 stage 2: per-module builds (split B2a/B2b)
  B3 performance follow-ups   B4 tooling and GC leftovers
Phase C (after A, B1 and ideally B2 are on main)
  C1 EDA benchmark: mylang port (four lanes)
```

- Phase B lanes touch different areas: B1 the text methods, B2 the build driver and caches, B3 the RC runtime and codegen, B4 CLI, GC and tests.
- B2 is the riskiest. Give it the strongest agent, and keep B3's codegen work off the same files, or sequence them.

## 6. Work packages

### WP-A1: re-gate the integration branch

- **Start:** worktree `claude-rc-perf`, branch `claude/rc-perf`. That is `1f744a3f` plus the one commit that adds this plan and `gate.sh`, which changes docs and the script only.
- **Do:** run `experiments/rc-perf-20260927/gate.sh m16`.
- **Watch two merge-sensitive areas:**
  - `src/native_text.c` and `src/native_text_methods.c`: text indexing from str-index, together with the shared `myl_rc_pointer_leaf`/`myl_rc_octet_leaf` descriptors from rc-typeids. The conflict was resolved by keeping the str-index logic.
  - All 43 corpus rows must be present. Gate m15 measured only 30 because Lox failed to build.
- **Done when:** every summary line is 0, and dev geomean and rows are within 1% of `results-m14-dev.json`, except the expected improvements: nbody and sort_quick LLVM, plus small RC-startup gains at smoke size.

### WP-A2: merge `claude/tool-gaps`

- Merge it into `claude/rc-perf` (it is based on `main`).
- Expect a conflict in `SPEC.md` and maybe the CLI docs. Keep both sides.
- Rebuild, then run the CLI tests (`zig build test-cli`) and the Lox port.
- **Note:** RUN-FRAME-BUDGET-1 now refuses `--max-frames` values that `--max-memory` cannot back, at 32 KiB per frame. Harness commands that pass `--max-frames` need enough memory, e.g. the EDA harness's `--max-frames 30000 --max-memory 2G`.

### WP-A3: finish the typing lane

- **Start:** worktree `claude-typing`, branch `claude/typing` `4d6ffdf7`, plus 9 uncommitted files:
  - `SPEC.md`, `docs/module-constants.md`, `src/features.json`
  - `src/constant_values.zig`, `src/floats.zig`, `src/numeric_surface.zig`
  - `src/sema.zig`, `src/sema_calls.zig`, `src/sema_expressions.zig`
- Inspect `git diff` first, and continue the work rather than restarting it.
- **Remaining items:**
  1. **Float module constants:** `const PI: float = 3.14` is `E_CONSTANT_TYPE` today. Fold only when the result is bit-identical to runtime; otherwise emit a static value. Interfaces must print them.
  2. **Float-to-integer casts:** `u64(3.5)` is `E_TYPE` today. `i8`…`i64` and `u8`…`u64` from `float` truncate toward zero. Trap on NaN, infinity and out-of-range values with a clear `R_…` code. Check the range before converting, because LLVM `fptosi` on out-of-range values is poison. Keep `int(x)` consistent with this.
- **Invariant to keep:** in any hint or inference pass, never resolve a name through `Names.reference` unless it is known to be a constant. A failed resolve records a problem on the project (see `constantType` in `src/sema.zig`).
- **Done when:** the lane gate passes, including Lox. This branch also carries embed, so run `tests/lang/embed.my` under the default runtime, `--gc-runtime` and `--release`.

### WP-A4: finish stage 1 (devspeed fidelity)

- **Start:** worktree `claude-devspeed-fidelity`, branch `claude/devspeed-fidelity` `a48b62f5`. It is clean.
- **Do:** rerun the lane gate from the RC fuzz step: fuzz, then `quick.py` against `results-m14-dev.json`, then the Lox port.
- Fix only what fails. The ports are done; see the commit messages of `d17eea10`, `a1f8bedf`, `3928e4ab` and `ee908d43` for what landed and what was deliberately not carried.

### WP-A5: land

- Merge A3 and A4 into `claude/rc-perf`.
  - Both contain the hint fix, as cherry-pick `a48b62f5` and as `3e946072`. The patches are identical, so keep one copy.
  - Expect `SPEC.md`, `features.json`, docs and maybe `sema*.zig` conflicts.
- Then run `gate.sh` with a new tag.
- When it is green, **ask the user** before fast-forwarding `main`.
- Afterwards:
  - Remove merged worktrees with `git worktree remove --force`, keeping the branches.
  - Update `docs/audits/rc-future-performance-2026-09-28.md`: mark done items and add the new open ones from section 6.

### WP-B1: Python text surface (what stage 1 did not bring)

- **Start:** a fresh worktree from the new `main`.
- First check what exists: PY-TEXT-ORDER-1 (`<` on `str`/`bytes`) and PY-REPEAT-1 (`"ab" * 3`) came with stage 1.
- **Implement, with Python semantics:**
  - **`sorted` and `.sort()` on `list[bytes]`**, and `bytes`/`str` keys (GAPS.md G07). Today `sorted` requires int, float or str.
  - **`strip`/`lstrip`/`rstrip(chars)`** for `str` and `bytes` (G02). Today they take no arguments.
  - **`find`/`rfind`/`index`/`rindex`/`count(sub, start, end)`**, and `startswith`/`endswith` with `start`/`end` (G12).
  - **`repr()`** (G01):
    - exact CPython output for `str` (quote choice and escapes), `bytes`, `int`, `float` and `bool`;
    - lists, dicts and records if straightforward;
    - otherwise state the scope.
- **Out of scope:**
  - `cmp=` sorting, and key lambdas that capture locals: mylang has no closures by design;
  - `**`, `<<` and `>>`.
- **Tests:** guest tests against CPython-derived expected values. Also check non-ASCII `str` performance (TEXT-INDEX-*) for the new methods: they must stay linear.

### WP-B2: stage 2, per-module incremental builds

- **Goal:** land the per-module build chain from the devspeed branches on the new `main`. It is the largest dev-speed win on record:
  - at 200k lines, an edit-to-build took 0.42 s vs 1.98 s whole-program;
  - an edit-to-check took 0.025 s vs 0.47 s;
  - a no-op run took 0.047 s.
- **Sources:**
  - branches, in order: `devspeed/module-compile` -> `module-schedule` -> `module-projects` -> `module-nowait` -> `module-test`, plus `module-interface`;
  - the adaptations already made in `merge/devspeed-into-main` `fbd12a85`;
  - the lane reports under `docs/audits/devspeed-*` on those branches.
- **Why it is risky.** These branches predate value semantics and the RC runtime. Several RC-era analyses assume the compiler sees the whole program:
  - COW-PIN-ELIDE-1 (`src/rc_pin_summary.zig`) is a whole-program fixed point over callee bodies. Across modules today, a project build keeps the pin, which is conservative. Keep that conservative, or carry the summary in module interface facts (`.myi`), with the callee's summary in the caller's cache key.
  - RC-TYPE-ID-1 numbers descriptors across the whole linked program in the shared `runtime_data` unit, with a tolerant fallback for module-local numbering. Verify it holds when modules compile separately.
  - RC-GLUE-1 per-type glue lives in one metadata unit per program.
  - The readonly/interval/operand anchors, inert receivers, element borrow/take and VALUE-SEMANTICS-14 all read callee contracts. Every fact a caller's codegen depends on must be in the callee module's interface and in the caller's cache key.
  - Stand-ins: an earlier stand-in bug came from analyses reading a stand-in's empty body as "writes nothing" ("param writes from empty body"). Any analysis that reads callee bodies must treat stand-ins as unknown.
  - Embedded files (EMBED-*) must feed the schedule's early cutoff and module identity. The embed lane found "no per-module schedule in `src`" to key.
- **Suggested split:**
  - B2a: module-compile plus module-schedule, with the RC reconciliation.
  - B2b: module-projects, module-nowait and module-test.
- **Done when:**
  - the per-module build is byte-identical to the whole-program build for the corpus, `tests/lang` and the Lox port;
  - an edit to a callee body that changes a summary rebuilds its callers;
  - timings are reproduced on the devspeed 200k scale project (see the devspeed reports for its generator);
  - the full integration gate passes.

### WP-B3: performance follow-ups (ranked, rough)

1. **`==` allocates.** `myl_native_equal` does malloc/calloc/free on every comparison: 12,044 calls for 6,000 iterations in Lox `string_equality`. It also makes rows jump 1–3% with allocator state. Remove the per-call allocation (the user has a task chip for this).
2. **Scope protocol inline in IL.** A pin plus unpin still costs 150–180 instructions. Emitting it in IL with alias classes is expected to save about 2–4% LLVM geomean (rc-future-performance, section 3).
3. **List literals with many elements are superlinear.** QBE slows on one huge function, and each element emits about 300 IL lines of RC glue. A 250-element list builds in 5.1 s, and 1,000 elements hit "function too large". Emit constant lists as static data and skip glue for immortal elements.
4. **Delete the four alias refusals MUT-EXCLUSIVE-1 made unreachable.** They are listed in rc-future-performance, section 2. Check `--legacy-sharing` first. The corpus gain is zero; the gain is for multi-`mut` APIs.
5. **knucleotide dictionary uniqueness hoist.** About 3%. The pins lane declined it: RC admits hoists only through `qbe_rc_hoist` proofs, which whitelist lists and buffers. A type-disjointness argument is needed first.
6. **RC startup.** About 150–190k instructions of Lox registration remain: shape registration, builder and index commit. A static precomputed registration image would remove them.
7. **32-bit counts, then collapsing to one count.** Header work; rc-future-performance, section 1.
8. **Text.**
   - `s[pos:]` copies once `pos` is past 3/4 of the owner (TEXT-VIEW-3), so `find` loops over large texts cost seconds even on ASCII.
   - Static literal texts carry no position index.

### WP-B4: tooling and GC leftovers

- **Test wiring:** tests inside `src/memory_budget.zig`, including MEMORY-CEILING-*, run in no gate step (the user has a task chip). Check other named modules for the same gap.
- **Cache leaks:** `mylang test --no-cache --cache-dir DIR` still builds objects in the cwd's `.mylang-cache/qbe`, and `mylang doctest` writes `<root>/.mylang-cache`.
- **Embed coverage:**
  - `mylang context` inputs and its staleness check ignore embedded files.
  - Providers without an embed callback (`host_native.zig`, `generic_api.zig`, `reference.zig`, context sources) give `E_EMBED_UNAVAILABLE` for projects that embed.
  - Project byte budgets (`max_file_bytes`, `max_total_bytes`) ignore embeds.
- **Memory:**
  - `mylang test` prints no advice on `R_FRAME_LIMIT`.
  - A guest cannot map more than the compiler's own `MYLANG_HOST_MEMORY_LIMIT` (8 GiB), because it inherits it. Lifting that for the guest only was not attempted.
- **`selfhost/lexer.my`** still scans numbers the old way. It is not gated.
- **GC-only bugs.** Repros are in `experiments/rc-review-20260928/repros/open-gc-*.my`:
  - `--gc-stress` crashes: a `mut`-argument clone case and an arena case;
  - "a descriptor's scan plan disagrees with its fields" under stress;
  - a false `R_LIST_ITERATION_MUTATION` when a field is moved while an iteration source shares it.

  They reproduce on the pre-RC compiler too. The fuzzer finds a few per 200 seeds (`zig build test-rc-fuzz`).

### WP-C1: EDA benchmark, mylang port

- **Start:** after Phase A and WP-B1 are on `main`, and ideally WP-B2, since per-module builds shorten the agents' edit loop.
- **Prepare:**
  - Install a pinned compiler from the new `main`:
    ```
    zig build --prefix /home/epentland/ai/canopy/eda-bench-wt/mylang-<commit>
    ```
    Use the Debug compiler; guest binaries are identical.
  - Point `harness/langs.toml` `[mylang]` at it.
  - Update `mylang/PORTING-MYLANG.md` and `PLAN.md` for what the compiler now has:
    - `embed_bytes`/`embed_str` for `stdlib/embed` and the fixtures (deviation D5);
    - hex literals (N1);
    - `check` on library files (G13);
    - capability methods on fields (N4);
    - `sorted` on bytes, `strip(chars)`, `find` ranges, text ordering and repetition (G02, G07, G08, G12);
    - float constants and casts (G14, G15);
    - `Some(...) ==` (G16);
    - `_` in nested loops (G17);
    - `mylang.json` `limits` for test budgets (G18);
    - linear non-ASCII `str` (G11), so `str` is usable again.
  - Rerun `mylang/tools/check_guide_examples.py`.
- **Do:** four lanes A–D as in `mylang/PLAN.md`. The S-expression pilot on branch `mylang/probes`, now merged, is a head start for lane A. Follow `PORTING.md`'s rules, including no generated code.
- **Done when:**
  - `python3 harness/bench.py equiv mylang` gives 34/34 byte-identical;
  - `map mylang` is OK;
  - every Zig test has a counterpart (`mylang/tools/check_tests.py`);
  - `bench.py time` and `counts` have been recorded;
  - the lanes have kept the development-speed evidence the benchmark exists for: agent time, repair rounds, and the edit-to-test loop times seen.
- **Compiler bugs found during the port:** record them in `mylang/GAPS.md` with repros. Hand them back to the compiler track; don't patch the compiler from a porting lane.

## 7. Open questions for the user

- Should stage 2 (WP-B2) finish before the EDA port starts (WP-C1), or can the port start on whole-program builds?
- Should the GC stay a supported runtime long-term? It has open stress-only bugs (WP-B4), and the gate runs a GC lane.

## 8. Evidence index

| What | Where |
|---|---|
| Gate logs m13–m16 | `claude-rc-perf/.tmp-gate/<tag>/` |
| Corpus results | `claude-rc-perf/.tmp-rc-quick/results-<tag>-{dev,smoke,full}.json` |
| RC adversarial repros (fixed, rejected, open) | `experiments/rc-review-20260928/` |
| RC design and future work | `docs/audits/rc-future-performance-2026-09-28.md` |
| EDA gap list and probes | `eda-bench/mylang/GAPS.md`, `eda-bench/mylang/probes/` |
| Stage 2 sources and decisions | `merge/devspeed-into-main` `fbd12a85`, `devspeed/*` branches |
| Differential fuzzer | `experiments/rc-fuzz/`, `zig build test-rc-fuzz -Dfuzz-seeds=N` |
