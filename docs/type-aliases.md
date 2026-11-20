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

- An alias may target a scalar, nominal type, fixed array or concrete generic application. Forward references and chains
  work; cycles and duplicate type names reject. An alias has no type parameters of its own.
- A value of `Count` is an `i64`, and `NumberPair` is exactly `Pair[i64]`. Aliasing a record keeps its identity and
  fields. Moves and must-handle result obligations carry through. For a distinct identity, declare a `record`.
- Alias names work in annotations, constructors, generic arguments and scalar constant declarations.
- Export and privacy rules apply: a public alias needs a public target, a private alias cannot be named by an importing
  module, and a public signature that uses a local alias needs it exported. Runtime schemas use the target type, with no
  wrapper or conversion.

## Aliasing an enum from another module

Another module's enum is reached through the import (`tk.Kind.colon`). An alias gives it a short name without a
from-import (`from tk import Kind` is refused): `import tk`, then `type Kind = tk.Kind`. The alias is the enum itself,
so `Kind.colon` constructs and compares like `tk.Kind.colon`, a `Kind` parameter takes a `tk.Kind` argument, and a
pattern names its case alone, `case colon:`. `import tk as t` shortens the module name instead.

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
