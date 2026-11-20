# Generic call inference

Generic function calls can omit their type arguments when the argument types and the expected result type determine every parameter:

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

`identity(1u8)` infers `u8`; it does not widen the argument. Explicit calls such as `identity[u8](1u8)` remain available and share the same specialization. Recursive and mutually recursive calls infer from signatures without expanding bodies during abstract checking.

Inference matches checked argument types against parameter signatures, following fixed arrays (including const lengths), nominal applications, and callback signatures. Generic callers retain their own symbolic type and length identities. Every occurrence of a parameter must agree; `same(1, true)` cannot choose a common type for two `T` inputs. Normal requirements, structural contracts, effects, result handling, and ownership rules apply after inference. Expressions are checked and evaluated once, in their usual order.

The entire list is either explicit or inferred. A parameter appearing only in a constraint still requires explicit specialization. Inference does not choose defaults, perform coercions, infer nominal constructor syntax, or infer generic function values. Unmaterialized phantom types within nominal arguments also require explicit specialization. Missing or conflicting information produces `E_GENERIC_INFERENCE`. A parameter no argument and no expected result
determines is named in the message, with a note at its declaration; two sources that infer different types are both
named, `the type parameter T is inferred as i64 from the argument 3 and as Link from the argument link_of`, with a note
at the one that inferred it first.

The back end receives the concretely specialized checked program; inference adds no runtime work.

## Expected result types

A binding annotation, function return type, record field, or known function parameter
can supply the result type of a generic call. That context participates in the same
inference as the call's arguments, including fixed array lengths and symbolic types
inside generic functions.

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

When the expected result determines every generic parameter, the resulting parameter
types also guide nested calls and constructors: `value: Option[int] = identity(Some(42))`
works for `func identity[T: copy + storable](value: T) -> T`. Context propagates inward
from an already known type; it does not search later statements for a possible type.

Every source of inference must agree. An `int` destination cannot accept
`identity(1u8)`, and `value = zero()` still needs an annotation or an explicit
`zero[int]()`. Requirements are validated after inference; they do not select a
default type. If context determines only some parameters, remaining parameters must
come from independently checkable call arguments.

## Functions passed for function-typed parameters

A named function passed for a parameter of function type contributes its parameter types and its result. A function
type spelled `-> T fails E` answers a `Result[T, E]`, so a function argument declared `-> Link fails str` gives `Link`
to `T` and `str` to `E`; the spelling `-> Result[T, E]` reads the same. An expected result works the same way for a
callee declared `-> T fails E`: the `Result[S, E]` an argument position expects gives `S` to `T`. So a helper that
decodes every element of a list needs no type arguments:

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

A generic function cannot be passed as a function value (`E_CALLBACK_TYPE`), so it never fixes a type argument;
pass an ordinary function, or a generic function's instance through a wrapper.

## Helpers a generic function calls

The abstract check of a generic function walks the generic functions only. An ordinary function it calls is checked by the
concrete checker, as it is when no generic function reaches it, so a helper may use any prelude builtin (`set()`, `dict()`,
`list(...)`, `sum`, `min`, `max`, `abs`, `any`, `all`, `reversed`, `zip`), `print` or a standard module, and an invalid helper is
rejected with the concrete checker's diagnostic. The generic body itself is still limited to the forms the abstract check knows: a
prelude builtin written directly in it is `E_GENERIC_BODY_UNSUPPORTED`, which names the repair, an ordinary function that uses it.

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
