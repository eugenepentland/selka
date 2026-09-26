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
| WP-4pre physical borrow inference | `450d151a`, refreshed at `ba4a1340`; report `86da9613` on branch `codex/d9-physical-borrow-after-astra` | Isolated prerequisite, integration after default switch. Refreshed full gate: 93/93 main steps, 2,119 executed tests; QBE 51/51, 429 tests; QBE build 29/29; formatting. Schematic: 72 added borrow classifications, 12 conservative copies. Four matched VM cases show approximately unchanged GC cost; actual RC traffic measurement remains WP-4 |
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
| WP-3b COW | Compiler `91d1311e`, joined gate `b59cf06f`; source through `3fd1c590` | Scoped receivers and indexed transfers pass the full joined gate: 2,119 main tests, 428 QBE tests, native-build and formatting. Independent stress/44-IL evidence is joined. The pre-setter 43-key sweep passes QBE (1.02928×, no outliers) but fails LLVM (1.07134×, three outliers). Setter plus global-table hoist is being measured. Broader external Lox parser/resolver native-stress failures are under investigation |
| WP-3f default flip | Preparation at `codex/d9-stage3f-prep` (`75820f45`; report `7b51bacd`) | Current four-step gate passes: 2,123 main tests, 428 QBE tests, native-build and formatting; 652 language, 139 value, 42 smoke and two compatibility guests execute with zero cached results. The historical golden/oracle policy is retained. Formal performance and the separately discovered Lox native-stress investigation remain open |
| WP-4 reference counting | Not started | Requires 3f/4pre and the RC performance/RSS gate, including rewritten graph programs |
| WP-5 concurrency | Not started | Design after WP-4, following the existing concurrency proposal |

The plan's literal “on main” scheduling dependencies are being supplied by validated
integration commits so downstream development can continue without prematurely
landing partial D9 work. This is a scheduling deviation, not an acceptance waiver.
Performance limits, arenas, Debug compiler builds, real merge commits and final
joined validation remain required.

The joined compiler at `b6328bcd` passed all four gates: 93/93 main steps
with 2,118 executed tests, QBE 51/51 with 428 tests, native-build 29/29 and
formatting 2/2. It includes pure recursive-box reads, scoped nested receivers,
closed-region transfer analysis and the earlier copy/root optimizations.
Source-only Lox improvements join at `d7f4cf85`; compiler code is unchanged
from `b6328bcd`. The isolated default candidate is refreshed to this source
and remains separate pending its current gate and performance acceptance.

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
The final combined compiler/source must satisfy the complete
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
and the validated environment readers joined at `5bdd99ea`. Its complete
43-key diagnostic sweep passed every output/SVG check but failed performance:
QBE geomean 1.06194×, LLVM 1.09626×. Three QBE and four LLVM programs
exceeded 1.3×; the raw data and exact baseline/compiler hashes are in the
[43-key audit](d9-performance43-2026-09-26.md).

The later pure-box read guard (`f6b5de09`) reduces the parity binary-tree ratio
from 3.31× to 1.20× on QBE and from 2.15× to 1.07× on LLVM in matched
measurements. Scoped receivers, instance/class scalar readers and late closure
publication are now joined. Late publication reduces the matched VM closures
case by 4.9% QBE and 7.7% LLVM. The fresh 43-key sweep records this exact
combination; individual improvements do not establish acceptance.

The indexed payload-transfer proof `aa2fcbc6` and matching Lox setter
`ff9096bb` are now joined. Independent review found and fixed an earlier-match
alias counterexample before acceptance of that proof. The combined compiler
passes its full gate and independent scoped-receiver checks, with all 44
legacy IL inputs identical. The composed Lox source `b8fdb39e` passes 65 normal
tests per mode, 104 smokes and 184 native-stressed VM traces.

The complete scoped-receiver snapshot has QBE geomean 1.02928× with no outlier,
but LLVM 1.07134× with binary trees, closures and method calls over 1.3×:
[full measurements](d9-performance43-scoped-2026-09-26.md). That snapshot
precedes the setter. The subsequent global-table hash hoist `617ce4dc` removes
two more COW transfers and improves matched closures by 9.7% QBE/18.9% LLVM
and method calls by 5.6%/10.4%. Both proposed frame caches and the weak scalar
upvalue-accessor experiment were rejected. The complete setter/hoist/default
combination is being measured; individual gains are not final acceptance.

An expanded external Lox source-test run under native GC stress exposes ten
parser/resolver panics. The normal 65 tests and VM stress traces pass. The
failure reproduces before the hash hoist and in both value modes, while an
original class-based parser test passes on `60b668cf`. Three Astra agents are
reducing it, reviewing descriptor/root lifetime and running historical controls.
The current full gate does not include this broader stress scope, and its
green result does not close that investigation.

The isolated physical-borrow prerequisite has been refreshed onto the current
default at `bd923864`; its full gate passes 2,128 main tests, 429 QBE tests,
native-build and formatting. The [RC readiness inventory](d9-rc-readiness-2026-09-26.md)
sets out receiver lifetime holds, arena ownership, iterative destruction and
legacy GC compatibility. WP-4 implementation and WP-5 remain unstarted.

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

The nested receiver fixes (`6b40a61c`, `a2c62941`, `426d201e`) are now
joined at `b6328bcd`. Scoped pins preserve the selected receiver across index
callbacks, dictionary replacement/rehash and nested fixed arrays. They copy
only the finite pending path and retain constant-time unpinned box transfers.
The branch passed all four gates and six deep recursive checks. Independent
joined validation passes all 55 regressions on each backend under GC stress,
with zero cached verdicts, and all 44 switch-off IL comparisons are byte
identical: [joined evidence](d9-nested-cow-joined-validation-2026-09-26.md).
The full integration gate above closes these known correctness follow-ups.

The Lox migration had a separate assignment bug: evaluating a right-hand side
could mutate another receiver field, then a stale saved instance overwrote
that mutation. `4a926ec7` keeps the original receiver identity and reloads its
fields after right-hand-side evaluation. Two new regressions fail before the
fix and pass in both base and optimized ports. The composed source includes
this fix, scalar instance/class readers and late closure publication. Each
component has port tests, both-backend smoke/stress validation and exact patch
replay; the current composition is included in the fresh performance sweep.
