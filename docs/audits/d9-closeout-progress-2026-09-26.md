# D9 close-out progress, 2026-09-26

This is the integration ledger for the [close-out plan](d9-closeout-plan-2026-09-26.md).
It records completed acceptance separately from work in progress. The three delegated
workers use GPT-6 Sol. The orchestrator works in separate worktrees and serializes
full gates with `../.d9-closeout-gate.lock`. The original dirty checkout, `main`
(`b292660a`), and the pending devspeed merge are untouched.

## Accepted work

| Work | Code/evidence | Validation |
|---|---|---|
| WP-3a switch and checker | `7c1fc1f8`; [report](d9-stage3a-closeout-2026-09-26.md) | Full gate; switch-off IL 44/44 identical and guest results 642/642 unchanged; switch-on failures and informational costs recorded |
| WP-3c recursive values | `67afc00a`, `2e4ac251`; [report](d9-stage3c-recursive-values-2026-09-26.md) | Full gate; million-node equality/hash and both-backend tree measurements; existing depth-bounded printing truncation documented as a plan deviation |
| T1 library checking | `ff10f2f1` | New `check-module`; three focused CLI tests; full gate: test 91/91 steps, 2,075 executed tests; QBE 49/49, 426 tests; QBE build 29/29; formatting green |
| T2 formatting feedback and fixtures | `30948da9`, `df177cc2` | First-difference file/line/column; three focused CLI tests; 93 examples and nine copied pilot starters format clean; joined full gate |
| T3 indexed empty-list inference | `8842ac60` | Seven guest tests and twelve selected Zig tests; original regression reproduced; joined full gate |
| T4 sibling-test hint | `71196c15` | CLI regression covers missing/existing/already-loaded sibling and unchanged JSON/status; joined full gate |
| T5 primer diagnostics | `0472d324` | Runnable discard/public-interface examples; primer doctests and feature coverage; joined full gate |
| T6 headerless test formatting | `2d0d045e` | Formatter/test agreement and ordinary-module rejection regression; joined full gate |
| Q1 distinct contract traps | `cfa31018` | Dedicated runtime entries preserve literal assertion prefixes; 21 focused contract tests; full gate: test 91/91, 2,073 executed; QBE 49/49, 426; QBE build 29/29; formatting green |
| Q2 invariant cache and input validation | `bb02624b`; [report](d9-invariant-closeout-2026-09-26.md) | Cache relocation and nested native/JSON input regressions; full gate: test 91/91, 2,076 executed; QBE 49/49, 426; QBE build 29/29; formatting green |
| Q3 list write-back decision | `bafcdc4a`; [decision](d9-list-writeback-decision-2026-09-26.md) | Retains copied write-back based on prior LLVM full-LTO regression; documentation/whole-tree Guardian and joined full gate |

The first combined WP-3a/WP-3c/tooling gate passed at `bc07201f`:
91/91 test steps, 49/49 QBE steps with 426 tests, 29/29 QBE-build steps,
and formatting. T1, Q1 and Q2 subsequently passed their own full gates and were
joined with two-parent merges. Q2 also includes the independently reproduced
NATIVE-STAGING-2 race fix (`78ec28ba`, ported as `cc5e5d54`). Later implementation work requires another joined gate.
Guardian feedback entries have been appended and committed in `guardian-zig`
for every accepted package above.

## In progress

| Work | Branch/worktree | Remaining acceptance |
|---|---|---|
| WP-3b COW | `d9/stage3b`, `../d9-stage3b` | Phase 2 `a95dabb6` passes 37 value-semantics guest tests under GC stress and native heap tests; full gate exposed stale IL assertions and an independent staging race; performance gate pending |
| WP-3d class/Cell retirement | `codex/d9-stage3d` | Active inventory migrated; S-expression 114/114 both modes; Lox 63/63 both modes and VM 13/13 pinned scripts with COW; full gate pending. Historical snapshots/rejection fixtures are explicitly inventoried exceptions; tree interpreter remains slow |
| WP-3e migration warnings/fix | `codex/d9-stage3e` | Minimal native fix-tool prerequisite ported; historical P1 agreement now 80/101 exact, 83/101 after three proven line shifts, below the required 95%; 30 extras. Dual-mode explicit mut-record fix `18d66f92`; analysis and final gate pending |
| WP-3f default flip | Not started | Waits for 3b/3d/3e; includes complete switch-on corpus migration and the stage 3 performance gate |
| WP-4pre borrow inference | Not started | Requires explain output, invalidation tests and schematic transfer measurements |
| WP-4 reference counting | Not started | Requires 3f/4pre and the RC performance/RSS gate, including rewritten graph programs |
| WP-5 concurrency | Not started | Design after WP-4, following the existing concurrency proposal |

The plan's literal “on main” scheduling dependencies are being supplied by validated
integration commits so downstream development can continue without prematurely
landing partial D9 work. This is a scheduling deviation, not an acceptance waiver.
Performance limits, arenas, Debug compiler builds, real merge commits and final
joined validation remain required.
