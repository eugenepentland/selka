# D9 close-out progress, 2026-09-26

This is the integration ledger for the [close-out plan](d9-closeout-plan-2026-09-26.md).
It records completed acceptance separately from work in progress. The three delegated
workers initially used GPT-6 Sol. At the user's request, the current workers
use GPT-6 Astra with extra-high reasoning; their worktrees and evidence were
preserved across the handoff. The orchestrator works in separate worktrees and serializes
full gates with `../.d9-closeout-gate.lock`. The original dirty checkout, `main`
(`b292660a`), and the pending devspeed merge are untouched.

The active user goal is Stage 4 performance acceptance. The earlier
[30-program joined diagnostic](d9-rc-joined-parity-2026-09-27.md), measured on
fully gated `5b876012`, completes all 60 rows with correct output. Instruction
geomeans are **2.831332× QBE / 3.283233× LLVM** against accepted GC; only 8/30
and 9/30 programs meet the 1.3× cap. Median peak RSS is 0.755455× / 0.745243×
GC for this subset. All 13 Lox programs per backend are excluded, so this does
not establish the required complete-corpus acceptance.

Dictionary-tail `3c4251e8`, native type-fact `c71d4046` (report correction
`242439ec`) and adjacent variant read `4f60ff94` now pass the combined gate at
`c90c84be`. The [five-program combined diagnostic](d9-rc-ownership-joined-2026-09-27.md)
measures unchanged dictionary counting at **6.598428× QBE / 7.383473× LLVM** and
Lox binary trees N10 at **27.911220× / 44.806239× GC**. Schematic cases remain
17.51–17.58× / 26.23–26.76×. All outputs and four counted runs pass; all sixty
instruction observations report 100% running. This diagnostic measures no RSS
and does not replace complete-corpus acceptance.

The [historical full corpus](d9-rc-corpus-2026-09-27.md) has also finished on its
older immutable `e926d1e1` compiler: all 86 rows have correct output, with failing
instruction geomeans **13.833063× / 20.538954×** and lower median peak RSS. These
are predecessor results, not the current combined build. Lox accounts for 98.58%
of its cumulative recorded instruction-counter time, excluding builds and RSS
runs. Focused diagnostics guide development; the final accepted build still
requires the unchanged full corpus.

Anchored immutable dictionary keys, repeated scalar-loop readiness validation,
named owning-record scalar writes and plain-result read-only helper composition
now pass the [combined correctness checkpoint](d9-rc-readers-joined-gate-2026-09-27.md)
at `c47058f5`. Their isolated measurements improve dictionary, append, Lox and
schematic workloads but remain above the performance cap; those comparisons
use different recorded bases and must not be multiplied into a combined result.
The separate dictionary-loop candidate `88f4e477` reaches **1.481235× QBE /
1.461035× LLVM** against accepted GC, requiring another 12.2% / 11.0% reduction
to reach 1.3×. It is not part of this combined gate. Current follow-on work
addresses scalar-list read loops, managed borrowed-helper composition and the
remaining plain dictionary overwrite cost. Full current combined performance
has not been measured. GC remains the default; changing it is outside this
active performance goal.

