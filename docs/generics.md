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

Ownership is judged at the declaration. `selka check` (a file, a module or a
project, with `check-module`, `check-project` and `selka fix` alike) checks the body
of every generic function of the program, those a program already instantiates
included, through one instance per kind of type argument the function's bounds
admit: a scalar (`int`), a text (`str`), a record with a managed field and a list
(`int[]`). Each type parameter is tried with each managed kind while
the others are `int`, and, when there are two or more, every parameter with the same
managed kind; mixed managed kinds (`str` beside `int[]`) are not tried, and a real
instance of them is still judged where a program makes it. A body that one of these
kinds refuses is an error at the declaration, reported once, naming the type
parameter and the kinds, with the place in the body as a note: `first[T](xs: T[]) -> T`
that returns `xs[0]` is refused when `T` is a text, a record or a list, and `selka
fix` writes the certain repair, ` from xs` on the result or `copy(...)` on a stored
value (a `copy` only when every type parameter admits one). A result an instance's
view sources cannot lend (`E_BORROW_SOURCE`) is still reported at the call, naming
the instance. A function whose parameter has a structural requirement is not tried
with stand-ins: its instances are judged where programs make them. A build
(`build`, `run`, `test`) makes no stand-in instance; it judges the instances its
program makes and reports a refusal inside one at the template's declaration in the
same words.

The standard library's generic functions are judged once per compiler, not in each
`check`: the library is embedded in the compiler, and a gate test runs
`selka template-stand-ins --standard-library`, which tries every library template
with every stand-in above (and more), and fails when one is refused. A judgment that
passed is kept with the ownership proofs of the template's module, under the
template's stable key, the digest of the declarations its body and signature name
(a callee's signature and `from` contract, a record's fields, the compiler's
identity) folded with the rule's own version, and the digest of the declaration's
tokens; while all three are what this check computes, the template is not judged
again, so a comment or a line shift keeps it and a changed token, bound, callee
contract or named record judges it again. `SELKA_ENGINE_VERIFY=N` judges one held
template in N anyway.

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

`record Name[T]:` and `enum Name[T]:` take the same parameter lists. An instance
is identified by the declaration plus its ordered arguments, so `Box[int]` and
`Box[bool]` are unrelated types that never share a schema, and two declarations
with identical fields stay distinct. Construct a generic record with its
arguments spelled out, `Box[int](value=7)`, because a square-bracket application
in call position names a record when the base is a type. A generic enum case
names only its template — `Slot.some(value=x)`, never `Slot[int].some(value=x)`,
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

A bound may name a shape instead of a nominal type. `field(name: Type)` requires
the argument type to declare a field of exactly that name and type. The
requirement follows `copy` in the parameter's bound. A contract exposes only
what it names: it preserves nominal record identity and does not
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

## Structural contracts (removed)

The old structural-contract feature combined field and type-owned operation
requirements. Type-owned `op(...)` requirements are removed; pass the operation
as an explicit callback parameter. [Field requirements](#field-requirements)
remain available.

## Named constraints (removed)

Named constraints and `op(...)` requirements report `E_DOMAIN_REMOVED`.
`selka fix` expands a named bundle into its surviving built-in and field
requirements, then replaces each operation requirement with a callback
parameter. Generic forwarding passes that callback explicitly.

```selka
# doc: expect 42
record DiscountPrices:
    value: int

func price(policy: DiscountPrices, subtotal: int) -> int:
    return subtotal - policy.value

func total[P: copy](policy: P, subtotal: int, operation: func(P, int) -> int) -> int:
    return operation(policy, subtotal)

func main() -> int:
    return total(DiscountPrices(value=8), 50, price)
```

## Interfaces: records of functions

A generic record can hold the operations a generic function needs, so one value
carries the whole contract. The record is generic over its state, each implementation
is an ordinary function that builds one record value, and a record passed down a call
chain stays a single argument. Callbacks passed one by one work too, but every level
then repeats each operation.

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

Rules that follow from this shape:

- The contract is an ordinary record whose fields are function types; there is no
  separate declaration form and no implements statement.
- An implementation is any function that returns the record. Two implementations of one
  contract are two functions, and the caller chooses by calling one of them.
- The record is a runtime value. It can be stored, passed, and returned like any other.
- A contract record may hold functions that take capabilities such as `Filesystem` or
  `Entropy`. The function value stores none of them: each call passes the capability in.
  A function type adds no storage, so a record that recurses only through one is stored unboxed.
- A field is called through a local (`const add = sink.add`), as the rule for function-typed
  fields requires.

## Limits

- A declaration takes at most 16 combined type and constant-length arguments, and
  a program is bounded at 4,096 function specializations.
- `main` cannot be generic.
- Generic function bodies reject direct file operations and `with` resource
  scopes with `E_GENERIC_BODY_UNSUPPORTED`. Put those operations in an ordinary
  helper and call it from the generic function. `with arena()` is retired in
  every function; see [retired arenas](managed-memory.md#retired-arenas).
- Structural contracts apply to function type parameters only.
- The public schema lists generic templates separately from concrete functions
  and types, and schema export of a generic type constructor is unsupported.

## Related pages

- [Generic call inference](generic-inference.md) — when the type arguments can be omitted
- [Constant length parameters](const-length-generics.md) — `const N: u64` alongside type parameters
