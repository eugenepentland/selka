# Records, unions and enums

These are the language's user-declared data types. `record` groups named fields into
one value, `union` names a closed set of alternatives with optional payloads, and
`enum` names a closed set with no payloads at all. All three are nominal: two
declarations with identical shapes are different types, and a value of one is never
accepted where the other is expected. There is no inheritance, no method table and no
open extension point, so the set of shapes a declaration can take is fixed where it is
written. For the syntax these examples use, see the
[Python-style application guide](python-syntax.md).

## Records

`record` declares a value record. Every field carries a type annotation, and the record
has no methods, no inheritance and no implicit `self` — a function that operates on a
record takes it as an ordinary parameter. Assignment and argument passing copy the
fields, so writing `point.x = ...` inside a helper changes only that helper's copy;
managed fields such as `list`, `dict`, `str` and `bytes` still share the collection they
point at, because copying a record copies the reference, not the collection. Ordinary
field assignment updates a record local or a record held in a list slot.

```mylang
# doc: expect 14
record Point:
    x: int
    y: int

record Segment:
    start: Point
    end: Point

def shift(point: Point, dx: int) -> Point:
    point.x = point.x + dx
    return point

def main() -> int:
    origin = Point(x=1, y=2)
    moved = shift(origin, 10)
    line = Segment(start=origin, end=moved)
    return line.start.x + line.end.x + line.end.y
```

This returns `14`. `shift` reassigns its own parameter, so `origin.x` is still `1`
afterwards and only `moved.x` is `11`. Records with only scalar fields carry no
collected reference, which is what lets them leave an arena block freely; see
[managed arenas](arenas.md) for that rule and [managed memory](managed-memory.md) for
what sharing a managed field means.

## Managed class records

`class` declares the same named fields as `record` but with reference semantics.
Construction allocates a GC-traced object, and assignment, argument passing and field
reads all refer to that one object, so a write through any binding reaches the original.
Use `record` when a copied value is wanted and `class` when the object has identity.

```mylang
# doc: expect 8
class Counter:
    n: int

def bump(counter: mut Counter):
    counter.n = counter.n + 1

def main() -> int:
    a = Counter(n=1)
    b = a
    b.n = 7
    bump(mut a)
    return a.n
```

This returns `8`: `b` is the same object as `a`, and `bump` receives that object.
Classes may hold managed fields and be held by other classes, so a self-referential
graph is legal; printing one stops at the renderer's depth cap. A class instance has no
value copy to mistake for an alias, so only a `record` copy write is rejected; a
`record` copy write that nothing reads afterwards is `E_DEAD_RECORD_WRITE`.

## Positional and named constructors

A record is constructed by calling its type. Positional arguments bind to fields in
declaration order, named arguments bind by field name in any order, and the two may be
mixed as long as every positional argument precedes the first named one. Construction is
complete: every field must be supplied unless its declaration carries a default, and a
missing one without a default is rejected with `E_INCOMPLETE_CONSTRUCTION` naming the
field and its declaration. An empty record declares `pass` and is constructed with no
arguments.

```mylang
# doc: expect 321
record Colour:
    red: int
    green: int
    blue: int

record Marker:
    pass

def main() -> int:
    positional = Colour(1, 2, 3)
    named = Colour(blue=30, red=10, green=20)
    mixed = Colour(100, blue=300, green=200)
    _ = Marker()
    return positional.red + named.green + mixed.blue
```

This returns `321`. The same positional-then-keyword rules apply to ordinary function
calls, which also accept trailing defaults.

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

def main() -> int:
    base = Config(verbose=True)
    fixed = Config(7)
    if base.verbose and len(base.label) == 4:
        return base.retries + fixed.retries + 2
    return 0
```

This returns `12`: `base.retries` is the declared `3`, `fixed.retries` is the
positional `7`, and `base.label` defaults to `"auto"`.

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

def main() -> int:
    base = Settings(verbose=True)
    changed = replace(base, retries=5)
    return changed.retries + 2
```