Stage 3 and WP-4pre are accepted on the integration branch. The complete
43-program-per-backend instruction sweep passes at 1.021851044× QBE and
1.046853543× LLVM, with every output correct and no program above 1.3×.
The final combined default/borrow gate at `f6bea5d9` passes all four steps:
2,130 executed main tests, 429 QBE tests, native-build and formatting.
WP-4's compiler, runtime, collection, arena and host ownership paths are implemented
behind an experimental runtime selector. The latest fully green checkpoint at
`c47058f5` passes 2,351 main tests, 448 QBE tests, native build and formatting.
Both uncached RC sweeps pass **998/998 assertions across 169 programs**, with
zero failures, skips, cached verdicts, dropped files or unloaded files. The
[joined checkpoint](d9-rc-readers-joined-gate-2026-09-27.md) includes corrected
module callable resolution, argv ownership, empty-local journals and certified
fresh returns, omitted empty receiver storage, direct plain scalar writes,
empty-frame linkage omission, complete fresh constructors, closed field transfer,
plain retain, immediate scalar field borrowing, physically fresh loop roots,
bounded physical loans, borrowed returns through read-only loops and helper
composition, scalar appends with spare capacity, and ownership-free numeric loops.
Historical untagged native manifests now explicitly remain GC independently of
the future process default.
Earlier augmented-field and iterator failures remain preserved
as negative controls. The intermediate `685e2631` gate was **not green**: the
resolver dropped the declared-`replace` guest file despite 865 passing executed
assertions. The [failed receipts](d9-rc-nbody-gate-2026-09-26.md) remain unchanged;
the accepted GC compiler reproduced that old resolver bug before its correction.

The supplemental [golden replay](d9-rc-history-flat-goldens-2026-09-27.md)
completes **462/462 matching outcomes** on immutable `19e16e1d`, including 440
balanced counted RC executions, ten explicit legacy GC cases and twelve CLI
refusals before guest startup.
That compiler builds the complete performance corpus and passes all 60 parity
and schematic output checks, but Lox QBE binary trees times out at 600 seconds;
the remaining checks were stopped and archived. Nbody profiles motivated further
plain-record/read-loan work in `codex/d9-rc-nbody-integration`. Those changes are
now integrated at `685e2631`. The unchanged five-million-step nbody produces
correct output and balanced counts but still uses 2.324486× QBE and 7.325101×
LLVM instructions against accepted GC (median of three). A further validated
empty-local journal refinement is integrated: isolated full-size instructions
fall another 6.3% on QBE and 18.0% on LLVM with identical counts and output.
The argv lifetime fix closes the four-object/six-owner Lox shutdown gap on both
backends. Scope-storage and scalar-update refinements are now joined and gated.
The Lox audit attributes excessive object-table copies to an extra temporary
owner; explicit field-transfer `d4bff2a1` is now integrated. The bounded
empty-frame proof `57a26e87` and complete fresh-constructor preflight `cdec9ff5`
join it in the latest green checkpoint.
Their matched measurements improve full-size nbody and the tree diagnostic,
respectively, without changing successful-run ownership counts.

The frozen `7d68202d` [30-program diagnostic](d9-rc-parity-diagnostic-2026-09-27.md)
completes all 60 actual-backend rows with correct output. Its instruction
geomeans remain 4.806047× QBE and 6.291449× LLVM against accepted GC, with 23
and 22 programs above 1.3×. Median RSS is lower for this subset, but the 13 Lox
VM cases per backend are excluded. Exact counters identify repeated uniqueness
checks in fannkuch and broad loan/value traversal in schematic as priorities.
The three Astra workers now address those paths and allocation/retirement costs.
The next joined slices are green: plain retain `5237aebc`, plain projection
`6ce92814` and fresh-root loop checks `4f7eeea9`. Their isolated full workloads
improve substantially, but a separate combined four-program comparison still
shows instruction ratios above the limits. The complete 43-program sweep against immutable predecessor `e926d1e1` has now
finished all 86 rows, with correct outputs and large remaining overhead; the
historical full-corpus report above preserves the exact results.
Flat lifetime holds `c0a5904a`, borrowed loop returns `3b867d50`, plain appends
`3bc671b7`, anchored helper composition `b2a251c3` and numeric loops `280ef314`
now pass the joined full gate. Exact predecessor diagnostics still show Lox
binary trees at 117.54× QBE and 207.36× LLVM against accepted GC. The next
candidates address broad inline record publication, conservative lifetime-hold
propagation and descriptor lookup. Bounded physical retain `c2357ae4` now joins
the fully green checkpoint, with its isolated 48-sample archive independently
verified. The managed-memory guides and repaired example also pass their joined
gate; final RC-default wording remains conditional. Each slice preserves its existing
callback, trap and refusal behavior.
Exact nonheld scalar-list capture `aca67a7a` now passes the combined gate.
Scalar record publication `6a75eb2a`, private scalar descriptor identity
`45567840`, and record-field snapshot correction `2631a44f` now pass the combined
gate. The snapshot correction connects owned compiler field receivers to their
source record during borrow analysis. Permanent heap/arena, nested-path and
independent-home controls pass; historical negatives remain archived with the
precise GC/RC applicability. Full RC instruction/RSS acceptance remains open,
followed by the ordinary runtime default transition, documentation and final
combined validation.
GC stays the default.
WP-5 has a [committed design](d9-wp5-concurrency-design-2026-09-26.md), with
implementation dependent on WP-4 acceptance.

