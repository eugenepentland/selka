# Records, unions and enums

`record` groups named fields into a value. `enum` declares a closed set of
payload-free or named-payload alternatives. Both are nominal: declarations with
the same shape remain different types. Rare nominal `result` declarations keep
their existing identity and handling rules. There is no inheritance or open
extension of a declaration's cases.

## Records

`record` declares a value record. Every field carries a type annotation, and the record
has no methods, no inheritance and no implicit `self` — a function that operates on a
record takes it as an ordinary parameter. Assignment and argument passing preserve
independent values, including managed fields such as `list` and `dict`. The runtime
can share backing storage until either value is written. Ordinary
field assignment updates a record local or a record held in a list slot.

```mylang
# doc: expect 14
record Point:
    x: int
    y: int

record Segment:
    start: Point
    end: Point

func shift(source: Point, dx: int) -> Point:
    mut point = source
    point.x = point.x + dx
    return point

func main() -> int:
    mut origin = Point(x=1, y=2)
    mut moved = shift(origin, 10)
    mut line = Segment(start=origin, end=moved)
    return line.start.x + line.end.x + line.end.y
```

This returns `14`. `shift` updates its own mutable local copy, so `origin.x` is still `1`
afterwards and only `moved.x` is `11`. A record that holds a list, dictionary or
string is a value too; see [value semantics](value-semantics.md) for how its
managed fields are shared until a write.

