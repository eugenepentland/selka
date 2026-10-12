# Default and selector-retirement preparation

Neither patch is applied. This directory is reviewable preparation, not a completed
milestone or qualification result. The coordinator must approve C2 only after C1's
whole release inventory qualifies, and C3 only at the retirement stage.

`C2-default.patch` changes ordinary pipeline/check/dump-IR selection to checked
ownership and updates command help. Frontend ownership selection is limited to
check/check-project/check-module/check-session/lint; partial navigation commands
keep their existing ability to inspect invalid programs. Existing experimental selectors temporarily
select the same default; there is no CLI switch to fall back to RC. This temporary
acceptance still prevents a selector-retirement claim. Cost, coverage, test workers,
providers and cache lowering inherit the selected pipeline policy. Doctest children
already inherit their compiler's ordinary default when no opt-in is forwarded.

`C3-cli-selector-retirement.patch` applies after C2. It removes active parser
acceptance and child forwarding. Both old selector spellings, including `=VALUE`,
produce status 2 with the flag name and `was retired; checked ownership is the
default; drop the flag`. The common public dispatcher checks before the profiling
check, doctest or cost paths can bypass it. The standalone Core entry does the same.
Arguments following the guest `--` separator remain guest arguments. This patch
only retires CLI selection: it does not remove the runtime or IR implementation.

Exact source-file hashes and patch hashes are in `draft-identities.json`.
`git apply --check` passes on the prepared C2 source, and C3 passes against a
scratch copy with C2 already applied. `zig fmt --check` passes on both scratch
stages. No draft compiler has been built, and no default or retirement gate has
been claimed. Production support fixes made while preparing this inventory are
tracked separately in the A10 handoff.

## Internal API migration obligations

`internal-api-calls.json` records every active `src/**/*.zig` import-qualified call
to the enumerated Core APIs, their internal wrapper calls, imported type references,
and all mode-field sites. It resolves local import aliases and direct `@import`
uses and excludes comments/guest source literals. There are no function-value
aliases of the enumerated APIs. The accompanying Markdown groups files for owner
assignment. This is a source inventory, not a dataflow proof or executed coverage.

| Layer / owner | Producer and required action |
| --- | --- |
| Source lowering / A07 | `build.Input` defaults false. `buildModule`, `buildRoots`, `buildModuleSource`, `buildRootsSource` and `coverageSource` construct default Inputs. `buildExecutable[Cached]` and `buildRootsCached` accept Inputs; `coverageInput` now accepts selected Inputs too. C3 must remove optional RC lowering and make all wrappers use the owned contract. Source ownership validation must stay eager; merely setting IR bits is insufficient. |
| Hand-built IR / coordinator + A07 | `ir.Module` defaults both mode bits false. `test_support.Hand` and explicit `.Module = .{}` constructions inherit them. `kindOffset` and shared-list families retain legacy layout/uniqueness behavior. Decide one current ABI and reject old IR snapshots; do not reinterpret old headers as owned. |
| Test source helpers / coordinator | `test_support.buildSource` checks source but directly calls `buildModule`. Every `irText`, `llvmText`, facts, optimized, release and owned-text helper inherits this. Migrate checked source helpers and all their inline programs together; don't add a test-only RC fallback. |
| Direct execution / coordinator + A07 | `runModule`/`runOwned` run whichever ABI the supplied Module selects. `runOwned` means running the ownership pass, not necessarily zero-RC. Direct count/retain/uniqueness and snapshot tests need owned behavior/copy or explicit-refusal replacements; intentional wrong-ABI negative tests may retain frozen invalid artifacts without executing RC. |
| Pipeline emission / A10 + A07 | `pipeline_emission_test` and `backend_owned_test` build modules directly before supplying default pipeline options. C2's checked verifier and the actual Module ABI must agree. Preserve whole/split emission and source lifetime assertions. |
| Native emission / A07 | `emit_llvm.emitModule[WithScratch]`, `emitUnitWithScratch` and `emit_units.emit[WithScratch/Cached]` inherit the Module ABI. `emit_release.Parts.zero_rc` defaults false; its legacy callback descriptors and count-release generation must be removed in C3. Audit all callers before deleting fields. |
| Runtime link / coordinator + runtime owners | `driver.wholeUnit` recognizes emitted ABI markers; `driver.link[WithScratch]` combines unit dependencies and selects `runtimeForMode`. Runtime selection and count/COW implementations remain active until C3. `runtimeDirectory` native harnesses currently expose legacy source and also need migration. Task pending-work counters and direct child destruction stay. |
| List methods / A02 | `build_list_methods.zig` keeps legacy reverse/clear/insert/remove/slice-copy/composition branches. At C3 retain owned in-place helpers and explicit child copies; remove unused Range reconstruction and legacy reverse composition. `collection_lower.zig` has no memory-mode selector. |
| Static allocation / A10 | `cost.calleeAllocation` preserves the historical allocation-free RC encode control while checked encode allocates an independent result. Remove that legacy exception in C3; retain strict copy/reverse costs and nonallocating borrowed views. |
| Cached ABI / A08 | `emission_cache.Artifact` and `Dependencies` default `zero_rc=false`; lowering keys, snapshots and canonical IR include both modes. Remove obsolete selectors or retain a mandatory owned ABI marker, but old RC receipts must be refused/invalidate across the actual final compiler identity. |
| Test receipts / A10 + A08 | Local/portable/indexed receipts bind selected modes. Portable canonical lowering now takes the selected ABI instead of default `buildRootsSource`. `test_runner_affected.Request.ownership` still has legacy defaults but production passes both bits explicitly. Remove obsolete defaults/selectors in C3. |
| Allocation contracts / A10 | Mode is now explicit in frontend Session warning analysis, pipeline, cost, test union/provider sessions, dump-IR and coverage. `collectProgram` remains a legacy-compatible internal wrapper until default/retirement approval; tests calling it directly need a deliberate transition. Root lint warnings receive Parsed mode. |
| Developer inspection / A10 | Coverage now validates source ownership and lowers with selected Input. `dump-typed` checks source to display typed trees; its internal allocation warning Session defaults also need the C3 uniform contract, even though it emits no guest runtime. |
| Package / coordinator + A08 | Optional owned compiler pin route is prepared separately. Default component build still uses the immutable historical seed and produces RC guests. Only a real qualified source+binary pin, component protocols, installed manifests and packaging route qualification can close that boundary. |

