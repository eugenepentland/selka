# A02 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Production commit: `ac4e945c5` (capacity arithmetic safety).
- Owned production files: `src/core/runtime/core_rt.c`, `core_bytes.c`.
- New regressions: `src/core/a02_capacity_test.zig`, `a02_capacity_fixture.c`.
- Shared edits: coordinator authored the `OWNED-CAPACITY-BOUNDS-1` SPEC bullet
  and `src/core/root_test.zig` import directly in this worktree and authorized
  inclusion in the production commit. No outstanding shared-file request.
- A07 reviewed the complete safety diff and approved it; no ownership, layout,
  helper-signature, or source-language contract changed.

The fix rejects negative capacities/sizes, overflow in element-byte products,
header or alignment addition, and signed list doubling before allocation or
copying. C0 reproducers and exact source fingerprints are committed. Zero-sized
elements, normal growth, snapshots, cleanup and memory-budget diagnostics are
covered.

Validation: `scripts/build-slot.sh build "$ZIG" build test-core
-Dtest-filter='A02 capacity' -j"$MYLANG_DEV_JOBS" --maxrss
"$MYLANG_DEV_MAXRSS"` exited 0; the one registered test passed all 22 native
scenarios across zero-RC and legacy control builds. The precommit whole-tree
Guardian gate passed all 88 checks. No Guardian FEEDBACK entry was written.
Exact test/compiler details: [safety-validation.json](safety-validation.json).

Policy decision: **measured tradeoff, retain the existing policy**. Start-one
reduces retained singleton capacity but increases five-element-list allocation
count by 2.5× and bytes by 2.125× without lowering peak; 1.5× growth increases
reallocations and can have larger final capacity. Existing reserve hints avoid
byte-buffer growth. All 28 native counted runs preserved checksums, used no RC,
and ended with no managed bytes live. See [README](README.md) and [raw evidence](raw/).

The runtime policy artifacts reconstruct exact C0 from Git and use the recorded
Zig hash, independent of the safety-patched working tree. Plain and counted
binaries have separate identities. Native timing samples are preliminary and
noisy and are not guest compiler qualification or a speedup claim. Actual
historical JSON guest reproduction is delegated to A03's
`owned-payload/json_nested` case (expected `121000`), avoiding duplicate builds.

Remaining integration responsibilities: rerun the registered safety test and
the complete verification coordinator on the integrated final compiler; A09
requalifies affected guest runtime/peak/RSS paths under the final compiler
identity. Remaining native timing/RSS cases are queued for A09's measurement
schedule after the smoke-build backlog. No unresolved correctness defect is
known in the A02 change. This evidence does not claim default promotion or
legacy-RC retirement.

## Managed list mutation follow-up

`insert`, `reverse`, indexed `pop`, and `remove` now operate on zero-RC lists of managed children. Insert appends the new owner and rotates it into place; indexed removal rotates the selected owner to the final slot and uses the existing pop transfer/destruction path. Reverse swaps slots. The consuming runtime helpers preserve the list header, capacity, layout descriptor and every child owner, with bounded byte scratch and no allocation or deep copies. Ordinary RC lowering is unchanged at this stage. A07 reviewed the complete helper and lowering path.

The registered `A02 list methods` test passes release, unoptimized debug, verified release, optimized debug, and release without facts. Every mode checks 100 nested-list, wide-record and recursive-union trials (output `500`), independent snapshots, clamped insertion, discarded pop, removed-child cleanup and four failure paths. Counted runs have zero exit-live bytes, clean RC symbols/LLVM, and exact indexed-pop error metadata for -3/2, 2/2 and 0/0. `remove` of a missing element reports `R_LIST_VALUE`. Exact compiler, source, binary and LLVM hashes and complete counter/trap results are in `raw/list-methods/`. No runtime-speed or RSS claim is made for this API completion.

The test uses a read-only equality helper for nested comparisons: direct nested-list equality followed by mutation currently produces an unrelated ownership phi retain. A07 received the full IR reproducer at `.tmp/memory-closeout/A02/list-methods-ir.txt`; this remains a separate support issue, not a passed general equality claim.

