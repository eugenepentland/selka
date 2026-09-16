# Guardian feedback: WARM (warm compiler-build invalidation)

Recorded 2026-09-16 while closing the stale `qbe_build_assets` warm-build gap in
the `velocity-warm` worktree (branch `codex/velocity-warm`, base `6a99ef4b`).
Guardian ran automatically on every `zig build` / `zig build test-*`; the final
diff-scoped run passed all 88 checks. The shared
`~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.

## What Guardian exercised

`zig build` runs the repository Guardian gate on every install, and it ran on
each cold and warm rebuild used to reproduce the defect. No blocking findings
were raised by the fix or its regression. The recurring report-only
`line-length`/`function-length`/`file-size` findings were unchanged by this
package. `change-classification` was satisfied by landing the regenerated-module
invariant test in the same change as the build-graph fix.

## Root cause

`build_qbe_assets.module` registered `b.dependOnDirectory(b.path("src"))` (and
one dependency per subdirectory). In this Zig build system a directory
configure-dependency tracks entry creation, deletion and rename only: rewriting
the contents of an existing file does not repeat the configure phase. The
generated `assets.zig` embeds `content_hash` (the selected runtime sources) and
`compiler_identity` (every compiler input), both computed by `read()` during
configure. The `addWriteFiles()` copy step, by contrast, is invalidated by the
source files' contents, so a warm build could pair freshly copied `@embedFile`
bytes with the previous build's `content_hash`/`compiler_identity`.

That mismatch defeats the content addressing the runtime path relies on:
`materialize` returns an existing `<cache>/runtime/<content_hash>` tree without
rewriting it, `runtimeInstalledHash` names installed archives by the same hash,
and `qbe_build_cache` folds `compiler_identity` into object keys. A rebuild after
an in-place runtime edit could therefore reuse the old materialized sources and
the old installed archive name while the compiler carried new codegen.

## Fix

`build_qbe_assets.read` now calls `b.dependOnFileContents(b.path(relative))` for
every source file it reads, keeping `dependOnDirectory` for add/remove/rename.
Any content edit to `src/` repeats configure, so the identity the artifact
embeds and the bytes it bundles are produced from the same read. The generated
write-file directory is already content-addressed (its `assets.zig` bytes are
part of the step configuration), so changing `content_hash` or
`compiler_identity` moves the module root path and every importer recompiles;
no separate content-addressed file name or per-artifact module copy is needed.

## Regression

`src/qbe_build_test.zig` adds "bundled content hash digests exactly the embedded
runtime bytes": it rebuilds the exact `manifest`/`digest` encoding from
`bundled.files` and asserts it equals `bundled.content_hash`. On the buggy warm
module the check fails (embedded hash `bf8213…`, recomputed `2536c0…`); with the
fix it passes. A true end-to-end warm-invalidation test cannot be expressed as an
in-tree test without mutating a tracked bundled source inside one `.zig-cache`,
so the exact reproduction transcript is recorded in the package report.

## Exact integration / documentation patch requested

This package owns only the build system and `src/qbe_build*.zig`. The
integrator should:

1. In `docs/audits/velocity-implementation/final-status.md`, delete the
   "Build-cache staleness" bullet from "Known limitations carried forward" (or
   mark it fixed with this branch), because a warm in-place runtime edit no
   longer keeps the old `content_hash`.
2. In `docs/audits/velocity-implementation/README.md`, change the WARM row's
   Status from `in progress` to the integration commit.
3. No `SPEC.md`/`src/features.json` change is required: `QBE-3` already promises
   one materialized tree per build-time content hash, and `QBE-RUNTIME-INSTALLED-1`
   already names installed archives by that hash. The fix makes the promise
   true under in-place edits rather than adding a new behavior.