## Assertion and documentation work before applying

C2 must replace ordinary-parser opt-in assumptions in `single_owner_test` and
`zero_rc_test` with ordinary checked behavior. Directory child tests currently
expect no owned flag for ordinary defaults; the C3 patch updates that test after
forwarding is removed. Receipt three-mode tests must become frozen old-identity
invalidation tests when modes retire. Do not force existing test contexts to RC
simply to preserve obsolete assertions.

The current ownership and managed-memory guides still contain historic implicit
copy/COW contracts. A10 must migrate their runnable examples and prose at C2,
including explicit independent copies, borrowed element/field extraction,
noalloc warnings and scoped resources. Full documentation doctests and the
registered native gate are required; a new introductory paragraph cannot qualify
the older examples. `migration.md` records current migration guidance without
claiming the ordinary default already changed.

After actual stage approval, run the A10 command, followup, cost and analysis-path
matrices with `--default`, installed tests/components, A08 old-artifact checks,
all guest inventories and the complete registered verification coordinator.
C3 additionally needs runtime preprocessing, LLVM/symbol audits and affected fresh
measurements at the exact final SHA. These patches alone meet none of those gates.

The coordinator-owned shared `src/compiler.zig` `zero_rc_flag` declaration becomes
unused after parser retirement and can be removed with its last active caller.
Literal retired flag names must remain in explicit refusal tests/diagnostics;
those strings do not select a runtime. The optional component builder's legacy
fallback/default must also be removed at C3 after the real owned pin is qualified;
changing only root build invocation would leave an active legacy build route.

`retirement_matrix.py` prepares 64 explicit retired-selector command rows, including
profiling-check dispatch, directory tests, doctests, developer commands and
`=true` spellings, plus one ordinary run preserving both names after the guest
separator (65 rows total). Run it in bounded admitted batches on the actual C3 compiler;
it has not run against these unapplied drafts. The Core separator regression checks the same dispatch boundary directly.

`ownership-C2.md` is an unapplied replacement draft for the tooling ownership
page. Its example uses an explicit copy and omits stale historical compiler
statistics. The installed-component boundary remains explicit. The companion `managed-memory-C2.md` draft updates moves, borrowed extraction,
independent copies and direct destruction, and makes the prior text-only examples
executable doctests. Both pages still require actual integrated doctest execution
and final source-contract review before publication.

## Support5 draft qualification

`support5/` pins refreshed code, documentation and API-inventory drafts to
`a1f19edf255c8c0886731d8d7cce450d5f657720`. `prepare_docs.py` creates an eight-page
unapplied patch from the exact draft/original hashes. `migrate_reference_docs.py`
reproduces six newly reserved page migrations; `managed_docs.py` reproduces the
managed-memory draft. Current production pages are unchanged.

`qualify_docs.py` tests bounded block selections through the actual doctest
command and preserves each source hash and raw unit result. Projects count all
source blocks but share one execution/check unit; splitting a project across
batches is refused. `summarize_support5.py` joins only evidence matching the
current draft block hashes. The current result is 47/51 blocks (46/50 units)
passing. Three tuple bindings and one round helper remain concrete compiler
blockers. Copies and the current-length index-loop migration preserve their
original output/assertions. The original foreach mutation remains a checked
negative, not silently admitted by a relaxed borrow guard.

These results use explicit opt-in Support5. Applying the C2 documentation still
requires ordinary-command qualification on the actual default compiler, the
remaining compiler fixes, and the complete documentation/registered gate.
