# Syntax for compiler-shaped code: an audit (2026-10-30)

Status: proposals for the user's decision (§5). Nothing here is implemented. Written against main d7f6edc7f.

## 1. What was measured

The corpus is the compiler-shaped Selka code that exists: 71 hand-written files, 8,762 code lines.
- **The new lexer:** `selfhost/frontend/`.
- **The older Selka compiler components:** `selfhost/components/`.
- **Two parsers:** the markdown parser and the kicad-convert s-expression converter in `selka-projects`.
- **The parsers in the standard library:** `json.my`, `csv.my` and `http.my`.
- **A tool:** `tools/selka/shadow_summary.my`.

Generated tables and tests are excluded. The 10,322-line parser pilot of 11 October (older syntax) was read separately.

Counts are regex- and indentation-based. Every claim about what the compiler accepts comes from running main's `mylang check`
on a small probe. The probes, their outputs and the counting scripts are archived in
`~/ai/canopy/mylang-evidence-archive/docs/audits/compiler-shaped-syntax-audit-2026-10-30/`.

Settled decisions are respected and not reargued (`docs/design/surface-simplification-2026-10-13.md`):
- no methods on user types, no lambdas or closures, no tuples, no comprehensions;
- no conditional expressions, no value-producing `match`, no `in` on lists;
- `mut` at the call site, `own` on every move.

§4 says where each decision costs compiler-shaped code the most.

## 2. A third of the cost is features that exist and go unused

Literal `match` arms landed on 21 October, after most of this code was written, and `try` on an Option is not
documented. Six features would remove a large share of the verbosity today and appear almost nowhere:

| Feature (works today) | Uses | Sites it fits |
| --- | ---: | --- |
| `c in b"+-/%"`: a byte in a set of bytes | 0 | 88 `c == 43 or c == 45 or ...` chains |
| `try` on an Option inside a `-> T?` function | 0 | 14 guard-and-bail sites, every nested Option match |
| `type K = token_kinds.Kind`, then `K.colon` | 0 | 231 qualified variant names (the lexer shrinks 6.6%) |
| Pattern shorthand `case text(value)` | 0 of 245 arms | 132 `value=value` bindings |
| Chained comparison `48 <= b <= 57` | 21 | 30 `b >= 48 and b <= 57` range tests |
| Literal `match` (`case 61:`) | 2 matches | 27 `if x == A ... elif x == B` chains |

**Now** (`kicad-convert/footprint.my:260`, 18 lines):

```mylang
func read_spot(v: ast.Node[]) -> Spot?:
    match q.as_number(v[1]):
        case Some(x):
            match q.as_number(v[2]):
                case Some(y):
                    if len(v) < 4:
                        return Spot(x=x, y=y, rotation=0.0, turned=False)
                    match q.as_number(v[3]):
                        case Some(rotation):
                            return Spot(x=x, y=y, rotation=rotation, turned=True)
                        case None:
                            return None
                case None:
                    return None
        case None:
            return None
```

**With what exists** (checked on main):

```mylang
func read_spot(v: ast.Node[]) -> Spot?:
    const x = try q.as_number(v[1])
    const y = try q.as_number(v[2])
    if len(v) < 4:
        return Spot(x=x, y=y, rotation=0.0, turned=False)
    const rotation = try q.as_number(v[3])
    return Spot(x=x, y=y, rotation=rotation, turned=True)
```

**Proposal A (no new syntax).** Document each form in the guide where a reader looks for it:
- `try` on Options in `docs/results-and-options.md`;
- byte sets and chained comparisons in `docs/bytes.md`;
- type aliases for enums in the enum section.

Then add a lint with a `mylang fix` rewrite for each mechanical case:
- an or-chain of byte equalities becomes `in b"..."`;
- a `>= and <=` pair on one value becomes a chained comparison;
- an equality if-chain on one scalar becomes a literal `match`;
- `field=field` in a pattern becomes the shorthand;
- an Option match whose `None` arm only returns `None`, in a `-> T?` function, becomes `try`.

## 3. Proposed additions, ranked by what they remove

### P1. Character codes as constants: `ord("=")` folds in `const` and `case`

One line in four of the new lexer compares a byte with a bare number: 389 lines, 640 literals, and 0 named byte
constants. A reader has to know that 61 is `=`.

**Now** (`selfhost/frontend/lexer.my:56`):

```mylang
func pair_kind(ch: int, next: int) -> token_kinds.Kind:
    if next == 61:
        match ch:
            case 43:
                return token_kinds.Kind.plus_equal
            case 45:
                return token_kinds.Kind.minus_equal
```

`ord("=")` already folds inside expressions, but the constant evaluator refuses it (`E_CONSTANT_EXPRESSION`) and a
case arm refuses it (`E_SYNTAX`).

**Proposed:**

```mylang
const EQUALS: int = ord("=")

func pair_kind(ch: int, next: int) -> K:
    if next == EQUALS:
        match ch:
            case ord("+"):
                return K.plus_equal
            case ord("-"):
                return K.minus_equal
```

There is no new syntax. The constant and case evaluators accept `ord` of a one-byte literal (and `b"="[0]`). A `char` type
or a `'='` byte literal is not proposed: `'...'` is already a string, and `str` is bytes by decision.

