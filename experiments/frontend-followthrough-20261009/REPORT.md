# Readable frontend follow-through

Base: `d21b2dfa9b36f1de285985a6b38e39847d6beca2`.
Branch: `codex/frontend-followthrough-20261009`.
Implementation commit: `d8fe5b797`.
This is the first implementation batch of the revised October 9 plan.

## Changes

- Reconciled active language, standard-library, memory and cache documentation.
- Added a live `.my` formatting gate to `test` and `fmt-check`: 752 selected
  sources, with 257 explicitly explained exclusions. New files in the selected
  roots join automatically. Frozen evidence, intentional syntax failures,
  compiler-internal builtin syntax and exact-span fixtures keep their bytes.
- Reused and adapted the historical embedded-source migration/census tools for
  `func` and headerless modules. They use compiler-provided repairs, validate
  staged results, preserve golden outcomes, and replace validated files with
  checks against concurrent edits.
- Completed `E_ARENA_REMOVED` with structured migration fixes, retained alongside
  independent semantic errors. Ambiguous binding rewrites are withheld. Live
  sources and 15 embedded golden payloads were migrated; golden IDs, options,
  outcomes and the six original golden exclusions remain intact. Two deliberate
  view-storage refusals still report `E_VIEW_STORED`.
- Fixed migration of independent same-named locals, comprehension/generator
  binders, overlapping enum payload/type edits and nested comprehensions.
- Fixed parenthesized byte literals changing from managed bytes into fixed arrays.
- Prevented numeric conversion repairs from silently calling a user function
  named `parse_int` or `parse_float`. A full EDA run exposed recursive calls from
  this defect; its failed receipts and reduced regressions are preserved.

## Validation

Final compiler SHA-256:
`5e072ee17b825cfbd40ed5533c3bce9f166ce4ae576395020cd5e435cc45ed11`.

- Full repository gate: **94/94 steps passed** (`full-gate-2.log`), 63.23 s
  gate body and 72.87 s including admission. The earlier full run passed all
  2,235 selected Zig tests but failed three migration-driver tests; those
  failures exposed the external-path selection bug described below. The final
  run executed 559 Zig tests and reused valid cached steps (3,913 shard skips).
  Skipped/enumerated counts are not executed-test counts.
- Formatting: all 752 selected `.my` sources pass, with 257 reasoned exclusions;
  the first formatting gate passed 15/15 steps. The final receipt is
  `fmt-check-3.log` (15/15 steps, exit 0).
- Whole-tree Guardian: 88 checks passed, exit 0 (`guardian-full-2.log`);
  configured report-only findings remain disclosed in that receipt.
- Focused checks: 79 frontend, 21 arena and nine CLI fix tests passed, followed
  by 18 arena-retirement tests after the final capture guard. Filter totals
  contain their standard unnamed tests and must not be summed as distinct tests.
- Developer tools: six format-driver tests and 12 embedded-migration-driver
  tests pass, including the real cache-backed TMPDIR configuration.
- Lox: all 974 native conformance answers match frozen exit/stdout/stderr;
  all 84 mode commands preserve 65 guest tests and 13 configured cases in
  Debug, release and verify, including directory runs.
- EDA: all 34 native goldens match exit/stdout/stderr/output files; all 366 mode
  commands preserve 310 tests per mode. Six property-bearing commands explicitly
  use the frozen seed `8679566789041942096` to preserve the original samples
  after the intended `src.` module-name migration. The different default-seed
  runs remain supplementary evidence, not frozen-sample equivalence.

`external/successor-qualification.json` binds the final compiler and source
identity. All 450 mode commands passed again on it, with zero unexplained
complete-report or stderr differences. Lox's complete generated IR is identical
and EDA's rebuilt native executable is byte-identical to the source-frozen
candidate on which the native answers were compared. Configured provider text
and fingerprint changes have explicit source/contract reviews; arbitrary
fingerprint equality is not claimed.

The first full gate found that the migration helper treated an unrelated host
`.cache` ancestor as a selected-source exclusion. External selection is now
bounded by the requested tree, while repository exclusions and selected-tree
cache/history boundaries remain protected. Twelve driver tests pass with the
actual cache-backed TMPDIR. Failed attempts remain saved.

The final install spent 281 seconds waiting for a shared build slot; compiler
work took about four seconds. Admission time is not compiler time. These runs
are functional qualification under shared-machine conditions, not uncontended
performance measurements or satisfaction of the old numerical budgets.

## Scope and remaining work

This closes the first implementation batch: current syntax/documentation,
format enforcement, safe arena retirement, migration repairs and frozen
external qualification. The source-shaped IR, parser recovery, stable cache
identities, effect simplification, generic lowering and additional cost work
remain subsequent phases in `docs/audits/frontend-followthrough-2026-10-09.md`.
No old numerical gate has been relabeled or rerun. The original 15/21 accepted
jobs and 177/333 samples remain unfinished historical evidence. The old FP2
branch is evidence to selectively refresh; existing FB1/cost CLI work is already
on the merged base. No merge to main or push is part of this batch.

External migration deliverables are patches and per-file mappings from verified
Lox/EDA pins, not edits to application worktrees. Some application changes need
explicit review: EDA's `src.` module identity, `SchematicUnit`, numeric wrapper
names, and hoisted fallible expressions. Do not describe automatic `fix` as a
complete migration of arbitrary old programs.

`src/core/ir.zig` has no change in this batch. The old checkpoint inventory is
rechecked by `historical-preservation-check.json`; dirty historical evidence
remains in its original worktree.

## Follow-up discovered during qualification

`dump-ir` cannot resolve the configured-root EDA `src` imports although normal
check/build work. Failed dump receipts are preserved and empty output was not
accepted as equality. Native executable identity supplies the EDA successor
proof. Unify the project-loading paths before the next typed-IR corpus audit.
The historical stdlib-row JSON dump crash remains outside this batch.

## Evidence and machine limits

All raw successful and rejected qualification receipts, source mappings,
patches, reports and guard manifests are preserved. Large evidence is committed
in scoped batches below the local diff-reader ceiling. Reproducible compiler
artifacts and source snapshots remain local and ignored; the patches bind the
snapshots to verified Git pins.

The shared disk filled after the successful full gate. The first final Guardian
attempt returned exit 1 without a captured log, and `fmt-check-2.log` records
`NoSpaceLeft`. Neither is a pass. Only this worktree's inactive, reproducible
unit/Core and external native/mode caches were removed to recover space; raw
receipts, shared caches, historical evidence and other worktrees were preserved.
Fresh final check receipts are `guardian-full-2.log` and `fmt-check-3.log`.

Guardian usage feedback was appended and committed separately as `cea9ab5749c5bc69d99b4d805a77105adb28711e`.

`patch-whitespace-audit.json` records the whitespace check on archived patches:
all findings are required unified-diff context prefixes on blank lines. The
implementation diff passed its whitespace check; patch bytes remain intact.
