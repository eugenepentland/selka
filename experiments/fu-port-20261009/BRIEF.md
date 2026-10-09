You are porting mylang's F/U integration onto the newest `main`. `main` changed the language's surface syntax while the work below was being built and timed. Work autonomously to the exit, then stop and report.

## What you are porting

**`claude/fu-x`** (integration worktree `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure`; read only for you) is `main` `ab85c16c2` plus:
- lane **U1**, uniqueness and state: `own.zig` test hoisting, `forward.zig`, `emit_state.zig`, sinking in `stores.zig`, buffer `realloc` in `core_bytes.c`;
- lane **F2**, index facts: `index_keys.zig`, `index_checks.zig`, `fields.zig`, bounds versioning in `version.zig`, `facts.zig`, and the wrap in `emit_llvm.zig`;
- coordinator fixes and evidence.

**Reports.** The lanes' reports are `experiments/u1-state-20261009/REPORT.md` and `experiments/f2-index-20261009/REPORT.md`. The integration's is `experiments/fu-x-20261009/` (`REPORT.md` there, commit `80f1d6ce5`).

**Qualification on `ab85c16c2`:** the full gate, `qualify_merge` 1518/0/0 in both modes, fuzz 9×200, Lox 974 + 65, EDA 34 + 310, and parity. CPU-10 timing is done.

**What has moved on `main` since `ab85c16c2`:**
- `d21b2dfa9`: the readable syntax redesign. `func`, `const`/`mut` bindings with block scope, `T[]`/`T?`/`FixedArray`, `fails`/`fail`/`try`, headerless modules and more; see `docs/audits/frontend-syntax-redesign-2026-10-09.md`. It migrated the compiler, stdlib, tests, benchmarks and guides, including every `test/core` fixture and Zig-embedded source that existed at `ab85c16c2`.
- `e23651f6a`: optimized debug guest builds (Core passes and LLVM O2).
- `main` may have moved again by the time you start. Use whatever it is then, and record the hash.

## Your work

1. **Set up.** Use worktree `/home/epentland/ai/canopy/mylang-worktrees/claude-main-ce`. It is locked for this session and currently a detached checkout of `ab85c16c2`.
   - Create branch `claude/fu-port` at `claude/fu-x`'s head: `git switch -c claude/fu-port claude/fu-x`.
   - Merge `main` into it: `git merge main`. Don't rebase; `claude/fu-x`'s commits are the qualified evidence.
2. **Resolve conflicts, keeping both sides' behaviour.** Expect them in:
   - `SPEC.md`;
   - `root_test.zig`;
   - test files the redesign rewrote;
   - perhaps `emit_llvm.zig`, `passes.zig` and `facts.zig`, if `e23651f6a`'s optimized-debug work touched the pass pipeline. Read that commit. If it runs the Core passes in debug builds, U1's and F2's passes now run there too. Check that this is sound: they assume release, so check the `verify`/`release` conditions.
3. **Migrate the integration's new mylang sources to the new syntax.** These include:
   - `test/core/u1_*.my`, `test/core/f2_*.my`, and any other `.my` fixture the integration added;
   - the mylang source strings embedded in `src/core/u1_state_test.zig`, `src/core/f2_index_test.zig` and any other test file the integration added or changed;
   - the expected outputs those tests assert, if the migration changes them. It shouldn't change program output, so investigate any change.

   Use `mylang fix` (`docs/tooling/fix.md`) where it applies. Check every migrated file against the redesign's rules; `fix` documents what it cannot do (escaping block locals, embedded propagation). Leave frozen evidence under `experiments/` in its original syntax, as the redesign did.
4. **Migrate copies of the two external benchmark ports.** These are needed for the gates and for future timing.
   - Lox: copy `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.mylang-cache/lox` into your `.mylang-cache/lox`, without `.tmp/` and `results/`. Migrate `ports/mylang` and `ports/mylang-base` with `mylang fix`. The redesign's audit says the legacy Lox project migrates with 412 edits. Create `.tmp/lox-bench/tmp` in your worktree root.
   - EDA: copy `/home/epentland/ai/canopy/eda-bench-wt/claude-eda-bench-newcore/mylang` into `.mylang-cache/eda-src` and migrate it.
   - Never edit the originals.
