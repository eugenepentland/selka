# Canonical module formatting

The formatter accepts module headers and qualified names through a syntax-only
module parser:

```sh
zig build run -- fmt-module examples/modules/main.selka
zig build run -- fmt-module examples/modules/main.selka --check
zig build run -- fmt-project examples/modules/main.selka --check
```

`fmt-module` formats exactly the named file to stdout. `--check` compares canonical
bytes and reports a difference without writing. It parses module/import header
order, exports anywhere among top-level declarations, and the full body, but does
not load imports, match the file path to its declaration, validate export targets,
reject duplicate import aliases, or check types, ownership, effects and name
resolution. This permits unfinished source to be formatted. Malformed headers or
bodies still reject.

`fmt-project --check` loads the entry's reachable import graph, then parses and
formats each module independently. The loader's declaration/path, alias/export
duplication, cycle and source/graph limits apply because it must identify the
graph. Body semantic checking is not performed. The check requires `--check`:
there is no ambiguous multi-file stdout format or automatic source overwrite.
Changed file paths are reported in dependency-first order after every body has
parsed successfully. A malformed body reports its syntax error instead of a
partial formatting-difference list. Files outside the reachable graph are not
checked.

Module headers and top-level exports preserve directive order and placement.
Dotted module names and qualified `alias.Type` or `alias.function` names have
canonical tight separators; ordinary type annotations retain the space after their
colon. The same fixed rules as single-file formatting apply: four-space suites,
one space around operators, one space after commas and annotation colons, no
padding inside delimiters, no trailing whitespace, one final newline, two blank
lines between top-level declarations, and one blank line after the header
directive group. Blank lines inside a suite are removed. Line comments remain in the same token gap even when placed
around qualified names. Formatting does not rename symbols, reorder
imports/exports, load dependency policy, or merge code.

The implementation uses the same formatter engine for both grammars. Module parsing
for formatting is separate from the single-file Compilation syntax cache, so a
later single-file check still rejects module headers instead of silently ignoring
imports. Repeated formatting is idempotent.

Exit 0 indicates canonical input or successful stdout formatting; exit 1 indicates
syntax/graph errors or formatting differences; exit 2 indicates usage/host failures.
Project success says nothing about semantic validity. To apply a change, capture
`fmt-module` stdout and replace the intended file explicitly; use project checking
and execution for semantic validation afterward.

Acceptance covers canonical bytes, per-gap comment identity, CRLF conversion,
qualified arrays/types/calls, header ordering, malformed input, semantically
unresolved drafts, parser-cache isolation, every host allocation failure, actual
CLI stdout/check behavior, multi-file graph checks, and native execution
preservation. The committed module examples still execute after a formatting pass;
the repository corpus is reformatted only in the dedicated integration commit.
