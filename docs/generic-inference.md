# Generic call inference

Generic function calls can omit their type arguments when the argument types and the expected result type determine every parameter:

```mylang
# doc: expect 42
def identity[T](value: T) -> T:
    return value


def first[T, const N: u64](items: [N]T) -> T:
    return items[0]


def forward[U](value: U) -> U:
    return identity(value)


def main() -> i64:
    values: [2]i64 = [40, 2]
    return forward(first(values)) + values[1]
```

`identity(1u8)` infers `u8`; it does not widen the argument. Explicit calls such as `identity[u8](1u8)` remain available and share the same specialization. Recursive and mutually recursive calls infer from signatures without expanding bodies during abstract checking.

Inference matches checked argument types against parameter signatures, following fixed arrays (including const lengths), nominal applications, and callback signatures. Generic callers retain their own symbolic type and length identities. Every occurrence of a parameter must agree; `same(1, true)` cannot choose a common type for two `T` inputs. Normal requirements, structural contracts, effects, result handling, and ownership rules apply after inference. Expressions are checked and evaluated once, in their usual order.

The entire list is either explicit or inferred. A parameter appearing only in a constraint still requires explicit specialization. Inference does not choose defaults, perform coercions, infer nominal constructor syntax, or infer generic function values. Unmaterialized phantom types within nominal arguments also require explicit specialization. Missing or conflicting information produces `E_GENERIC_INFERENCE` with a related parameter declaration when available.

The QBE native backend consumes the existing concretely specialized checked program; inference adds no runtime work.

## Expected result types

A binding annotation, function return type, record field, or known function parameter
can supply the result type of a generic call. That context participates in the same
inference as the call's arguments, including fixed array lengths and symbolic types
inside generic functions.

```mylang
# doc: expect 42
record Node:
    value: int

def empty[T: copy + storable]() -> list[T]:
    return []

def zero[T: integer]() -> T:
    return T(0)

def forward[U: integer]() -> U:
    return zero()

def main() -> int:
    nodes: list[Node] = empty()
    small: u8 = forward()
    return 42 + len(nodes) + int(small)
```

When the expected result determines every generic parameter, the resulting parameter
types also guide nested calls and constructors: `value: Option[int] = identity(Some(42))`
works for `def identity[T: copy + storable](value: T) -> T`. Context propagates inward
from an already known type; it does not search later statements for a possible type.

Every source of inference must agree. An `int` destination cannot accept
`identity(1u8)`, and `value = zero()` still needs an annotation or an explicit
`zero[int]()`. Requirements are validated after inference; they do not select a
default type. If context determines only some parameters, remaining parameters must
come from independently checkable call arguments.