5. **Gates.** Every one must pass on your final commit; a wrong answer is never acceptable.
   1. `zig build` (Guardian), `zig build test --summary all` and `zig build fmt-check`.
   2. `python3 experiments/new-core-s5-20261007/tools/qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install --evidence <a fresh directory inside experiments/>`: **1518/0/0** in debug and release. Never reuse an evidence basename. If the redesign changed what `qualify_merge` expects, follow what `main`'s own last qualification did, and say so.
   3. Frozen fuzz 9×50: `experiments/new-core-s5-20261007/tools/fuzz_matrix.py --references experiments/new-core-s5-20261007/references/fuzz-v1.json.gz --new <a copy of your Debug zig-out/bin/mylang> --cases 50 --evidence <dir below experiments/> --jobs 3`. All 9 kinds PASS. It needs a clean tracked tree. If the frozen references can't apply to the new syntax, report exactly why and what `main` itself does.
   4. Lox, with your migrated copy and your ReleaseFast compiler's plain release Lox binary:
      - `python3 harness/lox_bench.py conformance --binary <it> --engine both --stress -j 4`: **974/974**;
      - `mylang test .` in `ports/mylang`: **65/65**.
   5. EDA, migrated:
      - all 34 cases byte-identical to the goldens (see `experiments/fu-x-20261009/tools/ce.py` for how the integration ran them);
      - `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G --cache-dir <yours>`: **310/310**.
   6. Every parity program's output equals its `.expected` (`bench/parity`, as migrated on `main`).
6. **Does the timing carry over?** Build ReleaseFast compilers of:
   - `claude/fu-x` (`~/.cache/mylang/fu-final-x` already is one);
   - the newest `main`;
   - your port.

   Then answer, by comparing emitted LLVM (`mylang build --release --emit-llvm`) across the 45 parity programs, the 46 rows (`test/core/row_*.my` and the S0 rows), the Lox port and EDA. Normalize away metadata numbering and site ids, as `experiments/fs-x-20261009/tools/llvm_diff.py` does, but compare real code exactly.
   - **(a)** For each program, is the port's code for its new-syntax source identical to `fu-final-x`'s code for the old-syntax source from `claude/fu-x`'s tree? If so, the integration's CPU-10 timing carries over. List the programs that differ and say why: the redesign's own codegen changes, or an interaction.
   - **(b)** For each program, does the port differ from the newest `main` only in the ways `claude/fu-x` differed from `ab85c16c2`? A spot check of the programs the lanes targeted is enough.
   - **Measure instructions on CPU 8** for the targeted programs: matmul, sort_quick, sieve, nbody, str_build, knucleotide, list_append_sum, the 4 Lox VM cells and 2 tree cells (scripts are in `/home/epentland/ai/canopy/mylang-worktrees/claude-parity-measure/.tmp/pm/lox/`, migrated where needed), and EDA. Do it for port against newest main, interleaved `perf stat`, so the gains are confirmed on the new base.
   - Take no wall time on CPU 10.

## Rules

- **Builds** go through `scripts/build-slot.sh`, with at most four build-heavy processes machine-wide.
- **CPUs:** never run heavy work on CPUs 2, 3, 10 or 11. Measure only on CPU 8.
- **Caches and `TMPDIR`** stay inside your worktree.
- **Disk.** `/home/epentland/ai` filled up once today. Check `df -h /home/epentland/ai` before big builds and delete your own scratch when done.
- **Never end your turn to wait for background work.** Run long steps in the foreground (timeout up to 600000 ms) and split longer ones.
- **Never `pkill -f`.** Kill only PIDs you started.
- **Evidence** goes in `experiments/fu-port-20261009/`, under 10 MB.
- **Commits** go on `claude/fu-port`, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never merge into `main`, never push, and never touch another worktree's files, branches or the original port trees.
- **Stop and report** if:
  - a wrong answer appears that you cannot fix;
  - a migration needs a language decision;
  - Guardian needs a ratchet acceptance;
  - a gate fails for a reason outside the port.
- **Your final reply** is the full report:
  - the `main` hash you merged;
  - the conflicts, and how each was resolved;
  - what you migrated, with the `mylang fix` edit counts;
  - every gate receipt;
  - the LLVM identity results (a) and (b), with the reasons for each difference;
  - the CPU-8 instruction table against newest main;
  - where the migrated Lox and EDA copies are, for future timing runs;
  - remaining limits.

  Also try to write `experiments/fu-port-20261009/REPORT.md`.
