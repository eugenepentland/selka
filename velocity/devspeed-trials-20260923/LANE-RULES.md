# Rules for every development-speed implementation lane (2026-09-23)

Context: the audit `docs/audits/development-speed-2026-09-23.md` (read the copy at
`/home/epentland/ai/canopy/mylang-worktrees/devspeed-audit-20260923/docs/audits/development-speed-2026-09-23.md`).
Its §9 lists the recommendations; your lane prompt says which one is yours and what
"done" means.

## Git

- Work only in your own git worktree. First run
  `git checkout -B <your-branch> base/devspeed-impl-20260923` (commit `371dbd17`: `main`
  fae238ec plus seven audited fixes; its full gate is green).
- Never touch `/home/epentland/ai/canopy/mylang` itself (another session's dirty
  checkout), other worktrees, `main`, `devspeed/integration` or any other lane's branch.
  Never `git reset --hard`, never force-push, never merge into `main`.
- Commit logically on your branch. End every commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The pre-commit hook runs
  Guardian over the whole working tree, so every commit must be self-consistent (tests,
  spec tags and SPEC bullets land together).

## Building and testing (the machine is shared by six lanes)

- Prefix every `zig build …` with
  `~/capbuild /home/epentland/ai/canopy/mylang/.tmp/perf-plan-20260922/slot.sh build`
  (use `slot.sh gate` instead of `slot.sh build` for the full-gate steps). `capbuild`
  caps memory at 16 GB and sets `TMPDIR=/home/epentland/.cache/mylang-tmp`.
- Add `--maxrss 8000000000` to `zig build test`.
- While iterating use `python3 scripts/focused_test.py units FILTER` /
  `python3 scripts/focused_test.py cli FILTER` and `zig build -Dcompiler-only`
  (installs `zig-out/bin/mylang` in seconds). For timing, build a ReleaseFast compiler:
  `zig build -Doptimize=ReleaseFast --prefix <dir>`.
- Guest programs you run for experiments: `TMPDIR=/home/epentland/.cache/mylang-tmp`.
- Before finishing, run the full gate once, all green:
  `zig build test --summary all --maxrss 8000000000`, `zig build test-qbe --summary all`,
  `zig build test-qbe-build --summary all`, `zig build fmt-check`, and
  `zig-out/bin/mylang test tests/lang`.

## Repository rules (CLAUDE.md and Guardian)

- Every behavioural change under `src/` needs a test carrying `// spec: TAG` (extra tests
  for the same bullet use `// spec-case: TAG`) and a matching one-line
  `- [TAG] …` bullet in `SPEC.md`, inserted next to related bullets. Bullets are single
  lines; never insert inside a wrapped multi-line bullet.
- Structs ≤ 7 fields, functions ≤ 6 parameters, `///` doc comment on every `pub`
  declaration, no `if`/`while`/`switch`/extra `for` at the top level of a test body,
  at least one `expect*`, lines ≤ 240 characters, no `@import` cycles, new `src/*.zig`
  files reachable from a root in `guardian.toml`. The type-size ratchet must not grow
  unless you accept it deliberately
  (`../guardian-zig/zig-out/bin/guardian-check accept type-size .`).
- Language behaviour is tested in `tests/lang/<area>.my` (`public def test_*() -> bool`);
  diagnostics, CLI and tooling in Zig (`src/*_test.zig`, `test/integration.zig`).
- A user-visible feature needs its `src/features.json` entry and a documented runnable
  example (`mylang doc-coverage .`, `mylang doctest .`).

## Scope

Stay inside your lane's scope. Shared files (`SPEC.md`, `src/features.json`,
`src/sema.zig`, `src/main.zig`, docs) get small, localized edits so the integrator can
merge six branches. If you need something from another lane, say so in your report
rather than implementing it.

## Finish

Commit a report at `docs/audits/devspeed-<lane>-2026-09-23.md`: what changed, the
measurements against your acceptance rule (with commands), known gaps, and anything the
integrator must know (conflict risks, follow-ups). Reply with: branch, head SHA, gate
results, acceptance status.

## Fixtures

- Scale ladder: `/home/epentland/ai/trials/devspeed-20260923-private/scale/`
  (`gen_scale.py OUT M F`, `run_scale.py TIER --langs mylang-debug,go,rust,zig`;
  copy both, set `MYLANG` in `run_scale.py` to your compiler, generate your own tiers
  in your worktree's scratch area). Tiers: 10k = `25 36`, 50k = `120 38`, 200k = `480 38`.
  Run timings under `taskset -c 0-11` and report the load average; the integrator
  re-measures on a quiet machine.
- The Lox interpreter port with its original end-to-end tests:
  `/home/epentland/ai/trials/devspeed-20260923-private/lox-mylang-full/` (spec, corpus
  and conformance harness in `/home/epentland/ai/trials/devspeed-20260923-private/probe/benchmarks/lox/`).
  Copy it before modifying.
