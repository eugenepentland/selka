# Guardian feedback — package E1

Branch: `codex/velocity-e1`. Base: `66e96ce`. Guardian was exercised
automatically by `zig build test-units`, `test-cli`, `test-docs`,
`test-doc-coverage` and `fmt-check`.

## Good findings

- `twin-drift` caught the new effect-name writer in `src/callables.zig` beside
  `effect_set.write` and `incremental.writeEffectMask`. The callable form must
  spell `effects(output)` while `effect_set.write` keeps the brace-set form, so
  the new copy carries an explicit `// twin-drift-ok` rationale.
- `spec` caught five unlinked `CALLBACK-E1` tags and then a duplicate
  `CALLBACK-1` primary tag. E1 regression tests now use
  `// spec-case: CALLBACK-1`, leaving the existing `CALLBACK-1` primary intact.
- `repeated-string-literal` caught repeated `@import("effect_set.zig")` in
  `src/symbolic_types.zig`; it is now one file-scope const.

## Friction

- The behavior-change check requires a linked `// spec:` tag, but E1 has no
  SPEC.md bullet yet and SPEC.md is integrator-owned. The new tests link to the
  existing `CALLBACK-1` bullet; the integrator must add the directional wording
  to SPEC.md and update the `bounded-guest-callbacks` feature summary.
- `zig build test-docs` reports one pre-existing mis-tagged fenced block at
  `docs/audits/development-velocity-proposals-2026-09-15.md:141`; E1 did not
  modify that audit file. `docs/functions.md` and `docs/effects.md` examples
  passed.
