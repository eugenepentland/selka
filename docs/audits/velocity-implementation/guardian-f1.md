# Guardian feedback: F1 canonical formatter

Scope: `codex/velocity-f1`, base `66e96ce`. Guardian ran through `zig build` and
`zig build test-units`/`test-cli`. All checks passed in the final runs.

## Good findings

- `formatting` caught a real `zig fmt` style change in the new 500-line source
  before any commit. Cheap and correctly diff-scoped.
- `change-classification` required a `// spec:`-tagged test in the same change.
  Adding spec-tagged formatter tests was the right pressure; the check also
  correctly accepted `// spec-case:` repeats.
- `error-path-test` initially flagged the two new `errdefer`s in private helpers
  (`collectComments`, `collectTopStarts`). Naming those helpers in an allocation
  failure test cleared it and made the test intent explicit.
- `repeated-string-literal` flagged `"canonical.my"` four times in the new test
  file; extracting `canonical_path` was a small, real cleanup.

## Friction

- `spec` reported "duplicate tag: id:tool-5" when several tests used the same
  `// spec:` tag. The intended pattern (one `// spec:` plus any number of
  `// spec-case:`) is only discoverable by reading existing files or the check
  source; the fix message does not say so.
- `error-path-test` subjects a new `errdefer` to the *enclosing function name* and
  then requires a test to name that private identifier. For a helper with no
  public surface this reads as test-only ceremony; a `// UNTESTED-ERROR:` waiver
  would have been easier but weaker. Naming the helper in the test title is a
  reasonable compromise once the rule is understood.
- The install step is gated on a green Guardian run, so a red diff-scoped check
  prevents even running the existing focused test binary. That is by design, but
  it makes the "run focused tests first" instruction require clearing Guardian
  findings before the first useful test signal.
- `zig build test-docs` reports a pre-existing mis-tagged `text` fence in
  `docs/audits/development-velocity-proposals-2026-09-15.md:141` (the audit's
  formatter example). The audit is frozen, so the integrator or D2 must decide how
  to exempt historical evidence from the doctest mis-tag lint.
