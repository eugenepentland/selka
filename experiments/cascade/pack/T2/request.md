# T2 — inches as a fourth dimension unit

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
../bin/mylang test tests/parser_test.my     # one file
../bin/mylang run main.my -- <file.sexp> --render
```

Work only inside this directory.

## The change

Dimension literals today accept two suffixes, `mm` and `mil`, both normalised to
millimetres at parse time (`10mil` is 0.254). Vendor parts also give dimensions
in inches, and the reader must accept `in` as a third suffix:

```text
10in    2.5in    0.5in    0.25in    -2in
```

1. `in` immediately after a number, with nothing that can continue an atom
   behind it, is a dimension suffix. The literal lexes as a dimension unit
   (`tk.Kind.unit_val`), exactly as `10mm` and `10mil` do.
2. The parsed value is normalised to millimetres: 1 inch is exactly 25.4 mm, so
   `10in` is the measure 254.0 and `2.5in` is 63.5. The sign is part of the
   number, so `-2in` is -50.8.
3. Rendering is the same as for the existing units: a measure prints its
   normalised millimetre value followed by `mm`, so `10in` renders as `254.0mm`
   and `(size 0.5in 0.25in)` renders as `(size 12.7mm 6.35mm)`.
4. The suffix only counts when it ends the number token: `input`, `int`, `in`,
   `10index` and `10in1` are still atoms and keep their text.
5. `mm` and `mil` keep their current behaviour in every respect.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today). The port's own guest tests must still pass.

## How this is checked

Hidden guest tests and golden renderings that are not in this directory exercise
the public names above and the rules stated here: the parsed millimetre value for
each of the forms listed, the rendering of a form containing inch dimensions, the
unchanged mm/mil behaviour, and the look-alikes that must stay atoms.
