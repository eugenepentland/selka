# Typed holes

A typed hole is a place where an implementation is missing and the author has
said so in the source. Everything around it is checked normally, so the rest of a
half-written module still reports its real errors, and the hole itself is a
located diagnostic rather than a value that compiles and fails later.

## Typed holes

Write `todo<T>()` in expression position, where `T` is the type the missing code
has to produce. The type is declared, not inferred from context: the checker
validates it, then reports `E_TYPED_HOLE` at the `todo` with a related span on
the declared type. Ordinary bodies and uncalled generic bodies each report their
own holes in one check, at safe recovery boundaries, so a file with several
gaps names all of them instead of stopping at the first. Nothing is published
while a hole remains — no checked program, no bytecode, no executable — which is
what makes the construct an obligation rather than a runtime panic hidden behind
a passing check.

```mylang
# doc: expect-error E_TYPED_HOLE
class Invoice:
    subtotal: int
    tax: int

def total(invoice: Invoice) -> int:
    return invoice.subtotal + invoice.tax

def discount(invoice: Invoice) -> int:
    return todo<int>()

def main() -> int:
    invoice = Invoice(subtotal=40, tax=2)
    return total(invoice) - discount(invoice)
```

## Limits

- `todo<T>()` takes exactly one type argument and no value arguments. It is the
  one construct that keeps angle-bracket type arguments in the Python surface;
  ordinary generic calls are written `f[T](x)`.
- A hole blocks `run`, `run-project`, `build` and every other command that would
  produce or execute a program. `check` is the command that reports it.
- Source formatting preserves a hole, so running the formatter over an unfinished
  file does not quietly erase the obligation.
- This is an explicit declared type, not expected-type completion: the compiler
  does not propose an implementation or rank candidates. Pair the diagnostic with
  the navigation queries to find the types and functions a filling would need.

## Related pages

- [Typed implementation obligations](experiments/typed-holes.md) — the experiment record behind this feature
