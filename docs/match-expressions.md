# Matching a variant

A `match` statement dispatches on a variant and binds its payload. The scrutinee
evaluates once, exactly one arm runs, and every variant needs an arm unless a
wildcard covers the rest.

## Variant matches

```selka
# doc: expect 42
result Read:
    ok: i64,
    err: i64


func value(input: Read) -> i64:
    match input:
        case ok(number):
            return number
        case err(code):
            return -code


func main(out: Stream) -> i64:
    print(out, value(Ok(42)))
    return 0
```

A case pattern names its case alone: `case ok(number)`, or `case ok(_)` to ignore the
payload. The matched value's type says which enum or union the case belongs to, so a
qualified pattern such as `case Read.ok(number)` is refused with `E_PATTERN_QUALIFIED`,
and `selka fix` drops the qualifier. A bare name in a payload position names a case when
the payload's own type declares one; otherwise it binds the payload. An owned payload may
move out of its arm or be cleaned up after it. A result-bearing payload must be handled or
transferred; ignoring it does not erase its obligation, and the ownership state an arm
leaves behind must agree with every other arm's.

A bare name in a fielded case's payload that names one of its fields binds that field:
`case circle(radius)` binds `radius`, and `case circle(radius=r)` renames it to `r`.

Boundary `try` inside an arm propagates a declared failure while preserving
pending result obligations. Extract a fallible call into a declaration before
using its successful value in a larger expression. `with arena()` regions are
removed; ordinary value ownership and cleanup apply to match results.

Ordinary and generic functions share these rules. Lowering uses exhaustive
variant dispatch, owned payload cleanup included.