Reproduction: `scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter="A02 list methods" -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"`; durable native matrix: `scripts/build-slot.sh build python3 -B experiments/memory-closeout-20261012/A02/list_methods.py --compiler COMPILER --output NEW_DIRECTORY`. The integrated candidate must rerun this registered test. Coordinator authored SPEC/root registration and approved A07 contract edits in this worktree.

## Managed list slice and extension follow-up

Slices and extensions now make independent copies of managed children in checked ownership mode. Syntactic bounded slicing uses the existing explicit-copy operation for aggregate children; Core stepped slicing and extension use the existing deep-copy lowerer. Ordinary RC Core lowering is unchanged. No append/store behavior is relaxed. Self-extension reads the finite original prefix from the current owner after each growth. The output copy is required by the existing independent-value contract.

A07 approved the source and ownership review. The registered list test and separate native matrix pass in all five modes: nested bounded/stepped/empty slices, destination mutation with source preservation, source destruction, nested self-extension from 20 to 40 elements with outer reallocation, managed union payload copies that create control-flow, zero-size children, scalar duplicate removal, and all existing mutation/trap cases. Output remains `500`; admitted counted runs have no RC events or managed exit-live bytes, and LLVM/symbol audits pass. Exact source/compiler/artifact hashes and results are under `raw/list-copying/`. The registered test printed PASS and the build command exited 0; Zig additionally printed its test-runner command, preserved verbatim in the log.

Pending-result and resource slices remain rejected. This worker compiler refuses the negative fixtures before the newly explicit slice guard (`E_GENERIC_REQUIREMENT` for the pending generic list; `E_ZERO_RC_UNSUPPORTED` for resource-list parameters). These are recorded as earlier boundary refusals, not coverage of A01's subsequent pending-list admission. The integrated compiler must rerun them alongside A01's obligation regressions. No runtime-speed or RSS improvement is claimed.

## List-copy arithmetic follow-up

`myl_core_list_copy` now rejects negative lengths and `INT64_MAX` before evaluating `len + 1`. The maximum length is testable with a zero-sized element payload. Before the fix, signed-overflow trap instrumentation terminates scenario 11 with SIGILL; the malformed negative-length scenario 12 is incorrectly admitted. After the fix both report the existing fatal out-of-memory message and status 1. All 26 registered capacity scenarios pass across owned and ordinary control runtimes. A07 approved the guard.

`raw/list-copy-overflow/` records exact source/native hashes and logs. The first UBSan link attempt lacked the handler runtime, so the successful reproduction uses compiler-supported trap instrumentation explicitly; no full UBSan runtime availability is claimed. The new guard preserves the existing capacity policy and is separate from the unapplied Stage 4 preview.

## Source migration follow-up

A separate source migration preserves 72 reserved fixtures, all 358 original test functions and every explicit assertion statement, with original source/hash pairs in `migrations/originals/` and `additional/originals/`. The combined ledger records changed lines and explicit-copy burden. Support4 source checks admit the additional 21 Core fixtures; Support3 admits 43/51 original fixtures. Native validation is partial and its exact compiler identity, counters, diagnostics and artifact hashes are retained in `migrations/interim/`. Pending compiler fixes and remaining batches are detailed in the migration README. These fixtures still require qualification on the frozen final compiler.

The only outstanding test-registration request from this source migration is the coordinator-owned `ce_lists_test.zig` expected budget-trap line adjustment from 60 to 62 (column 17 unchanged), caused by explicit self-append input snapshots. Tuple `.copy()` in `stores` requires the newly integrated A01 tuple-copy API, so Support4's earlier refusal must not be relabeled as a result for Support5.

## Coordinator continuation: unqualified nested-extension patch

Status on 2026-10-12: the coordinator requested a handoff and no additional investigation in this worker turn. Preserve the current uncommitted edits; the nested-extension fix has **not** passed native qualification.

Completed checks:

