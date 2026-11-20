# Records, unions and enums

`record` groups named fields into a value. `enum` declares a closed set of cases, with or without named payloads. Both are nominal: declarations with the same shape are different types. There is no inheritance and no open extension of a declaration's cases.

## Records

A record has typed fields, no methods and no implicit `self`: a function that works on a record takes it as an ordinary parameter. Moving, borrowing and `copy(value)` follow [value semantics](value-semantics.md).

```selka
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

`shift` changes its own mutable copy, so `origin.x` stays `1`.

An `@invariant(self.low <= self.high)` above the record is checked at every construction, `replace(...)` and field write; a violation traps `R_INVARIANT` ([contracts](contracts.md#invariants)).

## Identity and recursive records

There are no shared reference records: a `class` declaration is `E_VALUE_CLASS` and builtin `Cell` is `E_VALUE_CELL`. Use a recursive record or union for a finite tree, and a stable handle in `pool.Pool[T]` for a graph whose nodes need identity.

```selka
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

`b = a` copies, so writing `b` leaves `a` at `1`. A write to a copy nothing reads is accepted; `selka lint FILE --rule=dead-write` finds it ([lint](tooling/lint.md#writes-nothing-reads)).

## Named constructors

Call the type and name every field you supply. Order is free; expressions run once, in written order. A field needs a value unless its declaration gives a default; a missing one is `E_INCOMPLETE_CONSTRUCTION`. An empty record declares `pass` and is built with no arguments. Record field labels are always required.

```selka
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

### Type names the language already uses

A record, enum, union, domain, resource or alias cannot be named like a builtin type: `Unit`, `int`, or the checker's internal names (`unit`, `file`, `text_file`). The prelude's library types (`Stream`, `Option`, `Filesystem`) are not builtin: a module may declare its own of that name. A builtin name is `E_BUILTIN_TYPE_NAME`; `selka fix` renames the type to the module name plus the builtin's (`ShapeUnit` for a `Unit` in `kicad/shape.selka`) and every qualified reference to it.

```selka
# doc: expect-error E_BUILTIN_TYPE_NAME
enum Unit:
    farad
    henry

func main() -> int:
    return 0
```

## Field defaults and functional update

A field may default to an integer, Boolean, `None`, string literal or negated integer literal (the literals a function parameter accepts), or to an empty collection `[]`, `{}`, `b""` or `set()`. An omitted field gets the default; each construction makes its own collection. A required field may follow a defaulted one. A non-empty collection (`[1]`, `{"a": 1}`, `set(xs)`) is `E_DEFAULT_ARGUMENT`, and so is an empty collection as a function parameter default.

```selka
# doc: expect 12
import strings

record Config:
    retries: int = 3
    verbose: bool = False
    label: str = "auto"

func main() -> int:
    mut base = Config(verbose=True)
    mut fixed = Config(retries=7)
    if base.verbose and strings.char_count(base.label) == 4:
        return base.retries + fixed.retries + 2
    return 0
```

`replace(record, field=value, ...)` returns a copy with only the named fields changed; the base is untouched and is evaluated before the values. An unknown field is `E_UNKNOWN_FIELD` and a repeated one `E_DUPLICATE_FIELD`. (`replace(list, index, value)` is a different, positional form.)

```selka
# doc: expect 7
record Settings:
    retries: int = 3
    verbose: bool = False

func main() -> int:
    mut base = Settings(verbose=True)
    mut changed = replace(base, retries=5)
    return changed.retries + 2
```

### Enum and record defaults

A field of enum or record type may default to:

- an enum case without a payload: `kind: Kind = Kind.ground`;
- a case whose payload fields are such defaults: `mark: Kind = Kind.tagged(code=7)`;
- a record constructor whose arguments are such defaults: `turn: Turn = Turn()` or `far: Turn = Turn(angle=90)`.

Arguments may be scalar literals, empty collections or further constructors, to any depth. Each construction builds the value afresh, and a module that builds the record needs no import of the enum or record. A default is a constant, never a call: `pick(2)` is `E_DEFAULT_ARGUMENT`, an undeclared case is `E_UNKNOWN_VARIANT`. A constructor default must be buildable: `inner: Inner = Inner()` is `E_INCOMPLETE_CONSTRUCTION` when `Inner` has a field without a default (`selka fix` drops that default). Function parameters and variant-case fields keep scalar defaults only ([functions](functions.md#keyword-arguments-and-defaults)).

```selka
# doc: expect 1307
enum Kind:
    ground
    supply
    tagged(code: int)

record Turn:
    angle: int = 0
    names: str[] = []

record Rail:
    net: str
    kind: Kind = Kind.ground
    mark: Kind = Kind.tagged(code=7)
    turn: Turn = Turn()
    far: Turn = Turn(angle=1200)

func code_of(kind: Kind) -> int:
    match kind:
        case tagged(code=number):
            return number
        case _:
            return 0

func main() -> int:
    mut first = Rail(net="a")
    const second = Rail(net="b", kind=Kind.supply)
    append(mut first.turn.names, "x")
    if first.kind == Kind.ground and second.kind == Kind.supply:
        return first.far.angle + code_of(first.mark) + len(first.turn.names) * 100 + len(second.turn.names)
    return 1
```

### Constant defaults

A field may default to a non-empty bytes literal (`net: bytes = b"GND"`) or a constant of the record's module or an imported one (`limits.MAX`), or its negation: `limit: int = LIMIT`, `below: int = -LIMIT`. A `float` constant may hold NaN or an infinity (`top: float = INF`); a call such as `math.nan()` is refused, so bind it to a constant and name that.

The default is read in the declaring module, so the constant may be private and the constructing module needs no import of it.

```selka
# doc: expect 2630
const LIMIT: int = 100
const NAN: float = 0.0 / 0.0
const INF: float = 1.0 / 0.0

record Probe:
    net: bytes = b"GND"
    limit: int = LIMIT
    unset: float = NAN
    top: float = INF
    id: int

func main() -> int:
    const probe = Probe(id=5)
    const named = Probe(id=1, net=b"VCC", limit=2)
    if probe.unset == probe.unset or not (probe.top > 1.0e300):
        return 1
    return probe.limit + len(probe.net) * 10 + probe.id * 100 + named.limit * 1000
```

## Linear records

`@linear` above a `record` makes every value of it an owner that must be consumed exactly once on every path before its scope ends: a connection, a statement, a lock. A record, option, Result or union that holds one is linear too.

An owner is consumed in four ways, and no other:

- given to an `own` parameter, written `own` at the call: `close(own conn)`;
- returned, bare or inside a returned value: `return conn`, `return Some(own conn)`;
- moved into another owner: `const next = own conn`, `Pair(left=own conn, right=1)`;
- ended by reading one of its fields with `own`: `own conn.db`. The field's value must be kept (`const db = own conn.db`, or a return): a discard `_ = own conn.db` of a list or text field is `E_OWN_MARKER`.

A `match mut` lends the owner to its arms and does not end it. Inside an arm the payload binding names the payload in place: read it, write it, or lend it to a `mut` parameter. `own held`, `const other = held`, a store or `return held` is `E_LINEAR_USE`, and a program whose only use of an owner is a `match mut` is `E_LINEAR_UNCONSUMED`.

```selka
# doc: expect 42
@linear
record Lease:
    id: int


func acquire(id: int) -> Lease:
    return Lease(id=id)


func release(own lease: Lease) -> int:
    return own lease.id


func renew(mut lease: Lease):
    lease.id = lease.id + 1


func main() -> int:
    mut lease = acquire(40)
    renew(mut lease)
    renew(mut lease)
    return release(own lease)
```

`on fail: close(own conn)` after the opening line closes the owner on every failure exit that follows, so a `try` between open and close is safe ([cleanup on failure](results-and-options.md#cleanup-on-failure)).

A parameter says what the callee does with the caller's owner:

| Parameter | The callee may |
|---|---|
| `own p: T` | consume it |
| `mut p: T` | borrow it exclusively: write or replace it |
| `p: T` | borrow it read-only for the call; the caller writes no marker and still consumes the owner |

Through a plain parameter the callee reads the owner and its fields and lends it to another plain parameter. It cannot move it (`own`, a binding, a store, a return, a `fail`, a constructor input), end it with `own conn.db`, discard it, write or replace it, or lend it `mut` or to a `match mut`: each is `E_LINEAR_USE`. A plain parameter takes a named owner or a field of one; a value made for the call (`peek(open(host))`), an argument written `own` and a call through a function value are refused. The loan lasts for the whole call: `look_close(conn, own conn)` and `look_bump(conn, mut conn)` are `E_LINEAR_USE`, two loans of one owner are fine. A generic function still takes a `@linear` parameter `own` or `mut`.

```selka
# doc: expect 42
@linear
record Conn:
    id: int
    uses: int = 0


func peek(conn: Conn) -> int:
    return conn.id


func peek_twice(conn: Conn) -> int:
    return peek(conn) + peek(conn) - conn.id


func touch(mut conn: Conn):
    conn.uses = conn.uses + 1


func close(own conn: Conn) -> int:
    return own conn.uses


func main(out: Stream) -> int:
    mut conn = Conn(id=41)
    const seen = peek(conn)
    touch(mut conn)
    const again = peek_twice(conn)
    print(out, seen + close(own conn) + again - 41)
    return 0
```

| Code | When |
|---|---|
| `E_LINEAR_USE` | `copy`, `take`, `exchange`, `_ = own conn`; a list, dictionary, set or fixed array of linear values; a generic instantiated with one; a `parallel` task argument or result |
| `E_LINEAR_UNCONSUMED` | an owner left unconsumed on some path, at the end of that path |
| `E_LINEAR_CONSUMED` | a use after consumption |

`unwrap_or` on an option of a `@linear` value is `E_LINEAR_USE`: the default is made before the option is looked at, so it would be dropped unconsumed. Take the payload with `match own` and make the default in the `None` arm.

```selka
# doc: expect 7
@linear
record Lease:
    id: int


func current(held: bool) -> Lease?:
    if held:
        return Some(Lease(id=7))
    return None


func release(own lease: Lease) -> int:
    return own lease.id


func main() -> int:
    match own current(True):
        case Some(lease):
            return release(own lease)
        case None:
            return release(Lease(id=0))
```

An early `return`, a `fail`, a `try` whose error path returns, a `break` and a `continue` must each find the owners of the scopes they leave consumed, and the arms of an `if` or `match` must agree: an owner consumed in one arm only, or in the right operand of `and` or `or`, is refused. An owner declared before a loop can be consumed inside it only on a path that leaves the function; a loop that goes on after consuming it is `E_LINEAR_USE`. Consume it before or after the loop, or declare it inside the body.

```selka
# doc: expect-error E_LINEAR_USE
@linear
record Lease:
    id: int


func release(own lease: Lease) -> int:
    return own lease.id


func drain(own lease: Lease) -> int:
    for i in range(3):
        _ = release(own lease)
    return 0


func main() -> int:
    return drain(Lease(id=5))
```

Nothing is closed at run time on your behalf, and a trap ends the process without consuming anything. `@linear` may stand beside `@invariant`. A record holding a C handle (`extern type`) with a closing function that ends it with `own record.handle` is the pattern in [opaque handles](c-ffi.md#opaque-handles).

## Sealed records

`@sealed` above a `record` lets only its own module build or change one. Other modules read its fields and move, copy, compare, sort, print and key a dictionary with its values, but make one only by calling a function of the declaring module. With an `@invariant` beside it, every value outside was checked when the module built or last changed it.

```selka
# doc: project sealed-markup
# doc: file markup.selka
# doc: check
@sealed
public record Markup:
    html: str


func escape_char(c: str) -> str:
    match c:
        case "<":
            return "&lt;"
        case ">":
            return "&gt;"
        case "&":
            return "&amp;"
        case _:
            return copy(c)


public func escape(text: str) -> Markup:
    mut out = ""
    for i in range(len(text)):
        out += escape_char(text[i:i + 1])
    return Markup(html=own out)


public func join(a: Markup, b: Markup) -> Markup:
    return Markup(html=a.html + b.html)
```

```selka
# doc: project sealed-markup
# doc: file main.selka
# doc: expect 25
import markup

func main() -> int:
    const page = markup.join(markup.escape("<b>"), markup.escape("a&b"))
    return len(page.html)
```

In another module `markup.Markup(html="<script>")` and `page.html = "<script>"` are `E_SEALED_RECORD`, and the message names a function of the module that returns one. The declaring module and its [test file](tooling/guest-tests.md#test-files-and-their-modules) are exempt. Refused elsewhere:

- a constructor call, also through a facade's re-exported name, and `R()` from the record's defaults;
- a field default in another module that builds one (`tok: seal.Token = seal.Token()`);
- every write to a field: `r.f = v`, `r.f += v`, `h.r.f = v`, through a `mut` local or parameter, a list or fixed-array element or a `match mut` binding; `append(mut r.items, v)` or any other `mut r.f` argument; `exchange(mut r.f, v)` and `take(mut r.f)`. A `match mut` whose place passes through a field is refused whatever its arms do;
- `replace(r, f=v)`, and `take(mut place)` of a whole value, which leaves one built from its defaults. `exchange(mut place, value)` with a value the module made is allowed, and so is `take` of an option or a list of them;
- a generic function of another module that writes its field through a `field(...)` requirement, at the instance;
- a test parameter that holds one anywhere (a field, an element, a key, an option or a case), since the runner would build it;
- on a record that is also [`@linear`](#linear-records), `own r.field`: outside its module such a value ends only by being given to an `own` parameter or returned, so a protocol (`begin` makes it, `commit(own s)` ends it) cannot be skipped.

`copy(r)` is allowed. `@sealed` attaches to a `record`, generic or not; elsewhere it is `E_ATTRIBUTE_TARGET`. It is part of the module's interface (`selka interfaces show` prints it).

## Tagged unions

`enum` declares a closed set of cases, each with no payload or with named fields: `number(value: int)`, `point(x: int, y: int)`. Construct fields by name and bind them by name in a `match`. Matching checks coverage, so adding a case makes incomplete matches fail at compile time. A final `case _` covers the rest, subject to the handling of [checked results](results-and-options.md#checked-results).

```selka
# doc: expect 21
import strings

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
        case heartbeat:
            return 1
        case count(value=n):
            return n
        case message(value=text):
            return strings.char_count(text)

func urgency(level: Level) -> int:
    match level:
        case failure:
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

## Payload variant construction

`Type.case` constructs a payload-free case; `Type.case(value=expression)` one whose field is `value`. Every payload argument names its field and evaluates once, in written order. `case name(value=binding)` binds the field, `value=_` discards it, and nested patterns may inspect variants inside payloads. A local that shadows the type name keeps ordinary member resolution, and a name that is not a declared case stays an ordinary call.

```selka
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
        case empty:
            return 0
        case radius(value=r):
            return r * r
        case point(value=_):
            return 1

func main() -> int:
    mut shapes = [Shape.radius(value=4), Shape.point(value=Point(x=1, y=2)), Shape.empty]
    mut total = 0
    for shape in shapes:
        total = total + area(shape)
    mut taken: Slot[int] = Slot.filled(value=9)
    match taken:
        case empty:
            return total
        case filled(value=value):
            return total + value
```

## Named variant case fields

A case may declare named fields, `case(f1: T1, f2: T2 = default)`. Required fields come first; defaults are the same immutable literals as record fields. Construct with `Type.case(f1=value, f2=other)`; omitted defaults are filled in. A single payload is a named field such as `item(value: T)`.

Patterns name the fields too: `case name(f1=first, f2=_)`. A missing, extra, unknown or duplicate field is a located error. Patterns bind read-only locals and must cover every value. `case _` over a case with a `Result` field is still `E_RESULT_DISCARD`: that field needs its own arm.

```selka
# doc: expect 10
import strings

record Span:
    line: int
    col: int


enum Node:
    form(items: Node[], span: Span)
    atom(text: str, span: Span)
    decimal(value: float, span: Span, literal: str? = None)


func width(node: Node) -> int:
    match node:
        case form(items=items, span=_):
            return len(items)
        case atom(text=text, span=_):
            return strings.char_count(text)
        case decimal(value=_, span=_, literal=literal):
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

Arms can list several cases, and `..` ends a pattern that ignores the rest ([alternatives and the rest marker](match-expressions.md#alternatives-and-the-rest-marker)). To ask only which case a value holds, write `value is text` or `if value is list(items):` ([testing one case with `is`](match-expressions.md#testing-one-case-with-is)).

### Binding a field under its own name

A pattern field written `name=name` may drop its label: `case atom(text, span=_)` is `case atom(text=text, span=_)`. The bare name is the field's own, not a position, so `case form(span, items)` binds the same fields in any order. A field bound to a different name keeps its label (`literal=text`).

| Written | Result |
|---|---|
| a bare name that no field has | `E_FRONTEND_VARIANT` (`E_NAMED_PATTERN` for an enum of another module); `selka fix` writes the label |
| `field=field` | `selka lint` reports `L_PATTERN_SHORTHAND`; `selka fix` drops the label |
| a bare name in a nested pattern | `E_NAMED_PATTERN`: write `case Some(item(value=value, note=note))` |

```selka
# doc: expect 6
enum Shape:
    rect(width: int, height: int)
    circle(radius: int)


func area(shape: Shape) -> int:
    match shape:
        case rect(height, width):
            return width * height
        case circle(radius):
            return radius * radius * 3


func main() -> int:
    return area(Shape.rect(width=2, height=3))
```

## Case names

`case_name(value)` is the case's identifier as a `str`: `case_name(Status.missing)` is `"missing"`, and a payload is ignored. `Status.cases()` is every case in declaration order and `Status.from_name(text)` is the case a `str` or `bytes` name spells, or `None`; both are for an enum none of whose cases carries a payload. A case added to the enum is in all three at once.

`str(value)` of an enum is `E_TEXT_CONVERSION`: printing writes `Kind.case`, and `case_name` answers the bare identifier. A case called `cases` or `from_name` keeps its case. A name with a hyphen or other punctuation cannot be an identifier, so map it by hand.

```selka
# doc: expect Some(Status.missing) None
# doc: expect ok
# doc: expect failed
enum Status:
    ok
    missing
    failed

func main(out: Stream) -> int:
    print(out, Status.from_name("missing"), Status.from_name("Missing"))
    for status in Status.cases():
        if status != Status.missing:
            print(out, case_name(status))
    return 0
```

## Recursive payloads

A record or union can refer to itself, directly or through another value type, when there is a way to finish the value: an optional field has `None`, or a union has a case with no recursive payload. Recursive values move on assignment; `copy(value)` makes an independent one.

```selka
# doc: expect 42
record Binary:
    left: Expr
    right: Expr

enum Expr:
    number(value: int)
    binary(value: Binary)

func total(expr: Expr) -> int:
    match expr:
        case number(value=n):
            return n
        case binary(value=node):
            return total(node.left) + total(node.right)

func main() -> int:
    mut tree: Expr = Expr.binary(value=Binary(left=Expr.number(value=20), right=Expr.number(value=22)))
    return total(tree)
```

`record Loop: next: Loop` is `E_RECURSIVE_RECORD`, since it has no finite value. Nested recursive values compare, hash, print and cross typed JSON boundaries as values; printing stops with `...` at a depth cap.

A recursive value cannot own a resource, an unhandled result or a capability, including builtin `File` and `TextFile` fields:

```selka
# doc: expect-error E_RECURSIVE_RECORD
record OpenChain:
    file: TextFile
    next: OpenChain?

func main() -> int:
    return 0
```

Moving a recursive value transfers its boxes and `copy(value)` walks the contents, so copy cost grows with the structure: borrow a subtree that only needs reading.

## Fixed arrays and enum tables

`T[]` is a growable array; an array literal is always growable, whatever type is expected. Build a fixed array as `FixedArray[T, N]([elements])`: its length belongs to its type, it has no `append`, and writes need a writable binding. The enum-indexed table is `[Kind]T`, and a table literal needs exactly one entry per key case. Both have value semantics; `replace(value, index, element)` returns a changed copy.

```selka
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

### Writing array elements

`a[i] = v`, `a[i] += v`, `a[i].field = v`, `grid[r][c] = v` and `window.samples[i] = v` work on a fixed array or table held in a variable, a record field or a list slot. The array is a value: the write changes the variable it is spelled through, and a copy taken earlier keeps what it held. `a[i] = v` means `a = replace(a, i, v)`.

```selka
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

### Negative indices

A fixed-array index must satisfy `0 <= i < N`, for reads, writes and `replace`; a computed negative index traps `R_LIST_BOUNDS` with the index and the length, as for lists. A constant negative position is `E_NEGATIVE_INDEX_REMOVED`, and `selka fix` rewrites a certain local-base `values[-1]` to `values[len(values) - 1]`. An enum table is indexed by its key and has no positional indexes.

### Passing an array to be written

A parameter `mut values: FixedArray[T, N]` names the caller's array for the whole call, and the caller marks the argument `mut`, as for a list. The callee's writes, whole-value reassignment included, land in the caller's variable; nothing is copied. A writable local, field or indexed element can be passed (`fill(mut box.cells, 0)`). Writing through an ordinary parameter is `E_IMMUTABLE`; make a `mut` copy to keep changes local. An unused `mut` is allowed.

```selka
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

### Iterating a fixed array

`for x in a` and `for i, x in enumerate(a)` walk a fixed array from first to last. The loop reads the array as it was when it began, so element writes in the body do not change which values it visits. An enum table is indexed by its key rather than walked.

```selka
# doc: expect 124
func main() -> int:
    mut values: FixedArray[int, 4] = FixedArray[int, 4]([3, 1, 4, 1])
    mut total = 0
    for index, value in enumerate(values):
        total += index * value
        values[index] = 0
    mut doubled: int[] = []
    for value in values:
        append(mut doubled, value * 2)
    return total * 10 + len(doubled) + doubled[0]
```

## Related pages

[Contracts](contracts.md#invariants), [Results and options](results-and-options.md), [Python-style application code](python-syntax.md), [Value semantics](value-semantics.md), [Match expressions](match-expressions.md).

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/records-and-unions.md).