A plain `match` on a place whose payload owns no storage (numbers, flags, records of them, fielded or not) copies the
payload when it binds it, so the arm may write the matched place, the list or record that holds it, or a field beside it
while the binding is live, and the binding keeps the value the arm started with. A payload that holds text, bytes, a
list, a dictionary or a resource is not copied, and `match mut` writes its place: both hold the place until the arm's
last use of a binding ([mutable element matches](#mutable-element-matches)).

```selka
# doc: expect 1 -1 1
enum Key:
    num(v: int)
    other


record Table:
    keys: Key[]
    seen: int[]


func spend(mut t: Table, i: int) -> int:
    match t.keys[i]:
        case num(v=n):
            t.keys[i] = Key.other
            append(mut t.seen, n)
            return n
        case other:
            return -1


func main(out: Stream) -> int:
    mut t = Table(keys=[Key.num(v=1)], seen=[])
    const first = spend(mut t, 0)
    const second = spend(mut t, 0)
    print(out, first, second, len(t.seen))
    return 0
```

## Alternatives and the rest marker

Cases that need the same body list their patterns with `|`, as literals do: `case leaf | blank:` for cases with no
payload, and `case text(value) | code(value):` for cases that bind. Every alternative binds the same names with the
same types, so the one body reads them whichever alternative matched; alternatives that bind different names, or one
name as two types, report `E_ALTERNATIVE_BINDINGS` at the offending alternative and name the first. Each alternative
is an arm in every other respect: a case listed twice (in one list or in two arms) reports `E_DUPLICATE_ARM`, and a case
no arm lists still reports `E_INCOMPLETE_MATCH`. The body is checked once for each alternative, so a diagnostic in it
points at the one source body.

A pattern names every field of its case by default, so a reader sees which fields an arm uses. The rest marker `..`
ends a pattern and discards every field it does not name: `case fenced_code(..):` ignores all of them, and
`case atom(text, ..)` binds `text` and ignores the rest. A single payload is ignored the same way, `case Some(..):`,
and the marker ends a nested pattern too, `case Err(Malformed(..)):`. A case with no payload has no fields to ignore
(`E_PATTERN_PAYLOAD`), and nothing may follow the marker.

A name that a pattern binds and the arm never reads is `W_UNUSED_BINDING`, and the warning says what to write in its
place. A single payload and a labelled field are ignored with `_`: `case Some(_):`, `case circle(radius=_):`. A field
that the pattern names bare is ignored with its label, `name=_`: `case number(n, lit)` becomes `case number(n, lit=_)`
(a bare `_` in a case with named fields is `E_FRONTEND_VARIANT`), or with the rest marker when the unread fields end
the pattern. `selka fix DIR` and `selka fix FILE --warnings` write it. The repair is withheld where it is not
certain: a name the arm writes under `match mut`, a payload that must be handled, an arm of a `case a(x) | b(x):` list,
and a case name that an enum and a `result` both declare keep the plain message.

Under `match mut` each alternative's bindings write into that alternative's own payload, so the alternatives of one arm
must bind the same fields under the same names: `case up(n) | down(n):` may increment `n`, while
`case up(n) | other(extra=n, m=_):` is refused with `E_ALTERNATIVE_BINDINGS`, because the one name would write two
different fields.

```selka
# doc: expect 3 12 4 0
enum Node:
    text(value: str)
    code(value: str)
    pair(left: int, right: int)
    wide(a: int, b: int, c: int, d: int)
    leaf
    blank


func weight(node: Node) -> int:
    match node:
        case text(value) | code(value):
            return len(value)
        case pair(left, right):
            return left * 10 + right
        case wide(..):
            return 4
        case leaf | blank:
            return 0


func main(out: Stream) -> int:
    print(out, weight(Node.text(value="abc")), weight(Node.pair(left=1, right=2)), weight(Node.wide(a=1, b=2, c=3, d=4)), weight(Node.blank))
    return 0
```

## Testing one case with `is`

A function that only asks which case a value holds does not need a `match`. `value is PATTERN` is a `bool`:
`node is text` tests a case with a payload, `kind is ident | integer` lists alternatives, and `x is Some` or
`result is Ok` test an Option or a Result. Case names are bare, as in `case`, because the value's type already says which type
they belong to, and a bare name stands for the case with any payload (`node is text` is `case text(..)`). A payload can be
spelled out as `pair(..)`, or, for a case with named fields, `number(value=_)`; the test binds nothing, so it composes with
`and`, `or` and `not`, and the value is evaluated once. `value is None` keeps its meaning as the test that an Option is absent.

When the pattern binds names, the test is the whole condition of an `if`, an `elif` or a `while`, and the names belong to
that statement's body: `if node is list(items):` is a `match node:` with the `case list(items):` arm and a final arm for
every other case that runs the `else` branch or nothing. The names are read-only and borrow the value exactly as a match
arm's names do, so the body cannot reassign the value it tests; `while` tests again before each pass and leaves, as
`break` does, when another case arrives. A binding pattern anywhere else reports `E_IS_BINDING`, so a name never escapes an
expression, and a value with no cases (`7 is leaf`) reports `E_IS_OPERAND`. A pattern in a test names a case and its own
fields: a nested pattern needs `match`. A two-arm `match` over an Option or a Result one of whose arms does nothing (`case None: pass`) is
`if value is Some(x):` written the long way: it draws `W_MATCH_IS`, and `selka fix` writes the `if`
([idiom rewrites](tooling/lint.md#idiom-rewrites)).

```selka
# doc: expect True False True 7 100 4
enum Node:
    text(value: str)
    code(value: str)
    pair(left: int, right: int)
    leaf
    blank


func is_text(node: Node) -> bool:
    return node is text


func is_inert(node: Node) -> bool:
    return node is leaf | blank


func weigh(node: Node) -> int:
    if node is text(value) | code(value):
        return len(value) * 100 + 4
    elif node is pair(left, right):
        return left * 10 + right
    return 0


func main(out: Stream) -> int:
    print(out, is_text(Node.text(value="a")), is_text(Node.leaf), is_inert(Node.blank), weigh(Node.pair(left=0, right=7)), weigh(Node.text(value="a")) - 4, weigh(Node.leaf) + 4)
    return 0
```

```selka
# doc: expect-error E_IS_BINDING
enum Node:
    text(value: str)
    leaf


func length(node: Node) -> int:
    return node is text(value)


func main() -> int:
    return 0
```

## Wildcard arms

A `match` may end with `case _`, which takes every variant no earlier arm named
and discards that variant's payload. It must be the last arm and must cover at
least one variant; an earlier position, or a match whose arms are already
exhaustive, reports `E_WILDCARD_ARM`. A wildcard also refuses to cover a variant
whose payload still carries an unhandled result, reporting `E_RESULT_DISCARD`,
because dropping that payload would drop its obligation; that variant needs its
own arm.

```selka
# doc: expect-error E_WILDCARD_ARM
enum Event:
    start
    tick(value: int)
    stop(value: int)


func weight(event: Event) -> int:
    match event:
        case tick(value=count):
            return count
        case _:
            return 0


func misplaced(event: Event) -> int:
    match event:
        case _:
            return 0
        case tick(value=count):
            return count


func main() -> int:
    return weight(Event.tick(value=42))
```

## Literal arms

A `match` on an `int`, `str`, `bytes` or `bool` compares the value with literal arms. An
arm lists one or more literals with `|`, and the first arm that holds runs, so `case 0 | 1:`
matches either value. A negative integer is written `case -1:`. A character is written as the number it folds to: `case ord("+"):` or `case b"+"[0]:` ([character codes by name](bytes.md#character-codes-by-name)). A bare name in such an arm
must name a top-level constant of this module, such as `case LIMIT:`. The arm is not a capture:
a parameter, a local or any other variable named in an arm is refused with `E_LITERAL_ARM`, and a
comparison with a variable is written `if n == limit:`. A `bool` match that lists both `True` and `False`
needs no wildcard. Every other match on these types ends with `case _`.

```selka
# doc: expect 30
const LIMIT: int = 7


func label(code: int) -> int:
    match code:
        case 0 | 1:
            return 10
        case -1:
            return 20
        case LIMIT:
            return 70
        case _:
            return 0


func main(out: Stream) -> int:
    print(out, label(-1) + label(1))
    return 0
```

An `if`/`elif` chain of three or more `x == literal` tests on one value is this match written the long way; `selka lint` reports it as `L_LITERAL_MATCH` and `selka fix` rewrites it ([idiom rewrites](tooling/lint.md#idiom-rewrites)). A chain on an Option (`bytes?`), on a `str` or `bytes` field or element, or in a generic function is not reported, because a literal arm is refused there; compare an Option with `if head == b"net":` as written.

The matched value is read once. A plain name or parameter is compared in place, and a call
result or a slice is bound to a hidden local that the comparisons only read, so neither is
copied. A `str` or `bytes` element or field is refused with `E_LITERAL_ARM`, because
binding it would copy it: bind it first with `const value = copy(...)`. The arms lower to
the same `if`/`elif` chain a hand-written match would, and a release build turns that
chain into a lookup table.

A match on these types without `case _` reports `E_INCOMPLETE_MATCH`, and `case _` must be
the last arm (`E_WILDCARD_ARM`). A literal that repeats an earlier arm reports
`E_DUPLICATE_ARM`, judged by value: `case 1:` and `case 0x1:` are one value, and so are `"a"` and `"\x61"`.
A constant compares by its value when the checker folds it, and otherwise by its declaration. A literal
of another type reports `E_LITERAL_ARM`. A literal is a
whole arm, so `case Some(1):` is refused with `E_SYNTAX`.

```selka
# doc: expect-error E_INCOMPLETE_MATCH
func grade(score: int) -> int:
    match score:
        case 90:
            return 4


func main(out: Stream) -> int:
    print(out, grade(90))
    return 0
```

## Mutable element matches

`match mut <place>:` matches a value and lets its payload bindings write into the place they came from. The place is
a local, a field, or a list element such as `slots[i]`; a call result or a temporary has no place to write into and
is refused with `E_MATCH_MUT`. Inside an arm, a binding is a name for its place in the matched value. A read projects
it from the container, a write stores into it, and a field of it can be assigned, passed `mut`, or assigned whole:

```selka
# doc: expect 51 2
record Account:
    balance: int
    holds: int[]


enum Slot:
    empty
    account(value: Account)


func credit(mut slots: Slot[], i: int, amount: int):
    match mut slots[i]:
        case account(value=payload):
            payload.balance = payload.balance + amount
            append(mut payload.holds, amount)
        case empty:
            return


func main(out: Stream) -> int:
    mut slots = [Slot.empty, Slot.account(value=Account(balance=40, holds=[]))]
    credit(mut slots, 1, 2)
    credit(mut slots, 1, 9)
    match slots[1]:
        case account(value=p):
            print(out, p.balance, len(p.holds))
        case empty:
            print(out, 0, 0)
    return 0
```

While an arm runs, the container is held: the arm may write its bindings, but any other access to the container
before the arm's last use of a binding is refused with `E_SINGLE_OWNER_OVERLAP`, so move that access after the last
use. Under `match mut`, when the payloads hold no text, bytes or list (plain numbers, flags, records of them), a read
of the container during the hold is allowed, and so is a write to a field of the record beside the matched place; a
write that replaces the matched place, or a container of it, is refused, so a binding always names the case it
matched. A plain `match` whose payloads own no storage copies them when it binds them, so its arm may replace the
matched place too ([Variant matches](#variant-matches)); a plain `match` whose payload holds text, bytes, a list, a
dictionary or a resource holds the container as `match mut` does. An arm that binds nothing holds nothing.

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Holder:
    tag: int
    shape: Shape


enum Shape:
    empty
    circle(radius: int)


func main() -> int:
    mut h = Holder(tag=1, shape=Shape.circle(radius=2))
    match mut h.shape:
        case circle(radius=r):
            h.tag = 2
            h.shape = Shape.empty
            r = r + 1
        case empty:
            return 1
    return h.tag
```

A binding is looped over as a `mut` local is: `for key in value:` over a dictionary binding, or `for word in items:` over a
list of text, reads what the loop variable names from the binding, and reading the loop variable is reading the binding.
Changing the binding in a loop over it is refused with `E_SINGLE_OWNER_OVERLAP`, whether or not the loop variable is read
afterwards (rule R7: nothing changes a collection while a loop walks it, a list would grow under its own loop and a dictionary
would trap at run time), exactly as for a `mut` local; a loop variable that is still used also says it would name storage the
change may free. So change the binding after the loop, or take `copy(word)` first.

```selka
# doc: expect 5 6
enum Slot:
    words(items: str[])
    empty


func measure(out: Stream, mut slot: Slot):
    match mut slot:
        case words(items):
            mut total = 0
            for word in items:
                total = total + len(word)
            append(mut items, "tail")
            print(out, total, len(items[2]) + len(items[0]))
        case empty:
            return


func main(out: Stream) -> int:
    mut slot = Slot.words(items=["ab", "cde"])
    measure(out, mut slot)
    return 0
```

An element of a list binding is written through the place by every spelling of a write: `items[i] = value`,
`lists.exchange(mut items, i, value)`, the builtins `exchange(mut items[i], value)` and `take(mut items[i])`, and for a
list of lists `append(mut cells[i], value)`. The builtins stage the element in a compiler temporary of their own, which
reaches the matched place as the binding does. A loop over the binding refuses them like any other change (R7).

```selka
# doc: expect old-a new-a/b
enum Slot:
    words(items: str[])
    empty


func swap(out: Stream, mut slot: Slot):
    match mut slot:
        case words(items):
            const old = exchange(mut items[0], "new-a")
            const gone = take(mut items[1])
            print(out, "old-" + old, items[0] + "/" + gone)
        case empty:
            return


func main(out: Stream) -> int:
    mut slot = Slot.words(items=["a", "b"])
    swap(out, mut slot)
    return 0
```

One arm may write its binding as often as a `mut` local is written, in any order and with reads between: each write sees
the ones before it, a field of an element (`rows[0].text = value`) is written in place, and the same holds for a
dictionary or set binding (`table[key] = value`, `dicts.pop`, `sets.add`). A write whose argument changes the binding
while the write runs, such as `lists.exchange(mut items, 0, take(mut items[1]))`, is refused at the check with
`E_SINGLE_OWNER_OVERLAP`, as it is on a local.

```selka
# doc: expect b|assigned|second f0
import lists


record Row:
    text: str


enum Slot:
    rows(items: Row[])
    empty


func rewrite(out: Stream, mut slot: Slot):
    match mut slot:
        case rows(items):
            items[0] = Row(text="assigned")
            const other = lists.exchange(mut items, 1, Row(text="second"))
            append(mut items, Row(text="f"))
            items[2].text = "f0"
            print(out, other.text + "|" + items[0].text + "|" + items[1].text, items[2].text)
        case empty:
            return


func main(out: Stream) -> int:
    mut slot = Slot.rows(items=[Row(text="a"), Row(text="b")])
    rewrite(out, mut slot)
    return 0
```

A binding cannot be moved out, given away with `own`, or stored: store
`copy(value)` instead. The case cannot change through a binding; assign the whole element outside the match to
switch variant. Matching a dictionary element with `match mut d[k]` is not yet supported and is refused with
`E_MATCH_MUT`; read it with `match d[k]` and write the updated value back with `d[k] = ...`.

A payload that holds a [`@linear` owner](records-and-unions.md#linear-records) is lent the same way: the binding is read,
written and passed `mut` in place, and `match mut` does not end the owner, which is still to be consumed after the match
on every path (a `match mut` alone is refused with `E_LINEAR_UNCONSUMED`).

A write through a binding changes every record the matched place lies in, so each record with an `@invariant` on the
place's path is checked after the write, as after a direct field write: an assignment to the binding or a field of it,
`+=`, a `mut` argument, `take`, `exchange`, `append` and the other writes of a list binding, and a write inside a
nested `match mut`. A broken invariant traps `R_INVARIANT` at that write, whatever the arm does next:

```selka
# doc: expect-trap R_INVARIANT
enum Mode:
    off
    on(level: int)


func level(m: Mode) -> int:
    match m:
        case on(level=v):
            return v
        case off:
            return 0


@invariant(level(self.mode) >= 0, "level is never negative")
record Switch:
    tag: int
    mode: Mode = Mode.off


func main() -> int:
    mut s = Switch(tag=1, mode=Mode.on(level=1))
    match mut s.mode:
        case on(level=v):
            v = -5
            return v
        case off:
            return 2
```

## Consuming matches

`match own <name>:` consumes a named owner, an owned local or an `own` parameter, the way matching a fresh call result
does. Each payload binding then owns its value: it may be moved, stored or returned without a copy, and
`own payload.field` takes one field and drops the rest of the payload, as it does for an owned record. An arm that does
not use its payload drops it. After the match the name is unavailable on every path; assign it again to use it.

```selka
# doc: expect 2 a1 0
record Account:
    name: str
    holds: int[]


enum Slot:
    empty
    account(value: Account)


func holds_of(own s: Slot) -> int[]:
    match own s:
        case account(value=payload):
            return own payload.holds
        case empty:
            return []


func main(out: Stream) -> int:
    mut kept: Account[] = []
    const s = Slot.account(value=Account(name="a1", holds=[]))
    match own s:
        case account(value=payload):
            append(mut kept, own payload)
        case empty:
            pass
    print(out, len(holds_of(Slot.account(value=Account(name="b", holds=[4, 5])))), kept[0].name, len(holds_of(Slot.empty)))
    return 0
```

Only an owner can be consumed. A borrowed parameter, a borrowed local (a `const` binding of a place, or a payload of a
borrowing match), a `mut` parameter, a field or element place and `match mut own` are refused with `E_OWN_MARKER`, whose
certain fix removes the marker, so the match borrows the payload (`selka fix` applies it). To consume instead, declare
the parameter `own`, or bind the place first (`const slot = own box.slot`, or take an element out with `pop()` or
`exchange()`) and match `own slot`. A use of the name after the match or inside an arm is
`E_SINGLE_OWNER_MOVED`, and a live borrow of the owner blocks the match with `E_SINGLE_OWNER_OVERLAP`.

```selka
# doc: expect-error E_OWN_MARKER
enum Slot:
    empty
    names(value: str[])


func first(s: Slot) -> str[]:
    match own s:
        case names(value):
            return value
        case empty:
            return []


func main() -> int:
    return len(first(Slot.names(value=["a"])))
```
