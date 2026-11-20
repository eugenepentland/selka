# Matching a variant

A `match` statement dispatches on a variant and binds its payload. The scrutinee evaluates once, one arm runs, and every
variant needs an arm unless a wildcard covers the rest.

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

A case pattern names its case alone: `case ok(number)`, or `case ok(_)` to ignore it. A qualified pattern,
`case Read.ok(number)`, is `E_PATTERN_QUALIFIED` (`selka fix` drops the qualifier). A bare name in a payload position
names a case when the payload's type declares one; otherwise it binds the payload. In a fielded case a bare name that
names a field binds it: `case circle(radius)`; `case circle(radius=r)` renames it.

- An owned payload may move out of its arm or be cleaned up after it. A payload that carries a result must be handled
  or transferred, and every arm leaves the same ownership state.
- `try` inside an arm propagates a declared failure; declare a fallible call's value first.
- A plain `match` on a place whose payload owns no storage (numbers, flags, records of them) copies the payload when it
  binds it, so the arm may write the matched place while the binding keeps the original value. A payload holding text,
  bytes, a list, a dictionary or a resource is not copied: the place is held until the arm's last use of a binding, as
  under `match mut` ([mutable element matches](#mutable-element-matches)).

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

Cases that need the same body list their patterns with `|`: `case leaf | blank:`, `case text(value) | code(value):`.
Every alternative binds the same names with the same types (`E_ALTERNATIVE_BINDINGS` otherwise); under `match mut` they
must also bind the same fields, so `case up(n) | other(extra=n, m=_):` is refused. In every other respect each alternative
is an arm: a case listed twice is `E_DUPLICATE_ARM`, and a case no arm lists is `E_INCOMPLETE_MATCH`.

A pattern names every field of its case by default. The rest marker `..` ends a pattern and discards the fields it does not
name: `case atom(text, ..)`, `case Some(..):`, `case Err(Malformed(..)):`. A case with no payload has nothing to ignore
(`E_PATTERN_PAYLOAD`), and nothing may follow the marker.

A bound name the arm never reads is `W_UNUSED_BINDING`, with the fix in the message:

| Unread | Write |
| --- | --- |
| a single payload or a labelled field | `_`: `case Some(_):`, `case circle(radius=_):` |
| a field the pattern names bare | its label, `case number(n, lit=_)` (a bare `_` there is `E_FRONTEND_VARIANT`), or `..` at the end |

`selka fix DIR` and `selka fix FILE --warnings` write it, except for a name the arm writes under `match mut`, a payload
that must be handled, an alternatives arm, and a case name that an enum and a `result` both declare.

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

`value is PATTERN` is a `bool`: `node is text`, `kind is ident | integer`, `x is Some`, `result is Ok`, `value is None`.
A bare case name stands for the case with any payload (`node is text` is `case text(..)`); spell a payload `pair(..)` or
`number(value=_)`. The test binds nothing, so it composes with `and`, `or` and `not`.

When the pattern binds names, the test is the whole condition of an `if`, `elif` or `while`, and the names are read-only
and live in that statement's body: `if node is list(items):`. `while` tests again before each pass.

| Written | Result |
| --- | --- |
| a binding pattern anywhere else | `E_IS_BINDING` |
| a value with no cases (`7 is leaf`) | `E_IS_OPERAND` |
| a nested pattern | use `match` |
| a two-arm `match` over an Option or Result where one arm does nothing | `W_MATCH_IS`; `selka fix` writes the `if` ([idiom rewrites](tooling/lint.md#idiom-rewrites)) |

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

## Wildcard arms

`case _` takes every variant no earlier arm named and discards its payload. It must be the last arm and cover at least
one variant, or the match is `E_WILDCARD_ARM`. It refuses to cover a variant whose payload carries an unhandled result
(`E_RESULT_DISCARD`): that variant needs its own arm.

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

A `match` on an `int`, `str`, `bytes` or `bool` compares the value with literal arms. An arm lists literals with `|`, and
the first arm that holds runs: `case 0 | 1:`, `case -1:`. A character is the number it folds to: `case ord("+"):` or
`case b"+"[0]:` ([character codes by name](bytes.md#character-codes-by-name)).

- A bare name in an arm must name a top-level constant of this module (`case LIMIT:`); any other variable is
  `E_LITERAL_ARM`: write `if n == limit:`.
- A `bool` match listing `True` and `False` needs no wildcard; every other match on these types ends with `case _`
  (else `E_INCOMPLETE_MATCH`).
- A literal that repeats an earlier arm is `E_DUPLICATE_ARM`, judged by value: `case 1:` and `case 0x1:` are one.
- A literal of another type, or a `str` or `bytes` element or field (binding it would copy it: bind
  `const value = copy(...)` first), is `E_LITERAL_ARM`. `case Some(1):` is `E_SYNTAX`.
- An `if`/`elif` chain of three or more `x == literal` tests on one value draws `L_LITERAL_MATCH`; `selka fix` rewrites it
  ([idiom rewrites](tooling/lint.md#idiom-rewrites)). A chain on an Option, a `str` or `bytes` field or element, or in a
  generic function is not reported.

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

## Mutable element matches

`match mut <place>:` lets its payload bindings write into the place they came from. The place is a local, a field, or a
list element such as `slots[i]`; a call result or temporary is `E_MATCH_MUT`. Inside an arm a binding names its place: a
field of it can be assigned, passed `mut`, or assigned whole.

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

While an arm runs the container is held: any other access to it before the arm's last use of a binding is
`E_SINGLE_OWNER_OVERLAP`, so move that access after the last use. An arm that binds nothing holds nothing.

- When the payloads hold no text, bytes or list (numbers, flags, records of them), a read of the container is allowed
  during the hold, and so is a write to a field beside the matched place. A write that replaces the matched place or a
  container of it is refused (a plain `match` copies such payloads and allows it: [Variant matches](#variant-matches)).

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

- Changing a binding in a loop over it (`for word in items:`) is `E_SINGLE_OWNER_OVERLAP`, as for a `mut` local: change
  it after the loop, or take `copy(word)` first.
- A list binding is written by `items[i] = value`, `lists.exchange(mut items, i, value)`, `exchange(mut items[i], value)`,
  `take(mut items[i])` and `append(mut cells[i], value)`, as often as a `mut` local, in any order. A dictionary or set
  binding works the same (`table[key] = value`, `dicts.pop`, `sets.add`). A write whose argument changes the binding
  while it runs, `lists.exchange(mut items, 0, take(mut items[1]))`, is `E_SINGLE_OWNER_OVERLAP`.
- A binding cannot be moved out, given away with `own`, or stored: store `copy(value)`. The case cannot change through a
  binding; assign the whole element outside the match to switch variant.
- `match mut d[k]` on a dictionary element is `E_MATCH_MUT`: read with `match d[k]` and write back with `d[k] = ...`.
- A payload holding a [`@linear` owner](records-and-unions.md#linear-records) is lent the same way; the owner is still
  consumed after the match (`match mut` alone is `E_LINEAR_UNCONSUMED`).
- A write through a binding checks the `@invariant` of each record on the place's path (`R_INVARIANT`).

## Consuming matches

`match own <name>:` consumes a named owner, an owned local or an `own` parameter. Each payload binding owns its value:
move, store or return it without a copy; `own payload.field` takes one field. The name is unavailable after the match.

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

Only an owner can be consumed. A borrowed parameter or local, a `mut` parameter, a field or element place and
`match mut own` are `E_OWN_MARKER`; `selka fix` removes the marker. To consume instead, declare the parameter `own`, or
bind the place first (`const slot = own box.slot`, or `pop()`/`exchange()` an element out) and match `own slot`. A use of
the name after the match or inside an arm is `E_SINGLE_OWNER_MOVED`; a live borrow of the owner is
`E_SINGLE_OWNER_OVERLAP`.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/match-expressions.md).
