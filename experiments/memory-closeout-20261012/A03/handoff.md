# A03 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Branch: `codex/memory-closeout-20261012-A03`.
- Original scope: this directory only. The coordinator subsequently transferred
  A01's 36 guest fixture reservations and reserved
  `src/core/a03_migration_boundaries_test.zig`; the coordinator supplied its
  `src/core/root_test.zig` registration. The exact guest file list is in
  `guest-migrations/review-identities.json`. A subsequent explicit reservation
  covers the eight additional core fixtures in `additional-migrations/originals.json`.
- Delivered commits: harness `d23f84d0c`, baseline `58fb3cf25`, first guest
  migration `448062611`, supplemental corpus `338fc9dd2`, additional core
  migration `17a70623b`, follow-up boundary/corpus evidence `b89021c4e`.
- Implemented: isolated failure-preserving census adapter; 81-case pinned
  manifest preserving the original 30 IDs and all historical 48 matrix cases.
- Completed tests: all 81 C0 release cases / 131 executions; zero RC, no managed
  exit leaks, matching outputs/exits and 81 clean LLVM/symbol audits. Original 30
  freshly measure 23 allocating / 7 allocation-free at inputs 4 and 11. No
  migrated workload refuses; original unmigrated source checks admit 21/refuse 9.
- Fresh controls: JSON hits add 3 allocations/320 bytes at 1/16/128 siblings;
  misses add 0. Record explicit copies use 27,000 blocks versus field transfers
  at 21,000 for 1,000 unpacks; both managed peaks are 1,536 bytes. These are
  source-variant comparisons on C0, not a compiler-only before/after saving.
