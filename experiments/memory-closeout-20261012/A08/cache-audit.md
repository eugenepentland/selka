# A08 cache boundary audit at C0

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
This is a source audit; executable qualification is recorded separately.

- `build_identity.zig` hashes every production compiler/runtime source plus Zig
  version and compiler build mode. Its registered `tests/compiler_identity_cache.py`
  checks same-cache runtime edits, frontend edits, Core edits, and source relocation.
- `src/core/frontend_reuse.zig` puts that identity into the semantic contract and
  frontend identity. Checked semantic trees do not themselves choose a runtime ABI.
  `pipeline.validateSource` rechecks single ownership eagerly even when those trees
  are reused; the executable matrix must verify invalid edits remain refusals.
- `src/core/lowering_cache.zig:Session.prepare` hashes `drop_debug`, `single_owner`,
  and `zero_rc` into the lowering catalog. The existing three-mode cache regression
  compares cached and uncached emitted LLVM, and expects each mode's first access
  to lower freshly.
- `src/core/stage_store.zig:Store.initWithOptions` derives its namespace from the
  complete compiler identity. `Store.key` includes that namespace, a stage schema,
  and length-delimited inputs. Lowering, optimization and emission artifacts cannot
  be adopted across a production-source change under an unchanged C0 identity.
- `src/core/emission_cache.zig` stores `zero_rc` with completed LLVM and compact
  receipt dependencies. The ABI choice travels to driver runtime selection.
- `src/core/driver.zig:runtimeForMode` prefixes zero-RC runtime C with
  `#define MYL_ZERO_RC 1`; the runtime's actual source content participates in its
  object key. Driver native identities include the complete compiler identity.
- `src/core/build_replay.zig:settingsKey` hashes complete compiler identity, flags,
  entry/configuration, tool identities and environment. Whole-build replay is available for unchanged source under the same checked
  ownership flags; it validates dependency content hashes before accepting a
  receipt. Lazy/demand body restoration is disabled for checked single ownership
  at C0 (`pipeline.useDemandBodies`), so any changed build checks ownership eagerly.
  `--emit-llvm` disables whole-build replay and exercises the underlying stages.
- `src/core/lowering_cache_test.zig` retains the 64-level typed owned-match DAG
  regression. The selector relationship for unpack bodies prevents duplicate
  traversal while keeping field bindings and body edits in the key.

Retirement decision: no gratuitous semantic wire-format bump is needed. Any
retirement production edit changes the compiler namespace automatically. A final
compiler must nevertheless execute against populated C0 caches and reject old mode
selectors after A10 retires them. That final-artifact test remains pending until
C3 exists. No RC retirement change has been applied by A08.

The A08 frontend metadata fix uses the existing `LocalOrigin.iteration` enum value,
so it needs no wire-format change. Production `sema_collections.zig` participates
in compiler identity, isolating old cached semantic/lowered artifacts. Final ABI
qualification must still run against the changed integrated compiler.

## Aggregate provider pin review

The planned compiler-only `myl_core_provider_pin_<physical ir.Type ID>` helper
uses a physical type ordinal, not a private metadata string slot. The lowering
catalog hashes the ordered typed declaration graph, and `Session.advance` hashes
all new physical compounds, function names/signatures and checked-to-physical
bindings. Restore appends the guarded discovery delta at the same indices.
Optimization snapshots independently hash the entire compound/function layout.
The helper name therefore stays exact; renderer string-slot relocation must not
be applied to this suffix. A changed preceding physical discovery changes the
catalog/guard, causing fresh lowering rather than changing a restored suffix.

`a08_provider_cache_test.zig` prepares cold/warm and earlier-record discovery
coverage, full cached/fresh IR comparison, native cleanup and wrong/stale marker
signature refusals. It awaits the coordinator's aggregate-provider implementation
and registration; this draft is not passing evidence. Marker validation must reject
wrong parameter types, ownership bits and use outside the selected zero-RC ABI.


Support5 (`a1f19edf255c8c0886731d8d7cce450d5f657720`) passes forty CLI cache
correctness cases across fresh modes, retained C0 generic/map artifacts, Result
obligations and partial rendering artifacts. See `support5-cache-transition-summary.json`.
The mode audit records fresh RC/zero-RC lowering separately and confirms matching
mode reuse. Whole-module LLVM emission rows have zero unit-emission counters and
must not be reported as direct unit-cache qualification. Final compiler/default/
retirement reruns and registered stage-cache gates remain required.


## Numeric runtime object boundary

`number_runtime.zig` embeds the prebuilt Zig object. Its Blake3 digest determines
its object-store name and is passed explicitly into the native program key;
`number_runtime.object` also compares cached bytes to the embedded payload before
linking. A04's Unicode header correction changes this object and the C shim that
clears the ASCII flag. The ordinary C0 object was found in the original shared
store and matched byte-for-byte to its immutable compiler at offset 10,213,424;
`C0-number-object-provenance.json` records its SHA-256 and exact original path.
A03 and A09 independently confirmed the same 409,072-byte object.

`numeric_object_cache.py` prepares a private old-object seeding/repair probe. The
fixture checks both UTF-8 output and Unicode `len`/index behavior, since correct
bytes alone do not expose a stale ASCII header. Its final candidate execution is
pending the integrated A04 fix; no passing result is claimed for this preparation.
The probe never modifies the old shared object or historical compiler/cache.
