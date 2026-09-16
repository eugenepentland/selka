# Guardian feedback — HASH declared mutation and return-origin API fingerprints

Task: close the carried-forward exported-mutation-contract gap in incremental
API fingerprints (`HASH` row of the velocity ledger).
Branch: `codex/velocity-hash`
Base: `6a99ef4b`

## What Guardian exercised

The change touches `src/incremental.zig` and `src/incremental_test.zig`; no
`src/interfaces.zig` or `src/schema_graph.zig` change was needed because the
declared `mutates` positions and `return_origin` facts already existed on
`typed.FunctionSignature`.

Guardian findings fixed before the green run:

- `twin-drift` compared `writeEffectMask` in `src/incremental.zig` with
  `interfaces.appendEffectNames` after the incremental file entered the
  diff-scope. The two functions deliberately render different consumers (a
  canonical brace-set fingerprint field versus schema text), so the incremental
  copy now carries a `// twin-drift-ok:` explanation. The underlying duplication
  remains a useful future cleanup but is not behavior in this task.
- `change-classification` initially rejected the production lines because the
  tests were not yet in the diff. The final change lands the mutation-token,
  explicit-empty, generic-mutates, and return-origin regressions in the same
  commit.
- `spec` blocked two temporary `// spec:` tags added under an already-linked
  primary tag. The regressions now live inside test blocks and the existing
  `// spec: INCREMENTAL-ID-1` primary behavior; no new SPEC bullet is required.
- `debug-print-ban` blocked a temporary `std.debug.print` used to distinguish
  inferred private return origins (`params(0)` versus `fresh`). It was removed
  before commit; the final test relies on public hash behavior instead.

All 88 diff-scoped Guardian checks pass in the final focused and broad gate
runs.

## Feedback for later API-fingerprint work

1. The distinction between a declared contract field and its inferred summary
   is easy to lose in serializers. `writeTypedFunction` now deliberately uses
   `declared_mutates` and the conservative exported `unknown` return origin; any
   future serializer change should keep inferred `function.signature.mutates` /
   `return_origin` out of the declaration layer so E2 body-edit stability holds.
2. The `spec` checker enforces one primary `// spec:` tag per behavior. In an
   already-tagged test file, additional regressions should be plain test blocks
   or `// spec-case:` tags; adding another `// spec: INCREMENTAL-ID-1` duplicates
   the linked behavior.
3. `change-classification` correctly forces the regressions into the same
   commit, but the full `test-units` suite is longer than the tool timeout and
   has to run as a polled background job. Focused `-Dtest-filter=incremental`,
   `-Dtest-filter=interface`, and `-Dtest-filter=effect` runs are the useful
   inner loops.
4. The twin-drift waiver is intentionally narrow. A future integrator who also
   owns `src/interfaces.zig` can lift the shared effect-name iteration into one
   helper and remove the waiver; it was not safe to widen this task’s ownership
   for that cleanup.

## Concrete request

- Keep `docs/experiments/incremental-contract.md` as the authoritative wording
  for this behavior: it already says `interface_sha256` includes the normalized
  `mutates(...)` footprint and the published `return_origin` bound, and excludes
  inferred implementation facts. No integration patch is required for HASH
  unless the integrator also wants a dedicated SPEC/features entry for the
  emitted contract fields.
- If the R3 owner changes `interfaces.zig` effect-name rendering, re-run
  `zig build test-units -Dtest-filter=incremental` and remove or narrow the
  `twin-drift-ok` comment only after confirming the fingerprint spelling still
  matches `writeEffectMask`.
