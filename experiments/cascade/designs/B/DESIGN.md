# Design B — the port as it stands (baseline arm)

Status: frozen design, 19 September 2026. This arm is the current
`experiments/sexpr-port/` reader, unmodified apart from being copied here with
its own tests. It is the baseline the two redesigns are compared against; the
only designer cost it carries is zero, and its `evidence/` directory holds the
gate run rather than a designer session.

## What this design is

A four-module reader plus a CLI:

| file | holds |
| --- | --- |
| `sexpr/ast.my` | `Span`, the `Node` union, the accessors that read a node without matching it |
| `sexpr/tokenizer.my` | bytes to tokens: parens, strings, comments, atoms, ints, floats, `mm`/`mil`, SI-suffixed literals, `%`, `LexError` |
| `sexpr/parser.my` | tokens to AST: the nesting cap, `unit_val` normalisation, SI scaling, `ParseError` |
| `sexpr/printer.my` | AST to canonical text: the short-list width test, the multi-line layout, number rendering |
| `main.my` | the CLI: a census line for the differential checker, or `--render` |

## Facts this design gives a single home

- **Where a token starts.** Every token carries a `Span` minted by the lexer, and
  every node carries the span of its first token, so no consumer re-derives a
  position from raw bytes — except in the parser's error path (below).
- **What a token is.** Kind classification happens once, in the lexer; the parser
  never rescans a token's spelling to decide what it is.
- **The canonical text of a node.** Only `printer.push_node` decides how a value
  is written; `main.my` prints what it returns.
- **The source spelling of a suffixed literal.** It rides on
  `Node.decimal`'s `literal` field, and `ast.value_text` is the one reader of that
  field, so the printer cannot apply a different precedence from a test helper.

## Facts this design states more than once

These are the seams the redesign arms were pointed at; they are recorded here
before any run so that a later comparison cannot invent them.

- **The unit/scale policy is split three ways.** The lexer decides which letters
  are scale letters, unit letters and dimension suffixes with byte predicates
  (`is_scale_letter`, `is_unit_letter`, the inline `m`/`mm`/`mil` peeks); the
  parser owns the multipliers (`si_scale`, `mil_to_mm`); the printer restates the
  millimetre unit as a literal `"mm"` suffix. Adding a unit or a scale means
  finding all three.
- **Line/column bookkeeping exists twice.** `tokenizer.advance` maintains the
  cursor, and `parser.span_at` walks the same bytes again to recover a column for
  a `LexError`, because `LexError` carries no column.
- **The unit-token convention is stated twice and disagrees.** `CONTRACT.md` says
  a `unit_val` token keeps its `mm`/`mil` suffix; the landed tokenizer strips it.
  `parser.parse_unit` accepts both readings and consults the raw source bytes
  (`source_has_mil_suffix`) to decide.
- **Normalisation is not represented.** `10mil` becomes `0.254` at parse time and
  the fact that it was written in mils is gone, so the printer cannot reproduce
  the source and `Node.measure` has no `literal` to read.
- **The comment rule is implicit in the lexer's skip loop.** There is no name for
  the dialect, so a second comment convention would be a second branch rather
  than a second value.

## Gate

`evidence/gate.json` is `arm_gate.py`'s report for this arm: the 79-test guest
suite, the 17 byte-identical Zig goldens and the differential census against
`reference_parse.py` over the four in-repo fixtures and the two ~185 kB EDA
boards, all from the repository root's installed compiler.

## Designer cost

None. B is the baseline: no session produced it, so its upfront term is zero and
its `R` is the pack total it earns.
