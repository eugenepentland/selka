# D9 close-out progress, 2026-09-26

This is the integration ledger for the [close-out plan](d9-closeout-plan-2026-09-26.md).
It records completed acceptance separately from work in progress. The three delegated
workers initially used GPT-6 Sol. At the user's request, the current workers
use GPT-6 Astra with extra-high reasoning; their worktrees and evidence were
preserved across the handoff. The orchestrator works in separate worktrees and serializes
full gates with `../.d9-closeout-gate.lock`. The original dirty checkout, `main`
(`b292660a`), and the pending devspeed merge are untouched.

## Accepted work

| Work | Code/evidence | Validation |
|---|---|---|
| WP-3a switch and checker | `7c1fc1f8`; [report](d9-stage3a-closeout-2026-09-26.md) | Full gate; switch-off IL 44/44 identical and guest results 642/642 unchanged; switch-on failures and informational costs recorded |
| WP-3c recursive values | `67afc00a`, `2e4ac251`; [report](d9-stage3c-recursive-values-2026-09-26.md) | Full gate; million-node equality/hash and both-backend tree measurements; existing depth-bounded printing truncation documented as a plan deviation |
| WP-3d class/Cell retirement | `19144c19`; [report](d9-stage3d-closeout-2026-09-26.md) | Full four-step gate at `f1265a0b`; S-expression 114/114 and Lox 63/63 in both modes; VM 13/13 scripts; historical/diagnostic class exceptions inventoried; tree performance remains a stage 3f blocker |
| WP-3e migration diagnostic/fix | `dd4ee663`; [report](d9-stage3e-closeout-2026-09-26.md) | 93/101 exact, 96/101 normalized census matches; 14 extras classified. Full four-step gate; Lox 63/63 tests and 13/13 VM scripts in both modes. Cyclic graph checker cost reduced from over 150 seconds to 0.30 seconds |
| WP-4pre physical borrow inference | `450d151a`; `docs/audits/d9-stage4pre-borrow-closeout-2026-09-26.md` on branch `codex/d9-stage4pre` | Gated prerequisite, integration after default switch. Full gate: 93/93 test steps, 2,089 tests; QBE 51/51, 427 tests; QBE build 29/29; formatting. Schematic: 72 added borrow classifications, 12 conservative copies; actual RC traffic measurement remains WP-4 |
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
NATIVE-STAGING-2 race fix (`78ec28ba`, ported as `cc5e5d54`). The combined T1/Q1/Q2 gate passed at `13681014`: test 91/91 steps and 2,079 executed tests, QBE 49/49 and 426 tests, QBE-build 29/29, formatting 2/2. The library-switch follow-up passed three focused CLI tests. WP-3d joined at `32414db3`, WP-3e at `2544b718`. The COW correctness candidate through `8514037f` joined provisionally at `9f73bf99`; this is not performance acceptance. The joined tree through `3a74a9b2`, including field-transfer proofs, inline COW marking and the recursive alias-warning fix, passed the full gate: test 93/93 steps, 2,103 executed tests; QBE 51/51 steps, 428 tests; QBE-build 29/29; formatting. The first resumed attempt exposed exponential recursive type traversal in the migration warning; `b39deab8` replaced it with a per-program graph fixed point, reducing the affected module check to 0.03 seconds.
Guardian feedback entries have been appended and committed in `guardian-zig`
for every accepted package above.

## In progress

