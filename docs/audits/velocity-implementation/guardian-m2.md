# Guardian feedback — M2 origin, alias and call-permission enforcement

## Good findings

- `function-size` (<=6 runtime parameters) caught several analysis helpers that
  had grown past the cap; bundling call-site state into `WriteSite`/`CallSite`
  made the pass easier to read rather than merely satisfying the linter.
- `test-no-conditional` (one top-level loop per test) rejected a temporary
  diagnostic test that printed two independent traversals; the final origin
  tests use one nested traversal and read better for it.
- `doc-comments` forced every new `pub` origin helper (`Origin.fromPosition`,
  `merge`, `isFresh`, `typesMayAlias`, ...) to explain its lattice meaning, which
  is exactly the part a future reader needs to trust.
- `change-classification` plus `spec` linking correctly stopped a new
  `MUTATION-ENFORCE-*` tag family whose SPEC bullets M2 is not allowed to add.
  Reusing the linked `MUTATION-METADATA-1` id as `// spec-case:` kept the change
  green; the SPEC/feature bullet for the M2 guarantee is still an integration
  patch (recorded in the completion report).
- `errdefer`/error-path checks pushed the temporary analysis allocations to
  exact-size allocations and an explicit `defer if (!keep)`, removing leak
  ambiguity under `checkAllAllocationFailures`.

## Friction

- The hard `line-length` limit (240) on a long corpus signature is stricter than
  the report-only file/function length limits and required wrapping a doc line;
  acceptable, just asymmetric.
- `test-no-conditional` counts loops added to a test even when they are distinct
  assertions with no shared fixture; splitting the temporary diagnostic into two
  tests would have duplicated the whole compile, so the loops were nested.
- As with M1, the full `test-units` suite exceeds the tool timeout and must run
  as a polled background job; the `-Dtest-filter=effect` inner loop stayed under
  a minute and is the useful signal.

## Concrete request

- Add the M2 SPEC bullet (`## Ungrouped` may be needed) and the matching
  `src/features.json` entry so `// spec: ` can name the origin/call-permission
  guarantee directly. The exact text is in the M2 completion report.
