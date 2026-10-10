# Explicit noalloc and effect consumer audit

The final semantics reserve the strong Core allocation contract for explicitly
written `noalloc`. Existing `effects(...)` lists retain guest-level effect
semantics even when managed_allocation is omitted. A shared
`effect_set.coreAllocationBound` predicate inspects the exact bound's source span;
concrete specialization bounds retain their source spelling. Absence of a clause
never opts into the strong promise.

All explicit noalloc concrete roots are lowered together, including unused
functions and no-main libraries. Debug ownership expands copy-on-write branches
on that scratch module before release optimization. One reverse-callgraph fixed
point uses the existing `core/cost.zig` classifier on every instruction in every
block and internal callee, including cold/disconnected paths, loops and recursive
cycles. Managed backing, runtime scratch and unresolved foreign/callback sites
reject. Unsupported concrete lowering reports E_CORE_ALLOCATION_BOUND; per-root
retry attributes its bounded caller. This is a static may-allocate verdict, not
measured allocations. Abstract generic bodies retain frontend checks; concrete
noalloc instances receive Core checking. Opaque extern/Host declarations do not
prove that their calls are allocation-free.

## Entry points and caching

Core Session checkFile/checkDeclared add verification after typed checking for
Core check, build/run, test and cost. The existing mylang CLI also calls the same
validator after single-unit/project checks and check-module/library checks.
checkLibraryProgram APIs return trees for backend validation without setting an
executable `.program`; existing frontend-only APIs retain their guest-level
verdicts. No Core import cycle or executable library invariant was introduced.

Core validationOnly and CLI check-project use allocation_contracts body policy.
Only explicitly written noalloc bodies and their transitive callees require
concrete trees. Previous summary edges stay in the previous table and map by
stable key to current declarations, preserving unrelated unchanged stand-ins.
A new/changed noalloc body conservatively requests concrete trees because its
new edges are unknown; ordinary typed-body reuse still works. Empty terminating
summary bodies are additionally recognized as unverifiable and propagated to
bounded callers, so an opaque stub cannot establish allocation safety.
Compiler/source-bound stored complete verdicts keep their normal replay rules.

## Consumer audit: inferred facts retained deliberately

| Fact | Consumers | Why deletion is unsound or a separate API change |
| --- | --- | --- |
| Transitive effects | capability/ceiling diagnostics, callback slots, contract purity, generic calls, origins/interface facts | Source authority and guest-level contracts still require transitive validation |
| Mutation footprints | mutation/origins, callable contracts, overlap checks, interfaces | Explicit mut retains checked write and alias guarantees |
| Return-origin bounds | origins/mutation and returned-input alias propagation | Ownership/value independence needs sound returned-input information |
| writes/external | origins, module_interface fingerprints/rendering, semantic_key, semantic_summary, navigation | Persisted semantic dependencies and exposed navigation facts remain legitimate consumers |
| Cleanup effects | resource cleanup, generic/resource checks | Error/trap/cold cleanup cannot bypass capability checking |

No inferred fact was deleted merely because Core now verifies noalloc. The
simplification separates the explicit backend promise through a shared cost API
without duplicating an allocation opcode table or replacing capability/mutation
inference with allocation guesses. Frozen Core schema is unchanged.

## Final verdict differences

| Reduced case | Frontend-only | Compiler command | Reason |
| --- | --- | --- | --- |
| cow-library.my unused fixed-slot update under noalloc | accepts | E_CORE_ALLOCATION_BOUND | Ownership may detach list backing |
| scratch-cold-library.my compound dictionary lookup under False via helper and noalloc | accepts | E_CORE_ALLOCATION_BOUND | Compound-key hashing/equality may grow runtime scratch; cold callees count |
| Unresolved callback under explicitly written noalloc | callback ceiling may accept | conservative E_CORE_ALLOCATION_BOUND | No static Core target |
| Unknown user extern under noalloc | declared effects may accept | conservative E_CORE_ALLOCATION_BOUND | No foreign allocation proof |
| Unsupported concrete noalloc body | may accept | actionable E_CORE_ALLOCATION_BOUND | Missing Core evidence is not safety |
| Scalar noalloc library/recursive graph/generic specialization | accepts | accepts | No allocation witness |
| Same fixed-slot update under effects(mutation) | accepts | accepts | Legacy guest-level contract preserved |
| Indirect callback under effects() | accepts | accepts | Legacy callable API preserved |

## Audited classifier and provenance fixes

Generated scalar runtime helpers use extern_c for ABI. The old classifier marked
them unresolved even when their audited name was allocation-free. The allowlist
now applies only when the declaration also has span==0 (compiler-generated).
Source extern name spans are nonzero; reserved myl_/mylang_ names also fail
E_EXTERN_SYMBOL. Tests cover both namespace impersonation rejection and raw
source-spanned helper conservatism. No shared signature descriptor table exists;
builtin builders remain the signature authority. No ABI/linkage was changed.
Unknown user externs stay unresolved.

