# T1 — scientific-notation literals on a dotted mantissa

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

The reader must accept the engineering notation that design files and part
datasheets use for values, and it must print those literals back exactly as they
were written.

These literals must read as **numbers**, not atoms:

```text
1.5e3     2.2E3     1.5e-3     -2.5e+2     4.7e+2
```

Rules, all of which are exercised:

1. An exponent is `e` or `E`, then an optional `+` or `-`, then at least one
   digit. It is part of the number only when it ends the token, so `1.5e3k` and
   `1.5e` stay atoms.
2. Only a mantissa that already contains a decimal point may take an exponent.
   `1e3` and `913e4971` therefore stay atoms with their source text: the design
   corpus is full of digit-leading hex identifiers (`913e4971`) and the Zig
   reader this port mirrors reads them as atoms.
3. An exponent literal lexes as a float token (`tk.Kind.float_val`), and its
   token text is the verbatim source spelling including the exponent.
4. It parses to an `ast.Node.decimal` whose `literal` field carries that same
   source spelling, so `printer.render` writes `1.5e3` back unchanged and
   parse -> print -> parse is a fixed point.
5. Plain floats keep the port's canonical rendering. Do **not** start keeping the
   spelling of every float: `0.020` must still print as `0.02`.

The negative SI literals that already share this number path — `-4.7k`,
`-100nF`, `-3.3V` — must keep parsing, scaling and printing as they do today.

## What must not change

The public module layout and names (`sexpr.ast`, `sexpr.tokenizer`,
`sexpr.parser`, `sexpr.printer`, `main.my`, and the names each of them exports
today). The port's own guest tests must still pass; update one only if this
change legitimately invalidates it.

## How this is checked

Hidden guest tests and golden renderings that are not in this directory exercise
the public names above and the rules stated here. They include, among others, the
token kind and text of each exponent form, the parsed value, the round trip
through `printer.render`, and the look-alikes that must stay atoms.
