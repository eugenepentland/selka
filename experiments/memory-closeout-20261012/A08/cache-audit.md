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
