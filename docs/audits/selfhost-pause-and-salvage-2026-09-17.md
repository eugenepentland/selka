# Self-hosting pause and salvage (2026-09-17)

## Decision

The P6 self-hosting port on `selfhost/integration` is **paused** at checkpoint 32
(`f614b108`), the branch is tagged `selfhost-paused-2026-09-17`, its worktree and
the stage-0 pin cache are kept, and the twelve satellite `selfhost/*` worktrees
are removed with their branches retained. The port is retained as a **fixture,
not a product**: it is the largest `.my` program that exists, and it stays useful
as a maintained compiler-shaped workload, a regression corpus, and a demand
census for language work.

Work resumes on the ranked language items in the two 17 September audits, not on
P7-P10.

## Why

The port is pinned to a stage-0 oracle built from `290b5c5f` plus the P6
checkpoint 1 working tree (pin `fdcb34f2...`). Since that base the velocity branch
has moved 135 commits ahead with effects-v3, mutation origins, inferred ceilings,
the semantic cache and specialization replay. The port already reproduces pinned
semantics that the velocity branch has since changed - the ledger records
`dict.items()` yielding `(position, value)` because the *pin* does, while the
current tree yields key/value.

That makes the remaining packages a second implementation of moving machinery:
P7 (CLI, test runner, diagnostics parity) and P8 (incremental engine) would each
re-derive the new frontend in `.my`, and every subsequent language change would
have to be made twice, once per frontend. The port's own risk control says the
language must hold still until stage 1 exists; the audits say the opposite is
what agents need now. Both cannot hold at once, and the language changes are the
goal, so the port stops.

## Corrections to the analysis this record is based on

The proposal was drafted against a snapshot that had already moved. Recording the
corrections so a successor does not repeat them:

- It reported **checkpoint 31** and **38 uncommitted lines in `check.my`** with
  "an agent editing `check.my` right now", and asked not to kill that work
  mid-write. By the time the plan was actionable that work was verified and
  committed as **checkpoint 32** (`f614b108`); `git status` in the worktree is
  empty. The pause therefore happens between checkpoints, not mid-write.
- It reported that `check.my` and `lower.my` were unmeasurable. Checkpoint 32
  removed the two checker blockers, so both are now **checker-complete**
  (`project-complete|1`, 0 unsupported, 0 diagnostics). What remains for them is
  lowering backlog, not a checker gap, and the refusal census is now complete for
  every module for the first time.

Neither correction changes the pause decision; both change what a successor
should expect to find.

## Verified state at the pause

| Item | Measured value |
| --- | --- |
| Branch / checkpoint | `selfhost/integration` at `f614b108` (P6 checkpoint 32) |
| Worktree status | clean (`git status --porcelain` empty) |
| Stage-0 pin | `fdcb34f2e75c0730257952fa8d08510ffe8925d5bda50f85bdecd070e78bf203`, unchanged |
| Port size | 1005 `.my` files; 19243 lines under `selfhost/` |
| Differential fixtures | 429 |
| Satellite worktrees | 12, all clean; 5 fully merged, 7 carrying one unmerged commit each (branches retained) |
| Main checkout | `codex/velocity-integration`, 79 dirty paths, 61 files, +3896/-486 |
| Packages | P0-P3 verified; P4 scalar slice verified, S2-S6 pending; P5 done; P6 checkpoint 32 (checker-complete, 546/695 lowering refusals in the checker/lowerer closures); P7-P10 not started |

The port's gate is green at the pause: Zig `44/44 steps, 1052/1052 tests`,
`test-qbe 37/37`, `test-qbe-build 23/23`, `fmt-check` clean, and all 19 aggregate
self-host runners plus the corpus sweep exit 0.

## Salvage

1. **Finish the open checkpoint, commit, write a PAUSED handoff.** Done: the
   checkpoint was committed as `f614b108` before the pause, and the handoff note
   is at the top of `## Resumable handoff` in
   `selfhost-execution-progress-2026-09-16.md`.
2. **Tag the branch, keep the worktree and the pin cache.** Done: tag
   `selfhost-paused-2026-09-17`.
3. **Remove the twelve satellite worktrees, keep the branches.** Done. Each was
   clean, so no uncommitted work was at risk, and the branches still hold their
   commits.
4. **Commit the main checkout's uncommitted work.** Pending; it is another
   workstream's in-flight state and has not been reviewed here.
5. **Cherry-pick the standalone Zig-side pieces into the velocity branch.**
   Pending, and partly moot: the main checkout already *is* the velocity branch
   with that work uncommitted, so this needs a decision about what is
   duplicative.
6. **Freeze `selfhost/` as a fixture.** The documentation half is done (this
   record and the handoff note). The engineering half - wiring the 429 fixtures
   into the Zig regression corpus and using the tree for the S1 latency gate - is
   not started.

## What to work on instead

The ranked order from the two 17 September audits, with items the uncommitted
tree already closed removed:

1. **Decide the aliasing model** (`agent-audit-guide-scorecard-2026-09-17.md`
   §2.1): writes through a record copy still silently vanish and the new warning
   has a false positive on `Cell` parameters. This decision blocks several items
   below.
2. **Silent wrong answers** (`agent-velocity-2026-09-17.md` §1): the record-copy
   write, `dict.items()`, and `round`'s half-away-from-zero behaviour.
3. **Expression idioms batch** (§3.2-3.5): tuples, `is None` narrowing, number
   formatting, methods on records, plus ternary, chained comparisons, list
   concatenation, `**`, bit operators, f-string specs, `str * int`, record
   equality and `set`. No design work, and the probes showed it removes the most
   repair turns.
4. **Diagnostics as an oracle** (§4 and scorecard §2.6): did-you-mean on every
   name error, expected-versus-got on arity, `mylang explain E_CODE`,
   per-subcommand help.
5. **Change-impact while the project is red** (scorecard §2.2).
6. **Edit-loop fixed cost** (scorecard §2.3, velocity §5.4).
7. **Show inferred mutation in `list-interfaces`** (scorecard §2.4), then
   methods on records and the module-ergonomics items (velocity §2.5).
8. **Surface removal** (velocity §6, scorecard §2.9): reserved legacy keywords,
   unused subcommands, ungated Python files, `dump-bytecode`.
9. **Unblock and run the productivity trial**: review the task packs, freeze the
   cohort and model baseline, run it. It is the only evidence that answers whether
   any of this made agents faster.

## Resume criteria

Resume self-hosting when all three hold: the bootstrap subset has been stable for
a release, the scorecard clears its next threshold, and the productivity trial
shows agents are productive on compiler-shaped `.my` code. At that point the
stale base is the first problem to solve, not P7: the port must be re-based onto
a current stage-0 oracle before any further package work.