## Accepted work

| Work | Code/evidence | Validation |
|---|---|---|
| WP-3a switch and checker | `7c1fc1f8`; [report](d9-stage3a-closeout-2026-09-26.md) | Full gate; switch-off IL 44/44 identical and guest results 642/642 unchanged; switch-on failures and informational costs recorded |
| WP-3c recursive values | `67afc00a`, `2e4ac251`; [report](d9-stage3c-recursive-values-2026-09-26.md) | Full gate; million-node equality/hash and both-backend tree measurements; existing depth-bounded printing truncation documented as a plan deviation |
| WP-3d class/Cell retirement | `19144c19`; [report](d9-stage3d-closeout-2026-09-26.md) | Full four-step gate at `f1265a0b`; S-expression 114/114 and Lox 63/63 in both modes; VM 13/13 scripts; historical/diagnostic class exceptions inventoried; formal VM performance remains a stage 3f blocker; tree timing is a supplemental audit |
| WP-3e migration diagnostic/fix | `dd4ee663`; [report](d9-stage3e-closeout-2026-09-26.md) | 93/101 exact, 96/101 normalized census matches; 14 extras classified. Full four-step gate; Lox 63/63 tests and 13/13 VM scripts in both modes. Cyclic graph checker cost reduced from over 150 seconds to 0.30 seconds |
| WP-3b COW | Compiler through `21fafaee`, Lox source through `617ce4dc`; [final performance](d9-performance43-final-2026-09-26.md) | Complete 43-key sweep passes both backends, all outputs, unchanged thresholds; 260 uncached Lox native-GC-stress runs and 44 identical legacy IL comparisons; full combined gate |
| WP-3f default flip | `9ab98d5f`, joined at `698039c5`; [report](d9-stage3f-default-validation-2026-09-26.md) | Full gate: 2,125 main tests, 428 QBE, build/format; complete stage 3 performance passes. Legacy opt-out, 231 golden cases and explicit CPython divergences retained. Random snapshot migration has negative old-compiler controls |
| WP-4pre physical borrow inference | `450d151a`, final combined gate `f6bea5d9`; [report](d9-physical-borrow-astra-2026-09-26.md) | Main 94/94 with 2,130 executed tests; QBE 429; build 29/29; formatting. Schematic: 72 added borrow classifications, 12 conservative copies. Independent mixed-result COW stress audit passes. Actual RC count reduction remains WP-4 |
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
| WP-4 reference counting | `codex/d9-rc-integration`; frozen full gate `c47058f5`, both forced RC sweeps 998/998 across 169 programs; historical golden replay complete | Validate further performance refinements; pass complete RC instruction/RSS acceptance including rewritten graph programs; transition the ordinary default to RC and update docs; rerun the final joined gate. GC remains default until acceptance |
| WP-5 concurrency | Design committed in `df482879`; [proposal](d9-wp5-concurrency-design-2026-09-26.md) | Resolve the documented Weft-source provenance gap and remaining design decisions; implement and validate after WP-4 acceptance |

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