- Support4 nested self-extension (`rows[0].extend(rows[0])`, 16 managed children) passed source/Core/native compilation and then aborted with SIGABRT. Original source, full Core IR, command lines and compiler hash: `.tmp/memory-closeout/A02/nested-self-extend/{main.my,results.json}`.
- The proposed fix adds borrowed scalar pointer identity (`myl_core_owned_same_block`) and branches before composition into self/current-owner and distinct/source-owner loops. A07 reviewed the exact implementation and ownership contract. The coordinator authored its `zero_rc.zig` contract hunk.
- First registered five-mode test attempt failed at the already-known native object lifetime bug. The coordinator applied the approved `driver.zig` dependency from integrated commit `632726724` solely for validation; **exclude that file from the A02 feature commit**. Initial failure log: `nested-self-extend/fixed-test.log`.
- With that dependency, the registered test compiled its guest but aborted during the first native mode. It did not complete the five-mode matrix. Log: `nested-self-extend/fixed-test-driver.log`; exact tested source hashes: `nested-self-extend/fixed-source.json`.
- Reduced validation against the updated private compiler repeats the runtime abort for nested self-extension. A control extending the nested destination from a fresh independent source prints `passed` and exits 0. `nested-self-extend/trace-results.json` includes compiler hash and an `abort` backtrace shim; `self-trace.ll` preserves emitted LLVM. The shim converts the abort to exit 134 for diagnostics. The underlying cleanup/parent-writeback problem remains unresolved; no successful fix or final ABI claim is made.
- Recursive ancestor-source controls use `tree.children[1].children.extend(tree.children)` and the explicit `.copy()` form. Both ordinary controls print `2 0`; Support4 rejects both zero-RC builds with `E_ZERO_RC_LOWERING`. Typed dumps and results are in `.tmp/memory-closeout/A02/ancestor-extend/`. The destination path is `[field 1, index 1, field 1]`, while source path `[field 1]` is a strict ancestor. A07 owns the approved source ancestry refusal and explicit-copy positive boundary.

Current changed production/test files are `src/core/build_list_methods.zig`, `src/core/runtime/core_rt.c`, coordinator-authored `src/core/zero_rc.zig`, `src/core/a02_list_methods_fixture.my`, and `src/core/a02_list_methods_test.zig`. The tests add empty nested self-extension, dynamic same/distinct sibling sources, forced growth, source independence and stronger RC counter checks. `src/core/driver.zig` is the validation-only approved dependency described above.

Also uncommitted are `qualify_migrations.py` and `qualify_additional.py` changes adding explicit `default` qualification without a prototype flag, fuller RC event checks, and LLVM audits. Their `--help` parsing passes; no fresh native campaign has used these revisions. Preserve them separately from the production alias fix as appropriate.

The broad Support4 migration sweep stopped after four complete batches at the coordinator's request. All 12 ordinary controls pass; eight checked-ownership runs pass and four hit known compiler defects (two providerStore unit panics, two nested-array lowering refusals). Batch 4 never acquired admission and was cancelled while pending. Existing committed interim evidence contains batches 0–2; the additional complete batch 3 is preserved at `.tmp/memory-closeout/A02/migration-runs-support4/batch-3/results.json`. No native jobs from this worker remain running.

Next required work: resolve the remaining nested-extension native abort with A07, add the ancestor-overlap rejection and explicit-copy positive regression, rerun the five-mode matrix and structural/count/cleanup checks, regenerate the unapplied runtime retirement preview after the helper change, then commit the tested feature without the already integrated driver dependency. The helper's separate allocation-free cost qualification is A10 commit `685012b24158e723abb300948f3d36ed1ac3ad2d`; it does not qualify the alias behavior. Resume all 72 fixture migrations on the next integrated compiler and qualify default/retired modes only on their actual later artifacts.


## Evidence-only continuation for C2/C3

The runtime, Core lowering, registered fixture/test and validation-only driver
changes listed above remain uncommitted and unchanged. A01's later read-only
diagnosis attributes the observed abort to parent preparation: a shallow outer
list copy precedes destruction of the old parent, freeing the child before the
extension uses it. A07 is reviewing the narrow place-copy identity path; this
is a diagnosis, not a shipped fix or successful native result.

`QUALIFICATION.md` describes explicit default-mode harnesses for all 72 fixture
migrations and the five-mode list matrix. Default mode supplies no prototype
flag and still requires normal-return RC0/live0 and LLVM/symbol checks. Fresh
output and nonzero aggregate failure checks prevent partial/old evidence from
appearing qualified. Guest command/property/trap evidence is distinguished from
supplemental counted normal-return contracts. C2/C3 execution remains pending.

