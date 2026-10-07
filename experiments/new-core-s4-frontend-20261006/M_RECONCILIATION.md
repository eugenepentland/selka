# Read-only M / E reconciliation plan

Reviewed exact M `b8d007bdc884caf1959fed09c01e529f4174d382` against E
`702ede7f1c459845529d3bae03e9ed98b5514c35`. `git merge-tree --write-tree`
produces trial tree `4ba9573af37cefe7c53ca54a2773bc932fa22a5e` with four
conflicting paths: SPEC.md, driver.zig, number_runtime.zig and pipeline.zig.
No worktree, index or branch changed. Both commits have identical frozen ir.zig
SHA256 `7232a25ca00d51c16b3cd552ae86859769a3ffb48d7a4f20ed4323708b651d5d`.
This is preparation, not an authorized merge or Wave B implementation; E's
actual application gate is still pending. Use its final qualified source later.

- **One preparation API:** keep M's `pipeline.emitted(allocator, module, unit,
  options, report)` pure, but change its return from `[]const u8` to an
  `Emission { units: []const emit_units.Unit, whole: ?[]const u8 = null }`.
  Move E's existing pre/post verification, mode selection, passes and stats into
  that function. Release calls passes.run once; Debug calls ownership once.
  Build one emit_llvm.Options with Analysis `{facts=result.known,
  vectors=result.plans, provenance=&result.provenance}` and locator.path.
  Emit split units, then emit compatible whole LLVM only when show.llvm is set,
  using that same transformed module and Analysis before the local Result dies.
  Return only arena-owned LLVM/unit bytes, never a borrowed Analysis/provenance
  pointer. There is no second pass invocation for whole output or receipt hashing.

- **Finish and callers:** pipeline.finish calls emitted once, writes its optional
  whole text to --emit-llvm, then invokes driver.link with units. Do not pass
  optional whole text as a second native dependency input; leave Request.llvm
  empty when units exist. finish owns output/tool operations; emitted writes no
  file and runs no subprocess. M programIdentity is the only additional emitted
  caller: it creates its existing fresh single-case programFor module in its
  private arena and hashes the returned split units. buildExecutable separately
  constructs its fresh selected batch through programFor and calls finish once.
  Do not reuse an already transformed identity module for execution. The raw
  merge tree's return llvm and Request.program references are stale.

- **Receipt API and version:** replace receipt.key(base, name, llvm) with
  key(base, name, units), retaining its nonallocating Digest result. Frame an
  explicit unit count, then each unit in actual native order: name, source_path,
  kind, LLVM bytes, number and math flags. Bind the filename rule too: a shared
  documented emit_units.native_extension constant (currently .ll), used by the
  driver and key, plus each unit name describes the exact canonical basename.
  A filename/order policy change must alter this input/domain. Random staging
  parents are excluded; the actual E Debug unit proof shows unchanged full bytes
  across private cwd with the same basename. Update the two receipt key tests
  and add meaningful swapped-unit, basename, flags and field-delimiting cases.
  Recommend core-test-program-v2, core-test-settings-v3, receipts-v2 /
  core-test-receipt-v2, and manifests-v2 / core-test-manifest-v2. The file manifest
  bypasses programIdentity, so its base/version must reject old whole-emission
  interpretation too. Preserve all current compiler/tool/schema/seed/options,
  native/environment/config/provider/source guards and ineligible-case rules.
  Tool-helper inventory/content codecs and frozen IR/ABI formats stay unchanged.

- **Driver and native names:** retain M tool_identity capture, resolved absolute
  executable, Guard and NativeCache; add E emit_units. Adopt E's seven-field
  Request (units replaces program, llvm keeps its empty-unit fallback). Remove
  stale .program initializers in driver_test, driver_native_cache_test and
  test_support; support fixtures retain their actual LLVM fallback. Materialize
  split inputs in invocation-owned staging under resolved.work with canonical
  unit.name + native_extension, preserving E's unit order. Keep whole.ll for the
  empty-unit fallback. A random parent avoids concurrent shared input overwrite;
  retain materialized inputs through the native action and clean only owned
  staging. Final external-link or unproved-tool actions still use linkNative's
  separate fresh local/global cache environment, followed by the original Guard.
  Closed runtime/numeric compilation retains the captured original environment.

- **Dependencies and publication:** initialize number/math only from fallback
  whole LLVM when no units exist, then union every split unit's flags. Append
  runtime once, the required numeric object once, --link inputs in their original
  order and -lm when any unit requires it. Preserve M runtime-object-v2 full
  256-bit keys and pre-rename Guard, numeric tool-digest namespace, random staging,
  cleanup, explicit target x86_64-linux-gnu.2.31 and six-argument guarded object
  API. Retain E flags.buffer_float_symbol in number_runtime.needed; dropping it
  reintroduces the nine retained undefined-formatter conformance failures. C's
  later object integrity/executable reuse is outside this reconciliation.

- **Budgets, typed cases and inventories:** programFor still builds reachable
  original roots, captures originals before batch_entry.add, adds copied-value
  trial adapters, and instruments original source blocks before any passes.
  Preserve original instruction costs, per-trial resets and adapter exclusion;
  do not charge ownership/imported code again. Keep M canonical decimal typed
  validation, exact argument shape/count, typed expected-result validation,
  property_codec encoding checks and invalid-case cold/warm native regressions.
  The root test must retain driver_native_cache_test/property_validate plus all
  E unit/provenance tests. Keep directory loaded-source/provider/import/embed/
  config/policy/case/API snapshots, add/remove detection and final parent tool
  guard. Emitted-unit inventories cannot replace those source-race controls.

- **SPEC and verification:** union the additive M/E spec entries once, preserve
  primary links, identical managed-undef repair and propagation-suite inclusion.
  After the authorized merge freeze exact source/IR/compiler hashes; run compile
  preflight, scoped receipt/provider/budget/typed-case tests, all managed-undef
  native cases, numeric buffer links, provenance/entry closure traces, restored-
  mtime headers, and runtime/number publication/source races. Then qualify every
  inherited package gate on that combined source, including old before strict
  fuzz under the shared qualification lock. Historical green receipts do not
  qualify a new combined compiler. No production source was edited for this plan.