## Stage 3 performance evidence

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
The final combined compiler/source was validated against the complete
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
upvalue-accessor experiment were rejected. The complete corrected setter/hoist/default combination subsequently passed
the [final 43-key sweep](d9-performance43-final-2026-09-26.md); individual
gains were never used as a substitute for that acceptance run.

The expanded external Lox native-GC-stress failures are fixed by `21fafaee`:
`ref_local` was missing from local liveness, allowing a record held for a later
mutable call to be collected across an intervening allocation. The one-arm
liveness correction applies to both modes. A reduced fixed-array case also
fails on historical `60b668cf`; the later mut-record Lox migration exposed the
pre-existing defect more broadly. The fix passes the full gate (2,120 main
tests, 428 QBE tests, native-build and formatting), all 260 uncached Lox port
stress runs (65 per mode/backend), four permanent guest regressions, and 44
byte-identical legacy IL comparisons. See the [fix report](d9-mut-reference-liveness-2026-09-26.md),
[independent receiver audit](d9-mut-reference-root-independent-2026-09-26.md)
and [history review](d9-mut-reference-history-2026-09-26.md).

The corrected default compiler at `178d43dc` has SHA-256
`52ddd1337b4998b2a22184cac58af5ae4b0f4bc465dd449cfae3271c7451575d`.
The final 43-key sweep uses that actual default, source `4798d47f`, and private
byte-verified copies of the historical baseline executables. It passes both
backends. The refreshed correctness gate exposed two sharing-era random-stream
assertions; `9ab98d5f` migrates them to independent snapshots while preserving
explicit legacy checks. The old compiler fails the corrected snapshot
assertions, and the fixed compiler passes both backends under stress. Its full
gate passes, including all 656 ordinary language guests uncached.

The isolated physical-borrow prerequisite passed the full gate at `bd923864`
(2,128 main tests, 429 QBE tests, native-build and formatting). Its corrected
refresh `f74abcce` encountered those same two random assertions; the final
`f6bea5d9` combined gate passes after their migration. The
[RC readiness inventory](d9-rc-readiness-2026-09-26.md) and
[allocator review](d9-rc-allocator-review-2026-09-26.md) set out lifetime holds,
arena ownership, iterative destruction and legacy GC compatibility. A result's
borrow origin is a provenance upper bound, not proof that every return edge is
borrowed; RC call contracts must also distinguish fresh/mixed results.
The shared RC interface and selector implementation now begin from accepted
integration `266d9d5a`; WP-5 remains dependent on completed WP-4.

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

## Joined RC host and staged-clone regression checkpoint

The experimental branch passes a new frozen four-command gate at `d0178601`:
94 main steps and 2,162 executed tests, QBE 51 steps/436 tests, native build
29 steps, and formatting 2 steps. The [checkpoint report](d9-rc-host-staged-gate-2026-09-26.md)
retains exact evidence for startup registration, iterative pinned snapshots,
production collection ownership and copied-codec/host trap cleanup. GC remains
the default. Compiler lowering, scopes/arena escape, actual borrow count
traffic and WP-4 performance acceptance are still underway with Astra agents
at extra-high reasoning; WP-5 remains dependent on completing WP-4.

## Joined RC scopes, arenas and statistics regression checkpoint

Frozen `a9361b46` passes the full gate: 94 main steps with 2,167 executed tests,
QBE 51 steps/436 tests, native build 29 steps, and formatting 2 steps. The
[checkpoint report](d9-rc-arena-stats-gate-2026-09-26.md) records scope-first
trap cleanup, transactional collection transfers, stable pinned dictionary
reads, charged arena cleanup, and optional physical counters. It also records
the arena finalizer-ordering follow-up found during review. Compiler lowering
now runs a first basic RC CLI guest on its own branch; full RC semantics,
borrow traffic, performance/RSS and WP-5 remain outstanding. The accepted GC
baseline has 58 private binaries and all 86 output checks pass.


