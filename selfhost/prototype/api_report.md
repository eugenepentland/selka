# Prototype API report

This report records the public surface actually required by `lexer.my`,
`parser.my`, and `bench.my` at commit `8420528`.  The programs use no FFI, host
binding, fixed-array intrinsic, or private compiler operation.

## Operations used

| Area | Operation needed | Spelling used | Exists today |
| --- | --- | --- | --- |
| list | Empty and populated construction | `items: list[T] = []`, `[0]` | yes |
| list | Append one value | `items.append(value)` | yes |
| list | Discard all retained pieces | `pieces.clear()` | yes |
| list | Length | `len(items)` | yes |
| list | Indexed read | `items[index]` | yes |
| list | Indexed write | `cursor[0] += 1` | yes |
| list | Sequential iteration | `for item in items` | yes |
| dictionary | Literal construction | `keywords: dict[str, bool] = {...}` | yes |
| dictionary | Membership | `word in keywords` | yes |
| string | Length | `len(source)` | yes |
| string | Unicode-scalar indexed read | `source[index]` | yes |
| string | Slice | `source[start:end]` | yes |
| string | Classification | `char.isalpha()`, `char.isdigit()` | yes |
| string | One-pass assembly | `"".join(pieces)` | yes |
| string | Comparison | `char == "\n"` | yes |
| string | Scalar interpolation | `f"...{value}..."` | yes |
| conversion | Decimal integer parsing | `int(text)` and `match Some/None` | yes |
| records | Construct/read record values | `Token(...)`, `token.start` | yes |
| variants | Token and AST discriminants | `enum TokenKind`, `enum NodeKind` | yes |
| control | Counted iteration | `for index in range(count)` | yes |
| output | Diagnostics and checksums | `print(text)` | yes |
| modules/time | Import the standard clock module | `import time` | yes in `mylang run` |
| modules/time | Wall-clock sample | `time.now(clock)` | yes |
| modules/time | Duration and integer milliseconds | `time.elapsed`, `time.to_milliseconds` | yes |

The list operations `pop`, `extend`, `insert`, `remove`, `reverse`, `sort`,
`copy`, and `index` exist at this revision, but this workload did not need them,
so they are not part of its measured minimum.  Likewise, the workload needed
dictionary membership but not `get`, removal, keys, values, items, or iteration.
Those operations should not be justified by this evidence alone.

## Missing operations and workarounds

| Missing operation encountered | Source workaround | Cost |
| --- | --- | --- |
| Dedicated text builder or string reserve API | Accumulate one independently allocated line per iteration in `list[str]`, then call `"".join(pieces)` once | O(piece count) appends plus one O(total characters) final copy. There is no per-iteration copy of the already-built prefix. The list temporarily retains all pieces as well as the final source. |
| Monotonic clock | Use documented `time.now(clock)` around lexing | Suitable for indicative evidence, but the wall clock can move backward. `elapsed_milliseconds` reports `-1` if that occurs or the span cannot be represented. |
| Mutable parser object/reference parameter | Put the cursor in a one-element `list[int]` shared through the parser record | One managed allocation and an indexed read/write for each cursor access. Record scalar fields otherwise have value semantics across top-level function calls. |
| Non-allocating token text view | Store source offsets in every token; slice only for identifiers that need keyword classification and literals that need conversion | Four integers per token avoid an allocated substring for punctuation and most identifiers. Each classified identifier still allocates one slice under the documented immutable-string API. |

A stderr-writing prelude operation was tempting for diagnostics, but the simple
public entry surface used here only needed `print`; the prototype therefore
prints located errors to stdout.  A full compiler CLI will need a documented
stderr/diagnostic channel at its program boundary.

## Minimum prelude set actually used

The exact bare-name prelude used by these programs is:

- `len`
- `int`
- `print`
- `range`

`Some` and `None` are also used to match the `Option[int]` returned by `int`.
No other proposed W4 builtin (`sum`, `min`, `max`, `sorted`, `abs`, `round`,
`any`, `all`, `zip`, or `reversed`) was needed by this lexer/parser workload.

## Builder and complexity evidence

`bench.my` creates 4,000 line pieces and performs exactly one join.  Its current
output reports 229,780 source characters and 36,001 tokens.  Each loop iteration
formats only its own bounded-size line; it never evaluates `source = source +
piece`.  Consequently input construction is linear in the total bytes of the
pieces, subject to the ordinary amortized-growth contract of `list.append`.

The lexer advances one source index monotonically and emits each token once.
Comments, identifiers, integers, and strings are consumed by inner loops that
advance the same index rather than rescanning their prefix.  Located-error
column discovery rescans only the prefix of an erroneous source and is outside
the successful benchmark path.  The parser cursor also advances monotonically;
precedence is expressed as recursive-descent levels, not repeated token-list
slicing.

An early 8,000-line probe exhausted the default instruction budget.  The checked
workload therefore uses 4,000 lines, remains above 200,000 characters, and runs
without a budget override.  On the evidence machine it measured 102 ms of guest
lexing and 0.62 s for the warm host command (including compilation/cache work).

## Temptations deliberately avoided

- Repeated `source = source + piece` construction, which would copy the growing
  prefix on every iteration and be quadratic.
- Building the keyword dictionary inside `is_keyword`; it is built once per lex.
- Materializing every token's lexeme. Tokens retain start/end offsets instead.
- Calling C, Python, an embedding host function, or a private runtime intrinsic.
- Raising `--max-steps` to make an oversized default workload appear healthy.

## Before this becomes self-host compiler code

A production lexer needs decoded string values, Unicode identifier policy,
indent/dedent tokens, richer numeric literals, recovery after malformed escapes,
and a non-allocating source-span/view API.  A production parser needs complete
statement and declaration grammars, explicit AST child ranges rather than the
prototype's linked argument nodes, synchronization after errors, and a durable
diagnostic sink.  For benchmarking, a monotonic clock and repeatable warm-run
harness are needed.  A dedicated builder would reduce retained-piece overhead,
but the existing list-plus-one-join path is already linear and is sufficient for
this Wave 1 workload.