### P2. Bind-or-else: `const x = f() else ...:` for exits that are not propagation

Option and Result unwrapping is the largest cause of rightward drift:
- 87 of 188 `match` statements (46%) unwrap an Option or Result;
- in 81 of them the other arm only exits;
- in 24 of those the rest of the function moves into the `Ok` arm.

`try` covers the exits that propagate the same failure. It does not cover an exit that does something else: printing a
diagnostic and returning an exit status, `continue`, or returning a different value.

**Now** (`kicad-convert/main.my:79`):

```mylang
    match read_source(fs, path):
        case Err(message):
            return read_failed(fs, path, message, err)
        case Ok(source):
            if too_long(source, MAX_INPUT_BYTES, path, err):
                return 1
            match parser.parse(source):
                case Ok(nodes):
                    write(out, printer.print_nodes(nodes))
                    write(out, "\n")
                    return 0
                case Err(failure):
                    ...
```

**Proposed:**

```mylang
    const source = read_source(fs, path) else Err(message):
        return read_failed(fs, path, message, err)
    if too_long(source, MAX_INPUT_BYTES, path, err):
        return 1
    const nodes = parser.parse(source) else Err(failure):
        const where = parser.position(source, failure.offset)
        print(err, f"{path}:{where.line}:{where.col}: error: {parser.message(failure.kind)}")
        return 1
    write(out, printer.print_nodes(nodes))
    write(out, "\n")
    return 0
```

**Rules:**
- **A statement, not an expression:** `const NAME = EXPR else PATTERN:` followed by a block. `EXPR` is an Option or a
  Result.
- **What binds:** the success payload binds to `NAME`. The failing case's pattern (`Err(e)`, `Err(_)`, or `None`, which
  may be written as `else:`) binds in the block.
- **The block must leave:** `return`, `fail`, `break` or `continue`, checked like a missing return.
- **Settled decisions hold:** it is control flow at statement level, the same position as `if`, so "no control flow
  inside expressions" holds. Ownership is `match`'s: `NAME` owns the payload as a match binding would.

### P3. Variant alternatives and a rest marker in patterns

Two gaps add up:
- 63 arms repeat another arm's body in the same match, because `case a | b:` is refused for enum variants (it works for
  literals).
- 98 `field=_` placeholders exist because a pattern must name every field; 61 arms ignore the whole payload.

**Now** (`markdown/render/html.my:238`, `markdown/leaf/start.my:169`):

```mylang
        match node:
            case text(value=value):
                render.escape.append_escaped(mut out, value)
            case code(value=value):
                render.escape.append_escaped(mut out, value)

        case fenced_code(fence_char=_, fence_length=_, fence_indent=_, info=_):
```

**Proposed:**

```mylang
        match node:
            case text(value) | code(value):
                render.escape.append_escaped(mut out, value)

        case fenced_code(..):
```

**Rules:**
- **Alternatives:** each alternative of a `|` binds the same names with the same types, or no names.
- **The rest marker:** `(..)` ignores every remaining field. Naming every field stays the default, so a reader still sees
  which fields an arm uses.
- **Exhaustiveness:** checking is unchanged.

### P4. A variant test: `node is text`, `kind is ident | integer`, and `if node is list(items):`

Two kinds of small function exist only to test a variant:
- 80 of 653 functions are a single `match`, and 49 of those are one-variant predicates or projections;
- 44 more matches have one real arm and a trivial `case _`.

**Now** (`markdown/inline/tree.my:57`, `kicad-convert/footprint.my:161`, `lexer.my:264`):

```mylang
func is_text(node: ast.Inline) -> bool:
    match node:
        case text(value=_):
            return True
        case _:
            return False

func has_layer(node: ast.Node, layer: bytes) -> bool:
    match node:
        case list(items=items):
            for child in items:
                if names_layer(child, layer):
                    return True
            return False
        case _:
            return False

    return kind == token_kinds.Kind.ident or kind == token_kinds.Kind.integer or kind == token_kinds.Kind.bytes or kind == token_kinds.Kind.format or kind == token_kinds.Kind.rparen or kind == token_kinds.Kind.rbracket or kind == token_kinds.Kind.rbrace or kind == token_kinds.Kind.kw_true or kind == token_kinds.Kind.kw_false or kind == token_kinds.Kind.kw_none
```

**Proposed:**

```mylang
func is_text(node: ast.Inline) -> bool:
    return node is text

func has_layer(node: ast.Node, layer: bytes) -> bool:
    if node is list(items):
        for child in items:
            if names_layer(child, layer):
                return True
    return False

    return kind is ident | integer | bytes | format | rparen | rbracket | rbrace | kw_true | kw_false | kw_none
```

**Rules:**
- **The test:** `EXPR is PATTERN` is a `bool` expression when the pattern binds nothing.
- **The binding form:** a pattern that binds is allowed only as the whole condition of an `if` or `while`. The names are
  read-only and scoped to that body, as in a match arm. So no binding escapes an expression, and the "no value-producing
  match" decision holds.
