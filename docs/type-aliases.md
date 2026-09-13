# Transparent type aliases

A type alias supplies another spelling for an existing type:

```my
type Count = i64
type Counts = [2]Count


class Pair[T]:
    left: T
    right: T


type NumberPair = Pair[Count]
```

Aliases may target scalars, nominal types, fixed arrays, or concrete generic
applications. Forward references and alias chains work; cycles and duplicate
type names reject. Aliases do not have their own type parameters in this version.
Existing type-expression depth/work budgets bound their expansion.

A value of `Count` is an `i64`, and `NumberPair` has exactly the identity of
`Pair<i64>`. Aliasing a domain preserves that domain's nominal identity and
private representation. It does not convert the domain to its backing scalar.
Likewise, aliases preserve owned-storage moves and must-handle result obligations.
Use a `domain` declaration when a distinct identity is required.

Alias names work in annotations, constructors, generic arguments and scalar
constant declarations. Domain operations remain declared under the original
domain's namespace; an alias does not add new function declarations.

Module export and privacy rules also apply to aliases. Exported aliases must
have public target types; a public alias cannot expose an otherwise private
record. Private aliases cannot be named by importing modules. Public signatures
using a local alias require that alias to be exported, just as other named types
do. Runtime schemas and native representations use the canonical target type,
with no wrapper allocation or conversion.
