# Typed holes

A typed hole is a place where an implementation is missing and the author has
said so in the source. Everything around it is checked normally, so the rest of a
half-written module still reports its real errors, and the hole itself is a
located diagnostic rather than a value that compiles and fails later.

## Typed holes

Write `todo[T]()` in expression position, where `T` is the type the missing code
has to produce. The type is declared, not inferred from context: the checker
validates it, then reports `E_TYPED_HOLE` at the `todo` with a related span on
the declared type. Ordinary bodies and uncalled generic bodies each report their
own holes in one check, at safe recovery boundaries, so a file with several
gaps names all of them instead of stopping at the first. Nothing is published
while a hole remains — no checked program, no Core IR, no executable — which is
what makes the construct an obligation rather than a runtime panic hidden behind
a passing check.

```mylang
# doc: expect-error E_TYPED_HOLE
record Invoice:
    subtotal: int
    tax: int

def total(invoice: Invoice) -> int:
    return invoice.subtotal + invoice.tax

def discount(invoice: Invoice) -> int:
    return todo[int]()

def main() -> int:
    invoice = Invoice(subtotal=40, tax=2)
    return total(invoice) - discount(invoice)
```

## Structured obligations

`check --diagnostics=json` attaches a versioned `typed-hole-obligation` record to each
`E_TYPED_HOLE` diagnostic, so an agent can read the hole's local context instead of
guessing it. The record carries the checked snapshot's identity and the hole's exact
source range, the declared result type, the enclosing callable, every in-scope
initialized binding with its type, the generic requirements in force, the declared
effect ceiling and the permitted `mutates(...)` footprint, plus the contextual expected
type when the checker knows one. Facts a hole cannot promise — a transitive effect
summary needs a whole program, which an unresolved hole prevents — are named in an
`unavailable` list rather than guessed. Uninitialized and consumed
bindings never appear as inputs; they are counted in `unusable_bindings`. The text
diagnostic stays as short as before.

```bash
$ mylang check --diagnostics=json hole.my
{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_TYPED_HOLE", …
"obligation":{"kind":"typed-hole-obligation","version":1,"identity":{…},
"declared":{"text":"int",…},"bindings":[{"name":"x","type":"int",…}],…}}
```

An obligation is identified by its snapshot digest — the source path, the checked text
and the hole's range — together with that range, so a query made against an older
snapshot answers "no such hole" instead of pointing at whatever now sits at the same
offset. Replacing the hole removes its obligation, and the program checks and runs
normally again.

## Limits

- `todo[T]()` takes exactly one type argument and no value arguments. It is the
  one construct that keeps angle-bracket type arguments in the Python surface;
  ordinary generic calls are written `f[T](x)`.
- A hole blocks `run`, `run-project`, `build` and every other command that would
  produce or execute a program. `check` is the command that reports it.
- Source formatting preserves a hole, so running the formatter over an unfinished
  file does not quietly erase the obligation.
- This is an explicit declared type, not expected-type completion: the compiler
  does not propose an implementation or rank candidates. Pair the diagnostic with
  the navigation queries to find the types and functions a filling would need.
- A snapshot is retained per check, beside the diagnostic that carries it: there is no
  durable hole database and no `context --at` query yet, so the structured JSON record
  is the only route to it. One snapshot keeps at most 32 bindings and 32 requirements
  and counts the surplus in `omitted`.
- Checker recovery still stops at its existing safe boundaries: a function whose body
  fails earlier than its hole reports only the earlier failure, and additional holes in
  one body are reported only where the checker already recovers.

## Related pages

- [Typed implementation obligations](experiments/typed-holes.md) — the experiment record behind this feature