The audit helper was validated against preserved artifacts: all 12 ordinary
controls fail the owned audit and all eight successful Support4 zero-RC runs
pass. Historical `release_unique` means direct destruction in owned mode and
is reported separately from RC events, as confirmed by A09. The previous
derived migration summary incorrectly included that telemetry in its RC sum;
`migrations/interim/support4-native-summary-v2.json` corrects the classification
and adds the fourth complete batch. Original raw records remain unchanged.
The preserved unqualified `a02_list_methods_test.zig` diff also adds
`release_unique` to its zero-event loop. Omit that single label when resuming
the patch; retain the new `unique_test` and native RC-total checks. The file is
unchanged during this evidence-only continuation, and A07/coordinator were
notified before qualification resumes.

`capacity-archive.json` hashes all 60 raw policy evidence files and verifies all
16 binary/runtime identities, including reconstructing runtime sources from C0.
Earlier harness hashes remain distinct from the current harness. The later A09
Guardian-interference caveat is now explicit. The growth policy remains a
measured tradeoff; remaining native timings belong to A09, and no final-compiler
qualification or runtime/RSS saving is claimed.

All six supplemental wrappers now source-admit on exact Support4. The two
intermediate constructor syntax failures are preserved alongside the corrected
final wrappers in `raw/harness-preparation/`; they are harness authoring errors,
not new compiler defects. Four Python AST checks, all three CLI help parsers,
the 20 historical artifact controls, missing-counter/output-reuse guards and
`git diff --check` pass. These checks do not replace native execution under C2/C3.

## Qualified nested receiver extension on integrated validation base

The five-file physical-identity feature is now qualified on coordinator-provided
validation base `3c5d19c74b5e323306d76bcc0fed18f90290d1af`, with A07's parent
identity/shallow-copy safety fix (`eb9dd1f8d`), exact slot transfers (`e597dbb26`),
and recursive-ancestor source guard (`f88116064`) integrated. The private compiler
SHA256 is `adfbb043082b12264701664274e93efb642b4c410bef89f88fb4b1fb9592da94`.
Exact source and artifact hashes are in `raw/nested-extension/summary.json`.

`extend` checks physical block identity when nested receiver/source expressions
produce different IR references. Identical blocks extend from the current
growing owner; distinct blocks retain the source borrow. Both paths capture the
original length and copy children into independent destination storage. The
borrowed pointer comparison allocates nothing and introduces no RC. A07
reaffirmed the complete helper/branch review after the new matrix passed.

The coordinator's requested single admitted build/test lease compiled
`core-test-binary -Dtest-filter='zero RC A02 list methods'` and ran the same
`--guardian-filter`: 1/1 registered tests passed. Its native matrix covers all
five compiler modes, empty/nested self-extension, dynamic same/sibling sources,
forced growth, child independence, wide and recursive payload cleanup and four
traps. The durable native matrix also passes all five modes, prints `500`, has
RC0/live0 and clean LLVM/linked-symbol audits. `release_unique` direct destruction
is recorded separately from RC events; the erroneous assertion is removed.

Exact and dynamic recursive ancestor sources refuse with
`E_SINGLE_OWNER_OVERLAP` and explicit-copy advice. The ancestor `.copy()` control
passes all five native modes, prints `2 0`, and has RC0/live0 plus clean LLVM and
symbols. The earlier native aborts, source, compiler hashes and ordinary
snapshot controls remain preserved under `raw/nested-extension/before/`.

Only the five approved feature files and A02 evidence are included. The driver
dependency is already in the integration base and is not included as an A02
change. The original worker checkout is untouched by this validation. The
runtime-retirement preview was refreshed separately under
`retirement/nested-extension-refresh/` to preserve the new helper; it remains
unapplied and has only a textual apply check at this revision.

This is feature qualification, not a completed closeout milestone. The compiler
uses explicitly recorded Support5 staged components, which remain a legacy
interim packaging boundary. Ownership is still opt-in and active RC remains.
The coordinator must integrate the feature and run the frozen candidate's full
verification and subsequent default/retirement qualification.

The tested feature was committed as `996501f02673c78b863ac5d0387a21b3c2a5b8ce` on the authorized validation
branch. Its admitted precommit Guardian gate passed all 88 checks; the exact
log is `raw/nested-extension/feature-commit.log`. Complete native/copy counters
and the unapplied retirement refresh follow as separate evidence-only files,
without changing tested production inputs.
