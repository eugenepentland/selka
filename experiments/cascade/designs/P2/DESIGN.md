# DESIGN — the generalised sexpr reader

`project/sexpr/` is the ported EDA S-expression reader with every assumption it
used to compile in turned into a value or a callback the caller supplies. The
defaults reproduce the port exactly: the 79 pre-existing tests pass unchanged,
and a byte-for-byte differential run against the pre-generalisation copy (28
corpus files, census and `--render`, stdout + stderr + exit status) reports 0
differences. 48 new tests cover the extension points.

## Configuration types and their entry points

| module | configuration | new entry points | default path |
| --- | --- | --- | --- |
| `sexpr.tokenizer` | `Dialect` = `Syntax` + `CharClasses` + `NumberPolicy` | `tokenize_with(src, dialect)` | `tokenize(src)`, `default_dialect()` |
| `sexpr.parser` | `ParseOptions(dialect, max_depth)` | `parse_with(src, options)` | `parse(src)`, `default_parse_options()`, `parse_with_depth_cap(src, cap)` |
| `sexpr.printer` | `Style(layout + five callbacks)`, `Layout` | `render_with(nodes, style)`, `render_node_with(node, style)` | `render(nodes)`, `render_node(node)`, `default_style()` |

Every configuration record is built from its defaults with `replace`, for
example `replace(default_dialect(), syntax=replace(Syntax(), line_comment="//"))`.
`sexpr.ast` is unchanged; the token kinds, `Token` and `LexError` are unchanged.

## What a caller can now vary

**Dialect (`Syntax`, all `str`, with `""` switching a convention off).** The
line-comment introducer (`;`) and block-comment delimiters (empty, off); the
bracket characters `(` and `)` (so the token set can be `[a b]`, `{a b}`, …);
the string quote `"`, the escape character `\`, the sign `-`, the decimal point
`.`, the percent sign `%` and the newline byte `\n` used for line/column
counting.

**Character classes (`CharClasses`, six callbacks `def(int) -> bool`).**
`is_space`, `is_digit`, `is_atom_start`, `is_atom_continue`, `is_operator` and
`is_operator_tail`; the port's predicates are exported as `byte_is_*` so a
dialect can wrap them (`def starts_at(b: int) -> bool effects(): return
byte_is_atom_start(b) or b == 63`).

**Number policy (`NumberPolicy`).** `scales: list[ScaleRule(letter, factor,
requires_unit)]` (default k/M/G/u/n/p bare, `m` unit-gated), `unit_letters`
(default `V A F H R`) and `dimensions: list[DimensionRule(suffix, to_mm)]`
(default `mm`=1.0, `mil`=0.0254). The tokenizer classifies with these tables and
the parser scales and normalises with the same ones.

**Parser.** The whole dialect, so classification, scaling and the diagnostics
that name a bracket all follow it (`[a b` reports `a '[' was never closed`), and
`max_depth` (default 10000).

**Printer.** The layout policy `fits_inline(entries, layout)`; the indentation
rule `indent_text(columns)`; number spelling `number_text(value)`; output string
rule `string_text(content)`; output atom rule `atom_text(text)`. Plus `Layout`
data: `max_width` (72), `depth_cutoff` (3), `indent_step` (2),
`inline_separator` (" "), `measure_suffix` ("mm"), `string_quote` ("\""),
`line_ending` ("\n"), `top_level_gap` (""), `trailing_newline` (False),
`first_on_open` (True), `empty_form` ("()").

## What stays fixed, and the sharp edges

- The token **kinds** and the AST are fixed. A dialect chooses which characters
  produce the existing kinds; it cannot add a kind, and the reader has one
  bracket pair per dialect, not a set of pairs.
- Conventions are single characters (the comment introducers may be longer) and
  the number tables are matched byte by byte, so keep scale letters, unit
  letters and unit suffixes ASCII.
- Hooks are non-capturing top-level functions: a policy that needs state takes
  it as a parameter. Callback types declare `effects(managed_allocation)`, so a
  pure implementation fits and an allocating one is allowed.
- The default `fits_inline` measures with the port's rules (Zig's `{d}` width
  for a literal-less float, the source spelling when the node carries one),
  independently of `number_text`; a caller that reformats numbers and wants
  exact widths also supplies `fits_inline`.
- Diagnostics other than the bracket spelling are fixed text, and
  `parse_with_depth_cap(src, cap)` remains as the reduced-cap seam the tests use.

## Verification

```sh
cd project
../bin/mylang test tests                          # 127 passed, 0 failed (79 pre-existing)
../bin/mylang run main.my -- <file.sexp> --render
```

(The same from the working-copy root is `./bin/mylang test project/tests` and
`./bin/mylang run project/main.my -- <file.sexp> --render`.) The default path
was additionally diffed against the pre-generalisation tree: 28 generated corpus
files (numeric, string, comment, layout, malformed and pseudo-random) in both
CLI modes, plus a token dump of each — stdout, stderr and exit status, 0
differences.
