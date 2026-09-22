# T3 — a measure keeps the spelling it was written with

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
../bin/mylang test tests/printer_test.my    # one file
../bin/mylang run main.my -- <file.sexp> --render
```

Work only inside this directory.

## The change

An SI literal already survives the parse with its source spelling: `100nF` parses
to a decimal that carries `"100nF"` and prints as `100nF` rather than as
`0.0000001`. A dimension literal does not: `10mil` parses to the millimetre value
0.254 and prints as `0.254mm`.

Make a dimension keep the spelling it was written with:

```text
10mil  ->  10mil
2.50mm ->  2.50mm
100mil ->  100mil
```

1. The `measure` case of `ast.Node` gains an optional source spelling. The
   pinned shape is

   ```mylang
   measure(value: float, span: Span, literal: Option[str] = None)
   ```

   because the default keeps the existing direct construction
   `ast.Node.measure(0.7, span)` compiling and printing `0.7mm`.

2. The value stays the normalised millimetre value: `10mil` is still 0.254.
3. `ast.value_text` is the one reader of a literal's spelling, so it must report
   a measure's spelling too (`10mil` for `10mil`).
4. `printer.render` writes the spelling when a measure has one, and the previous
   canonical form (value plus `mm`) when it does not.
5. Everything else about number handling is untouched: `220k`, `100nF`, `3.3V`,
   plain ints and plain floats keep their current rendering.

Note that `Node` is matched exhaustively in several places, so the new field
changes every match arm on the `measure` case, not just the printer's.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today). Two of the port's own tests encode the old convention
(`tests/tokenizer_test.my::test_mm_and_mil` and
`tests/printer_test.my::test_fixture_dimensions_bare_units`); update those two to
the new behaviour. Everything else in the suite must still pass.

## How this is checked

Hidden guest tests and golden renderings that are not in this directory exercise
the public names above and the rules stated here: the unchanged millimetre
values, the reported spelling, the rendering of spelled and spelling-less
measures, and the untouched SI and float behaviour.
