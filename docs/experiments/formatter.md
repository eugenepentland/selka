# T: canonical source formatter

Status: implemented as `fmt`, with `fmt --check` for verification. The formatter
parses syntax, formats existing token spellings, and preserves line comments in
order and in their original gaps between tokens. It does not type-check, lower,
execute, reorder declarations, simplify expressions, or modify files itself.

```sh
zig build run -- fmt examples/buffer-views.my
zig build run -- fmt examples/buffer-views.my --check
```

Normal mode writes formatted source to stdout and exits 0. Check mode emits no
source, exits 0 for canonical input, and exits 1 with `formatting differs` otherwise.
Syntax errors exit 1 with source diagnostics; usage and host failures exit 2. The
check option is fmt-only and accepted once. Input files retain their original bytes.

## Format contract

The single style uses four spaces per brace level, LF line endings, a final newline
for nonempty output, statement/block line breaks, and consistent token spacing.
Empty braces remain compact; record/variant fields and match arms break at commas
inside braces. Commas inside parentheses, brackets, and builtin type arguments stay
inline. Builtin type arguments remain compact, while comparison operators are
spaced. Numeric spelling, punctuation, parentheses, and token order are preserved.
No trailing comma is added and no optional syntax is removed.

Line comments keep their content, including trailing spaces, with CRLF line endings
normalized to LF. A comment that follows a token on the same original line remains
inline; standalone comments remain standalone. Each stays between the same pair of
source tokens. Blank lines and arbitrary whitespace are normalized rather than
preserved. Whitespace-only input becomes empty; comment-only input is accepted.

Formatting is idempotent. There is no width-based reflow or configurable competing
style. Long lines remain visible to the separate advisory quality report. Formatting
must not split or restructure a coherent expression merely to satisfy a metric.

## Syntax versus semantic work

Compilation now exposes a cached parse stage. Both checking and formatting reuse
its owned tokens and syntax. Formatting does not require main, valid names/types,
or satisfied ownership/effect rules; this allows formatting code while it is being
written. Invalid syntax still rejects formatting, rather than guessing a repair.
A formatted file can still fail semantic checking for its original reason.

For valid syntax, emitting each original token spelling in order and retaining each
comment's token gap preserves the parser's input meaning. Token-level round-trip
tests verify this invariant separately from checking and execution. New syntax or
comment forms must extend the formatter and its fixture coverage.

## Acceptance evidence

`src/formatter_test.zig` covers exact output with inline/standalone/trailing comments,
CRLF normalization, unchanged token tags and spelling, comment order, idempotence,
arrays/type arguments/operators, empty/comment-only inputs, syntax-only formatting,
syntax failures, execution of a formatted program, and every allocation failure
through parsing/formatting/round trips. Allocating-writer failures are consistently
reported as OutOfMemory, with request and output storage released.

Actual CLI tests verify stdout/check behavior, unchanged-file check success,
formatting differences, duplicate/wrong-command options, and syntax diagnostics.
All 30 semantically valid language CLI fixtures are formatted, checked again, and
verified idempotent, covering aggregates/domains/variants/tables, results, borrowing,
owned buffers, effects/capabilities, resource array/slice I/O, and source pool graphs.

[The project-verification driver](verification-driver.md) is now implemented. Formatter checks can participate
in that driver without becoming source type-validity rules or runtime coverage.
