# Canonical module formatting

The existing token-preserving formatter now accepts module headers and qualified
names through a syntax-only module parser:

```sh
zig build run -- fmt-module examples/modules/main.my
zig build run -- fmt-module examples/modules/main.my --check
zig build run -- fmt-project examples/modules/main.my --check
```

`fmt-module` formats exactly the named file to stdout. `--check` compares canonical
bytes and reports a difference without writing. It parses module/import/export
header order and the full body, but does not load imports, match the file path to
its declaration, validate export targets, reject duplicate import aliases, or check
types, ownership, effects, and name resolution. This permits unfinished source to be
formatted. Malformed headers or bodies still reject. Original `fmt` behavior for
single-file programs is unchanged.

`fmt-project --check` loads the entry's reachable import graph, then parses/formats
each module independently. The loader's declaration/path, alias/export duplication,
cycle, and source/graph limits apply because it must identify the graph. Body semantic
checking is not performed. The check requires `--check`: there is no ambiguous
multi-file stdout format or automatic source overwrite. Changed file paths are
reported in dependency-first order after every body has parsed successfully. A
malformed body reports its syntax error instead of a partial formatting-difference
list. Files outside the reachable graph are not checked.

Module headers preserve directive order. Dotted module names and `alias::Type` or
`alias::function` qualifications have canonical tight separators; ordinary type
annotations retain the space after their colon. Line comments remain in the same
token gap even when placed around/between qualifier colons. Existing indentation,
LF newline, comment preservation, and token spelling rules remain. Formatting does
not rename symbols, reorder imports/exports, load dependency policy, or merge code.

The implementation uses the same formatter engine for both grammars. Module parsing
for formatting is separate from the single-file Compilation syntax cache, so a
later single-file check still rejects module headers instead of silently ignoring
imports. Repeated formatting is idempotent.

Exit 0 indicates canonical input or successful stdout formatting; exit 1 indicates
syntax/graph errors or formatting differences; exit 2 indicates usage/host failures.
Project success says nothing about semantic validity. To apply a change, capture
`fmt-module` stdout and replace the intended file explicitly; use project checking
and execution for semantic validation afterward.

Acceptance covers complete token-tag/spelling preservation, per-gap comment identity,
CRLF conversion, qualified arrays/types/calls, header ordering, malformed input,
semantically unresolved drafts, parser-cache isolation, every host allocation failure,
actual CLI stdout/check behavior, and multi-file graph checks. Both existing module
example graphs were formatted, pass the graph check, and still execute to 12 and 46.

[Scalar project native parity](module-native.md) is implemented. Broader
module/candidate corpus and scaling review, generics,
compile-time/schema/incremental work, and wider native operations remain pending.
Future syntax must extend the same formatter and preservation tests when introduced.
