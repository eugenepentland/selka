# Guardian feedback: package retain (C3R1/C3R2 + retained WIP)

Recorded 2026-09-16 while implementing the semantic-retention half of the
C3/C4 correction pass in the `velocity-retain` worktree. Guardian ran
automatically on every `zig build test-units`; the final diff-scoped run passed
all 88 checks. The shared `guardian-zig/FEEDBACK.md` was not edited.

## Good findings

- `spec` is the gate that kept the package honest. The bounded-prefix,
  reference-sized-remap, clear-session and shared-budget regressions carry
  pending `// spec-pending: SEMANTIC-CACHE-9/10/13/14` notes, but because
  `SPEC.md` is integrator-owned they link through existing behaviors with
  `// spec-case:`. Guardian rejected the invented `// spec:` tags as unlinked
  and rejected a reused `SEMANTIC-CACHE-8` as a cross-file duplicate, which is
  exactly the 1:1 map doing its job. The integrator patch below promotes them.
- `type-size` caught the flat 10-field `Statistics`. Folding the per-kind
  breakdown into a nested `RetentionDetail` kept `retained_bytes` at the
  existing top-level report position while staying under the seven-field cap.
- `cognitive-complexity` flagged `Session.remember` at 28. Extracting
  `buildFreshEntry`, `freshMiss` and `fitsOrdinaryBudget` dropped the branch
  count without changing the ownership/rollback shape.
- `ban-globals` rejected the first shared insertion clock (a file-scope `var`).
  The clock now lives in `Cache.reuse.sequence` and sessions receive a pointer,
  which also makes the ordering explicit and testable.
- `try-in-return` and `twin-drift` were both actionable: `Entry.create` now
  binds the value before returning, and the deliberate
  `evictOldest`/`compact` mirrors carry `// twin-drift-ok:` reasons.
- `test-no-conditional` pushed the two multi-loop regressions into named
  helpers, leaving one table-driven loop per test and making the fixture
  builders reusable.

## Friction

- The `spec` 1:1 map has no slot for a package that is explicitly barred from
  `SPEC.md`. The regressions are real and run, but until the integrator adds
  SEMANTIC-CACHE-9/10/13/14 (and the `features.json` entry) the tags can only
  be `// spec-case:` links to neighboring behaviors. The final text is in the
  package report.
- The first shared-budget implementation converged by evicting every generic
  entry under a tight budget: `ArrayList` row capacity and
  `StringHashMapUnmanaged` index capacity never shrink, so the accounting kept
  seeing peak overhead. Guardian/tests could not have named that; it only
  surfaced when a "some entries must survive to be reused" assertion failed.
  The fix adds an explicit `compact` on eviction; a comment now records why
  compaction is load-bearing rather than an optimization.
- `change-classification` counts added test-block lines, so the new regressions
  satisfy it even though their tags are `// spec-case:`. The failure text still
  says "add a `// spec:`-tagged test"; the test-block alternative it also
  accepts would be clearer.

## Integrator patch requested

- Add the four bullets in the package report to `SPEC.md` and register the
  retention surface in `src/features.json`. No other integrator-owned file
  needs a change from this package.
