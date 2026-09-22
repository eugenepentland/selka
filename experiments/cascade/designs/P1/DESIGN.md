# Representation redesign — the reader's shared facts

The four modules now agree on three facts by construction. What follows is true
of the code as it stands; each claim was checked against the callers, the 79
guest tests and a before/after differential run.

## Facts that now have one home

**The numeric suffix rule — `sexpr.ast.suffixes()` and
`sexpr.ast.canonical_length()`.** Every spelling that may follow a numeric
prefix, the factor it multiplies by and the way it may combine is one list of
`Suffix(spelling, factor, role)` rows. `role` holds the five combining
behaviours that used to be spread over byte predicates, a precedence ladder and
the parser's multiplier table: a bare scale (`k M G u n p`), a scale that
requires a unit letter (`m`), a unit letter (`V A F H R`), a length (`mm`,
`mil`) and `%`. `canonical_length()` is itself a row of that list, so the `mm`
the lexer matches and the `mm` the printer appends — and the width it measures
— are one datum.

**The decoded number — `sexpr.tokenizer.Token.number`.** The lexer is the only
module that reads the source bytes, so it is the only one that can say where a
numeric prefix ends, which suffix followed it and what that suffix multiplies
by. It resolves the literal there and mints `Number.integer(value)`,
`Number.decimal(value, spelling)` or `Number.measure(value)` beside the
unchanged `text` and `kind`. Suffixed values carry the spelling they were
written with.

**The source position — `sexpr.tokenizer.LexError.col`.** The lexer's
`pos`/`line`/`col` cursor is the only computer of line and column; a rejection
carries the position it already had, and `parser.ParseError` is a
field-for-field copy of it.

## Callers that benefit

| module | lines (code) | what changed |
| --- | --- | --- |
| `sexpr.parser` | 291 (180) → 173 (94) | `si_scale`, `mil_to_mm`, `si_number_end`/`is_si_number_char`, `source_has_mil_suffix`, `span_at` and the four `parse_*` decoders are gone; `Cursor` no longer carries the source; numeric handling is the case mapping `parse_number`/`number_node` |
| `sexpr.tokenizer` | 297 (191) → 361 (219) | three byte-predicate families, `si_suffix_len`'s precedence ladder and the inline `mm`/`mil`/`%` branches are replaced by one table scan (`suffix_at`) plus the decode only the lexer can make; it now publishes what it already knew |
| `sexpr.printer` | 277 (141) → 274 (142) | the `"mm"` literal is gone: the measure suffix and its width come from `ast.canonical_length()` |
| `main.my` | unchanged | reads the same frozen API |

Across the four modules, code lines go 611 → 584; the tokenizer is the one
module that grew, by holding the table scan and the decode that used to be
re-done downstream.

## Now guaranteed rather than checked

- Every `unit_val` the lexer mints is a `length` row of the table, so "was it
  `mm` or `mil`?" is never asked again. `source_has_mil_suffix`'s walk over the
  raw source and `parse_unit`'s two conflicting text conventions are gone.
- The prefix a value is decoded from is exactly the prefix the lexer consumed,
  so the parser cannot disagree with the tokenizer about where a number ends;
  the parser never indexes `src` (`Cursor` holds tokens, pos and cap only).
- A suffixed value's spelling travels with it, so print-back is data, not
  reconstruction.
- Every `LexError` already carries line, column and offset; no caller re-walks
  the source to recover a position.
- `Token.number == None` is the only malformed-number state the parser sees, and
  it reports it (`invalid number literal`) at that token's span. The lexer
  deliberately does not fail on such a token, so a mixed input like
  `(n 99999999999999999999999999 "oops` still reports the later unterminated
  string, exactly as before.

## Deliberately left independent

- **Width versus rendering.** `estimate_width` keeps Zig's `{d}`-based measure
  and its `depth > 3` give-up, while `push_node` writes `printFloat` spellings.
  For a whole float the two differ by two columns; the layout is byte-identical
  to Zig's precisely because they are separate, so they stay separate.
- **`Kind` and `Token.text` versus `number`.** The kind and the spelling
  conventions (`si_val` verbatim with its suffix, `unit_val` before it) keep
  their old meaning for callers that read them; the decoded value is additive.
- **Record growth is additive.** `Token.number: Option[Number] = None` and
  `LexError.col` are new fields; every field the tests and other callers read
  keeps its name and meaning, and no public declaration was removed or renamed.
- **Entry point and tests.** `main.my` and `project/tests` are untouched.

## Evidence

- `bin/mylang test project/tests` → **79 passed, 0 failed**, 6 programs. (In
  this sandbox the toolchain caches must point inside the working copy; see
  `differential/RESULTS.md`.)
- Differential corpus of 52 files (every literal family, suffix-boundary atoms,
  UTF-8 and invalid-UTF-8 input, EOF cases, the 72-column and depth cutoffs, and
  a 473 KB / 3000-form stress file) driven through the frozen API: the token
  stream (kind/text/line/col/offset), lex errors, parse errors with all four
  fields, the AST census including `ast.value_text`, and `render` — **252,864
  output lines byte-identical** before and after.
- `main.my`'s census, `--render` and exit status are byte-identical over the
  same corpus.
