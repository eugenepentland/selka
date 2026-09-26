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
| WP-3d class/Cell retirement | `19144c19`; [report](d9-stage3d-closeout-2026-09-26.md) | Full four-step gate at `f1265a0b`; S-expression 114/114 and Lox 63/63 in both modes; VM 13/13 scripts; historical/diagnostic class exceptions inventoried; tree performance remains a stage 3f blocker |
| WP-3e migration diagnostic/fix | `dd4ee663`; [report](d9-stage3e-closeout-2026-09-26.md) | 93/101 exact, 96/101 normalized census matches; 14 extras classified. Full four-step gate; Lox 63/63 tests and 13/13 VM scripts in both modes. Cyclic graph checker cost reduced from over 150 seconds to 0.30 seconds |
| WP-4pre physical borrow inference | `450d151a`; [report](d9-stage4pre-borrow-closeout-2026-09-26.md) on branch `codex/d9-stage4pre` | Gated prerequisite, integration after default switch. Full gate: 93/93 test steps, 2,089 tests; QBE 51/51, 427 tests; QBE build 29/29; formatting. Schematic: 72 added borrow classifications, 12 conservative copies; actual RC traffic measurement remains WP-4 |
| T1 library checking | `ff10f2f1`, `f3f3a53f` | New `check-module`; three focused CLI tests; full gate: test 91/91 steps, 2,075 executed tests; QBE 49/49, 426 tests; QBE build 29/29; formatting green |
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
NATIVE-STAGING-2 race fix (`78ec28ba`, ported as `cc5e5d54`). The combined T1/Q1/Q2 gate passed at `13681014`: test 91/91 steps and 2,079 executed tests, QBE 49/49 and 426 tests, QBE-build 29/29, formatting 2/2. The library-switch follow-up passed three focused CLI tests. WP-3d joined at `32414db3`, WP-3e at `2544b718`. The COW correctness candidate through `8514037f` joined provisionally at `9f73bf99`; this is not performance acceptance, and the combined tree requires another full gate.
Guardian feedback entries have been appended and committed in `guardian-zig`
for every accepted package above.

## In progress

| Work | Branch/worktree | Remaining acceptance |
|---|---|---|
| WP-3b COW | `d9/stage3b`, `../d9-stage3b` | Full gate green at `54edf716` (93/93 test steps, 51/51 QBE steps and 426 tests, QBE-build 29/29, formatting 2/2). Million-node scalar copies pass both backends; mutable depth overflow reports `R_COW_DEPTH`. Dynamic counting and field-transfer optimization added afterward; final performance and refreshed gate pending |
| WP-3f default flip | Preparation at `codex/d9-stage3f-prep` (`9cffdde1`) | CPython-oracle preparation retains three explicit list/nested-list/dictionary divergences; 113-probe switch-on suite has zero undeclared disagreements. Flip waits for 3b performance acceptance; [guest inventory](d9-stage3f-switch-corpus-handoff-2026-09-26.md) records 595 passing, 20 failing and four refused programs/tests |
| WP-4 reference counting | Not started | Requires 3f/4pre and the RC performance/RSS gate, including rewritten graph programs |
| WP-5 concurrency | Not started | Design after WP-4, following the existing concurrency proposal |

The plan's literal “on main” scheduling dependencies are being supplied by validated
integration commits so downstream development can continue without prematurely
landing partial D9 work. This is a scheduling deviation, not an acceptance waiver.
Performance limits, arenas, Debug compiler builds, real merge commits and final
joined validation remain required.

## Performance work still blocking acceptance

The class-free Lox tree port is correct but expensive: the bounded QBE binary-tree
N=4 case measured 390.8 billion instructions against 192.6 million for the pinned
class source. A conservative field extraction/store-back optimization (`b456c84b`)
with its sibling-field follow-up (`85667ce3`) reduced a matched guest Debug
measurement to 293.7 billion with matching output (about 25%). Matched ReleaseFast
measurements were 47.6 billion before and 36.1 billion after the first proof. An
earlier comparison of 390.8 to 36.1 billion mixed guest build modes and is invalid;
all compiler builds remained Debug. This is progress, not a performance pass. The class-free VM equality case at N=1,000
measured about 755 million instructions after that optimization against 41.3
million for the class baseline. Sol and the orchestrator are profiling the two
remaining costs separately. Stage 3f is not ready to flip.