myl_core_octets_compare is added after inspecting its memcmp/length-only body;
myl_core_dict_ordinal scans existing dictionary metadata without allocation.
Known parse-range/text/comparison scalar helper calls now have accurate static
site/unresolved counts. This is classifier accuracy, not measured savings.
Ownership's copy-on-write marker inherits the original update span, correcting
COW JSON location from synthetic offset zero to line 2, column 5 and potentially
improving emitted debug locations without changing runtime behavior.

## Rejected broader attempt and compatibility review

An intermediate implementation applied full Core semantics to every explicit
allocation-excluding effects list. Full integration and the range differential
showed that this silently reinterpreted established guest-level APIs. The final
scope correction restricts the promise to written noalloc; failed logs remain.

The range differential's eight command failures represented four source cases.
Sorting's compare_strs exposed the missing octets_compare allowlist entry (fixed
with body evidence). python_collections.writeback COW and network resource-result
boxing are real implementation allocation but occur under legacy effects lists;
those lists retain their previous semantics. Intermediate edits adding allocation
to writeback and four network wrapper ceilings were reverted. Two callback cache
fixture ceiling edits were also restored; their original native-equivalence and
reuse/miss assertions remain. A separate explicit noalloc callback regression
keeps the strong rejection. Filesystem/environment wrappers have absent ceilings,
time pure helpers use scalar/record storage, and random managed Result helpers
already include guest allocation. No blanket annotation widening remains.

## Validation

Focused logs preserve compile mistakes, slot admission waits and superseded
queued requests cancelled before admission. `0bbfeb740:experiments/frontend-closeout-20261009/effects/test-session.log` passed 6/6 Core
regressions in 7.43s before the noalloc-only correction. `0bbfeb740:experiments/frontend-closeout-20261009/effects/test-summary-final.log`
passed 8/8 (one named regression plus seven mandatory unnamed blocks) in 9.32s.
Actual CLI checks are in cli-check-results.json and per-case logs: COW JSON
points to line2,column5 and scratch text points to the helper line2,column12.
Final noalloc-only Core suite passed 7/7 in test-final-seven.log (11.00s including compilation), including the legacy effects-list cold/warm positive and strict noalloc cold/warm/edit rejection. cli-final-results.json records the final source-built compiler: legacy effects COW/callback library exits0; explicit noalloc COW and cold scratch each exit1; spoofed runtime extern exits1 with E_EXTERN_SYMBOL.
The coordinator owns full gates, corpus qualification and Guardian feedback.

The final compatibility unit run `0bbfeb740:experiments/frontend-closeout-20261009/effects/test-compatibility-final.log` passed 9/9 in13.64s: the unchanged managed_lists_test fixed-slot positive uses legacy effects(mutation), and the noalloc summary/reorder regression passes with the exact source-spelling predicate. No edit to that legacy test fixture was needed.

## Full gate 2 followup: fixed UTF-8 diagnostic and resource contracts

The full gate exposed two distinct real implementation allocations. The cold
UTF-8 validation error called `myl_core_bytes_utf8_error`, whose implementation
in core_text.c returns `str_from` of a fixed message. build_text_more.zig now
lowers that message as pooled `str_const`, preserving its exact bytes and stable
lifetime while removing the allocation. No helper was marked allocation-free.
The regression lowers unused bounded `measure` and asserts zero static allocation
sites; its native invalid-byte counterpart matches Err and checks the exact
message `invalid UTF-8 in byte string`. The existing valid/numeric parsing case
is retained.

Resource attenuation is different: core_io_cap calls block_new for CoreIoAuthority;
resource acquisition/completion also use allocating adapters and result boxes.
A reduced no-main `bounded(fs: Filesystem) noalloc` calling `fs.read_only()`
therefore remains rejected. Source and IO ownership tests, resources.my,
resource-io.my, both matching examples and documentation now declare
`effects(filesystem)` instead of `noalloc`. Their authority and ownership
assertions remain unchanged. This deliberately restores their guest authority
contract while retaining a dedicated strong noalloc negative; no classifier
waiver permits allocating resource helpers.

Focused followup receipts are retained under test-fullgate2-fixes.log and the
subsequent Core regression log. Slot admission time is included in these timed
receipts. The coordinator owns fresh installation, full gate and followup commit.

Exactly seven resource function ceilings changed: two source-test mains, one IO-test main, two fixture mains, and two example mains; the documentation reproduces the resource-io example.

Followup unit validation passed 13/13 selected tests (including seven mandatory unnamed blocks), exit0, in test-fullgate2-fixes.log: 418.75s total including slot admission. The native invalid UTF-8 exact error payload and existing PY-BYTES-9 valid/numeric cases passed; resource ownership acquisition/completion/move/read assertions passed. The harness printed a failed-command description after its PASS result despite successful outer exit; the complete receipt is preserved. The static Core regression then passed with all eight selected Core allocation contract tests in test-fullgate2-core.log, exit0, 9.27s: unused scalar-count root has zero allocation sites and unused noalloc capability attenuation remains rejected.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