| Work | Branch/worktree | Remaining acceptance |
|---|---|---|
| WP-3b COW | `d9/stage3b`, `../d9-stage3b` | Joined compiler/source gate green at `d4904aa7`: 93/93 test steps, 2,108 tests; QBE 51/51 and 428 tests; QBE-build 29/29; formatting 2/2. The 13-key class-free VM sweep after `2b889ba5` and `b51cddc1` still fails: 1.47277× QBE geomean, 1.63346× LLVM; 10/13 cases exceed 1.3× on each backend. Profiling found repeated copies of the guest collector's mark bitmap during `heap::blacken`; transfer-proof work is in progress |
| WP-3f default flip | Preparation at `codex/d9-stage3f-prep` (`b937d4fc`) | Full existing-suite gate green at source commit `b937d4fc`: test 94/94 steps, 2,112 executed Zig tests; QBE 51/51 and 428 tests; QBE build 29/29; formatting 2/2. Includes 652 language, 49 value, 42 smoke and 2 compatibility guests, plus 231 historical golden cases. The 113-probe oracle has zero undeclared disagreements. Guide-only follow-up passes docs/coverage/formatting 28/28. Report: `docs/audits/d9-stage3f-default-validation-2026-09-26.md` on that branch. Subsequent review found boxed-field and nested list/dictionary alias leaks; their fixes and performance acceptance still block integration |
| WP-4 reference counting | Not started | Requires 3f/4pre and the RC performance/RSS gate, including rewritten graph programs |
| WP-5 concurrency | Not started | Design after WP-4, following the existing concurrency proposal |

The plan's literal “on main” scheduling dependencies are being supplied by validated
integration commits so downstream development can continue without prematurely
landing partial D9 work. This is a scheduling deviation, not an acceptance waiver.
Performance limits, arenas, Debug compiler builds, real merge commits and final
joined validation remain required.

## Performance work still blocking acceptance

The compiler changes `8a31f237` and `2b889ba5`, together with the Lox source
patch `b51cddc1`, reduce selected VM equality N=30,000 to 1.0836× QBE and
1.1991× LLVM full LTO. [The report](d9-lox-ip-publication-2026-09-26.md)
preserves matched baseline measurements, source/binary hashes, 63/63 port tests
in both modes, 52 smoke runs, and 276 exact runtime-error trace comparisons.
The broader VM sweep still fails as described above; `trees` is worst at
2.3944× QBE and 3.8210× LLVM. Its counted run copies about 2.09 GB in 410,240
COW operations, dominated by copying marker lists in the guest collector.
These measurements do not waive the 43-key acceptance gate. Matrix
multiplication and byte scanning match baseline closely after private-scratch
lowering. The prior 116-key sweep remains preserved in the performance report.
Every compiler was Debug.

Field extraction/store-back proofs progressed from `b456c84b` through
`85667ce3` to `d83e26a0`. Matched ReleaseFast tree N=4 measurements fell from
47.6 billion instructions to 36.1 billion and then 7.29 billion, with unchanged
stdout. An earlier comparison of 390.8 billion to 36.1 billion mixed guest
Debug and ReleaseFast modes and is invalid; all compiler builds remained Debug.
These reductions are progress, not a performance pass. Stage 3f remains isolated
until the strict stage 3 limits hold.

A matched QBE ReleaseFast tree-interpreter N=4 median-three comparison also
remains far outside the target: 63,001,763 instructions for the class baseline,
6,909,105,659 for the pinned class-free source, and 5,373,781,841 for the
optimized class-free source (85.3× baseline). Every output matched. Profiling
attributes much of this cost to repeated recursive-box descendant sharing.
The next compiler experiment targets that traversal while preserving snapshot,
pin and arena guarantees; it has not yet earned acceptance.

Independent review after the default gate reproduced a nested boxed-record
alias leak using `record A: child: B` and `record B: items: list[int]; tail: [0]A`.
Mutating `changed.child.items` after `changed = original` also changes the
original. The recursive-box performance experiment must fix this immutable-box
write-back path and its GC allocation/root analysis before integration. A green
existing suite does not close this newly discovered correctness issue.

A second regression affects general nested collection paths:
`original = [{"k": [1]}]; changed = original; changed[0]["k"].append(2)`
changes the original too. It reproduces without recursive boxes. The nested
path planner loses a dictionary receiver that comes directly from a list
read; a separate correction is in progress on `codex/d9-nested-cow`.
The standalone box-path fix `daaf525b` and its lazy-sharing follow-on have
focused validation but are not yet accepted by the joined gate.