This returns `7`. `changed` keeps `verbose` from `base` and `base.retries` is still `3`.

## Tagged unions

`union` declares a closed set of cases. A case is either payload-free or carries exactly
one declared payload type. `enum` is the payload-free form and nothing more: its cases
are ordinary comparable values and can index a table. A union value is read only through
`match`, which must have an arm for every case — adding a case to the declaration turns
every existing match into an `E_INCOMPLETE_MATCH` error rather than a silent fallthrough.
There is no `.case` projection that reads a payload without matching. A trailing
`case _` arm covers every case no earlier arm named, discarding the payload of each one
it covers; it must be last, must cover at least one case, and is rejected when it would
drop a payload carrying an unhandled [result](results-and-options.md#checked-results).

```mylang
# doc: expect 21
enum Level:
    debug,
    warning,
    failure

union Event:
    heartbeat,
    count: int,
    message: str

def weight(event: Event) -> int:
    match event:
        case Event.heartbeat:
            return 1
        case Event.count(n):
            return n
        case Event.message(text):
            return len(text)

def urgency(level: Level) -> int:
    match level:
        case Level.failure:
            return 10
        case _:
            return 0

def main() -> int:
    events = [Event.heartbeat, Event.count(6), Event.message("down")]
    total = 0
    for event in events:
        total = total + weight(event)
    return total + urgency(Level.failure) + urgency(Level.debug)
```

This returns `21`. `match` is a statement, not an expression; see
[match expressions](match-expressions.md) for how a value is produced from one.

## Payload variant construction

`Type.case` without parentheses constructs a payload-free case and `Type.case(value)`
constructs one carrying its declared payload. The payload expression is evaluated once.
Supplying no payload, more than one, a payload to an empty case, or a payload of the
wrong type is rejected with `E_VARIANT_PAYLOAD`. Patterns use the same spelling:
`case Type.case(binding)` names the payload and `case Type.case(_)` discards it. A
generic union names only its template at a use site — `Slot.filled(v)`, never
`Slot[int].filled(v)`, because the compiler cannot tell that spelling apart from an
index followed by a call — and takes its type arguments from the expected type of the
annotation, parameter, field or result it fills, reporting `E_GENERIC_INFERENCE` when
nothing supplies them.

```mylang
# doc: expect 26
record Point:
    x: int
    y: int

union Shape:
    empty,
    radius: int,
    point: Point

union Slot[T]:
    empty,
    filled: T

def area(shape: Shape) -> int:
    match shape:
        case Shape.empty:
            return 0
        case Shape.radius(r):
            return r * r
        case Shape.point(_):
            return 1

def main() -> int:
    shapes = [Shape.radius(4), Shape.point(Point(x=1, y=2)), Shape.empty]
    total = 0
    for shape in shapes:
        total = total + area(shape)
    taken: Slot[int] = Slot.filled(9)
    match taken:
        case Slot.empty:
            return total
        case Slot.filled(value):
            return total + value
```

This returns `26`. Construction resolves through the declared type identity, so a local
binding that shadows the type name keeps ordinary member resolution, and a name that is
not a declared case stays an ordinary call.

## Named variant case fields

A case may declare parenthesized named fields, `case(f1: T1, f2: T2 = default)`. The
fields follow the record rules: a required field may not follow a defaulted one, and a
default is one of the immutable scalar literals a parameter accepts. `Type.case(v1, v2)`
binds positionally, `Type.case(f1=v1)` by name, and the two mix as long as every
positional argument precedes the first named one; a field left out because it declared a
default is filled with that literal. A `case: T` payload and a payload-free `case` keep
their existing spelling and meaning, so existing declarations are unaffected.

A pattern binds exactly one name per declared field — `case Type.case(p1, p2)` — with `_`
discarding that field; a single-payload case still takes one binding and a payload-free
case takes none. A missing or extra field argument, an unknown field name, a duplicate
field, a required field after a defaulted one, and a pattern whose binding count differs
from the field count are all located diagnostics. A field whose type carries a handling
obligation keeps it, so `case _` over a case with a `Result` field still reports
`E_RESULT_DISCARD` and needs its own arm.

```mylang
# doc: expect 10
record Span:
    line: int
    col: int


union Node:
    form(items: list[Node], span: Span),
    atom(text: str, span: Span),
    decimal(value: float, span: Span, literal: Option[str] = None)


def width(node: Node) -> int:
    match node:
        case Node.form(items, _):
            return len(items)
        case Node.atom(text, _):
            return len(text)
        case Node.decimal(_, _, literal):
            match literal:
                case Some(_):
                    return 1
                case None:
                    return 2


def main() -> int:
    home = Span(line=1, col=1)
    tree = Node.form([Node.atom("x", home), Node.decimal(0.0000001, home, Some("100nF"))], home)
    return width(tree) + width(Node.atom("abc", home)) * 2 + width(Node.decimal(1.5, home))
```

This returns `10`. The case's payload stays a single value, so named fields do not change
how a union is laid out, compared, copied, or passed across a module boundary.

## Recursive payloads

A `record` is laid out by value, so its fields must close in finite space: a record field
that reaches the record again is rejected with `E_RECURSIVE_RECORD`. A recursive tree
node — an AST's binary node, for instance — therefore has to be a `class`, whose reference
payload keeps the layout finite. Declare the class before the union so the union's payload
names an already-declared type; the class may name the union it is eventually a case of.

```mylang
# doc: expect 42
class Binary:
    left: Expr
    right: Expr

union Expr:
    number: int,
    binary: Binary

def total(expr: Expr) -> int:
    match expr:
        case Expr.number(n):
            return n
        case Expr.binary(node):
            return total(node.left) + total(node.right)

def main() -> int:
    tree: Expr = Expr.binary(Binary(left=Expr.number(20), right=Expr.number(22)))
    return total(tree)
```

This returns `42`. The same shape with `record Binary` instead of `class Binary` is
rejected: `E_RECURSIVE_RECORD: type fields must form a finite by-value layout`. A
recursive union that reaches itself only through a `list[...]` payload — the
`sexpr`/node-list shape — needs no `class`, because the list is already a reference.

## Fixed arrays and enum tables

A fixed array `[N]T` and an enum-indexed table `[Kind]T` are value types with no
constructor keyword of their own. A list literal builds the array and a dict literal
keyed by `Kind.case` builds the table, but only where the surrounding context demands
one — an annotation, a parameter, a record field or a return type. In every other
position a list literal is still a managed `list` and a dict literal still a managed
`dict`. An array literal's length is checked statically against the expected array and
reports `E_ARRAY_LENGTH` when it disagrees; a table literal needs exactly one entry per
case of its own key enum, so missing cases, duplicates, non-case keys and cases of a
different enum are all rejected. Table entries are stored in enum layout order whatever
order the literal writes them in. Both are fixed-size values rather than collections:
they are copied by assignment, have no `append`, and `replace(value, index, element)`
answers a new one with a single slot changed.

```mylang
# doc: expect 115
enum Status:
    ok,
    missing,
    failed

record Window:
    samples: [3]int

def codes() -> [Status]int:
    return {Status.failed: 500, Status.ok: 200, Status.missing: 404}

def total(values: [3]int) -> int:
    return values[0] + values[1] + values[2]

def main() -> int:
    window = Window(samples=[1, 2, 3])
    widened = replace(window.samples, 2, 10)
    table = codes()
    return total(window.samples) + total(widened) + table[Status.failed] - table[Status.missing]
```

This returns `115`. `window.samples` is unchanged by `replace`, and `codes` writes
`Status.failed` first while the table still reads back in declaration order.

## Related pages

- [Results and options](results-and-options.md) — `Result`, `Option` and their contextual constructors
- [Python-style application code](python-syntax.md) — the surrounding syntax
- [Managed memory](managed-memory.md) — what a managed field shares
- [Match expressions](match-expressions.md) — producing a value from a match
