# T: canonical source formatter

Status: implemented as `fmt`, with `fmt --check` for verification. The formatter
parses syntax and returns the accepted program unchanged. It does not type-check,
lower, execute, reorder declarations, simplify expressions, or modify files itself.

```sh
zig build run -- fmt examples/records.my
zig build run -- fmt examples/records.my --check
```

Normal mode writes the source to stdout and exits 0. Check mode emits no source,
exits 0 for canonical input, and exits 1 with `formatting differs` otherwise.
Syntax errors exit 1 with source diagnostics; usage and host failures exit 2. The
check option is fmt-only and accepted once. Input files retain their original bytes.

## Format contract

Indentation is syntax on this surface. A suite opens at the `:` that ends its line
and closes at the dedent that leaves it, so the layout of a program the parser
accepts already is that program's canonical form: four spaces per level, LF line
endings, comments in their own gaps, blank lines where the author put them.
Reprinting from tokens could only move bytes that carry meaning, so `fmt` returns
what it read and `fmt --check` succeeds on everything that parses.

This is a narrower contract than a brace language's formatter, and deliberately so.
There is no competing style to settle, no width-based reflow, and no configuration.
Long lines remain visible to the separate advisory quality report.

## Syntax versus semantic work

Compilation exposes a cached parse stage. Both checking and formatting reuse its
owned tokens and syntax. Formatting does not require main, valid names/types, or
satisfied ownership/effect rules; this allows formatting code while it is being
written. Invalid syntax still rejects formatting, rather than guessing a repair.
A formatted file can still fail semantic checking for its original reason.

`fmt-module` applies the same rule to a module file, parsing the header, imports
and exports without loading the imported modules, so an unresolved draft still
formats.

## Acceptance evidence

`src/formatter_test.zig` covers the byte-for-byte round trip with inline,
standalone and trailing comments, idempotence, empty and comment-only inputs,
syntax-only formatting, syntax failures, execution of a formatted program, module
headers with unresolved drafts, and every allocation failure through parsing and
formatting. Allocating-writer failures are consistently reported as OutOfMemory,
with request and output storage released.

CLI tests verify stdout and check behavior, unchanged-file check success,
duplicate and wrong-command options, and syntax diagnostics. Every semantically
valid language CLI fixture is formatted, checked again, and verified idempotent.

[The project-verification driver](verification-driver.md) is implemented. Formatter
checks can participate in that driver without becoming source type-validity rules
or runtime coverage.
