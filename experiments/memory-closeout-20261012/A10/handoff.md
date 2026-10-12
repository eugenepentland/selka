# A10 command-support handoff (later milestones pending)

Latest preparation: `rollout/44947e696/README.md` audits integration
`44947e6967d8eb0deeaa86b25ca2bb44bc58803d` with per-owner source/hunk inventories,
all internal API callers and registered legacy-control/selector obligations.
The coordinator fixed the C3 OWN1 ABI contract; all drafts remain unapplied.
Prepared package launcher and verification-inventory checks close the additional
legacy `MYLANG_COMPONENT_DIR` manifest path. Isolated validation passes 29 builder
tests, 30 executed protocol tests and three verification-package tests. A real
ordinary-owned C3 source pin and final installed qualification remain required.

Base C0: fbfcaa7a923186a8e773c3760f81c10aa345a432.
Worker branch: codex/memory-closeout-20261012-A10.
Proposed command-support commit: this changeset; packaging/default/retirement remain separate.

Owns the assigned core CLI/test runner files, ownership docs, src/main.zig by
coordinator reservation, and these A10 fixtures/reports. Pipeline.zig reserved
for a later default stage but no default change has been applied.

Implemented guest-test selection through parser, directory children, eager source
validation, every reachable-root/key/cached/shadow lowering, and three receipt
domains. Three registered focused tests pass (3/3). A08 reviewed the deferred
canonical-fact path: full source validation remains eager, facts bind raw source
and both ownership bits, execution lowers independently. Keeping deferred fact
reuse does not skip source ownership checking.

Implemented opt-in ownership checking through the full frontend check parser,
including library sources, diagnostic/report options, disabling ordinary green
source-receipt replay and summary-only body omission. Developer --typed/--stats
still routes to the dedicated profiling check implementation.

Evidence:

- inventory.md: current source command and packaging matrix.
- C0-components.json: both installed component source entries refuse C0 zeroRC
  at with-try file acquisition; A07 owns checker fix and A08 module migrations.
- C0-package-symbols.json: both frozen installed components contain retain/release
  and sharing symbols; they are active RC-installed artifacts, not historical seeds.
- command_matrix.py and fixtures/: five guest modes, property copies, cached and
  child directory execution, Result entries, run-project and move/library refusals.
- admission_survey.py: preserves original identities across all 356 current .my
  files in tests/lang and tests/value_semantics; a private mirror adds the guest
  runner's inert main to 201 library entries for the C0-style check parser.
- migration.md: accurate opt-in migration notes; no default/retirement claim.

Commands run:

- pinned Zig build affected-compiler via common admission: pass before and after
  test mode plumbing; outputs zig-out/focus/mylang with libexec siblings.
- pinned Zig build test-core with filters 'zero RC guest test', 'zero RC test
  receipts', 'zero RC directory children': exit 0, Guardian test PASS 3/3.
- C0 check of both component main files through common admission: source refusal
  status 1 for both; exact output and C0 compiler hash recorded.
- Initial matrix/survey launch used wrong zig-out/bin path; did not execute guests,
  corrected to zig-out/focus and requeued. No passing claim from that harness error.

Shared requests: coordinator authored NEW-CORE-ZERO-RC-TEST-1 in SPEC.md here;
include with command-support commit. Final root verification and integrated
A07 helper/checker fixes remain coordinator-owned. No Guardian FEEDBACK write.

Milestone 2 default promotion and milestone 3 legacy retirement are intentionally
unapplied until coordinator qualification approval. Package recipe needs a
separately keyed qualified zeroRC final component build without changing immutable
seed history or creating a host/component bootstrap dependency cycle.

Command support qualification (worker candidate, C0 plus this command changeset):

- `test-support-matrix-qualified.json`: all 23 command rows pass, including
  the five guest modes, shadow/reference keys, warm receipt reuse (3/3 cached),
  library diagnostics, invalid moves after ordinary RC receipts, and both
  in-process and spawned-child directory execution. Compiler SHA256:
  `d0766f6dad145b76c1bec5cb700ee2d29da6937dbd66f84010ab3d774056539e`.
