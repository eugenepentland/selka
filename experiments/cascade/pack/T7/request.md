# T7 — lexical errors carry their column

## Where you are

This directory is a frozen copy of the EDA S-expression reader, ported from Zig to
mylang. It is a self-contained project:

```text
main.my              CLI: census or canonical rendering of a .sexp file
sexpr/ast.my         Span, the Node union and its accessors
sexpr/tokenizer.my   bytes -> tokens (ints, floats, SI literals, mm/mil, %, strings, comments)
sexpr/parser.my      tokens -> AST (depth cap, located diagnostics)
sexpr/printer.my     AST -> canonical text (single-line short lists, indented otherwise)
tests/               the port's own guest tests
CONTRACT.md          the interface the port was written against
```

The compiler is `../bin/mylang`; it is already built and must not be rebuilt.

```sh
../bin/mylang test tests                    # the whole guest suite
../bin/mylang test tests/tokenizer_test.my  # one file
../bin/mylang run main.my -- <file.sexp> --render
```

Work only inside this directory.

## The change

A `ParseError` carries `message`, `line`, `col` and `offset`. A `LexError`
carries only `message`, `offset` and `line`, so the parser re-derives the column
by walking the source up to the reported offset. That is a second implementation
of the same bookkeeping, and it can disagree with the cursor that actually found
the byte.

Give the lexical error its column:

1. `sexpr/tokenizer.my`:

   ```mylang
   public record LexError:
       message: str
       offset: int
       line: int
       col: int
   ```

   Every lexical error must fill it in with the column the cursor was on:
   an unexpected character reports the column of the offending byte, and an
   unterminated string reports the column of its opening quote (the same byte
   its `offset` already points at).

2. `sexpr/parser.my` reports the tokenizer's `line` and `col` in its
   `ParseError` unchanged. The offset-to-line/column derivation that duplicates
   the tokenizer's cursor must not survive as the source of truth; there should
   be exactly one place that knows how a newline resets a column.

3. Existing behaviour is otherwise unchanged: the messages, the offsets, the
   lines and the exit status of the CLI all stay as they are, and the port's own
   guest tests must still pass.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today).

## How this is checked

Hidden guest tests that are not in this directory exercise the public names above
and the rules stated here: the column of an unexpected character at the start of
a line and after a newline, the column of an unterminated string's opening quote,
and the parser reporting the same `line` and `col` as the tokenizer for those
same sources.
