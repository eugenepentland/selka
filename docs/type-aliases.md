# Transparent type aliases

A type alias supplies another spelling for an existing type:

```selka
type Count = i64
type Counts = FixedArray[Count, 2]


record Pair[T]:
    left: T
    right: T


type NumberPair = Pair[Count]
```

Aliases may target scalars, nominal types, fixed arrays, or concrete generic
applications. Forward references and alias chains work; cycles and duplicate
type names reject. Aliases do not have their own type parameters in this version.
Existing type-expression depth/work budgets bound their expansion.

A value of `Count` is an `i64`, and `NumberPair` has exactly the identity of
`Pair[i64]`. Aliasing a record preserves that record's nominal identity and
fields. It does not convert the record to one of its field types.
Likewise, aliases preserve owned-storage moves and must-handle result obligations.
Use a `record` declaration when a distinct identity is required.

Alias names work in annotations, constructors, generic arguments and scalar
constant declarations. An alias does not add new function declarations.

Module export and privacy rules also apply to aliases. Exported aliases must
have public target types; a public alias cannot expose an otherwise private
record. Private aliases cannot be named by importing modules. Public signatures
using a local alias require that alias to be exported, just as other named types
do. Runtime schemas and native representations use the canonical target type,
with no wrapper allocation or conversion.

## Aliasing an enum from another module

A module reaches another module's enum through the import (`tk.Kind`, `tk.Kind.colon`), and a long qualified
name repeated on every line is the main cost of writing a lexer or a parser over a shared token enum. A
transparent alias gives it a short name without a from-import (`from tk import Kind` is refused, with this advice in
the diagnostic): `import tk`, then `type Kind = tk.Kind`. The alias is the enum itself, so `Kind.colon` constructs
and compares exactly like `tk.Kind.colon`, a `Kind` parameter takes a `tk.Kind` argument, and a pattern names its
case alone, `case colon:`, as it does for any enum. `import tk as t` shortens the module name instead.

```selka
# doc: expect 1 2 True
import http

type Failure = http.Error


func describe(failure: Failure) -> int:
    match failure:
        case Incomplete:
            return 1
        case Malformed(value=_):
            return 2
        case _:
            return 3


func main(out: Stream) -> int:
    const waiting: Failure = Failure.Incomplete
    const broken = Failure.Malformed(value="bad")
    print(out, describe(waiting), describe(broken), waiting == Failure.Incomplete)
    return 0
```