- Earlier matrix reports retain harness mistakes explicitly: an empty leakcheck
  variable still requests instrumentation; cache tests require the string `0`.
  Old generated directory fixtures used a retired module header. Both harness
  errors were corrected; no production cache/directory change was needed.
- `guest-admission.json`: all 356 current guest files are retained; 179 admit,
  177 refuse. Source admission only, not guest execution. Sorted refused lists
  and `guest-migration-ledger.json` identify 123 explicit-copy local migrations,
  19 evaluation-order reviews, 33 production/lifetime reviews and 2 explicit
  boundaries. Classification records the first refusal; subsequent defects can
  still surface. Parent assigned migrations to their source owners.
- Required full integration verification remains the coordinator's gate. These
  focused passes are command-stage evidence, not milestone 1 qualification.

Support commit: `8d4a9845f`, required Guardian 88/88 passed. Post-refactor
repeat focused tests pass 3/3; all 23 command rows pass in
`test-support-matrix-refactor.json`, compiler SHA256
`8a4f53e6202bd25c44f0b7a65851b281188a6921630b5862ec6aaa6725e798f9`.
`test-support-assertion-audit.json` additionally checks exact test counts, no
unsupported tests, exact move diagnostics and run output against that raw report.

Separately prepared the optional independent owned-component compiler route,
including immutable-pin validation, mode-bound cache identity, explicit guest
selection and native qualification-driver forwarding. See
`packaging-preparation.md`/`.json`. Fake-tool orchestration tests pass 21/21.
No production new manifest exists and root builds still select the historical
route, so this is packaging preparation, not installed RC retirement.

Doctest/session followup: `check-session` accepts the ownership flags and keeps
eager checks on repeated, cleared and failed requests. `doctest` accepts zero-RC
and passes it into each check/run invocation. `followup-matrix.json` records all
six rows passing: module/project checks, positive and negative five-request
sessions, and repeated doctest runs with positive execution, library checking and
expected move refusal. Focused `zero RC doctest` unit selection passed 8/8
(one named regression and seven existing unnamed import blocks). The original
focus installation was preserved for A04; this candidate uses a private prefix.

Cost command followup: explicit zero-RC selection, eager whole-source ownership
validation before lowering-cache use, and a shared mode across lowering/emission.
`cost-matrix.json` passes 8/8 cases: four analysis modes, warm output, an ordinary
RC cache control, then two source refusals. The registered structural cost test
passes 1/1 and asserts the count-free module/LLVM ABI. Its first unregistered run
selected zero tests and failed; the coordinator added the root registration before
this passing rerun. Static `totals.rc.releases` currently counts direct ownership
cleanup sites too; it is not a runtime reference-count event measurement.

`rollout-test-inventory.json` and `rollout-test-plan.md` record exact test-path
inheritance, 175 additional Core sources and 44 additional fixture sources,
inline-source drivers and direct-IR retirement obligations. The first ten paired
source admissions took 1.31 seconds; the remaining paired source inventory is
independent of production fixes and remains distinct from the 356 denominator.

Additional source admission completed: all 219 files (175 `test/core`, 44
`test/fixtures`) retain original hashes and paired ordinary/owned outcomes in
`additional-admission.json`. Results: 106 admitted by both, 86 new owned refusals,
27 refused by both. They are a separate denominator, not added silently to or
substituted for the original 356. Total admitted-lease work was 8.94 seconds.
The compiler is C0 plus A10 command support, so these outcomes deliberately
precede A07 production fixes and integrated source migrations. Recheck C1 before
classifying a remaining in-scope failure as a release blocker. Exact first
refusals and sorted source paths are in `additional-admission-summary.json`
and `additional-owned-refused.txt`.

Support3 recheck (source `0d17e4e130706639c0f49e78b60502bfb2151ebc`, binary
`7b911f91acefccc9dbfd0d1bcfee46e1ec5acc7f47a7ca5954481d44393c7de7`): all
219 paired source checks completed in one 5.66-second admitted lease. Results are
113 admitted by both, 79 new owned refusals, 27 refused by both. Source hashes are
unchanged. Seven earlier refusals now admit due to integrated production fixes.
`additional-migration-support3.json` and the five `additional-migrations-Axx.md`
files give nonoverlapping proposed owner assignments and first diagnostics. The
coordinator owns dispatch. No additional fixture source is edited by A10.

