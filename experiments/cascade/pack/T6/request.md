# T6 — a KiCad dialect with no `;` comments

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

The reader serves two file formats that differ in exactly one lexical rule. The
Netlisp `.sexp` files use `;` for line comments. KiCad's s-expressions have no
comment syntax at all, so in a KiCad file a `;` is an ordinary atom byte and a
line such as `(a ; )` is a *complete* form whose second child is the atom `;`.

Make the dialect selectable per call, and make the difference a named value
rather than a second reader:

```mylang
# sexpr/tokenizer.my
public enum Dialect:
    standard,
    kicad

public def tokenize_dialect(src: bytes, dialect: Dialect) -> Result[list[Token], LexError]

# sexpr/parser.my
public def parse_dialect(src: bytes, dialect: tk.Dialect) -> Result[list[ast.Node], ParseError]
```

1. `standard` is today's behaviour, byte for byte. The existing `tokenize` and
   `parse` entry points keep their signatures and mean the standard dialect;
   `parse_with_depth_cap` also stays as it is today.
2. `kicad` does not skip `;` comments. A `;` is an atom byte: it can start an
   atom (`;b` is the atom `;b`) and it can continue one (`a;b` is the atom `a;b`).
3. Strings are unaffected in both dialects: `(a "x;y" b)` has three children in
   either one.
4. Both dialects must be usable in the same program, at the same time, without
   one call's choice leaking into another's.

The port's own guest tests must still pass.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today). `tokenize` and `parse` keep their current meaning and signatures.

## How this is checked

Hidden guest tests that are not in this directory exercise the public names above
and the rules stated here: the standard dialect still dropping `;` comments, the
KiCad dialect reading a semicolon as an atom in child and continuation position,
the same source parsed both ways in one program, semicolons inside strings, and
the token stream `tokenize_dialect` returns.
