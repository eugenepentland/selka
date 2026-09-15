# T: canonical source formatter

Status: implemented as `fmt`, with `fmt --check` for verification. The formatter
parses syntax and reprints the program under one fixed layout. It does not
type-check, lower, execute, reorder declarations, simplify expressions, or modify
files itself.

```sh
zig build run -- fmt examples/records.my
zig build run -- fmt examples/records.my --check
```

Normal mode writes canonical source to stdout and exits 0. Check mode emits no
source and exits 0 only when the input already is canonical; otherwise it reports
`formatting differs` and exits 1. Syntax errors exit 1 with source diagnostics;
usage and host failures exit 2. The check option is fmt-only and accepted once.
Input files retain their original bytes.

## Format contract

The canonical layout is fixed:

- four spaces per suite level and LF line endings;
- one space around binary and assignment operators;
- one space after commas and annotation colons;
- no padding inside ordinary delimiters;
- no trailing whitespace;
- exactly one final newline for a nonempty program;
- two blank lines between top-level declarations and one blank line after the
  module header directive group.

Blank lines inside a suite are removed; only the top-level separators above are
emitted. Comments and literal bytes are preserved; only whitespace between tokens is
rewritten. Declaration, directive and evaluation order never change. Token
spelling is retained, so an accepted compatibility spelling such as `class` stays
`class` until the source changes. Long lines are not wrapped and there is no
configuration.

## Syntax versus semantic work

Compilation exposes a cached parse stage. Both checking and formatting reuse its
owned tokens and syntax. Formatting does not require main, valid names/types, or
satisfied ownership/effect rules; this allows formatting code while it is being
written. Invalid syntax still rejects formatting, rather than guessing a repair.
A formatted file can still fail semantic checking for its original reason.

`fmt-module` applies the same layout to a module file, parsing the header, imports
and exports without loading the imported modules, so an unresolved draft still
formats.

## Acceptance evidence

`src/formatter_test.zig` covers noncanonical-to-canonical fixtures,
operator/assignment spacing, comment and literal preservation, unary operators,
nested blocks, generics and named constraints, top-level and header spacing,
idempotence, empty/whitespace-only/comment-only inputs, syntax-only formatting,
syntax failures, native execution preservation, module drafts, and every
allocation failure through parsing and formatting. Allocating-writer failures are
consistently reported as OutOfMemory, with request and output storage released.

CLI tests verify stdout and check behavior, canonical check success, nonzero
check on noncanonical input, duplicate and wrong-command options, and syntax
diagnostics.
