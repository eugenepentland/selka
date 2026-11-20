# Generic functions and types

A generic declaration is a template over type parameters. A call or a type annotation supplies concrete arguments, and
the compiler makes one specialization per distinct argument list. A template is checked before any specialization
exists, so one that no program calls still has to type-check.

## Generic functions

`func name[T](...)` declares a function template. A parameter may carry a requirement: `copy`, `equality` or `integer`
(`integer` implies `equality`, which implies `copy`). The body is checked once against that requirement alone, and a
requirement the body needs but the signature does not declare is an error in the template. Write the type arguments
explicitly as `f[int](x)`, or omit the list when the value arguments determine every parameter ([generic call
inference](generic-inference.md)).

Ownership is judged at the declaration. `selka check` tries every generic body with a stand-in for each kind of type
argument its bounds admit: a scalar, a text, a record with a managed field, a list. A body one kind refuses is an error
at the declaration, naming the type parameter and the kinds: `first[T](xs: T[]) -> T` that returns `xs[0]` is refused
when `T` is a text, record or list, and `selka fix` writes ` from xs` on the result or `copy(...)` on a stored value. A
function with a structural requirement is judged where programs instantiate it. A result an instance's sources cannot lend
(`E_BORROW_SOURCE`) is reported at the call, naming the instance.
`SELKA_ENGINE_VERIFY=N` re-judges one kept template in N.

```selka
# doc: expect 42
func pick[T](first: T, second: T, take_first: bool) -> T from first, second:
    if take_first:
        return first
    return second

func double[T: integer](value: T) -> T:
    return value + value

func main() -> int:
    return double[int](pick[int](21, 0, True))
```

<a id="generic-records-and-unions"></a>

## Generic records and enums

`record Name[T]:` and `enum Name[T]:` take the same parameter lists. `Box[int]` and `Box[bool]` are unrelated types, and two
declarations with identical fields stay distinct.

- Construct a generic record with its arguments spelled out: `Box[int](value=7)`.
- A generic enum case names only its template: `Slot.some(value=x)`, never `Slot[int].some(value=x)`. Its arguments come
  from the expected type of a binding annotation, parameter, field or result; `E_GENERIC_INFERENCE` is reported when no
  context supplies them.

```selka
# doc: expect 42
record Box[T]:
    value: T

enum Slot[T]:
    none
    some(value: T)

func contents[T](slot: Slot[T], fallback: T) -> T from slot, fallback:
    match slot:
        case none:
            return fallback
        case some(value=value):
            return value

func main() -> int:
    mut box = Box[int](value=7)
    mut filled: Slot[int] = Slot.some(value=box.value)
    mut empty: Slot[int] = Slot.none
    return contents[int](filled, 0) + contents[int](empty, 35)
```

## Field requirements

A bound may name a shape instead of a nominal type: `field(name: Type)` requires the argument type to declare a field of
exactly that name and type. It follows `copy` in the bound. A contract exposes only what it names: it keeps nominal record
identity and does not allow constructing a value of an unknown record. A caller bound only by `copy` cannot forward to a
function that requires a field: every link in a forwarding chain repeats the contract, or the call is
`E_GENERIC_BODY_UNSUPPORTED`.

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

One bound may list several requirements joined by `+`; each may mention fixed arrays, nominal applications and the
function's other type parameters. Requirements match by exact type, never by coercion or subtyping.

## Composite structural signatures

One parameter can carry the shape of a whole record while a second carries the element type that shape is written in
terms of: `field(items: [2]U)` and `field(box: Box[U])` constrain `T` and bind `U` in one signature. A repeated
requirement name is `E_GENERIC_REQUIREMENT`, as is a structural requirement on a `record` or `union` declaration rather than
a function parameter; an invalid template is rejected even when never called.

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

## Interfaces: records of functions

A generic record can hold the operations a generic function needs, so one value carries the whole contract and stays a
single argument down a call chain. Each implementation is an ordinary function that builds one record value.

```selka
# doc: expect 6 12 6
record Counter:
    total: int
    calls: int


# The contract: any state `S` that accepts one integer at a time.
record Accumulator[S]:
    add: func(mut state: S, value: int) -> Unit


func add_plain(mut state: Counter, value: int) -> Unit:
    state.total += value
    state.calls += 1


func add_doubled(mut state: Counter, value: int) -> Unit:
    state.total += value * 2
    state.calls += 1


# An implementation is a function that builds the record. A module constant holds
# only scalars, so the record is built at the point of use.
func plain() -> Accumulator[Counter]:
    return Accumulator[Counter](add=add_plain)


func doubled() -> Accumulator[Counter]:
    return Accumulator[Counter](add=add_doubled)


# The record travels through two generic levels as one argument.
func feed[S: copy](mut state: S, sink: Accumulator[S], values: int[]) -> Unit:
    for value in values:
        deliver(mut state, sink, value)


func deliver[S: copy](mut state: S, sink: Accumulator[S], value: int) -> Unit:
    # A call goes through a local; `sink.add(...)` reads as a method and is refused.
    const add = sink.add
    add(mut state, value)


func main(out: Stream) -> int:
    mut first = Counter(total=0, calls=0)
    feed(mut first, plain(), [1, 2, 3])
    mut second = Counter(total=0, calls=0)
    feed(mut second, doubled(), [1, 2, 3])
    print(out, first.total, second.total, first.calls + second.calls)
    return 0
```

- The contract is an ordinary record whose fields are function types; there is no implements statement. The caller picks
  an implementation by calling one of the functions that build it.
- The record is a runtime value: store, pass and return it freely. A field holding a function that takes a capability
  such as `Filesystem` stores none; each call passes it in.
- Call a field through a local (`const add = sink.add`); `sink.add(...)` reads as a method and is refused.

## Limits

- A declaration takes at most 16 combined type and constant-length arguments, and a program is bounded at 4,096 function
  specializations.
- `main` cannot be generic.
- Generic function bodies reject direct file operations and `with` resource scopes with `E_GENERIC_BODY_UNSUPPORTED`: put
  them in an ordinary helper. `with arena()` is refused in every function ([retired
  arenas](managed-memory.md#retired-arenas)).
- Type-owned `op(...)` requirements and named constraints report `E_DOMAIN_REMOVED`: pass the operation as a callback
  parameter (`func(P, int) -> int`); `selka fix` makes the rewrite. Structural contracts apply to function type
  parameters only.
- The public schema lists generic templates separately, and schema export of a generic type constructor is unsupported.

## Related pages

- [Generic call inference](generic-inference.md): when the type arguments can be omitted
- [Constant length parameters](const-length-generics.md): `const N: u64` alongside type parameters

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/generics.md).