## Joined RC bounded-proof checkpoint

Frozen `39f75f3f` passes all four gates: main 94/94 with 2,209 executed tests,
QBE 437, native-build 29/29, formatting 2/2. The
[checkpoint report](d9-rc-bounded-gate-2026-09-26.md) records held views,
acyclicity admission, callback/frame failure cleanup and bounded borrow proofs.
The separate RC sweep executes all 713 assertions but has eight text/sorting
failures after earlier temporary cleanup. Exposed view-mapping mutation and
copied-view codec fixes are being completed. The first matched binary-tree
measurements remain far outside the RC performance threshold. WP-4 remains
experimental and incomplete; GC remains the default, and WP-5 awaits WP-4.


## Joined RC receiver correctness checkpoint

Frozen `a49441c1` passes all four gates (main 94/94 and 2,209 executed tests,
QBE 437, native-build 29/29, formatting 2/2) and the actual uncached RC language
sweeps: **723/723 tests on each backend**, 125 programs and no dropped/unloaded
programs. The [report and evidence](d9-rc-receivers-gate-2026-09-26.md) include
copied held-view codecs, H mapping mutation, and sorted receiver-owner lifetime.
Verified LLVM O3/full LTO also produces all three exact schematic SVG hashes.
Historical mislabeled LLVM runner evidence is explicitly corrected and rerun.
The measured RC instruction gap is still substantial; WP-4 performance and
its default transition remain open, and WP-5 is not complete.


## RC borrowing and constructors checkpoint

Integration `3f300771` passes all four gate commands: 94 main steps with 2,215
executed tests, 51 QBE steps with 437 tests, 29 native-build steps and 2 formatting
steps. Actual uncached RC sweeps pass 731/731 tests on each backend, across 127
programs. See [the joined gate report](d9-rc-loans-gate-2026-09-26.md).
The receiver loans, recursive read-only bodies, pointer fast paths and constructor
ownership transfers are integrated. Private n12 constructor owner acquisitions
fall from 1,996,163 to 19, with all 669,060 allocations retired. This is focused
evidence; complete performance/RSS acceptance and the default transition remain
open. The superseded exact-workload diagnostic is preserved in
[the early performance report](d9-rc-early-performance-2026-09-26.md).

## RC identity and supplemental replay checkpoint

Frozen `d57fef03` passes all four gate commands: main 94/94 steps with 2,232
executed tests, QBE 51/51 with 437 tests, native build 29/29, and formatting 2/2.
Its uncached counted-runtime sweeps pass 774/774 assertions per backend, across
136 programs with none dropped or unloaded. Exact compiler hashes, logs and
backend selection are retained in the [identity report](d9-rc-identity-gate-2026-09-26.md).

An additional immutable-compiler replay covers 231 authoritative native goldens
per backend: 226 RC cases and five explicit legacy-sharing GC fallbacks.
This replay is still running. It has reproduced two older-receiver arena traps
and two failed-file error-text leaks. The receiver-region correction `1e708148`,
joined at `e2667d56`, passes the two exact cases and 83 RC guests per backend,
eight GC guests per backend, 45 focused tests and 92 sanitizer scenarios:
[receiver-region evidence](d9-rc-receiver-regions-2026-09-26.md).
The failed-file correction and a distinct live-view mapping snapshot/history
correction remain in progress. A scheduling-wrapper diagnostic prefix caused
one harness classification error; the guest refusal itself was unchanged.

Later integrated optimizations include physical loop versioning (`a9b60357`),
completed-constructor publication (`03a0cf08`) and omission of tracing roots
from counted frames (`10f122a6`). Each has focused both-backend evidence, but
the combined source still needs a fresh full gate and complete performance/RSS
acceptance. The frame-template experiment was rejected after an LLVM regression;
its evidence remains committed. Specialized allocation and compact journal
indices are being measured next. No partial timing establishes WP-4 acceptance.
