# Generic functions and types

A generic declaration is a template over type parameters. Nothing about it exists
at runtime: a call or a type annotation supplies concrete arguments, and the
compiler produces one specialization per distinct argument list. Templates are
checked before any specialization exists, so a template that no program ever
calls still has to type-check.

## Generic functions

`func name[T](...)` declares a function template. Each parameter may carry a
requirement — `copy`, `equality` or `integer`, where `integer` implies `equality`
and `equality` implies `copy` — and the body is checked once against that
requirement alone, without substituting a representative type. A requirement the
body needs but the signature does not declare is an error in the template rather
than at the call. Write the type arguments explicitly as `f[int](x)`, or omit the
whole list when the value arguments determine every parameter; see
[generic call inference](generic-inference.md).

```selka
# doc: expect 42
func pick[T](first: T, second: T, take_first: bool) -> T:
    if take_first:
        return first
    return second

func double[T: integer](value: T) -> T:
    return value + value

func main() -> int:
    return double[int](pick[int](21, 0, True))
```

## Generic records and unions

`record Name[T]:` and `union Name[T]:` take the same parameter lists. An instance
is identified by the declaration plus its ordered arguments, so `Box[int]` and
`Box[bool]` are unrelated types that never share a schema, and two declarations
with identical fields stay distinct. Construct a generic record with its
arguments spelled out, `Box[int](value=7)`, because a square-bracket application
in call position names a record when the base is a type. A generic union case
names only its template — `Slot.some(value)`, never `Slot[int].some(value)`,
which cannot be told apart from an index followed by a call — so its arguments
come from the expected type of a binding annotation, parameter, field or result,
and `E_GENERIC_INFERENCE` is reported when no context supplies them.

```selka
# doc: expect 42
record Box[T]:
    value: T

enum Slot[T]:
    none
    some(value: T)

func contents[T](slot: Slot[T], fallback: T) -> T:
    match slot:
        case Slot.none:
            return fallback
        case Slot.some(value=value):
            return value

func main() -> int:
    mut box = Box[int](value=7)
    mut filled: Slot[int] = Slot.some(value=box.value)
    mut empty: Slot[int] = Slot.none
    return contents[int](filled, 0) + contents[int](empty, 35)
```

## Structural contracts

A bound may name a shape instead of a nominal type. `field(name: Type)` requires
the argument type to declare a field of exactly that name and type;
`op(name(arg: T) -> R effects(...))` requires a public, nongeneric type-owned
operation with exactly that signature and effect ceiling, called as `T.name(arg)`
in the body. Both follow `copy` in the parameter's bound. A contract exposes only
what it names: it does not reveal a domain's backing value and it does not
authorize constructing a value of an unknown record. Because checking is
universal, a caller bound only by `copy` cannot forward to a function that
requires a field — every link in a forwarding chain repeats the contract, or the
call rejects with `E_GENERIC_BODY_UNSUPPORTED`.

```selka
# doc: expect 42
record Reading:
    value: int

record TaggedReading:
    tag: bool
    value: int

func value_of[T: copy + field(value: int)](item: T) -> int:
    return item.value

func forward[U: copy + field(value: int)](item: U) -> int:
    return value_of[U](item)

func main() -> int:
    return value_of[Reading](Reading(value=12)) + forward[TaggedReading](TaggedReading(tag=True, value=30))
```

One bound may list several requirements joined by `+`, and each requirement's
signature may itself mention fixed arrays, nominal applications and the
function's other type parameters. Requirements match by exact type, never by
coercion or subtyping.

## Composite structural signatures

A composite contract lets one parameter carry the shape of a whole record while a
second parameter carries the element type that shape is written in terms of. The
same substitution reaches through fixed-array lengths and nominal applications,
so `field(items: [2]U)` and `field(box: Box[U])` constrain `T` and bind `U` in
one signature. A repeated requirement name rejects with `E_GENERIC_REQUIREMENT`,
as does a structural requirement written on a `record` or `union` declaration
rather than on a function parameter; an invalid template rejects even when it is
never called.

```selka
# doc: expect 42
record Box[U]:
    value: U

record Frame:
    items: FixedArray[int, 2]
    box: Box[int]

func boxed[T: copy + field(items: FixedArray[U, 2]) + field(box: Box[U]), U: copy](frame: T) -> U:
    return frame.box.value

func main() -> int:
    mut frame = Frame(items=FixedArray[int, 2]([1, 2]), box=Box[int](value=42))
    return boxed[Frame, int](frame)
```

## Named constraints

A constraint names a structural contract once so several functions can share it.
`constraint Name[Subject] = REQUIREMENTS` binds exactly one subject type; a
function parameter uses it as a bound, `func f[T: Name](...)`. The subject is
local to the declaration, so the same contract can be written with any binder
spelling. A bound may combine names with builtins and inline requirements —
`T: Prices + codec + field(tag: bool)` — and a qualified import works:
`T: contracts.Prices`. Constraints are transparent: a type satisfies one
structurally, without an `implements` declaration, and two names with equivalent
requirements satisfy the same forwarding obligations. A constraint is not a
value type, so `policy: Prices` and `Prices[int]` are rejected, and a named
bound is only valid on a function type parameter.

```selka
# doc: expect 42
constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())

func total[P: Prices](policy: P, subtotal: int) -> int effects():
    return P.price(policy, subtotal)

domain DiscountPrices: int:
    func make(discount: int) -> DiscountPrices:
        return wrap[DiscountPrices](discount)

    func price(policy: DiscountPrices, subtotal: int) -> int effects():
        return subtotal - unwrap(policy)

func main() -> int:
    return total(DiscountPrices.make(8), 50)
```

## Limits

- A declaration takes at most 16 combined type and constant-length arguments, and
  a program is bounded at 4,096 function specializations.
- `main` cannot be generic.
- Generic function bodies reject `print`, the file builtins and `with arena()`
  with `E_GENERIC_BODY_UNSUPPORTED`. Write an ordinary function and call it from
  the generic one.
- Structural contracts apply to function type parameters only.
- The public schema lists generic templates separately from concrete functions
  and types, and schema export of a generic type constructor is unsupported.

## Related pages

- [Generic call inference](generic-inference.md) — when the type arguments can be omitted
- [Constant length parameters](const-length-generics.md) — `const N: u64` alongside type parameters
