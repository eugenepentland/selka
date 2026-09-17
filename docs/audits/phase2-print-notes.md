# Phase 2 / Wave 1 (D1) notes: output is a capability

Branch `eaa2/print` builds on `main` at `b9372850`, whose dual-spelling stepping
stone (Stream capability, `stream.print`, `stream.write`, `debug`, entry name
rule) landed in `f57d51b1`. This wave completes the flip. The only shared-file
material the wave may not commit is collected here: proposed `SPEC.md` edits,
`src/features.json` wording, and the migration record.

## Status

Complete:

1. **Migration.** Every guest `print(`/`eprint(` site moved to
   `out.print(`/`err.print(` with a threaded `Stream` parameter:
   - tracked `.my`: `examples/boundary-cli/main.my` and `selfhost/prototype/*.my`
     (11 sites); no other tracked `.my` prints.
   - Zig test/source multiline strings: 103 sites across 12 files, plus the
     normal-string sites in `src/io_print_test.zig`, `src/callbacks_test.zig`,
     `src/semantic_cache_test.zig` and `test/integration.zig`.
   - fenced doc examples: 7 files, 20 sites; `zig build test-docs` stays green.
   - `velocity/suites/idioms/*.my` is absent from this checkout, so nothing to do.
2. **`E_OUTPUT_CAPABILITY`.** A bare `print(...)`/`eprint(...)` now reports
   `E_OUTPUT_CAPABILITY` with the fix text "print needs a Stream; add
   `out: Stream` to this function and pass one from main". A user declaration or
   local binding named `print`/`eprint` still shadows the rule.
3. **ReleaseFast `debug` drop.** `mylang build` (without `--run`) passes an
   internal `--drop-debug` to the frontend when the mode is `ReleaseFast`;
   lowering replaces the node with a unit push, so no operand is evaluated and no
   byte reaches stderr. `mylang run`, `mylang build --run`, `mylang test` and
   `--mode Debug` builds keep the line.
4. **Guest test `Stream` pair.** `def test_x(out: Stream)` now works:
   - the export manifest carries `parameter_names`, and the generated codec
     dispatch injects sentinel `1` for `out` / `2` for `err` instead of reading a
     wire node;
   - `stream_cap` joins the codec type table only (never the wire table);
   - the parent codec and the declared-parameter count skip `Stream` parameters,
     so a test needs no cases-file `arguments` for them.

## Files changed (high level)

- Migration script: `scripts/migrate-print-to-stream.py` (now handles `.my`
  files, fenced `mylang`/`my` markdown blocks, and Zig multiline guest sources;
  threads a helper's stream parameter to its call sites).
- Compiler: `src/sema.zig`, `src/io_builtins.zig`, `src/lower.zig`,
  `src/compiler.zig`, `src/project_compile.zig`, `src/main.zig`,
  `src/qbe_build.zig`, `src/qbe_build_templates.zig`, `src/qbe_build_dispatch.zig`,
  `src/qbe_build_codecs.zig`, `src/qbe_wire.zig`, `src/qbe_exports.zig`,
  `src/native_test_wire.zig`, `src/native_test_contracts.zig`,
  `src/doctest_command.zig`.
- Tests: `src/io_print_test.zig`, `src/io_files_test.zig`,
  `src/python_format_test.zig`, `src/python_core_test.zig`,
  `src/managed_cell_test.zig`, `src/effects_test.zig`,
  `src/exit_status_test.zig`, `src/incremental_test.zig`,
  `src/callbacks_test.zig`, `src/semantic_cache_test.zig`,
  `src/structural_constraints_test.zig`, `test/integration.zig`.
- Docs: `docs/io.md`, `docs/effects.md`, `docs/functions.md`,
  `docs/managed-memory.md`, `docs/match-expressions.md`, `docs/plan.md`,
  `docs/results-and-options.md`.

## Proposed `SPEC.md` edits

Append `E_OUTPUT_CAPABILITY` to STREAM-CAPABILITY-1 and drop its dual-spelling
sentence:

```markdown
- [STREAM-CAPABILITY-1] ... A bare `print`/`eprint` names
  `E_OUTPUT_CAPABILITY` with the fix "add `out: Stream` to this function and
  pass one from main"; a local binding or declared function named `print`
  still shadows the spelling.
```

Amend IO-1..IO-6 to name `stream.print`/`out.print` and the receiver as the
destination, keeping the rendering rules, `sep=`/`end=`, the `output` effect,
shadowing and native lowering exactly as they are. IO-5's "print is a reserved
call spelling" becomes "the receiver method is reserved only while no local
binding or declared function shadows the bare spelling".

## Proposed `src/features.json` wording

`stream-capability` and `debug-line` are already present (added in wave 1). Only
the older summary is stale:

```json
"python-print-and-output-effect": {
  "kind": "language",
  "summary": "`stream.print`/`out.print` renders values Python-style through a `Stream` and contributes an `output` effect.",
  "doc": "docs/io.md#print"
}
```

## Verification run here

- `zig build` — green (guardian diff-scoped 88/88).
- `zig build test-units --summary all` — 1146 passed, 0 failed.
- `zig build test-cli --summary all` — 129 passed, 0 failed.
- `zig build test-docs` — 268 files scanned, 491 blocks, 124 run, 0 failed.
- `zig build fmt-check` — clean.
- `zig-out/bin/mylang doc-coverage .` — 0 failures.
- `zig-out/bin/mylang test tests/guest` — 42 passed across 11 programs.
- `mylang test` on a `def test_chatty(out: Stream)` program — passed, with
  captured `debug-marker` shown on a failing case; a `test_both(out: Stream,
  err: Stream)` case also passed.
- `mylang run` a `debug` program — line kept; `mylang build --mode ReleaseFast`
  — dropped; `mylang build --mode Debug` and `mylang build --run` — kept.

## Notes for the orchestrator

- `SPEC.md` and `src/features.json` were not edited (shared files); apply the
  bullets above and Guardian's spec check for the new tag will pass.
- `docs/io.md` prose was corrected in place because the migration changes every
  runnable example's meaning; the SPEC-level prose lives here instead.
- The migration script may be deleted once the guest-test and docs migrations
  are considered permanent. It is kept for the record and for any untracked
  corpus that still uses the old spelling.
