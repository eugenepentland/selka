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

def bump(counter: Counter):
    counter.n = counter.n + 1

def main() -> int:
    a = Counter(n=1)
    b = a
    b.n = 7
    bump(a)
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
complete: every field must be supplied, and a missing one is rejected with
`E_INCOMPLETE_CONSTRUCTION` naming the field and its declaration. Record fields do not
take default values — writing `green: int = 2` in a `record` body is a syntax error — so
a defaulted field has to become a defaulted parameter on a constructor function you
write yourself. An empty record declares `pass` and is constructed with no arguments.

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
calls, which do accept trailing defaults.

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
