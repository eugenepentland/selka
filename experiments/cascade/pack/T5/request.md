# T5 — a byte-range consumer for the form at an offset

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
../bin/mylang test tests                   # the whole guest suite
../bin/mylang test tests/parser_test.my    # one file
../bin/mylang run main.my -- <file.sexp> --render
```

Work only inside this directory.

## The change

A new consumer needs the byte range of the form around an editor cursor: it edits
a design file in place and must not reformat anything outside the form it is
changing. Add the consumer to the parser module:

```mylang
public record FormBounds:
    start: int
    end: int

public def form_bounds(src: bytes, offset: int) -> Option[FormBounds]
```

Semantics:

1. `start` is the byte offset of the `(` that opens the **outermost** form
   containing `offset`; `end` is one past the byte offset of its matching `)`.
   For an offset inside a nested form, the outermost top-level form is returned.
2. `None` when the offset is not inside a completed form: whitespace between
   forms, a top-level atom, a comment, past the end of the source, an
   unterminated form, or a source the reader cannot lex.
3. Parentheses inside quoted strings and inside `;` comments must not affect the
   answer: `(m "a)b" c)` ends after the final `)`, not at the one inside the
   string, and a `)` on a comment line is not a closing parenthesis.
4. The answer must come from the reader's own view of the source — its tokens or
   its spans. Do not add a second raw-byte scanner: the project already has
   exactly one place that knows what a string, an escape and a comment are, and a
   second one is the bug this consumer exists to prevent.

`main.my` and the printer are unaffected; the port's own guest tests must still
pass.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today).

## How this is checked

Hidden guest tests that are not in this directory call `parser.form_bounds`
through its public name and check `start`/`end` for offsets in the first and
second of two top-level forms, offsets in the gaps, offsets inside strings and
comments that contain parentheses, nested forms, top-level atoms, unterminated
sources and past-the-end offsets.
