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
| WP-3d class/Cell retirement | `19144c19`; [report](d9-stage3d-closeout-2026-09-26.md) | Full four-step gate at `f1265a0b`; S-expression 114/114 and Lox 63/63 in both modes; VM 13/13 scripts; historical/diagnostic class exceptions inventoried; formal VM performance remains a stage 3f blocker; tree timing is a supplemental audit |
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
| WP-3b COW | `d9/stage3b`, `../d9-stage3b`; optimization follow-up `d9/copy-through-transfers` | Gated compiler follow-ups through `f8dad8e8` are joined. The latest complete 13-key VM sweep (`adcbb4ca` plus source `6d54bace`) remains outside acceptance: 1.19444× QBE geomean, 1.35771× LLVM, with 4/13 and 9/13 over 1.3×. Subsequent root publication and variant-copy improvements have four-case measurements only; a frozen 43-key sweep is in preparation. Nested fixed-array correctness work remains open |
| WP-3f default flip | Preparation at `codex/d9-stage3f-prep` (`17540b57`; report `1f93f097`) | Full existing-suite gate green at source commit `17540b57`: test 94/94 steps, 2,116 executed Zig tests; QBE 51/51 and 428 tests; QBE build 29/29; formatting 2/2. Includes 652 language, 49 value, 42 smoke and 2 compatibility guests, plus 231 historical golden cases. The 113-probe oracle has zero undeclared disagreements. Guide-only follow-up passes docs/coverage/formatting 28/28. Report: `docs/audits/d9-stage3f-default-validation-2026-09-26.md` on that branch. Subsequent review found boxed-field and nested collection alias leaks. The box fix is gated and joined; the nested-list/dictionary fix is in validation with a further fixed-array follow-up. Final joined correctness and performance acceptance still block default integration |
| WP-4 reference counting | Not started | Requires 3f/4pre and the RC performance/RSS gate, including rewritten graph programs |
| WP-5 concurrency | Not started | Design after WP-4, following the existing concurrency proposal |

The plan's literal “on main” scheduling dependencies are being supplied by validated
integration commits so downstream development can continue without prematurely
landing partial D9 work. This is a scheduling deviation, not an acceptance waiver.
Performance limits, arenas, Debug compiler builds, real merge commits and final
joined validation remain required.

The Astra integration at `63b3a2ba`, including the gated box changes, closed-region
proof, transfer/alias scratch changes and latest Lox source, passed all four gates:
93/93 main steps with 2,112 executed tests, QBE 51/51 with 428 tests, build 29/29
and formatting 2/2. This does not include the unfinished nested-array follow-up
and does not establish performance acceptance. The isolated default candidate
passed its fresh four-step gate at `17540b57` (2,116 main tests). Later compiler changes and the nested-path follow-up still need joined validation.

## Performance work still blocking acceptance

The closed-region ownership proof `9f42e5a9` permits field extraction and
store-back across internal loops and match arms while preserving copies for
source observations, early exits and external entries. It reduces the Lox VM
`trees` N=5 counted copy traffic from about 2.09 GB to 50.9 MB. The matched
13-case VM sweep improves from 1.47277×/1.63346× to 1.39885×/1.49821×
(QBE/LLVM geomeans), still failing the plan's limits:
[report and raw measurements](d9-closed-region-transfers-2026-09-26.md).
Its standalone four-step gate passed before integration at `f71fe47a`.

The external Lox patch now keeps only used active-frame fields (`143a3e2b`)
and reads them directly from heap variants (`6d54bace`). The latter saves
2–6% in four matched VM cases on both backends using the same `9f42e5a9`
Debug compiler. It passes 63 port tests per mode, 52 VM smoke runs and 184
exact error-trace comparisons under native GC stress; a clean replay matches
every `.my` module byte for byte:
[direct-frame report](d9-lox-direct-frame-2026-09-26.md).
These source measurements are isolated improvements, not baseline acceptance.
The combined compiler/source still needs a fresh full gate and the complete
43-key-per-backend acceptance sweep: the historical 27 parity keys, three
schematic cases and 13 Lox VM scripts. The newly added recursive-tree parity
variant and Lox tree interpreter are supplemental, not extra formal thresholds.
No threshold or baseline has changed.

The complete latest-source VM sweep improves to 1.19444× QBE and 1.35771×
LLVM: [report](d9-vm-direct-frame-perf-2026-09-26.md). Root publication only
on allocating COW fallback (`af9b1318`) saves another 2–5% in four VM cases.
The immediate variant-copy optimization (`f8dad8e8`) removes two whole-Obj
copies from frame loading and saves another 1–3%; it passed the four-step
gate, three both-backend stressed guest regressions and 44 identical switch-off
IL comparisons: [report](d9-variant-element-2026-09-26.md). These follow-ups
and the validated environment readers are joined at `5bdd99ea`; this joined
commit is being measured independently and has not had its final full gate.

The tree interpreter's earlier matched 85.3× QBE regression is no longer
attributed primarily to recursive-box walking: lazy projection alone did not
resolve it. The closed-region proof removes repeated copies of `rt.objects`
and reduces an independently matched tree N=4 run from about 5.18 billion
to 156.9 million instructions (2.69× its same-run baseline). Smaller interpreter helpers (`ce215b9f`, composed with VM changes at
`bb699470`) reduce matched ADC-compiler N=4 instructions by 13.5% QBE and
11.4% LLVM. Scalar environment readers (`bb0fe9b4`) save a further 4–5% at
N=4/N=10. Each source change passes 63 port tests per mode, 104 smoke runs
and 184 stressed trace comparisons, with byte-identical patch replay. The
very expensive historical tree sweep was deliberately stopped after seven
completed rows; `a4260f7c` preserves it as partial supplemental evidence.
All compiler builds are Debug; no partial sweep establishes acceptance.

## Correctness follow-ups

The immutable-box alias leak in `changed.child.items.append(2)` is fixed by
`daaf525b`: nested writes detach boxes before making their mutable leaves
unique, preserving roots and generational barriers throughout allocation.
`0bde7992` makes immutable box transfers constant time and protects mutable
children on projection. The branch at `89ca1742` passed the full gate:
main 93/93 with 2,104 executed tests, QBE 51/51 with 428 tests, build 29/29,
and formatting. Million-node copy/equality/hash and a 1,101-node collection
chain passed on both backends. It joined at `3b2f8f7a`; final integration
validation passed at `63b3a2ba`; later joined changes need a new gate.

The separate nested regression
`original = [{"k": [1]}]; changed = original; changed[0]["k"].append(2)`
is fixed by `6b40a61c` in `codex/d9-nested-cow`: materializing the dictionary
receiver retains its owning path and source evaluation order. Fifteen guest
regressions and three adversarial key callbacks pass under GC stress. Its
main gate passed, while the QBE gate exposed an existing test that assumed
child log order matched spawn order. `bb83e6eb` now checks the live compile
session before declaration checking and verifies one call per child; all 228
native-test tests pass. The fix is joined at `6cac1c74`.

Nested fixed arrays still require a follow-up: paths through an inline array
must retain keys and owners across later index callbacks and avoid stale
dictionary addresses after rehash or entry replacement. The current scoped-pin prototype passes 18 normal array cases and 16
adversarial callback cases under GC stress, including recursive-box snapshots
and a 1,200-node recursive sibling. It detaches only the finite pending source
path and preserves constant-time transfers for unpinned boxes. Ancestor-box,
trap and cleanup-root review and the fresh four-step gate remain in progress.
A green existing suite does not close a newly discovered correctness issue.