Admission correction: inspection of the shared Git pre-commit hook showed it
executes Guardian directly and does not acquire build-slot admission. A10's earlier
commits ran that hook directly; their final Guardian outcomes remain correctness
evidence, but their resource/timing admission was not compliant. Successful hook
end times on 2026-10-12 UTC were 01:02:36, 01:08:23, 01:16:01, 01:23:37 and
01:27:30, with failed attempts before some of those times. Coordinator and A09
were notified so overlapping timing samples can be reviewed. All subsequent A10
commits use `scripts/build-slot.sh gate git commit ...`. No historical measurement
is silently relabeled as admitted, and no Guardian FEEDBACK entry is written.

Unapplied C2/C3 preparation is under `rollout/`: frontend default promotion and
CLI-selector retirement patches, source/patch hashes, exact internal API call-site
inventory and owner obligations. Both patches pass apply checks on their specified
stages and scratch Zig format checks. Neither is applied or compiled; no milestone
is claimed. Current docs and many internal legacy test assertions remain rollout
obligations and are explicitly listed.

Allocation/portable followup: selected ownership mode now reaches frontend
allocation warnings, lint, profiling checks, dump-IR, cost, provider/union test
sessions, coverage and portable test-key lowering. Before lowering for allocation
analysis, the frontend eagerly rejects invalid source ownership; coordinator
approved retaining later validation until an explicit validated-state contract
can safely replace the duplicate work. A08 reviewed portable canonical lowering
and whole-source validation. Coordinator/A07 authored/approved `coverageInput`.
Borrowed view helpers are audited allocation-free; owned text encoding and buffer
reversal are independent allocations, and explicit copies still warn under noalloc.
Coverage returns a failure status for owned frontend refusals while preserving
its ordinary legacy inspection control until rollout.

`analysis-validation/validation.json` identifies all changed production hashes and
compiler SHA256 `1e4d0146212d053a10c6c0a984c220ccb01de7069a7d32ef347745ec5f17c5c9`.
Three focused regressions pass. The final command matrix passes15/15, including
actual portable shared-receipt reuse across relocated roots with separate private
caches, eager refusal after an invalid move added to an unused helper, and emitted
owned ABI/absence of retain/count-release symbols. Receipt tests disable leak
instrumentation for eligibility; these rows are not a new counted corpus claim.
Early failed matrix evidence remains preserved. It exposed coverage status0 on
frontend refusal and the separately fixed uncacheable native-link object lifetime.
Approved dependencies38dc781a8 and a2160955e were consumed locally as6ac27ce04 and
a9dc0edfe. External timing/FIFO queue delays are logged and excluded from any
compilation or runtime comparison.

Reviewable rollout preparation now also includes full ownership/managed-memory
page drafts, an unexecuted65-row selector/guest-separator matrix, and an ordered
retirement dependency plan. Production docs/defaults and legacy retirement remain
unchanged. Actual integrated documentation tests, component qualification and
C1/C2/C3 gates are still required; drafts are not implementation milestones.

Followup helper audit: `myl_core_owned_same_block` borrows two list pointers and
returns only pointer equality; it performs no dereference, allocation or RC.
The cost allowlist now records that audit. The regression requires nonallocation
for the generated helper, unresolved cost for a source-spanned extern lookalike,
and source rejection of the reserved extern spelling. Focused allocation-contract
suite passes3/3. `helper-contracts/validation.json` pins source/test-binary hashes
and the exact native helper body audited in A02's tree. A02 owns native execution
and the generated alias/self-extend branch qualification.

The adjacent aggregate-provider-marker cost patch remains unapplied. It reuses
the coordinator's complete validator, never an open symbol prefix; valid borrowed
markers cost no allocation, malformed markers remain unresolved. It includes
cost-specific wrong-mode/signature/ownership-mask/source-extern regressions, but
execution waits for atomic integration of the actual utility. Rollout generation
and API inventory now accept an immutable source revision and separate output
path so support5/current-candidate drafts can be refreshed without editing another
worker's tree or overwriting the previous evidence.

