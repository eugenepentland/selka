# Guardian feedback — E2 (explicit exported ceilings)

## Good findings
- `change-classification` did its job: every production edit in `effects.zig`,
  `sema.zig`, `interfaces.zig`, `incremental.zig`, `navigation.zig` and
  `schema_graph.zig` was matched by new test lines, so a regression could not
  ship without a test. It did not fire for the corpus-wide `.my` migration
  because those edits are data/source migrations rather than Zig behavior.
- `function-size` (7 runtime parameters) forced the witness-reporting helper to
  bundle `program` + `graph` into a `BoundContext` instead of growing the
  parameter list; that is a real readability win.
- `spec` correctly rejected a new `// spec: EFFECT-CEILING-1` tag because
  `SPEC.md` has no matching bullet, and rejected reusing an existing tag a
  second time. This kept the 1:1 map honest.
- `debug-print-ban` caught a temporary `std.debug.print` used while diagnosing
  inference behavior; it was removed before commit.

## Friction
- E2 is forbidden from editing `SPEC.md`, so its new acceptance regressions are
  intentionally untagged in `interfaces_test.zig`, `incremental_test.zig`,
  `effects_test.zig` and `native_test_dependencies.zig`. The integrator must add
  the `EFFECT-CEILING-1` bullet (and tags) or the new behavior has no spec link.
  The exact bullet/gate patch is listed in the E2 completion report.
- Because the `spec` check is a strict 1:1 map, adding a second behavioral test
  under an existing tag fails as a duplicate tag even when it is a refinement of
  the same requirement. Extending the existing tagged test, or leaving the new
  test untagged until the SPEC bullet lands, were the only options available
  without touching the integrator-owned `SPEC.md`.
- `test-doc-coverage` was already failing on the integration checkout
  (`docs/tooling/work-report.md` section has no command/program block); it is not
  an E2 regression but it does keep a required gate red locally.
