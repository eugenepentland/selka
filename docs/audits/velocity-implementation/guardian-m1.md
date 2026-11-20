# Guardian feedback — M1 mutation classification

## Good findings

- Guardian caught real structural regressions early: `FunctionPolicy`/`CallbackType`
  field caps, an inferred error set on `mutation.insertPosition`, and a
  cognitive-complexity regression in `effects.check`. Each was fixed rather than
  waived.
- The diff-scoped `change-classification` check forced mutation regressions to
  land with real tests in the same change, including the write-form table,
  generic summary publication, callback assignability, cache-version rejection,
  and forged-IR rejection.
- `type-size` correctly pushed metadata out of existing public structs and into
  the new small `mutation` module / function signature fields.

## Friction

- `change-classification` counted new `// spec:` tags as unlinked unless the
  matching SPEC bullet was edited, but M1 was explicitly barred from editing
  `SPEC.md` or `src/features.json`. The tests were kept and the tags removed;
  the integration package still needs the SPEC/feature registration patch.
- The full `test-units` suite exceeds the 300 s tool timeout in this environment,
  so it must be run as a background job and polled. Focused filters completed in
  seconds and should remain the inner loop.
- Guardian runs as an install-step dependency of `test-units`; there is no local
  switch to run tests while a pending SPEC/feature patch is intentionally absent.
  That is safe for the release gate but noisy during package-local work.
