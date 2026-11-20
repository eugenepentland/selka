# Guardian feedback: package C1

Recorded 2026-09-15 while implementing C1 (per-function dependencies and stable
remapping) in the `velocity-c1` worktree. Guardian ran automatically on every
`zig build test-units` / `zig build test-cli`; the final diff-scoped run passed
all 88 checks. The shared `guardian-zig/FEEDBACK.md` was not edited.

## Good findings

- Diff-scoped mode reported exactly the C1 files in scope and caught real
  problems before the tests ran:
  - `formatting` / `deprecated-alias`: the first draft used
    `std.ArrayListUnmanaged`, which 0.17 deprecates; the rewrite uses
    `std.ArrayList` (unmanaged by default). `zig fmt` also caught one
    continuation-expression line.
  - `function-size`: `Entry.create` had 11 runtime parameters. Bundling the
    changing snapshot facts into an `Entry.Spec` value brought it to the cap.
  - `type-size`: the flat 14-field `Entry` tripped the seven-field cap. Nesting
    `Identity` (4 fields) and `Metadata` (5 fields) under `Entry` (7 fields)
    matches the contract shape and made the relocation facts easier to read.
  - `doc-comments`: three new public declarations were reported until each got
    a real `///` comment.
  - `orphan-files`: dropping the old whole-program `nominal_type_syntax.present`
    gate orphaned `src/nominal_type_syntax.zig`. C1 keeps one import and records
    the observation on `Prepared.nominal_syntax`, so the module stays reachable.
  - `change-classification`: correctly demanded a regression in the same change;
    the per-function reuse, reorder, negative-lookup, relocation and mutation
    tests arrived with the source edits.
  - `spec`: a speculative `// spec: SEMANTIC-CACHE-7` tag was rejected as
    unlinked because C1 may not edit `SPEC.md`. The regressions now use existing
    `// spec:` / `// spec-case:` links; a `SEMANTIC-CACHE-7` bullet should be
    added before the final pass to promote them.
  - `debug-print-ban`: a temporary matrix-wide `std.debug.print` was rejected;
    the final harness uses the exact per-case expectations instead.

## Friction

- The `spec` 1:1 map assumes `SPEC.md` is writable by the package. C1 explicitly
  may not edit it, so new C1 behavior is covered by reusing existing
  `SEMANTIC-CACHE-*` bullets. The integrator should add a C1 bullet (per-function
  eligibility, stable function/type remap, negative lookups) plus its features.json
  entry.
- `line-length` and `file-size` are report-only and stayed noisy on an otherwise
  green diff; the formatted dependency walk is the main contributor.
- `change-classification` counts added `test { ... }` lines, so the C1
  regressions satisfy it even when their tags are `// spec-case:`; that is
  correct, but the failure text ("add a `// spec:`-tagged test") could mention
  the test-block alternative.