A rule every value of a record must satisfy is written as an invariant above it,
such as `@invariant(self.low <= self.high)`. It is checked at every
construction, `replace(...)` and field write, and a violation traps
`R_INVARIANT`; see [contracts](contracts.md#invariants).

## Identity and recursive records

Use a recursive record or union for a finite tree. Use a stable handle in
`pool.Pool[T]` for a graph whose nodes need identity. There are no shared
reference records: a `class` declaration is rejected with `E_VALUE_CLASS` and
builtin `Cell` with `E_VALUE_CELL`.

```mylang
# doc: expect 2
record Counter:
    n: int

func bump(mut counter: Counter):
    counter.n = counter.n + 1

func main() -> int:
    mut a = Counter(n=1)
    mut b = a
    b.n = 7
    bump(mut a)
    return a.n
```

This returns `2`: writing `b` leaves `a` at `1`, then the marked `mut` call
changes `a`. Recursive value fields that would be infinitely large are stored
in immutable boxes; writing a nested path copies its boxes. A record copy write
that nothing reads afterwards is `E_DEAD_RECORD_WRITE`.

## Named constructors

Construct a record by calling its type and naming every supplied field.
Fields may appear in any order; expressions evaluate once in written order.
Every field needs a value unless its declaration provides a default. Missing
required fields report `E_INCOMPLETE_CONSTRUCTION`. An empty record declares
`pass` and is constructed with no arguments.

```mylang
# doc: expect 321
record Colour:
    red: int
    green: int
    blue: int

record Marker:
    pass

func main() -> int:
    const first = Colour(red=1, green=2, blue=3)
    const second = Colour(blue=30, red=10, green=20)
    const third = Colour(red=100, blue=300, green=200)
    _ = Marker()
    return first.red + second.green + third.blue
```

This returns `321`. Ordinary functions may also have positional parameters;
record field labels are always required.

## Field defaults and functional update

A field may declare an immutable scalar default after `=`, exactly the literals a
function parameter accepts: an integer, Boolean, `None`, string or byte literal, or a
negated integer literal. A constructor call that omits such a field materializes the
declared default, so `Config(verbose=True)` fills in `retries`. Required fields must
precede defaulted ones, as in a parameter list, and a required field after a defaulted
one is rejected with `E_DEFAULT_ARGUMENT`. Enum-keyed table literals are unaffected:
every key is still required.

```mylang
# doc: expect 12
record Config:
    retries: int = 3
    verbose: bool = False
    label: str = "auto"

func main() -> int:
    mut base = Config(verbose=True)
    mut fixed = Config(retries=7)
    if base.verbose and len(base.label) == 4:
        return base.retries + fixed.retries + 2
    return 0
```

This returns `12`: `base.retries` is the declared `3`, `fixed.retries` is the
explicit `7`, and `base.label` defaults to `"auto"`.

`replace(record, field=value, …)` is the functional update: it returns a copy of the
record with only the named fields changed and every other field preserved, leaving the
base value untouched. The base is evaluated before the values, the result is a fresh
record value, a field name that does not exist is `E_UNKNOWN_FIELD`, and a repeated one
is `E_DUPLICATE_FIELD`. The positional three-argument `replace(list, index, value)`
intrinsic is unchanged; the named form is recognized by its first argument separator.

```mylang
# doc: expect 7
record Settings:
    retries: int = 3
    verbose: bool = False

func main() -> int:
    mut base = Settings(verbose=True)
    mut changed = replace(base, retries=5)
    return changed.retries + 2
```

This returns `7`. `changed` keeps `verbose` from `base` and `base.retries` is still `3`.

## Tagged unions

`enum` declares a closed set of cases, each on its own line. A case may have no
payload or declare named fields, such as `number(value: int)` or
`point(x: int, y: int)`. Construct fields by name and bind them by name in a
`match`. Matching checks coverage; adding a case makes incomplete matches fail
at compile time. A final `case _` covers the remaining alternatives, subject
to the existing checked-result handling obligations.

```mylang
# doc: expect 21
enum Level:
    debug
    warning
    failure

enum Event:
    heartbeat
    count(value: int)
    message(value: str)

func weight(event: Event) -> int:
    match event:
        case Event.heartbeat:
            return 1
        case Event.count(value=n):
            return n
        case Event.message(value=text):
            return len(text)

func urgency(level: Level) -> int:
    match level:
        case Level.failure:
            return 10
        case _:
            return 0

func main() -> int:
    mut events = [Event.heartbeat, Event.count(value=6), Event.message(value="down")]
    mut total = 0
    for event in events:
        total = total + weight(event)
    return total + urgency(Level.failure) + urgency(Level.debug)
```

This returns `21`. `match` supports statement bodies and expression bodies with `yield`; see
[match expressions](match-expressions.md) for how a value is produced from one.

## Payload variant construction

`Type.case` constructs a payload-free case. `Type.case(value=expression)`
constructs a case whose field is named `value`; every payload argument names its
field and evaluates once in written order. A pattern such as
`case Type.case(value=binding)` binds that field; `value=_` discards it.
Nested patterns may inspect variants inside payloads. Generic type arguments
follow the existing expected-type inference rules.

```mylang
# doc: expect 26
record Point:
    x: int
    y: int

enum Shape:
    empty
    radius(value: int)
    point(value: Point)

enum Slot[T]:
    empty
    filled(value: T)

func area(shape: Shape) -> int:
    match shape:
        case Shape.empty:
            return 0
        case Shape.radius(value=r):
            return r * r
        case Shape.point(value=_):
            return 1

func main() -> int:
    mut shapes = [Shape.radius(value=4), Shape.point(value=Point(x=1, y=2)), Shape.empty]
    mut total = 0
    for shape in shapes:
        total = total + area(shape)
    mut taken: Slot[int] = Slot.filled(value=9)
    match taken:
        case Slot.empty:
            return total
        case Slot.filled(value=value):
            return total + value
```

This returns `26`. Construction resolves through the declared type identity, so a local
binding that shadows the type name keeps ordinary member resolution, and a name that is
not a declared case stays an ordinary call.

## Named variant case fields

A case may declare named fields, `case(f1: T1, f2: T2 = default)`. Required
fields precede defaulted fields, and defaults use the same immutable literals
as record fields. Construction names every supplied field:
`Type.case(f1=value, f2=other)`. Omitted defaults are filled from the declaration.
A payload-free case needs no parentheses. A single payload is an explicitly
named field, for example `item(value: T)`.

Patterns name the fields too: `case Type.case(f1=first, f2=_)`. `_` discards
that field; a nested pattern can match an enum or optional payload. A missing,
extra, unknown or duplicate field receives a located diagnostic. Patterns bind
read-only locals and must exhaustively cover the possible values. A field whose type carries a handling
obligation keeps it, so `case _` over a case with a `Result` field still reports
`E_RESULT_DISCARD` and needs its own arm.

```mylang
# doc: expect 10
record Span:
    line: int
    col: int


enum Node:
    form(items: Node[], span: Span)
    atom(text: str, span: Span)
    decimal(value: float, span: Span, literal: str? = None)


func width(node: Node) -> int:
    match node:
        case Node.form(items=items, span=_):
            return len(items)
        case Node.atom(text=text, span=_):
            return len(text)
        case Node.decimal(value=_, span=_, literal=literal):
            match literal:
                case Some(_):
                    return 1
                case None:
                    return 2


func main() -> int:
    mut home = Span(line=1, col=1)
    mut tree = Node.form(items=[Node.atom(text="x", span=home), Node.decimal(value=0.0000001, span=home, literal=Some("100nF"))], span=home)
    return width(tree) + width(Node.atom(text="abc", span=home)) * 2 + width(Node.decimal(value=1.5, span=home))
```

This returns `10`. The case's payload stays a single value, so named fields do not change
how a union is laid out, compared, copied, or passed across a module boundary.

## Recursive payloads

A record or union can refer to itself directly or through another value type when
there is a way to finish the value. An optional field has `None`, and a union can
have a case with no recursive payload. The compiler puts the recursive field or
case in an immutable managed box; source code still reads and writes its value.
Copies share boxes until a nested write creates new boxes along that path.

```mylang
# doc: expect 42
record Binary:
    left: Expr
    right: Expr

enum Expr:
    number(value: int)
    binary(value: Binary)

func total(expr: Expr) -> int:
    match expr:
        case Expr.number(value=n):
            return n
        case Expr.binary(value=node):
            return total(node.left) + total(node.right)

func main() -> int:
    mut tree: Expr = Expr.binary(value=Binary(left=Expr.number(value=20), right=Expr.number(value=22)))
    return total(tree)
```

This returns `42`; the `number` case ends the recursion. `record Loop: next: Loop`
still gets `E_RECURSIVE_RECORD`, because it has no finite value. Recursion through
`...[]` or `dict[...]` already has indirection and needs no box. Nested
recursive values compare, hash, print and cross typed JSON boundaries as values.
Printing stops with `...` at the renderer's depth cap.

A recursive box cannot own a resource, an unhandled result or a capability.
This includes builtin `File` and `TextFile` fields, even when construction would
pass a newly opened handle directly. The type is rejected before execution:

```mylang
# doc: expect-error E_RECURSIVE_RECORD
record OpenChain:
    file: TextFile
    next: OpenChain?

func main() -> int:
    return 0
```

Copying a recursive value shares its boxes by reference count without walking
their bodies, and a nested write copies only the boxes along the path it writes.
A million-node chain whose nodes each hold a list can be copied and have its outer
fields and lists changed independently.

## Fixed arrays and enum tables

`T[]` is a growable array value. An array literal always creates a growable
array; an expected fixed type does not change its meaning. Construct a fixed
array explicitly as `FixedArray[T, N]([elements])`. Its length belongs to its
type, it has no `append`, and writes require a writable binding.

The separate enum-indexed table spelling remains `[Kind]T`. A table literal
needs exactly one entry per key case. Fixed arrays and tables have independent
value semantics; `replace(value, index, element)` returns a changed copy.

```mylang
# doc: expect 115
enum Status:
    ok
    missing
    failed

record Window:
    samples: FixedArray[int, 3]

func codes() -> [Status]int:
    return {Status.failed: 500, Status.ok: 200, Status.missing: 404}

func total(values: FixedArray[int, 3]) -> int:
    return values[0] + values[1] + values[2]

func main() -> int:
    mut window = Window(samples=FixedArray[int, 3]([1, 2, 3]))
    mut widened = replace(window.samples, 2, 10)
    mut table = codes()
    return total(window.samples) + total(widened) + table[Status.failed] - table[Status.missing]
```

This returns `115`. `window.samples` is unchanged by `replace`, and `codes` writes
`Status.failed` first while the table still reads back in declaration order.

### Writing array elements

An array element is written with the list spelling. `a[i] = v`, `a[i] += v`,
`a[i].field = v`, `grid[r][c] = v` and `window.samples[i] = v` all work on a
fixed array or table held in a variable, in a record field of one, or in a list
slot. The array is still a value: the write changes the variable it is spelled
through, and a copy taken earlier keeps what it held. `a[i] = v` is exactly
`a = replace(a, i, v)`, and the compiler writes that element in place, so it
costs one bounds check and one store however long the array is.

```mylang
# doc: expect 91234
record Point:
    x: int
    y: int

func main() -> int:
    mut counts: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
    mut before = counts
    for step in range(4):
        counts[step] = step + 1
    mut points: FixedArray[Point, 2] = FixedArray[Point, 2]([Point(x=0, y=0), Point(x=5, y=5)])
    points[1].y = 9
    return points[1].y * 10000 + counts[0] * 1000 + counts[1] * 100 + counts[2] * 10 + counts[3] + before[3] + points[0].y
```

This returns `91234`: every element of `counts` was written, `before` is the
copy taken before the loop and still holds zeros, and only `points[1]` changed.
An index is checked exactly as a read is (see negative indices below).
`points[1].y += 1` keeps its operator, as `point.y += 1` does, and a field of a
record holding an array, `window.samples[i] = v`, is written where
the field lives rather than by copying the array and the record.

### Negative indices

A fixed array counts a negative index from its end, exactly as a list does:
`a[-1]` is the last element and `a[-N]` the first, for a read, for every write
above and for `replace`. An index outside `-N <= i < N` traps `R_LIST_BOUNDS`,
reporting the index as written and the length, the same trap a list raises. An
enum table is indexed by its key and has no negative positions.

```mylang
# doc: expect 2144
func main() -> int:
    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
    mut back = -2
    values[-1] += 10
    values[back] = values[-4] * 30
    values[0], values[-3] = values[-3], values[0]
    return values[0] * 1000 + values[1] * 100 + values[2] + values[3]
```

This returns `2144`: `values[-1]` is the `4` that becomes `14`, `values[back]`
is `values[2]`, and the swap exchanges `values[0]` and `values[-3]`, which is
`values[1]`. The rule costs nothing where the compiler can see the index is
never negative — a constant (`a[-1]` is compiled as `a[N - 1]`), a `range` or
`enumerate` loop counter, a length — and a few branch-free instructions otherwise.

### Passing an array to be written

A parameter declared `mut values: FixedArray[T, N]` names the caller's array for the whole call, and
the caller marks the argument `mut`, as for a list. The callee's element writes
land in the caller's variable; nothing is copied in or out.

```mylang
# doc: expect 1023
func fill(mut values: FixedArray[int, 3], start: int) -> Unit:
    for index in range(3):
        values[index] = start + index

func main() -> int:
    mut values: FixedArray[int, 3] = FixedArray[int, 3]([0, 0, 0])
    fill(mut values, 10)
    fill(mut values, values[2] - 11)
    return values[0] * 1000 + values[1] * 10 + values[2]
```

This returns `1023`: the second call starts from the `12` the first one left.
The same rules apply to growable and fixed arrays. Writing through an ordinary
parameter is `E_IMMUTABLE`; declare both the parameter and the argument `mut`
when the caller should change. A writable local, field or indexed element can
be passed, including `fill(mut box.cells, 0)`. Whole-value reassignment through
the parameter updates the caller too, using an explicit constructor for fixed
arrays. To keep changes local, make an independent `mut` copy of the readonly
parameter. Unused mutation permission is allowed.

### Iterating a fixed array

`for x in a`, `for i, x in enumerate(a)` and `[f(x) for x in a]` walk a fixed
array from its first element to its last. The loop reads the array as it was
when the loop began, so element writes in the body do not change which values
the loop visits. An enum table is indexed by its key rather than walked.

```mylang
# doc: expect 124
func main() -> int:
    mut values: FixedArray[int, 4] = FixedArray[int, 4]([3, 1, 4, 1])
    mut total = 0
    for index, value in enumerate(values):
        total += index * value
        values[index] = 0
    mut doubled = [for value in values yield value * 2]
    return total * 10 + len(doubled) + doubled[0]
```

This returns `124`. The loop saw `3, 1, 4, 1` although it zeroed each element as
it went, so the weighted sum is 12, and the comprehension afterwards reads the
four zeros. That guarantee costs one copy of the array when the loop begins, and
only when the body writes the array: a loop over a local array its body never
writes reads the elements where they are.

## Related pages

- [Contracts](contracts.md#invariants) — an `@invariant` a record checks at every construction, `replace` and field write
- [Results and options](results-and-options.md) — `Result`, `Option` and their contextual constructors
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Value semantics](value-semantics.md) — how managed fields are shared and copied
- [Match expressions](match-expressions.md) — producing a value from a match
