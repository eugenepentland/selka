# Generic call inference

A generic call may omit its type arguments when the argument types and the expected result type determine every
parameter:

```selka
# doc: expect 42
func identity[T](value: T) -> T from value:
    return value


func first[T, const N: u64](items: [N]T) -> T from items:
    return items[0]


func forward[U](value: U) -> U from value:
    return identity(value)


func main() -> i64:
    mut values: FixedArray[i64, 2] = FixedArray[int, 2]([40, 2])
    return forward(first(values)) + values[1]
```

- `identity(1u8)` infers `u8`; it does not widen the argument. `identity[u8](1u8)` stays available and shares the
  specialization.
- Inference matches checked argument types against parameter signatures, following fixed arrays (const lengths
  included), nominal applications and callback signatures.
- Every occurrence of a parameter must agree: `same(1, true)` cannot choose a type for two `T` inputs. Requirements,
  contracts, effects and ownership rules apply after inference.
- The whole list is explicit or inferred. A parameter that appears only in a constraint, and an unmaterialized phantom
  type inside a nominal argument, need explicit specialization. Inference chooses no defaults, coerces nothing, and infers
  no nominal constructor syntax and no generic function values.
- Missing or conflicting information is `E_GENERIC_INFERENCE`, naming the parameter nothing determines (with a note at
  its declaration), or both sources that infer different types: `the type parameter T is inferred as i64 from the
  argument 3 and as Link from the argument link_of`.

## Expected result types

A binding annotation, function return type, record field or known function parameter can supply the result type of a
generic call, in the same inference as the arguments.

```selka
# doc: expect 42
record Node:
    value: int

func empty[T: copy + storable]() -> T[]:
    return []

func zero[T: integer]() -> T:
    return T(0)

func forward[U: integer]() -> U:
    return zero()

func main() -> int:
    mut nodes: Node[] = empty()
    mut small: u8 = forward()
    return 42 + len(nodes) + int(small)
```

When the expected result determines every parameter, the parameter types also guide nested calls and constructors:
`value: Option[int] = identity(Some(42))` works for `func identity[T: copy + storable](value: T) -> T`. Context
propagates inward from a known type; it does not search later statements.

Every source must agree: an `int` destination cannot accept `identity(1u8)`, and `value = zero()` needs an annotation or
`zero[int]()`. If context fixes only some parameters, the rest must come from the arguments.

## Functions passed for function-typed parameters

A named function passed for a function-typed parameter contributes its parameter types and result. A function type
`-> T fails E` answers a `Result[T, E]`, so an argument declared `-> Link fails str` gives `Link` to `T` and `str` to `E`.
An expected `Result[S, E]` works alike for a callee declared `-> T fails E`. A helper that decodes every element of a
list needs no type arguments:

```selka
# doc: expect 2 -1
record Link:
    label: str


func link_of(value: str) -> Link fails str:
    if value == "":
        fail "empty"
    return Link(label=copy(value))


func each[T](values: str[], make: func(str) -> T fails str) -> T[] fails str:
    mut out: T[] = []
    for value in values:
        const item = try make(value)
        append(mut out, own item)
    return out


func count(found: Result[Link[], str]) -> int:
    match found:
        case Ok(items):
            return len(items)
        case Err(_):
            return -1


func links(values: str[]) -> Link[] fails str:
    return try each(values, link_of)


func main(out: Stream) -> int:
    print(out, count(links(["a", "b"])), count(each(["a", ""], link_of)))
    return 0
```

A generic function cannot be passed as a function value (`E_CALLBACK_TYPE`); pass an ordinary function or a wrapper.

## Helpers a generic function calls

An ordinary function a generic function calls is checked by the concrete checker, so a helper may use any prelude builtin
(`set()`, `dict()`, `list(...)`, `sum`, `min`, `max`, `abs`, `any`, `all`, `reversed`, `zip`), `print` or a standard
module. The generic body itself is limited to forms the abstract check knows: a prelude builtin written directly in it is
`E_GENERIC_BODY_UNSUPPORTED`, which names the repair, an ordinary function that uses it.

```selka
# doc: expect 3
func counts() -> dict[str, int]:
    mut result: dict[str, int] = dict()
    result["a"] = 1
    result["b"] = 2
    return result


func total(values: int[]) -> int:
    return sum(values)


func describe[T](value: T) -> int:
    _ = value
    return len(counts()) + total([1])


func main() -> int:
    return describe[int](0)
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/generic-inference.md).