- **Names:** variant names in the pattern are bare, as in `case`, because the operand's type is known. That removes the
  qualification noise without unqualified names in ordinary expressions.
- **No conflict:** `is None` keeps its meaning (None is the Option pattern).

### P5. A variant's name as text

Three refusals: `str(kind)` is `E_TEXT_CONVERSION`, `int(kind)` is `E_TYPE`, and a table constant keyed by an enum is
`E_CONSTANT_EXPRESSION`.

So:
- `token_kinds.kind_name` is 144 generated two-line arms;
- markdown keeps 8 `K_` integer constants instead of an enum;
- diagnostics spell variant names by hand.

**Proposed:** a builtin `variant_name(value) -> str` that answers the declared case name, for any enum or union. That is
enough for diagnostics and dumps. Enum-keyed table constants are not proposed: they need constant aggregates (FR-219),
a larger change.

### Library, not syntax
- **Builder appends:** make the infallible ones (`byte_builder.append_byte`, `append_spaces`) return `Unit`. That removes
  125 `_ = ...` lines, which exist only because a discarded `bool` must be written out.
- **Scan loops:** `bytes.skip_while(src, at, is_word) -> int` and a bounds-safe `bytes.peek(src, at) -> int`. Four modules
  define their own peek, and 58 of 178 `while` loops only step one counter.
- **A diagnostic fix:** the from-import refusal says `alternative: import the module and declare a record: import dataclasses`.
  That advice is wrong; the right one is `import tk` with `type Kind = tk.Kind`.

## 4. Where the settled decisions cost compiler-shaped code most

No change is proposed in this section; it records the price.
- **No conditional expression:** about 50 sites of `mut x = A` followed by `if c: x = B`.
- **`mut` at call sites:** 1,086 in the corpus, the most frequent token after names. The parser pilot threads its cursor
  as `mut p` through 343 `peek`/`expect`/`accept` calls.
- **No methods:** `full_model.expect(mut p, "lparen")` instead of `p.expect(...)`. Accepted on 13 October for local
  reasoning.
- **Ownership on trees:** the biggest structural cost is not syntax.
  - The lexer keeps tokens as three parallel lists, the markdown parser keeps a flat node pool with an integer kind, and
    one tree record bundles two lists to dodge `E_SINGLE_OWNER_OVERLAP`.
  - The parser pilot hit that error in 18 modules.
- **Field-granular borrows, checked on main d7f6edc7f.** The ledger entries are partly out of date:
  - FR-350 is resolved: `rebuild(mut state.items, state.stack)` is accepted.
  - FR-107 is resolved: `return own s.perm` moves a field out of a record that dies.
  - So the markdown parser's `Work` wrapper is no longer needed for the case it was written for.
- **What is still refused:**
  - **G1:** iterating one field while mutating another. `for root in tree.roots:` with
    `append(mut tree.nodes[root].children, 1)` is refused (R7): the loop borrows the whole record. The index-loop form
    is accepted.
  - **G2:** a `mut` element and a read element of one list at indices the compiler cannot prove distinct,
    `link(mut tree.nodes[p], tree.nodes[c])` (M5). This is a real aliasing question.
  - **G3:** the same at distinct literal indices with one argument read-only, `link(mut tree.nodes[0], tree.nodes[1])`.
    The rule admits literal indices only when both arguments are `mut`.
  - The M5 message says "the fields of one record count as one value" for list elements, which is wrong.
- **What to do with them:** G1 and G3 are sound to accept and look front-end only; the certificate check remains the
  backstop. G2 needs either the refusal or a runtime-checked form.
- **Resolved on 30 October (`experiments/incremental-engine-20261030/G1/DECISIONS.md`):** G1 and G3 are accepted (an
  iteration borrows the field it reads; distinct literal elements are disjoint with one argument read-only, also after
  a field prefix), and the M5 message for list elements says what is true there. G2 stays refused.

## 5. Decisions for the user

| | Proposal | Sites it fits | Estimate |
| --- | --- | ---: | --- |
| A | Document the six unused features, plus lints with `mylang fix` rewrites | about 300 | 4–6 h |
| P1 | `ord("x")` in `const` and `case` | 389 lines | 2–4 h |
| P2 | `const x = f() else ...:` | about 110 | 6–10 h (two steps) |
| P3 | `case a(x) \| b(x):` and `case v(..):` | about 160 arms | 4–6 h |
| P4 | `x is pattern`, and `if x is v(a):` | about 150 | 5–6 h |
| P5 | `variant_name(value)` | generated tables, diagnostics | 2–3 h |
| L | Unit-returning builder appends, `skip_while`/`peek`, the from-import diagnostic | about 190 | 3–5 h |

Every proposal is an addition: no accepted program changes meaning, so none needs a migration. Each lands with:
- `tests/lang` tests;
- a guide section with a runnable example and a `features.json` entry;
- where an old spelling has a mechanical rewrite, a lint whose `mylang fix` applies it.

Recommended order:
1. **A and P1 first:** cheapest, and the lexer is being written now.
2. **Then P3 and P4:** they share the pattern machinery.
3. **Then P2:** the most new surface. Its design is worth a second look before it is built.
