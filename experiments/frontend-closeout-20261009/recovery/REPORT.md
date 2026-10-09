# Parser recovery closeout — October 9, 2026

Phase 2 adds statement and declaration recovery without publishing partially
parsed programs. `Parser.parseDeclaration` consumes one declaration; the outer
parse loop handles source errors and continues at a source boundary. Suite
statement parsing applies the same recovery rule. Recovery rescans from the
failed construct's start, counts nested suites and parentheses/brackets, leaves
an enclosing dedent with its owner, and restores delimiter bookkeeping. This
rescan also preserves a next statement whose first token was already consumed
by a failed missing-expression parse. Host errors still propagate immediately.

Any recovered parse returns `SourceError` before AST publication or the
whole-program migration pass. Formatting therefore rejects malformed syntax,
and structural migration fixes are not derived from an incomplete AST. Existing
original source bytes and span-bearing tokens supply the lossless information
needed for formatter/fix consumers; this batch introduces no duplicated concrete
syntax tree, token/trivia storage or cache format changes.

Four focused regressions and a bounded nested-token mutation corpus cover independent failures across nested suites,
parent-suite dedents and later functions; malformed declaration headers;
formatting rejection and withholding whole-program migration edits; and missing
expressions that consume the next statement's head. Assertions check original
source ownership, source lines, byte bounds, exact offending token text and the
absence of a published AST. SPEC primary tag is `PARSE-RECOVERY-1`.
The previous first-error claim in `PARSER-HINT-1` is reconciled.

Validation used the pinned Zig 0.17.0-dev.1683+5ceec001b through the build-slot
wrapper, assigned local/global cache directories and temporary directory. Timed
logs preserve all attempts:

- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/focused.log`: rejected compile, helper named `declaration` shadowed existing
  locals; renamed to `parseDeclaration`.
- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/focused-02.log`: 8/9 passed; new regression expected `E_SYNTAX` instead of
  the unchanged expression diagnostic `E_EXPRESSION`; expectation corrected.
- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/focused-03.log`: 32/32 formatter/recovery tests passed before the additional
  missing-expression regression.
- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/focused-04.log`: final formatter/recovery tests, 33/33 passed, exit 0;
  4.89 s wall and 489876 KiB maximum RSS.
- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/compatibility.log`: 150/150 syntax, migration and navigation tests passed,
  exit 0, before the additional missing-expression refinement.
- `0bbfeb740:experiments/frontend-closeout-20261009/recovery/compatibility-02.log`: final syntax, migration and navigation verification,
  150/150 passed, exit 0.

These are focused checks, not the integration full gate. The Guardian test
runner reports passing results but Zig prints a `failed command` line even on
successful runs with stderr output; each passing timed log explicitly records
exit status 0. The coordinator runs the full source-quality and repository gates
and owns the required Guardian feedback commit.

Limits: lexical failures and malformed leading imports/module headers still
stop before declaration recovery. A malformed record/variant/domain declaration
is skipped as one construct; member-by-member recovery is not introduced.
Unbalanced continuation delimiters can conservatively skip to the suite dedent
or EOF. Source diagnostics keep their existing offending-token spans, including
the next token for a missing expression; recovery does not invent hole spans or
publish syntax suitable for semantic navigation from malformed input.

The later range/final-focused.log reruns recovery together with 210/210 semantic,
navigation and source-shaped range checks. Its mutation regression checks every
diagnostic span and absence of a published AST after a source error.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
