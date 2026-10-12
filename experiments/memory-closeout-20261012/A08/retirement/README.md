# A08 C3 draft — not applied or qualified

`retirement.patch` is an isolated draft against the file hashes and full source
commit in `draft-manifest.json`. The active compiler sources are unchanged. Apply
only under the coordinator's C3 authorization after C2 qualification, together
with A07's fixed Module/Input ABI and count-free runtime retirement, and A10's
command/package changes. A prepared patch is not milestone 3.

The exact A07 contract is `guest_abi.Abi = enum(u32) {
checked_owned_v1 = 0x4f574e31 }`, `current = .checked_owned_v1`, and
`identity = "mylang-checked-owned-v1"`. Every emitted whole, split, helper and entry
unit must begin with `; mylang-checked-owned-v1\n`. Persisted ABI fields have no
initializers; the nonzero OWN1 tag rejects old false/zero bytes.

The draft covers:

- Required ABI in Core snapshot and lowering wires; no ownership selector or
  shared-list table in layout/canonical/emission identity.
- An ABI envelope around every optimizer stage payload, including body-less
  identity transforms and scalar summaries. Deferred checkpoint loading uses
  the same envelope. Compact eager/demand optimizer indexes and lowering demand
  manifests also carry required ABI.
- Required ABI in LLVM artifacts, dependency receipts and native handles;
  centralized completed-artifact admission checks the actual text marker. The
  compact native-handle path carries provenance even when LLVM is not loaded.
- Whole-build replay requires fixed ABI in both the JSON envelope and its
  checksum-protected snapshot before checking or copying a program. Old/foreign
  tags refuse and the replay version, key and directory change.
- Native object settings, mapping records and linked-program identities bind
  the fixed ABI. Every input unit is checked before native tool discovery;
  dependency flags are combined only after that check. There is no ABI OR.
- Recovered LLVM must agree with the unit's dependency metadata. Old or malformed
  cached inputs miss; direct missing/legacy guest text gets an explicit error.
- The driver runtime has one source selection, optionally instrumented for
  counters, and no RC selector or macro prefix. Runtime source retirement is a
  required external dependency, not supplied by this patch.

The external number-text object remains a content-digested pinned compiler input;
foreign C sources retain their explicit provider/link boundary. Neither is an
alternate legacy guest LLVM path.

Only `zig fmt` syntax checks have run. No C3 typechecking, regression, native,
ABI, package or performance result is claimed. The five new-file drafted regressions
cover checksum-valid legacy and foreign artifact images, compact/native receipt
provenance, a mixed guest bundle refusing before tool discovery, snapshot wire admission,
and body-less optimizer stage envelopes. One additional in-file replay test covers missing/foreign
payload ABI, missing envelope ABI and an old envelope version. Source
snapshot/optimizer envelope tests, native-handle recovery and old receipt replay
must all pass on the combined C3 compiler.

## Coordinator-owned caller migrations

The following exact changes are required when this draft is applied. They are
requests, not edits to another worker's files:

- Add `try` to `driver.wholeUnit(...)` in `src/core/{task_ir_test,zero_rc_task_test,
  test_support,pipeline_emission_test,driver_handles_test}.zig`.
- In `count_test.zig`, use `(try emit_units.unit(...)).dependencies.counting`.
- In `native_receipt_test.zig`, add explicit current ABI to Settings, Artifact
  and NativeArtifact values; prefix synthetic LLVM with the marker; use mapping
  scope `native-unit-receipt-owned-v2` for corruption tests.
- In `driver_handles_test.zig`, add explicit current ABI to Artifact/handle
  construction. Existing native-handle recovery assertions must remain intact.
- In `a01_native_driver_test.zig`, prefix synthetic unit text with the marker
  and give each dependency record explicit current ABI. Keep its private-object
  lifetime and cleanup assertions; the native fallback remains required.
- In optimizer tests that directly encode/decode `Final`, `Transform` or
  `Summary`, use `optimization_cache.Owned(T)` with required ABI or Context
  save/read. Tests that deliberately corrupt a payload must retain a valid
  envelope when testing the inner defect.
- Direct shortcut index tests use `EntryIndex` or `DemandIndex` with explicit
  ABI and new key scopes. Direct lowering-demand receipt tests use the new
  manifest envelope. Test misses must remain observed rather than inferred.
- Update `driver_cache_test.zig` replay-loss path to `cache/replay-owned-v2`;
  update `compiler_shared_cache_test.zig` absent shared-replay path likewise.
  Preserve all existing native receipt/recovery controls.
- Register `a08_retired_abi_test.zig` in the Core test root. Existing spec tags
  are NEW-CORE-STAGE-CACHE-9 and NEW-CORE-DRIVER-1.

The patch does not migrate other tests' Module/Input ownership boolean literals;
that broad retirement migration belongs to the coordinator/A07/A10 assignments.

## Format changes

| Boundary | New identity |
| --- | --- |
| Snapshot catalog | `source-line-column-owned-v3` |
| Raw lowering | `lowered-function-owned-v5`, `lowered-header-owned-v4` |
| Deferred raw | `demand-raw-source-owned-v3`, `demand-raw-owned-v2`, `demand-raw-external-owned-v2` |
| Lowering demand manifest | `lowering-demand-owned-v4` |
| Optimizer payload | `optimizer-owned-v2` and required Owned(T) envelope |
| Optimizer shortcuts | `optimizer-shortcut-owned-v3`, `optimizer-demand-owned-v2` |
| Fusion body | `optimizer-fusion-owned-v2` |
| Facts | `final-facts-owned-v2` |
| Emission keys | `core-emission-input-owned-v3`, `core-emission-receipt-owned-v3` |
| LLVM stores | `llvm-helper-seed-owned-v2`, `llvm-unit-owned-v2`, `llvm-compact-receipt-owned-v3` |
| Native unit | `core-unit-object-owned-v2` |
| Native mapping | `native-unit-receipt-owned-v2` plus required ABI record |
| Whole-build replay | `core-build-replay-owned-v2`, `replay-owned-v2`, required ABI envelope and snapshot |
| Program | `core-program-owned-v3`, `core-shared-program-owned-v2` |
| Runtime object | `core-runtime-object-owned-v5` |

These explicit identities supplement the full compiler-source namespace.
Historical C0 caches, immutable seed inputs and comparison reports are untouched.