Support5 rerun and eight-page draft preparation:

- Exact integrated source `a1f19edf255c8c0886731d8d7cce450d5f657720`, compiler
  SHA256 `8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
  `support5-summary.json` reconciles 52/52 command rows: main 23, analysis 15,
  check-session/doctest 6 and cost 8. Each report checks compiler stability.
  Matrices ran in bounded shared build leases; FIFO waits are not guest timings.
- `rollout/support5/` refreshes unapplied C2 and C3 selector patches against that
  immutable source. Both staged patches passed apply/fmt checks. The inventory
  records 533 qualified API calls across 81 files plus wrapper/type/mode sites.
- `rollout/support5/C2-docs.patch` contains eight unapplied replacement pages;
  exact original and proposed hashes are in `docs-identities.json`. Production
  docs remain unchanged. Draft code blocks qualify with explicit zero-RC only;
  ordinary/default and final component-package qualification still must run.
- Draft docs have 51 source blocks representing 50 execution/check units (a
  two-file project shares one unit). 47 blocks / 46 units pass on Support5.
  Three dictionary-item tuple-binding blocks remain `E_SINGLE_OWNER_BORROW`
  (A01/A07); one round example lacks the exact audited `myl_core_round_float`
  contract (A04/A07). No refused block was removed from the denominator.
- Explicit `.copy()` repairs preserve the nested-list and sort-key examples'
  results. The live foreach mutation remains a whole-root invalidation boundary;
  its migrated index loop uses current length, visits the appended value and
  preserves total13 and the independent saved list. The preserved foreach
  version is `fixtures/live_foreach_refused.my`. The original draft failures and
  all repaired source hashes remain in the raw reports.
- The first final project-doc harness incorrectly compared units with blocks;
  raw doctest passed two units for three blocks. Corrected project-aware coverage
  checks all block identities, refuses split projects, and reruns the project.
  `docs-reference-support5-project.json` passes. No skipped/mistagged blocks count
  as qualification.
- Per coordinator decision, `dump-ir --facts` remains diagnostic Core inspection.
  Status0 there is not executable ABI admission; native emission must still
  reject unsafe Core. Guest tests preserve SPEC NEW-CORE-TEST-4's unsupported-only
  status0 contract; qualification explicitly requires JSON `unsupported == 0`.
- `helper-contracts/round-cost.patch` is an approved unapplied companion for
  atomic integration with A04's numeric ABI/ownership audit. Its exact scalar
  helper classification and source noalloc regression passed apply/fmt only;
  compilation depends on the new ownership contract. Source-spanned extern and
  unaudited suffix lookalikes remain conservative. This is preparation, not a
  passing runtime contract claim.

Support5 still stages older RC `libexec` components. A08's test-index protocol
qualification does not resolve its cache-plan lowering blocker or the installed
packaging route. No default or RC-retirement milestone is claimed here.

The isolated preserved foreach check passed its negative oracle on Support5:
status1 with `E_SINGLE_OWNER_OVERLAP`, exact source/compiler hashes and output in
`rollout/live-foreach-support5-negative.json`.

Optional real-pin forwarding followup: coordinator-authored root changes now
accept `component-owned-compiler-pin` and pass the same optional pin/archive to
provisioning and native qualification. Absolute paths work through cwd-relative
LazyPaths; component manifest input recipes cover both old and eventual new
manifests. No real new pin exists and the default historical selection is intact.
`component-builder` passes 3/3 steps without provisioning. The complete fake-tool
suite passes 25/25 (shared build tickets669/679; exact hashes and raw logs in
`packaging-real-pin/validation.json`). Four new tests cover strict native verdict
accounting and exact pin/archive/component-dir routing.

Native qualification now explicitly uses the provisioned candidate component
folder with the independent compiler, verifies installed hashes/owned mode and
rejects empty, failed, skipped or unsupported pure-test reports. This fixes a
qualification gap without changing the guest CLI exit policy. No installed host
fallback or component-build cycle is introduced. C1 actual-source archive/pin,
real protocols and installed ABI/symbol qualification remain coordinator/A08 work.

A01/root clarified existing D1-LIVE-PLACE semantics: direct syntactic source-root
rebinding selects an independent entry snapshot, also for direct dictionary
keys/values/items projections. Mutating methods/element writes remain refused.
Draft prose now distinguishes those cases and snapshot allocation costs; the
live-length index migration and preserved negative remain unchanged. No code-block
hash changed in this prose followup; the 47/51 Support5 evidence remains exact.

## Remaining current-document and recursive-diagnostic inventory

`rollout/other-current-docs-inventory.json` pins nine additional current documents outside A10's existing eight-page reservation. Their RC/COW prose and runnable examples need owner review; dated historical designs are distinguished from current contracts. No additional document was edited.

`rollout/C3-recursive-diagnostics.patch` is an unapplied coordinator request for `src/record_layouts.zig`: remove the obsolete sharing rationale while preserving the recursive boxed resource/result/capability refusal. Existing E_RECURSIVE_RECORD and owned-resource substring tests remain applicable. Patch application check passes; this is wording preparation, not retirement completion.

## Additional effects docs and concrete package retirement draft

Coordinator reserved `docs/module-constants.md` and `docs/effects.md`; additional drafts
are generated by `rollout/migrate_effect_docs.py`, with source/output hashes in
`effect-docs-identities.json`. Current pages remain unchanged. All20 fenced blocks
were checked on immutable Support5. After explicit-copy and lexical-scope migrations,
19/20 pass; the remaining provider-record source refusal awaits Support6. Expected
outputs and negative diagnostic codes are preserved. Combined A10 documentation now
has66/71 passing blocks (65/70 execution/check units); the prior three tuple binding
and one round helper refusals remain in the denominator alongside this aggregate
refusal. All52 command rows remain passing; no new final/default claim is made.

Coordinator approved a C3 `ownership_selection: checked-default-v1` marker. The
unapplied `rollout/C3-component-retirement.patch` removes legacy seed fallback and
selector forwarding, requires that marker and the independent seed-compiler recipe,
and validates it in installed manifests. Isolated ReleaseSafe/LLVM compilation and
all27 fake-tool tests pass, including missing/old/malformed pin negatives. Exact
source/binary identities and logs are under `rollout/component-retirement-validation`.
This tests the orchestration patch; no actual final compiler pin or RC-free package
is manufactured or claimed. Root must atomically select a real qualified ordinary-owned
compiler pin and default root forwarding at Stage4. Immutable old seed bytes remain
unchanged. Source deletion is still unapplied.

## Support6 candidate archive and extracted compiler build isolation

The actual frozen source5167c588be79dd43d21d5013c36db15110bf239b is archived at
`.tmp/memory-closeout/A10/owned-pin-support6-5167c588/source.tar`, SHA256
0557a645579881d54d3f4c493c8b07be38d42b0a21622ab712b84589ee212c27,
1,517,547,520bytes. The candidate pin, exact input hashes and reviewed qualification
script live under `packaging-support6-candidate`; no installed/default manifest
was created. Archive creation waited486seconds in shared admission; this is not
compiler or archive execution time.

Real provisioning required isolating the extracted compiler local Zig cache and
TMPDIR from the caller checkout. The native builder now sets those two paths
inside its extracted source tree, preserves the shared global cache and unrelated
environment, and binds private-local-and-tmp-v1 in the seed recipe identity. An
initial compile detected a variable-name clash, fixed before the final passing
build. The complete fake-tool suite passes26/26 including inherited-local-cache
and TMPDIR refusal controls. The exact tested native builder is c24cf61e5413599c8e147a0cf4d6eb132f09e2686bcfb29bd300ae85285af8bd.

After A08 Support6 Debug component protocol success (560cache-plan and128test-index
expected outcomes with RC0/returnedexitlive0 and structural checks), root authorized
actual independent ReleaseFast provisioning and native installed-component checks.
That run is in progress under shared admission; its status is recorded separately
and no success or package retirement is claimed.

Support6 targeted docs rerun passes four formerly refused tuple/round examples. The
existing entry-point Filesystem/Environment wrapper remains E_SINGLE_OWNER_BORROW
at Context(fs=fs,env=env); source/authority is preserved as a coordinator/A07 support
blocker. This is a five-case targeted result, not a relabeled full71-case run.

The borrowed-selection cost companion is prepared for atomic integration with
A07's exact validator. It has application/format checks and a focused source test,
not a native test result yet. `allocation_contract.zig` ownership is transferred
narrowly to A07 for Unsupported/noalloc handling; its narrow pipeline cache callback
Unsupported-to-CacheMiss overlay is also authorized, preserving fresh refusal/OOM.
The C3 component draft was rebased over cache isolation; prior27-test evidence is
kept under original hashes, and updated28-test native qualification remains pending.


## Independent ReleaseFast component qualification completed

The extracted compiler build isolation and candidate inputs shipped in
`c30a557ec1cacd9a4a68501d8f6587eb4b353e9b`; shared-gate Guardian passed all 88
checks. Its independently provisioned source5167c588 compiler
`29cfbd13390692757ce3add9cf61d8398eff283760d16cedb3c5b9addaa03e26` passed all
42 pure-test executions (four debug/release verified reports), fresh release and
installed protocol oracles, and installed RC symbol checks. A08's separate fresh
counted688 executions from this same compiler passed with RC0, returned exitlive0,
and clean LLVM/symbol audits. The exact source/compiler/installed/counted identities
and raw output remain separate in `packaging-support6-candidate/qualification-state.json`
and `provisioned-identities.json`. This qualifies the explicit independent pin route
for these component inputs, not the final integration package/default/retirement.
The historical seed digest and active root selection remain unchanged.

The borrowed entry capability wrapper is now also preserved as standalone
`fixtures/borrowed_entry_context.my`: ordinary Support6 check exits0, checked-owned
check exits1/E_SINGLE_OWNER_BORROW at Context(fs=fs,env=env). The exact paired
diagnostic report is `rollout/borrowed-entry-context-support6.json`. Coordinator/A07
own resolution; no replacement authority, external I/O or source semantics was used.

The rebased C3 component preparation now independently compiles ReleaseSafe/LLVM
and passes28/28 fake-tool tests, including private extracted cache/TMPDIR and
selector-free routing. Updated exact hashes/raw logs are recorded separately in
`rollout/component-retirement-validation/rebased-validation.json`; the prior27-test
report remains immutable. Production retirement remains unapplied and actual C3
compiler/package qualification is still required.


Coordinator development-build failure was audited read-only: immutable seed0689d340
has the pre38dc driver cleanup defect; its old ld.so.cache pin correctly disables
native reuse on this host, exposing deletion of staging objects before linking.
Exact root build options now documented in the qualified pin README reuse the
Support6 RF compiler/cache without altering historical seed bytes. Final Debug/RF
host packages may share that independent seed, but their actual component manifests
and binary identities must be verified on each final install. Root owns the final
registered gate and any decision to change package selection.

## Matched counter-only native adapter

Coordinator approved a separate manual-native method for A09's eight C0 counted
builds that emit valid release LLVM but hit the immutable old driver deletion bug.
`manual-native/manual_native.py` reconstructs the exact Git runtime, checks its bytes
against the frozen compiler ELF, extracts the exact embedded number object, invokes
the unchanged counting-runtime source generator and uses the original release
native flags. No compiler, source history, tool admission or frozen timing artifact
changes. C0 and Support6 preparations passed; candidate JSON and parallel controls
produce identical complete counter documents/output through normal and manual
native builds, RC0/live0. Wrong runtime/source and LLVM ABI guards refuse.

All hashes and raw commands/evidence are in `manual-native/validation.json` and
`manual-native/raw`. A09 has the API and prepared C0 runtime for the fresh15 input
supplement; those results and final candidate equivalence remain separate. All8
ordinary C0 build failures remain preserved, and no old failure is relabeled as a
successful supported compiler invocation.
