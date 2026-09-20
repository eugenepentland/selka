# sexpr-port — porting `eda/src/sexpr/` to mylang

Goal: a faithful, tested mylang port of the Zig S-expression reader in
`/home/epentland/ai/canopy/eda/src/sexpr/` (`ast.zig`, `tokenizer.zig`,
`parser.zig`), so the two implementations can be compared line-for-line.
Read the Zig source before writing anything; mirror its behaviour and errors.

## Workspace

- Project root: `experiments/sexpr-port/` in this repo (mylang root at `/home/epentland/ai/canopy/mylang`).
- Compiler: `./zig-out/bin/mylang` (already built; do **not** run `zig build`).
- Run one test file: `./zig-out/bin/mylang test experiments/sexpr-port/tests/<name>_test.my`
- Run the whole project: `./zig-out/bin/mylang test experiments/sexpr-port`
- Run the CLI: `./zig-out/bin/mylang run experiments/sexpr-port/main.my -- <file.sexp>`

Module resolution needs the root marker `main.my`; dotted imports resolve from
the project root, e.g. `import sexpr.ast as ast`.

## Frozen interfaces (do not change signatures)

`sexpr/ast.my` (shared; owner: representation workstream):

```mylang
record Span: line: u32, col: u32, offset: u32
union Node: form(items: list[Node], span: Span), atom(text: View, span: Span),
            string(text: View, span: Span), integer(value: int, span: Span),
            decimal(value: float, span: Span, literal: Option[View] = None),
            measure(value: float, span: Span)
def max_source_bytes() -> int
def zero_span() -> Span
def is_form(node: Node, name: str) -> bool
def as_items(node: Node) -> Option[list[Node]]
def as_atom(node: Node) -> Option[View]
def as_string(node: Node) -> Option[View]
def as_text(node: Node) -> Option[View]
def as_number(node: Node) -> Option[float]
def value_text(node: Node) -> Option[View]
def span_of(node: Node) -> Span
def children(node: Node) -> list[Node]
```

Each case carries the span of its first token, so the AST mirrors Zig's
`Node { tag, span, literal }`; `decimal.literal` is `None` for a plain float and
the source spelling (`100nF`, `220k`) for a suffixed one. The three span fields
are `u32` rather than `int`: a span is twelve bytes instead of twenty-four and a
node eight bytes smaller, which the audit's "test narrower source metadata using
existing integer types" asked for. `max_source_bytes()` is the largest document
a span can address, and `parse` rejects a longer one with a located error before
any span exists, so the checked `u32()` conversion is unreachable on valid
input.

Text is a `sexpr.view.View` — a `source`/`start`/`end` range of the document the
node was parsed from — rather than an owned `str`. That is the whole point of the
representation: Zig's `Node` holds `[]const u8` slices of the source, and a
`str` payload widened every consumed spelling to one four-byte scalar per code
point. Building a node now allocates nothing; a consumer that only re-emits text
copies the source range, and one that needs scalars calls `view.text_of`.

```mylang
record View: source: bytes, start: int, end: int
def at(source: bytes, start: int) -> View
def view_len(found: View) -> int
def bytes_of(found: View) -> bytes
def text_of(found: View) -> Result[str, str]
def matches(found: View, spelling: str) -> bool
def equal(first: View, second: View) -> bool
def first_byte(found: View) -> int
def take(found: View, count: int) -> View
def skip(found: View, count: int) -> View
def through(first: View, second: View) -> View
```

`view.text_of` is the only conversion to `str`, and it reports a range that is
not UTF-8 rather than substituting replacements. `view.matches` is how a fixed
word (`+`, `mm`, a form name) is compared without decoding a string.

`sexpr/tokenizer.my` (owner: tokenizer workstream):

```mylang
enum Kind: lparen, rparen, atom, string, int_val, float_val, unit_val, si_val, eof
record Token: kind: Kind, text: str, span: ast.Span
record LexError: message: str, offset: int, line: int
def tokenize(src: bytes) -> Result[list[Token], LexError]
```

`sexpr/parser.my` (owner: parser workstream):

```mylang
record ParseError: message: str, line: int, col: int, offset: int
def parse(src: bytes) -> Result[list[ast.Node], ParseError]
```

`sexpr/printer.my` (owner: printer workstream):

```mylang
def render(nodes: list[ast.Node]) -> str
def render_node(node: ast.Node) -> str
def render_bytes(nodes: list[ast.Node]) -> bytes
def render_node_bytes(node: ast.Node) -> bytes
```

Both entry points run one traversal into a byte builder; the `str` forms decode
that snapshot once instead of joining one decoded string per leaf and then
re-encoding the join.

### Token text convention

`Token.text` (the compatibility `tokenize` API) is still a decoded `str`, but the
streaming `RawToken` a parser actually consumes carries only the source range
`text_start..text_end`. For a `string` token that range is the **raw slice
between the quotes, escapes intact** (neither Zig nor this port unescapes —
`parser.zig` stores the slice as-is). For the numeric kinds (`int_val`,
`float_val`, `unit_val`, `si_val`) it is the **verbatim source spelling including
the suffix** (`"100nF"`, `"1mil"`, `"220k"`), so the parser can apply the scale
by inspecting the tail; `unit_val` is the one exception — its range stops before
the `mm`/`mil` suffix, exactly as in Zig. `si_val` also covers `%`-terminated
literals (`"10%"`).

## Language gotchas (each of these cost a compile in this port already)

- `match` is a **statement**, not an expression. Put it in a helper and `return`
  from each arm; there is no `x = match ...`.
- A payload binding may not shadow any in-scope or top-level name; `case
  Node.items(children):` fails with `E_SHADOWING` because `children` is a
  top-level function. Bind to a fresh name.
- Locals are function-scoped; predeclare a name before a loop that assigns it.
- Records and unions need a type on every field; a union is read only via `match`.
- `bytes` indexing yields an `int` (u8); `src[a:b]` yields `bytes`; `.decode()`
  yields `Result[str, Error]`. `int(text)`/`float(text)` yield `Option[int]`/`Option[float]`.
- Guest tests are `public def test_name() -> bool:` at top level, straight-line.
- Add `#` comments; keep prose comments where the Zig original explains "why".

## Reference Zig source

- `/home/epentland/ai/canopy/eda/src/sexpr/ast.zig`
- `/home/epentland/ai/canopy/eda/src/sexpr/tokenizer.zig` (SI scales, mm/mil, `%`)
- `/home/epentland/ai/canopy/eda/src/sexpr/parser.zig` (depth cap, diagnostics)
- Fixtures to parse: `experiments/schematic/fixtures/{spi,lmx2595rhar,straps-synth-lmx2595}.sexp`
- Existing simpler mylang art (syntax reference, not a target):
  `experiments/readiness-probes-2026-09-18/proj/sexpr/{tokenizer,parser}.my`

## Scope

Port `ast`, `tokenizer`, `parser` and the printer in full, including Zig's
72-column layout engine and the `Node.literal` source-spelling field (carried on
the `decimal` case). The port is byte-identical to the Zig printer on every
golden; note any remaining omission in the module header comment.
