# Records, unions and enums

`record` groups named fields into a value. `enum` declares a closed set of
payload-free or named-payload alternatives. Both are nominal: declarations with
the same shape remain different types. Rare nominal `result` declarations keep
their existing identity and handling rules. There is no inheritance or open
extension of a declaration's cases.

## Records

`record` declares a value record. Every field carries a type annotation, and the record
has no methods, no inheritance and no implicit `self` — a function that operates on a
record takes it as an ordinary parameter. A record with managed fields such as
`list` and `dict` moves on assignment and is borrowed by an ordinary parameter.
Use `copy(value)` when an independent owned value is needed. Ordinary
field assignment updates a record local or a record held in a list slot.

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

This returns `14`. `shift` updates its own mutable local copy, so `origin.x` is still `1`
afterwards and only `moved.x` is `11`. A record that holds a list, dictionary or
string is a value too; see [value semantics](value-semantics.md) for ownership,
borrowing and explicit copies of managed fields.

A rule every value of a record must satisfy is written as an invariant above it,
such as `@invariant(self.low <= self.high)`. It is checked at every
construction, `replace(...)` and field write, and a violation traps
`R_INVARIANT`; see [contracts](contracts.md#invariants).

## Identity and recursive records

Use a recursive record or union for a finite tree. Use a stable handle in
`pool.Pool[T]` for a graph whose nodes need identity. There are no shared
reference records: a `class` declaration is rejected with `E_VALUE_CLASS` and
builtin `Cell` with `E_VALUE_CELL`.

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

This returns `2`: writing `b` leaves `a` at `1`, then the marked `mut` call
changes `a`. Recursive value fields that would be infinitely large are stored
in immutable boxes; writing a nested path copies its boxes. A write to a copy
that nothing reads afterwards is legal and changes nothing; no error reports it.
The lint rule `dead-write` finds such writes, and is off unless asked for:
`selka lint FILE --rule=dead-write` (see [lint](tooling/lint.md#writes-nothing-reads)).

## Named constructors

Construct a record by calling its type and naming every supplied field.
Fields may appear in any order; expressions evaluate once in written order.
Every field needs a value unless its declaration provides a default. Missing
required fields report `E_INCOMPLETE_CONSTRUCTION`. An empty record declares
`pass` and is constructed with no arguments.

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

This returns `321`. Ordinary functions may also have positional parameters;
record field labels are always required.

### Type names the language already uses

A record, enum, union, domain, resource or alias cannot be named like a builtin type: `Unit` and `int`, the two builtin
spellings that are plain names, and the checker's internal type names (`unit`, `file`, `text_file`). The fixed-width integers
(`i8` to `u64`), `bool` and the other keywords are reserved words, so the parser already refuses them as a name. The names of the
prelude's library types (`Stream`, `Option`, `Filesystem`) are not builtin: a module may declare a type of the same name and its own
uses read that type. A declaration under a builtin name is refused with `E_BUILTIN_TYPE_NAME` at the name. Before it was
accepted and then could be neither built nor read in its own module, because the builtin won the lookup: the Zig `Unit` that three
ports declared is the usual case. `selka fix` renames the type to the module's own name and the builtin's (`ShapeUnit` for a `Unit`
in `kicad/shape.selka`, with a digit if that is taken) and rewrites every qualified reference to it in the modules that import it
(`shape.Unit` and `sh.Unit` for `import kicad.shape as sh`). A bare `Unit` inside the declaring module already meant the builtin, so
it is left as written, unless the module builds or reads the type itself (`Unit(number=1)`, `Unit.case`): that cannot be the builtin, so
the module means its own type by the name and the repair renames each `Unit` in it.

```selka
# doc: expect-error E_BUILTIN_TYPE_NAME
enum Unit:
    farad
    henry

func main() -> int:
    return 0
```

## Field defaults and functional update

A field may declare an immutable scalar default after `=`, exactly the literals a
function parameter accepts: an integer, Boolean, `None`, string literal, or a
negated integer literal. A constructor call that omits such a field materializes the
declared default, so `Config(verbose=True)` fills in `retries`. A record is built by
field name, so a required field may follow a defaulted one (a function parameter list
keeps its rule: required parameters first). Enum-keyed table literals are unaffected:
every key is still required.

A record field may also default to an empty collection: `[]`, `{}`, `b""` or `set()`.
Each construction that omits the field makes its own empty value, so two records never
share a collection and a default cannot be changed through another record. A non-empty
list or dictionary (`[1]`, `{"a": 1}`, `set(xs)`) is still refused with
`E_DEFAULT_ARGUMENT`, and so is an empty collection as a function parameter default. A field
of an enum or record type may default to a case or a constructor; see
[Enum and record defaults](#enum-and-record-defaults), and a field may default to a bytes
literal or a module constant; see [Constant defaults](#constant-defaults).

```selka
# doc: expect 10
record Box:
    items: int[] = []
    label: str = "box"


func main() -> int:
    mut first = Box()
    mut second = Box()
    append(mut first.items, 7)
    return len(first.items) * 10 + len(second.items)
```

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

This returns `12`: `base.retries` is the declared `3`, `fixed.retries` is the
explicit `7`, and `base.label` defaults to `"auto"`.

`replace(record, field=value, …)` is the functional update: it returns a copy of the
record with only the named fields changed and every other field preserved, leaving the
base value untouched. The base is evaluated before the values, the result is a fresh
record value, a field name that does not exist is `E_UNKNOWN_FIELD`, and a repeated one
is `E_DUPLICATE_FIELD`. The positional three-argument `replace(list, index, value)`
intrinsic is unchanged; the named form is recognized by its first argument separator.

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

This returns `7`. `changed` keeps `verbose` from `base` and `base.retries` is still `3`.

### Enum and record defaults

A record field may also default to an enum case or a record value, so a new field of such a
type keeps every existing constructor valid. The default is one of:

- an enum case without a payload: `kind: Kind = Kind.ground`;
- an enum case whose payload fields are such defaults: `mark: Kind = Kind.tagged(code=7)`;
- a record constructor whose arguments are such defaults: `turn: Turn = Turn()` (every field of
  `Turn` has a default of its own) or `far: Turn = Turn(angle=90)`.

The arguments may be scalar literals, empty collections or further constructors, to any depth.
Each construction that omits the field builds the value afresh, as it does for an empty
collection, so two records never share the list inside a default record. A default is resolved
where it is declared: a module that constructs the record needs no import of the enum or record
the default names, and a rename in the declaring module is reported at the default.

A default is a constant, never a call that runs code. `pick(2)` is refused with `E_DEFAULT_ARGUMENT`,
and a case the enum does not declare with `E_UNKNOWN_VARIANT`. The checker confirms the names where a
constructor first builds the default, as it does a scalar default's type; the exception is a constructor
that cannot build its record, which is refused where it is written (see
[A default that cannot be built](#a-default-that-cannot-be-built)). Function parameters and the fields of
a variant case keep scalar defaults only (see
[Functions and calls](functions.md#keyword-arguments-and-defaults)).

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

This returns `1307`: `first.far.angle` is `1200`, the `tagged` mark is `7`, and `first.turn.names` holds one
name while `second.turn.names`, built by its own construction, is empty.

```selka
# doc: expect-error E_DEFAULT_ARGUMENT
func pick(n: int) -> int:
    return n

record Turn:
    angle: int = 0

record Rail:
    turn: Turn = Turn(angle=pick(2))

func main() -> int:
    return Rail().turn.angle
```

### Constant defaults

A record field may default to a non-empty bytes literal or to a module constant, so the Zig
`net: []const u8 = "GND"` and `clearance: f64 = default_clearance_mm` keep their defaults:

- a bytes literal: `net: bytes = b"GND"` (a `str` literal was already accepted);
- a module constant of the record's own module, or of an imported one (`limits.MAX`), or its
  negation: `limit: int = LIMIT`, `below: int = -LIMIT`, `shape: bytes = SHAPE`;
- NaN and the infinities, which a `float` constant may hold (`const NAN: float = 0.0 / 0.0`,
  `const INF: float = 1.0 / 0.0`): `top: float = INF`, `bottom: float = -INF`. A call such as
  `math.nan()` is still a call and is refused; bind it to a module constant and name that.

A default is a constant of the module that declares the record, and it is read there: a function that
constructs the record sees none of its own locals in the default, and a module that constructs it needs
no import of the constant, which may be private. A literal or constant default is a static value, as
`""` and `[]` are: reading it allocates nothing, and a record that stores it holds the same static
data a literal written at the construction would.

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

This returns `2630`: the defaults give `probe` a limit of `100` and the net `GND`, and `named` overrides its limit with `2`.

### A default that cannot be built

A default that constructs a record must be able to: `inner: Inner = Inner()` is refused at the
declaration, with `E_INCOMPLETE_CONSTRUCTION`, when `Inner` has a field without a default and the
default does not name it. The repair `selka fix` applies is to drop the default, which is what the
program did before: a construction that left the field out was refused, and one that gave it never
used the default.

```selka
# doc: expect-error E_INCOMPLETE_CONSTRUCTION
record Inner:
    net: bytes
    gain: int = 1

record Outer:
    inner: Inner = Inner()
    z: int = 1

func main() -> int:
    return 0
```

## Linear records

`@linear` above a `record` makes every value of it an owner that must be consumed, exactly
once, on every path before its scope ends. It is how a library hands out something that
must be closed: a database connection, a prepared statement, a lock. The record and every
record, option, Result or union that holds one are linear.

An owner is consumed in four ways, and in no other:

- given to an `own` parameter, written `own` at the call: `close(own conn)`;
- returned, bare or inside a returned value: `return conn`, `return Some(own conn)`;
- moved into another owner: `const next = own conn`, `Pair(left=own conn, right=1)`;
- ended by reading one of its fields with `own`: `own conn.db`. This consumes the whole
  record and is how the closing function itself ends it.

A `match mut` is not one of them: it lends the owner to its arms and does not end it. Inside an arm the payload's
binding is a name for the payload in place: read its fields, write them, or lend it to a `mut` parameter
(`renew(mut held)`); `own held`, `const other = held`, a store of it or `return held` is refused (`E_LINEAR_USE`). After
the match the owner is still to be consumed, on every path out of the arms too, so a program whose only use of an owner
is a `match mut` is refused (`E_LINEAR_UNCONSUMED`, whose message lists the four ways). Until 13 November a `match mut`
counted as a consumption, which let such a program drop its owner unconsumed.

```selka
# doc: expect 41
@linear
record Lease:
    id: int


enum Slot:
    busy(held: Lease)
    idle


func renew(mut lease: Lease):
    lease.id = lease.id + 1


func release(own slot: Slot) -> int:
    match own slot:
        case busy(held):
            return own held.id
        case idle:
            return 0


func main(out: Stream) -> int:
    mut slot = Slot.busy(held=Lease(id=40))
    match mut slot:
        case busy(held):
            renew(mut held)
        case idle:
            pass
    print(out, release(own slot))
    return 0
```

The one field read ends the owner where the field's value is kept: `const db = own conn.db`, or a return. A discard
`_ = own conn.db` of a list or text field is not that, because a discard only reads: it is refused (`E_OWN_MARKER`), and
`selka fix` does not remove its `own`, which would leave the owner unconsumed.

```selka
# doc: expect-error E_OWN_MARKER
@linear
record Ledger:
    undo: int[]
    weight: int


func rollback(own ledger: Ledger):
    _ = own ledger.undo


func main() -> int:
    rollback(Ledger(undo=[], weight=0))
    return 0
```

A `try` between opening an owner and closing it would leave the owner unconsumed on its error
path; `on fail: close(own conn)` after the opening line runs the close on every failure exit
that follows, so the steps need no helper ([cleanup on failure](results-and-options.md#cleanup-on-failure)).

A field read without `own` (`conn.db`) borrows the owner. A parameter says what the callee does with the caller's
owner: `own` consumes it, `mut` is an exclusive borrow that may write or replace it, and a plain parameter borrows it
read-only for the call (decision LINEAR-LEND, 18 November). The caller writes no marker for a plain parameter, keeps
the owner and still consumes it on every path; the callee reads the owner and its fields and lends it on to another
plain parameter, and owes nothing for it. Through a plain parameter the callee cannot move the owner (`own`, a binding,
a store, a return, a `fail`, a constructor input), end it with `own conn.db`, discard it, write a field of it, replace
it, or lend it `mut` or to a `match mut`: each is `E_LINEAR_USE`, whose message names the loan and says that `own`
takes the value. A plain parameter borrows a named owner or a field of one, of its own type; a value made for the call
(`peek(open(host))`), an argument written `own` and a call through a function value are refused, because the value
would be dropped unconsumed. The loan lasts for the whole call, so the same call cannot also give the owner, a field of
it or a record that holds it with `own`, or lend an overlapping place `mut` (`look_close(conn, own conn)`,
`look_bump(conn, mut conn)`): `E_LINEAR_USE`; two loans of one owner in a call are fine. A generic function still takes
a `@linear` parameter `own` or `mut`.

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

`copy`, `take`, `exchange`, `_ = own conn`, a list, dictionary, set or fixed array of linear values, a generic
instantiated with one, and a `parallel` task argument or result are refused (`E_LINEAR_USE`). An owner left
unconsumed on some path is `E_LINEAR_UNCONSUMED` at the end of that path, and a use after consumption is
`E_LINEAR_CONSUMED`.

`unwrap_or` is refused for an option of a `@linear` value too, whether the option is a call's result or a local:
the default is made before the option is looked at, so it would be dropped unconsumed whenever the payload is there.
Take the payload with `match own` and make the default in the `None` arm, where only one owner exists on each path.

```selka
# doc: expect-error E_LINEAR_USE
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
    const lease = current(True).unwrap_or(Lease(id=0))
    return release(own lease)
```

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

Paths are checked as the checker follows them: an early `return`, a `fail`, a `try` whose
error path returns, a `break` or a `continue` must each find every owner of the scopes it
leaves consumed, and the arms of an `if` or a `match` must agree, so an owner consumed in
one arm only, or inside the right operand of `and` or `or`, is refused. An owner declared
before a loop can be consumed inside it only on a path that leaves the function, such as a
`return`. A loop that goes on after consuming it, by reaching the end of the body, a
`continue` or a `break`, is refused with `E_LINEAR_USE`: the next pass, or the code after the
loop, would find the owner gone. Consume it before or after the loop, or declare it inside
the body.

```selka
# doc: expect 5
@linear
record Lease:
    id: int


func release(own lease: Lease) -> int:
    return own lease.id


func find(own lease: Lease, limit: int) -> int:
    for i in range(10):
        if i == limit:
            return release(own lease)
    return release(own lease)


func main() -> int:
    return find(Lease(id=5), 3)
```

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

```selka
# doc: expect-error E_LINEAR_UNCONSUMED
@linear
record Lease:
    id: int


func release(own lease: Lease) -> int:
    return own lease.id


func check(flag: bool) -> int:
    const lease = Lease(id=1)
    if flag:
        return 0
    return release(own lease)


func main() -> int:
    return check(True)
```

A linear record is an ordinary record to the compiler's back end: the rules are checked
before code is generated, and nothing is closed at run time on your behalf. A trap ends the
process without consuming anything, as it does for every owner. `@linear` may stand beside
`@invariant`, and on a record that also holds a runtime resource (which the runtime closes
when its owner ends) it adds the obligation. A record that holds a C handle
(`extern type`) and a closing function that ends it with `own record.handle` is the pattern
`docs/c-ffi.md#opaque-handles` describes.

## Sealed records

`@sealed` above a `record` lets only its own module build one or change one. Another module reads its fields, and
moves, copies, compares, sorts, prints and keys a dictionary with its values, but makes one only by calling a function of
the declaring module. So a record that must always satisfy a rule (text already escaped, a count already checked, a state
only a transition may produce) keeps the rule in one place: the functions of its module. With an `@invariant` beside it,
every value outside the module was checked when the module built it or last changed it.

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

This returns `25`: `&lt;b&gt;` and `a&amp;b` joined. In another module `markup.Markup(html="<script>")` is refused, and
so is `page.html = "<script>"`:

```selka
# doc: project sealed-forged
# doc: file markup.selka
@sealed
public record Markup:
    html: str
```

```selka
# doc: project sealed-forged
# doc: file main.selka
# doc: expect-error E_SEALED_RECORD
import markup

func main() -> int:
    const page = markup.Markup(html="<script>")
    return len(page.html)
```

Outside the declaring module and its test file (the module named `<module>_test` that no module imports, the same file
that may call the module's private functions; [test files](tooling/guest-tests.md#test-files-and-their-modules)), these
are refused with `E_SEALED_RECORD`, and the message names a function of the module that returns one when there is one:

- a constructor call, also through a facade's re-exported name, and `R()` from the record's defaults;
- a field default written in another module that builds one (`tok: seal.Token = seal.Token()`), at its declaration. A
  default written in the declaring module (`tok: Token = Token()` in a record of `seal`) builds one wherever the record
  that holds it is built;
- every write to one of its fields: `r.f = v`, `r.f += v`, `h.r.f = v`, through a `mut` local or parameter, a list or
  fixed-array element, a `match mut` binding, `append(mut r.items, v)` and any other `mut r.f` argument, and
  `exchange(mut r.f, v)` or `take(mut r.f)`. A `match mut` whose place passes through one of its fields (`match mut
  r.mode:`, `match mut h.r.mode:`, `match mut xs[0].mode:`) is refused whatever its arms do, since its bindings write
  the field; a plain `match` reads it;
- `replace(r, f=v)`, which builds a new value, and `take(mut place)` of a whole value, which leaves one built from its
  defaults (`exchange(mut place, value)` with a value the module made is allowed, and so is `take` of an option or a
  list of them);
- a generic function of another module that writes its field through a `field(...)` requirement, at the instance;
- a test parameter that holds one anywhere (a field, an element, a key, an option or a case): the test runner would build
  it from a cases file or a generated input, so such a test belongs to the module or its test file;
- on a record that is also [`@linear`](#linear-records), `own r.field`, which would end the owner without the module's
  functions: outside its module a sealed linear value ends only by being given to an `own` parameter or returned, so a
  protocol (`begin` makes the state, `commit(own s)` ends it) cannot be forged or skipped.

`copy(r)` is allowed: it is the same value, already built by the module. `@sealed` attaches to a `record`, generic or not
(on a union, enum, alias, constraint or function it is `E_ATTRIBUTE_TARGET`). It is part of the module's interface
(`selka interfaces show` prints it above the record), and the checks are the front end's: the back end sees an
ordinary record.

## Tagged unions

`enum` declares a closed set of cases, each on its own line. A case may have no
payload or declare named fields, such as `number(value: int)` or
`point(x: int, y: int)`. Construct fields by name and bind them by name in a
`match`. Matching checks coverage; adding a case makes incomplete matches fail
at compile time. A final `case _` covers the remaining alternatives, subject
to the existing checked-result handling obligations.

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

This returns `21`. Use `match` statements with assignments or returns in each arm;
[match expressions](match-expressions.md) describes migration from retired value forms.

## Payload variant construction

`Type.case` constructs a payload-free case. `Type.case(value=expression)`
constructs a case whose field is named `value`; every payload argument names its
field and evaluates once in written order. A pattern such as
`case name(value=binding)` binds that field; `value=_` discards it.
Nested patterns may inspect variants inside payloads. Generic type arguments
follow the existing expected-type inference rules.

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

Patterns name the fields too: `case name(f1=first, f2=_)`. `_` discards
that field; a nested pattern can match an enum or optional payload. A missing,
extra, unknown or duplicate field receives a located diagnostic. Patterns bind
read-only locals and must exhaustively cover the possible values. A field whose type carries a handling
obligation keeps it, so `case _` over a case with a `Result` field still reports
`E_RESULT_DISCARD` and needs its own arm.

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

This returns `10`. The case's payload stays a single value, so named fields do not change
how a union is laid out, compared, copied, or passed across a module boundary.

Arms can list several cases at once, and `..` ends a pattern that ignores the rest of its fields; see [alternatives and the rest marker](match-expressions.md#alternatives-and-the-rest-marker). A function that only asks which case a value holds writes `value is text` or `if value is list(items):` instead of a `match`; see [testing one case with `is`](match-expressions.md#testing-one-case-with-is).

### Binding a field under its own name

A pattern field written `name=name` binds the field to a local of the same name, so the label can be
dropped: `case atom(text, span=_)` is `case atom(text=text, span=_)`. The bare name is the field's own, not a
position, so `case form(span, items)` binds the same fields in any order and a bare name that no field has is
refused (`E_FRONTEND_VARIANT`, or `E_NAMED_PATTERN` for an enum of another module). The message names the case's fields
and both forms: for `array(items: int[])`, `case array(elems)` is answered with "`case array(items):` binds it under its
own name, `case array(items=elems):` renames it", and `selka fix` writes the label; for a bare `_` (`case Failed(_)`) the
second form is said to discard (`case Failed(message=_):`). The message of an enum of another module names each field the pattern
left unlabelled (at most four, then "and N more"), as `selka fix` labels them all. A field bound to a different name
keeps its label (`literal=text`), and `_` still discards. `selka lint` reports `field=field` as
`L_PATTERN_SHORTHAND` and `selka fix` drops the label. Only the fields of the case an arm names are meant: a field of a nested
pattern keeps its label, `case Some(item(value=value, note=note))`, since the bare `case Some(item(value, note))` is refused
(`E_NAMED_PATTERN`), so the hint is not raised there and `selka fix` never writes that form.

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

An enum value is its case, and the case has a name. `case_name(value)` is that name as a `str`, the identifier the
declaration wrote: `case_name(Status.missing)` is `"missing"`, and a payload is ignored, so it names the case of a
tagged enum such as `Shape.radius(value=3)` too. `Status.cases()` is the list of every case in declaration order and
`Status.from_name(text)` the case a `str` or `bytes` name spells, or `None`; both are for an enum none of whose cases
carries a payload. They are what Zig's `@tagName`, `std.enums.values` and `std.meta.stringToEnum` are, so a program that
prints a tag, walks every case or parses a tag from text keeps no `match` over the cases, and a case added to the enum
is in all three at once.

`case_name` is a prelude function like `len` and `copy`, since its operand carries the type. `cases` and `from_name`
are calls on the enum type, the spelling `Kind.case` already has, because nothing they take is a value of that type;
an enum with a case called `cases` or `from_name` keeps its case. `str(value)` of an enum stays refused
(`E_TEXT_CONVERSION`): printing a value writes `Kind.case`, and `case_name` is the one that answers the bare
identifier. Convert it with `strings.encode(...)` where a `bytes` is wanted. A name with a hyphen or other punctuation
(Zig's `@tagName` of such a field is written `@"power-budget"`) cannot be an identifier, so it is not a case name;
map it by hand.

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

A record or union can refer to itself directly or through another value type when
there is a way to finish the value. An optional field has `None`, and a union can
have a case with no recursive payload. The compiler puts the recursive field or
case in an immutable managed box; source code still reads and writes its value.
Managed recursive values move on assignment. Use `copy(value)` to create an
independent value before retaining and modifying both values.

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

This returns `42`; the `number` case ends the recursion. `record Loop: next: Loop`
still gets `E_RECURSIVE_RECORD`, because it has no finite value. Recursion through
`...[]` or `dict[...]` already has indirection and needs no box. Nested
recursive values compare, hash, print and cross typed JSON boundaries as values.
Printing stops with `...` at the renderer's depth cap.

A recursive box cannot own a resource, an unhandled result or a capability.
This includes builtin `File` and `TextFile` fields, even when construction would
pass a newly opened handle directly. The type is rejected before execution:

```selka
# doc: expect-error E_RECURSIVE_RECORD
record OpenChain:
    file: TextFile
    next: OpenChain?

func main() -> int:
    return 0
```

A recursive value owns its boxes. Moving the value transfers that ownership;
`copy(value)` walks the owned contents to create an independent recursive value.
Read-only helpers borrow it, and mutation uses an exclusive `mut` argument.
Copy cost grows with the copied structure, so borrow a subtree when it only
needs to be read.

## Fixed arrays and enum tables

`T[]` is a growable array value. An array literal always creates a growable
array; an expected fixed type does not change its meaning. Construct a fixed
array explicitly as `FixedArray[T, N]([elements])`. Its length belongs to its
type, it has no `append`, and writes require a writable binding.

The separate enum-indexed table spelling remains `[Kind]T`. A table literal
needs exactly one entry per key case. Fixed arrays and tables have independent
value semantics; `replace(value, index, element)` returns a changed copy.

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

This returns `91234`: every element of `counts` was written, `before` is the
copy taken before the loop and still holds zeros, and only `points[1]` changed.
An index is checked exactly as a read is (see negative indices below).
`points[1].y += 1` keeps its operator, as `point.y += 1` does, and a field of a
record holding an array, `window.samples[i] = v`, is written where
the field lives rather than by copying the array and the record.

### Negative indices

A fixed-array index must satisfy `0 <= i < N`, for reads, writes and
`replace`. A computed negative index traps with `R_LIST_BOUNDS`, reporting the
index as written and the length. The same rule applies to lists. Constant
negative positions report `E_NEGATIVE_INDEX_REMOVED`; `selka fix` rewrites a
certain local-base use such as `values[-1]` to `values[len(values) - 1]`.
An enum table is indexed by its key and has no positional indexes.

```selka
# doc: expect 2144
func main() -> int:
    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
    const back = len(values) - 2
    values[len(values) - 1] += 10
    values[back] = values[0] * 30
    const first = values[0]
    values[0] = values[1]
    values[1] = first
    return values[0] * 1000 + values[1] * 100 + values[2] + values[3]
```

This returns `2144`: the final `4` becomes `14`, `values[2]` becomes `30`,
and the first two elements exchange values. One unsigned bounds comparison
rejects both negative indexes and indexes past the end; no implicit adjustment
from the end remains.

### Passing an array to be written

A parameter declared `mut values: FixedArray[T, N]` names the caller's array for the whole call, and
the caller marks the argument `mut`, as for a list. The callee's element writes
land in the caller's variable; nothing is copied in or out.

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

This returns `1023`: the second call starts from the `12` the first one left.
The same rules apply to growable and fixed arrays. Writing through an ordinary
parameter is `E_IMMUTABLE`; declare both the parameter and the argument `mut`
when the caller should change. A writable local, field or indexed element can
be passed, including `fill(mut box.cells, 0)`. Whole-value reassignment through
the parameter updates the caller too, using an explicit constructor for fixed
arrays. To keep changes local, make an independent `mut` copy of the readonly
parameter. Unused mutation permission is allowed.

### Iterating a fixed array

`for x in a` and `for i, x in enumerate(a)` walk a fixed
array from its first element to its last. The loop reads the array as it was
when the loop began, so element writes in the body do not change which values
the loop visits. An enum table is indexed by its key rather than walked.

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

This returns `124`. The loop saw `3, 1, 4, 1` although it zeroed each element as
it went, so the weighted sum is 12, and the collecting loop afterwards reads the
four zeros. That guarantee costs one copy of the array when the loop begins, and
only when the body writes the array: a loop over a local array its body never
writes reads the elements where they are.

## Related pages

- [Contracts](contracts.md#invariants) — an `@invariant` a record checks at every construction, `replace` and field write
- [Results and options](results-and-options.md) — `Result`, `Option` and their contextual constructors
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Value semantics](value-semantics.md) — ownership, borrowing and explicit copies
- [Match expressions](match-expressions.md) — producing a value from a match