- Baseline compiler: A09 full C0 Debug installation, SHA-256
  `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
- Tooling checks: Python AST parse and manifest uniqueness/coverage assertions;
  first commit's Guardian hook passed all 88 checks. No Guardian feedback write.
- Final dependency: coordinator-frozen integrated compiler and exact SHA.
- Evidence paths: `manifest.json`, `C0-release/{REPORT.md,results.json.gz,
  raw-json.tar.gz,controls.json,sha256.json}` and `C0-smoke/`. Full scratch raw
  outputs/binaries/LLVM: `.tmp/memory-closeout/A03/C0-batched/`; earlier `C0/`
  and `C0-smoke/` remain intact. `C0-batched.log` reports every release lane.
- Scheduling: coordinator-approved leases of at most ten compiler invocations,
  reacquired after 60 seconds at safe boundaries; separate queue-wait receipts.
  SIGUSR1 saves a checkpoint after the active lane. No nested admission.
- Shared-file request completed: coordinator added the new boundary-test root.
- Known limitations: managed counters do not measure RSS/native overhead;
  source checks of the original unmigrated corpus are reported separately.
  LLVM/symbol audit does not replace A07's runtime ABI layout proof.

The final compiler must run all five modes (405 builds / 655 executions) on the
same 81-case manifest. Per coordinator direction, C0 was measured release-first;
its result correctly marks `complete_matrix: false`. The pinned census found no
production defect; the expanded guest migration work below found additional
compiler blockers. The integrated candidate dependency remains open.
A baseline-only success does not qualify default promotion or legacy retirement.

The first transferred migration preserves 356 public test signatures. Explicit
source copy calls increase from 7 to 250 in that commit; it changes 331 added/286
removed lines including comments. This is source migration, not a compiler-only win.
The initial nine negative borrow/write cases preserve rejection of former implicit-snapshot
call windows and mutable iteration; the positive snapshot case executes in
debug and verified release. Five focused registered tests pass.

Interim support2 (`245e892f8518943ee44a0cc6009ab4b4fa6bca43`, compiler SHA-256
`3e9f7f2cd7e1ff7dc13b342dc812cb64b340cddc02b8b2b4b1ae8008cb203c7c`) source checks
admitted 22/36 files, with all 14 failures retained. A later native release subset
ran 21/24 files /118 Boolean tests successfully with RC0, no managed leaks and
clean LLVM/symbols. Exact tested sources and receipts are archived in
`guest-migrations/`; these results do not claim final C1 qualification.

Open production reproducers include nested writes, dictionary-item iteration,
fresh-value projections, optional narrowing,
interior dictionary mutable lowering, and a managed-string destructuring swap
(A07 and coordinator); aggregate render-helper ownership is assigned to A04.
The snapshot scalar panic is fixed by the coordinator and awaits fresh recheck.
See `guest-migrations/README.md` and `qualification.json` for source paths and
limits. The smallest valid local copy/staging migrations are already applied;
legitimate in-place operations remain intact for their compiler owners to fix.

The coordinator subsequently retained whole-root exclusivity for multiple mutable
children, including known-distinct constant slots. Three such calls now use local
child copies, one call, and source-order writebacks; the callee cannot observe
the original root. Original list/dictionary calls remain negative regressions.
This adds six explicit copies and is not a performance saving or a general
path-disjointness claim. See `guest-migrations/distinct-child-review.json`.

Additional core qualification on support4 admitted seven of eight assigned files,
executed 11 exact stdout/status/trap/trace contracts, and passed all seven LLVM
and symbol audits. All nine normal/Result-error runs had RC0/live0. Intentional
bounds traps retained 1,192 and 160 live bytes at abort and do not claim managed
cleanup. `v_narrow.my` remains unchanged and refused pending A07's optional-place
fix. All source identities, source burden, counter data, command receipts and
harness snapshots are archived under `additional-migrations/`. A09 owns the
precise counter native oracle and independently passed eight modes times two
paths on the same migrated source.

The separate supplemental corpus now includes six pinned new API fixtures: owned
list methods, text/JSON/codec/path contracts, borrowed repetition, generic resource
lifecycle, direct Result lists/maps, and borrowed aggregate rendering. Its final
five-mode matrix is 30 builds/40 executions; the original81 and original30
denominators remain unchanged. Fresh C0 refusals stay visible with no fictional
allocation observations. Final C1/C2/C3 measurements remain pending the actual
integrated artifact, not these interim support compilers.

Latest focused boundary result: seven registered tests pass, covering 11 negative
sources and two positive sources executed in debug/verified release with native
leak checking and emitted LLVM RC audits. The locally cherry-picked driver
dependency `90ce40266e589598a6e98ac9a2c88ec26e0cb233` duplicates already-integrated
`38dc781a8` and is explicitly excluded from A03's integration handoff. Guardian
required a module doc for the expanded test file; it was added and all 88 checks passed.
Final integrated verification still must rerun this coverage.

Follow-up integration commit: `b89021c4e` (88 Guardian checks; 7/7 focused tests). Skip its
parent local driver duplicate `90ce40266`. The six new-API sources are pinned;
main plus supplement require 435 final builds and 695 guest executions.

Counter interpretation for the upcoming candidate: A09 commit `8ba337fd6` fixes
missing recursive child-list copy telemetry. Its controlled debug/release fixture
changes recorded list copies 1→2 and copied bytes 24→40 while every allocation/free
byte total and managed peak 608 remains identical. This changes observability,
not physical allocation traffic. Do not describe such a C0/candidate copy-counter
increase as a new allocation or peak regression. Original 30 allocating predicates
remain based on workload allocations/reallocations and are unaffected. A09 raw
proof is under `A09/raw/counters/recursive-{before-support4,after-hook}.json.gz`.

Support5 targeted requalification resolves `v_narrow.my` without source changes:
all five native counted modes pass exact output, zero RC, zero exit-live and
LLVM/symbol audits. Sources and raw evidence are under
`additional-migrations/support5-narrow-*`. The guest migration source sweep
admits 29/36 files, and targeted native qualification passes 9/11 files with
141 Boolean assertions; the two mutable-place lowering failures remain recorded.
The original-30 release sanity passes all 30 builds/72 executions, with zero RC,
zero managed exit-live and clean LLVM/symbols. Its 23 allocating/7 allocation-free
count and 21 admitted/9 refused original-source checks match C0. Every paired
allocation-traffic/peak observation is identical; see `Support5-original30/`.
None of these results is final C1.
Seven missing explicit copies in sort-key lambdas, record snapshots and an owned
key-list comprehension have been
corrected locally, preserving every assertion; the exact source burden is in
`guest-migrations/owned-key-snapshot-review.json`.

The seven-copy correction and Support5 migration evidence were delivered in
`546ef247609681cf1474a4ec378fe1b5c14574a0`; all 88 Guardian checks passed.

Support5 original-30 evidence was delivered in `b4a083209`; Guardian passed all
88 checks. Support6 (`5167c588be79dd43d21d5013c36db15110bf239b`, compiler
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`)
then tested six targeted migration files. Four pass 60 Boolean tests after four
explicit copies in `loop_rebinding.first_of`; public test bodies are unchanged.
The list-field `+=` and nested-dictionary mutable-child compiler failures remain.
Three other known failures await fixes excluded from Support6. See
`guest-migrations/support6-summary.json` for every selected, held and unmeasured
file and archived attempts. The final 435-build/695-execution census remains due.

Three additional source reservations transferred from A06: explicit snapshots
in `rc_owning_element_borrows.my` and `row_cow.my` pass all five Support6 modes,
including 40 Boolean test executions and the unchanged 57-line row oracle.
Every admitted run has RC0/live0 and clean LLVM/symbols. `v_nested.my` admits at
source but all five native modes refuse the nested scalar slot write at line20;
A07/coordinator own this compiler blocker. The three sources retain C0, prior
A06, incoming and reviewed identities and oracles under `transferred-a06/`.
The approved row-return allocation effect and live index loop are documented
source-contract changes, not compiler-only performance wins. A reduced native
reproducer and successful raw/facts IR dumps are included; dump success does
not qualify the refused native lowering. No census denominator changed.

Support7 common source admission completed on the clean frozen `bed11cf3`
tree and full ReleaseFast compiler `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`:
85/87 admitted, two exact refusals, zero tool failures and zero unmeasured.
All 23 additional core sources admit. The list-field augmented write is assigned
to A02; recursive source migration is assigned to A03. See `Support7-source/`.
The source sweep retained its original ten-call/60-second lease methodology.
The coordinator subsequently approved at most 50 actions or 30 seconds per
shared lease; A03 runners now use that policy with unchanged slot and timing
budgets. Native census and generated-test qualification remain separate work.


## Common Support7 complete census and guest command evidence

Frozen source `bed11cf3bf3102ffec44487e431a1573fdf02ad5`, full ReleaseFast compiler
SHA-256 `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`:
`Support7-full/` passes all 405 builds and 655 counted executions in all five modes;
`Support7-supplement/` separately passes 30 builds and 40 executions. Every counted
run has matching output/status, zero measured RC events, zero managed exit-live
bytes and clean selected LLVM/symbol audits. Original30 remains 23 allocating/7
workload-free; original unmigrated source checks remain 21 admitted/9 refused.
`Support7-full/comparison-C0.json` preserves all131 paired release observations.
The only increased allocation traffic is library JSON +3blocks/+192bytes, localized
by A04 to the conservative literal-slice copy; a pending fix is not part of Support7.
Parallel whole-program allocation reductions are recorded separately by workers.

`Support7-properties/` executes all16 generated properties in each mode,192passed
inputs and25discards per mode. `Support7-guest-tests/` retains all64 source rows;
60files ran actual public guest tests (including reused exact property evidence),
with412passed/5failed/3unsupported test contracts per mode. Two source-refused files
retain16 blocked contracts per mode. The private-main and importing-helper paths
remain explicitly distinguished; no empty test command is counted as a pass.
All these command executions are uninstrumented with leakcheck enabled, with no
measured RC-event claim. `Support7-guest-blockers/` contains frozen source/functions,
exact commands and native controls for equality helper, mutable writeback and
indirect mutable-call defects. Root/A07/A10/A02 own their dispatched fixes.
This is intermediate evidence: C1/C2/C3, final gates and affected reruns remain open.


`Support7-core-contracts/` completes additional native coverage on that compiler:
110 counted builds/225runs pass, including195 normal/validation exits with RC0/live0
and30 intentional fatal traps with RC0 and explicitly retained exit-live storage.
The two public core-test modules total75passed/15unsupported contracts acrossfive
modes; unresolved helpers are generated equality and saturating integer (A10).
Five benchmark-shaped fixtures use documented independent checksum references
and a deterministic scalar clock provider, not timings or C0 native observations.
The private `rc_nonheld_captures` main passes; imported `surface_statements_case_2`
is exercised by its passing parent module. `Support7-contract-ledger.json` preserves
all87migration sources:81pass allfive-mode contracts,2source-refuse,4have native/helper
failures. The454public contracts per mode divide427passed/5failed/6unsupported/
16source-blocked; none is silently omitted. This separate source inventory does
not change the pinned81+6 census or original30 denominator.


`Support7-allocation-classification/` separates all five modes and workload versus
whole-program allocation counts. Original30 workload23allocating/7free applies to
release, verified release and optimized debug; unoptimized debug and release
without facts have28allocating/2free. All30 allocate somewhere when entry/setup is
included. Pinned81 workload70/11free in release-like modes and76/5free otherwise;
whole-program78/3free and79/2free respectively. Allsix supplemental cases allocate.
The classifications preserve every case ID; no timing/RSS conclusion is inferred.
The common guest harness can now run generated properties itself on a fresh
artifact and checks seed/run/pass counts; optional property reuse requires matching
compiler/source/ownership. Core qualification also accepts an explicit default
request for C2. These are prepared harness capabilities, not a default rollout claim.
