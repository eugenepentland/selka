# Value semantics

Collections and records are independent values: `check`, `run`, `build` and `test` implement that with moves, read-only
borrows, explicit copies and compiler-inserted destruction. The four verbs and three rules are in the
[ownership reference](ownership-rules.md#the-model); this page teaches them one use at a time. `mut next = own previous`
transfers the owner, `const next = previous` borrows read-only, and `copy(value)` is for when both values must stay usable.

```selka
# doc: expect 12
func main() -> int:
    mut a = [1]
    mut b = copy(a)
    append(mut b, 2)
    return len(a) * 10 + len(b)
```

Appending to `b` leaves `a` with one element. Without the copy, `mut b = a` needs an `own` marker (`E_OWN_MARKER`), and after `mut b = own a` a read of `a` is refused.

## The rules

- **Named moves are explicit.** Write `own` when a managed binding moves into another binding, an assignment, a field, a
  container, a constructor or an owning argument: `const next = own previous`, `rows[i] = own row`, `Row(items=own items)`,
  `Some(own items)`, `[own first, own second]`, `take(own items)`. A bare `return items` needs no marker (`return own items`
  is refused), but a returned constructor still marks its named inputs. Fresh values and scalars never take `own`. A
  misplaced marker is `E_OWN_MARKER`.
- **A `const` place borrows.** `const next = previous` borrows even when `previous` is an owner or an `own` parameter,
  through `next`'s last use, so the owner cannot change or move meanwhile. Write `const next = own previous` or
  `copy(previous)` to own it. A constructor whose managed fields all read places (`Spot(net=bank.power, x=1)`) borrows them
  the same way ([B9](ownership-rules.md#b9--const-place-bindings-borrow)).

- **A field transfer consumes its record.** `own record.items` makes the whole record unavailable and destroys its other
  fields. One statement may move several fields of one owned record, each once (`total(own p.lo, own p.hi)`). Use
  `copy(record.items)` to keep the record usable.
- **Borrowed results are declared.** `-> T from first, second` names the plain or `mut` parameter sources. Read the result in
  place, bind it with `const`, or return it under a matching `from`; `copy(...)` it to store it
  ([R4](ownership-rules.md#r4--borrowed-returns)).

```selka
# doc: expect 21
func appended(xs: int[]) -> int[]:
    mut ys = copy(xs)
    append(mut ys, 9)
    return ys

func main() -> int:
    const a = [1]
    const b = appended(a)
    return len(a) + len(b) * 10
```

A parameter stays read-only: `xs.append(9)` in `appended` is `E_MUTATION_MARKER`. Use a `mut` parameter when the caller
should see the change.

- **`mut` parameters update caller storage.** A field assignment, nested collection update or whole-value rebinding through
  one reaches the caller, and so do scalar `mut` parameters.

```selka
# doc: expect 22
record Counter:
    n: int
    items: int[]

func bump(mut counter: Counter) -> Unit:
    counter.n += 1
    append(mut counter.items, counter.n)

func main() -> int:
    mut counter = Counter(n=0, items=[])
    bump(mut counter)
    bump(mut counter)
    return counter.n * 10 + len(counter.items)
```

- **A writable call must not overlap another active borrow of its argument.** If a helper needs an independent earlier
  value, take the copy before the call. Two mutable arguments must address disjoint storage.

```selka
# doc: expect 23
func touch(mut target: int[], source: int[]) -> int:
    append(mut target, len(source))
    return len(source)

func main() -> int:
    mut values = [1, 2]
    const before = copy(values)
    const seen = touch(mut values, before)
    return seen * 10 + len(values)
```

- **Finish an overlapping call before updating its receiver.** `items[selected(mut items)] = 9` overlaps its mutable
  argument with the receiver being updated: save the call result, then select from the current receiver.

```selka
# doc: expect 19
func selected(mut items: int[]) -> int:
    append(mut items, 2)
    return 1

func main() -> int:
    mut items = [1]
    const index = selected(mut items)
    items[index] = 9
    return items[0] * 10 + items[index]
```

- **Loop and match bindings borrow their source.** Consume an owned source with `for x in own xs:` or `match own name:`,
  whose bindings own their payloads; copy a binding only if the source lives on. `selka fix` writes `match own name:` and
  `own payload` where a `match` copies a payload and `name` is an owned local nothing reads after.

- **Writing into an unnamed returned temporary** is `E_VALUE_TEMPORARY_WRITE`: bind the result first. An element of a new
  list needs no copy where a value is taken ([B7](ownership-rules.md#b7--no-moving-out-of-a-container)), and
  `maybe().unwrap_or("")` on a call's option gives an owned value ([R6](ownership-rules.md#r6--borrowed-selections)).

## Taking and exchanging a value

`take(mut place)` moves the value out of a writable place and leaves its type's default: an empty list, dictionary, set, text
or bytes, `None` for an optional, or, for a record whose fields all have defaults, the record those defaults build (what
`Block()` builds). `exchange(mut place, value)` moves the old value out and puts `value` in, for a value of any type. The
moved value is the call's result, owned by the caller; nothing is copied. A place is a local, a record field of one (nested
too), a list element `xs[i]`, a field of one `xs[i].f`, an element of an element `grid[i][j]`, or a `match mut` payload
binding and its fields.

The place is borrowed `mut`: the marker is required, and `own` there is refused with the repair `mut`. The replacement of
`exchange` takes no marker when fresh and `own` when named (`exchange(mut holder.items, own fresh)`); one built from the place
itself (`exchange(mut xs, own xs)`) is refused. A live borrow of the list, a loop over it or a running `match mut` arm holds
the whole list, so the take is refused (`E_SINGLE_OWNER_OVERLAP`); the index is checked first (`R_LIST_BOUNDS`).

`selka fix` writes a `take` for a copy of a field or element of a local that nothing reads again
([Moves instead of copies](tooling/lint.md#moves-instead-of-copies)).

Refused: an unmarked argument, a non-`mut` binding, a place a live borrow holds, a dictionary value `d[k]` (use `d.pop(k)`),
an octet of text, a call result, a value of another type (`E_ASSIGNMENT_TARGET`, `E_TYPE`). `take` of a type with no
default (`int`, a record with a field that has none, a union) is `E_TAKE_TYPE`, whose message names the `exchange` to write;
neither moves a resource, a capability or a pending result. A module function named `take` or `exchange` is
`E_BUILTIN_FUNCTION_NAME` when called bare.

```selka
# doc: expect 31
record Holder:
    items: int[]

func drain(mut holder: Holder) -> int[]:
    return take(mut holder.items)

func main() -> int:
    mut holder = Holder(items=[1, 2, 3])
    const got = drain(mut holder)
    const old = exchange(mut holder.items, [7])
    return len(got) * 10 + len(holder.items) + len(old)
```

## Consuming a list in a loop

`for x in own xs:` takes the list and gives each element to the body as its owner: `own x` moves it into a list, dictionary,
record or return, with no copy. A plain `for` variable borrows its element, so storing it needs `copy(x)`. The list must be
one the function owns: an owned local, an `own` parameter, or the new list a call returns (`for row in own rows():`).
`selka fix` rewrites `for x in xs:` with `append(mut out, copy(x))` to this form where nothing else reads `xs`.

```selka
# doc: expect 6
record Pin:
    pad: bytes
    ref: bytes


func pads_of(own pins: Pin[]) -> bytes[]:
    mut out: bytes[] = []
    for pin in own pins:
        append(mut out, own pin.pad)
    return out


func main() -> int:
    const pins = [Pin(pad=b"1", ref=b"U1"), Pin(pad=b"22", ref=b"U2"), Pin(pad=b"333", ref=b"U3")]
    const pads = pads_of(own pins)
    return len(pads[0]) + len(pads[1]) + len(pads[2])
```

An element the body does not move is dropped at the end of its iteration, and a `break`, `return` or `fail` drops the rest.
The list's name is moved from the loop on, so a use of it inside or after the loop is `E_SINGLE_OWNER_MOVED` (a `mut` local
can be assigned a new list afterwards). Refused, mostly as `E_ITERATION` with the line to write instead: a `mut` or borrowed
parameter (`mut items = take(mut values)` or `copy(values)`), a field, a `const` binding of a place, a dictionary, two names
and a list literal. A call result lent by its argument (declared `from` it) is `E_SINGLE_OWNER_BORROW`, which offers
`for x in own copy(first(xss)):`.

## Setting a list aside for a loop

`for x in r.items:` borrows `r.items` until the loop ends, so a call inside it that may change `r` (`note(x, mut r)`) is
`E_SINGLE_OWNER_OVERLAP`. When the call changes only another field, pass that field (`note(x, mut r.total)`). When it needs
the whole record, `for x in detach r.items:` moves the list out of its place for the loop and puts it back at every exit
(the loop running out, `break`, `return`, `fail`, a failing `try`). Inside the loop `r.items` holds its type's empty value,
so the body may change `r` and lend it with `mut`; nothing is copied.

```selka
# doc: expect 8
record Env:
    items: int[]
    total: int = 0
    log: str[]


func note(item: int, mut env: Env):
    env.total += item
    append(mut env.log, f"{item}")


func run(mut env: Env) -> int:
    for item in detach env.items:
        if item > 5:
            return len(env.log)
        note(item, mut env)
    return -1


func main() -> int:
    mut env = Env(items=[1, 2, 7], log=[])
    const seen = run(mut env)
    return seen + env.total + len(env.items)
```

- **The place** is a field of a `mut` local, a `mut` parameter or a `match mut` binding, through list elements
  (`detach groups[at].items`). A dictionary value, a call, a plain value, two loop names and a place an enclosing `detach`
  loop has set aside are `E_ITERATION`.
- **What leaves.** The value of a `return` or `fail` is computed first, then the list is put back, so
  `return len(r.items)` inside the loop sees the empty list. A value that borrows the loop variable or the list
  (`return x`) is `E_SINGLE_OWNER_OVERLAP`: return `copy(...)` of it, or a position.
- **`try`** in the loop must be a declaration's value or a statement of its own (`E_TRY_POSITION` otherwise), and `on fail:`
  clauses run before the list is put back.
- **A place written while set aside** traps `R_ASSERT` at the put-back: collect new elements in a list of their own and add
  them after the loop.

## Long-lived data: hold the key, not the borrow

A record that leaves its function cannot hold a borrow, so a structure that points into something else (a file's tokens, a
design's names, a cache's entries) either copies what it points to, the slow path, or holds a name for it. For data that
outlives the code that made it, hold a name:

| The data points to | Hold | Read it |
| --- | --- | --- |
| text of a file that lives as long as the program | a [`spans.Span`](standard-library.md#spans) | `spans.text(sources, span)` |
| a name repeated in many places | a [`symbols.Symbol`](standard-library.md#symbols) | `symbols.name(table, symbol)` |
| an entry of a table that grows (a cache, a pool of records) | the entry's key: an index or a `Symbol` | `table.entries[key.id]`, in place |

See [Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer).

A cache is a table, and the call that fills it answers the key of the entry, not the entry. A key is an integer, so the caller
can hold two across any number of `mut` calls; a borrow of an entry is invalidated by the next call that may write the
cache, so a caller of `lookup(mut cache, name)` cannot hold two of its results:

```selka
# doc: expect-error E_SINGLE_OWNER_OVERLAP
record Pinout:
    pins: int[]

record Cache:
    index: dict[str, int]
    entries: Pinout[]

func load(name: str) -> Pinout:
    return Pinout(pins=[len(name), 1, 2])

# Fills the cache if it must and lends the entry, from the cache.
func lookup(mut cache: Cache, name: str) -> Pinout from cache:
    if name not in cache.index:
        append(mut cache.entries, load(name))
        cache.index[name] = len(cache.entries) - 1
    return cache.entries[cache.index[name]]

func main(out: Stream) -> int:
    mut cache = Cache(index={}, entries=[])
    const first = lookup(mut cache, "U1")
    const second = lookup(mut cache, "J12")
    print(out, len(first.pins), len(second.pins))
    return 0
```

Split the call in two: `ensure` writes and answers the key, a read-only function reads in place:

```selka
# doc: expect 3 3 0 1
record Pinout:
    pins: int[]

record Cache:
    index: dict[str, int]
    entries: Pinout[]

func load(name: str) -> Pinout:
    return Pinout(pins=[len(name), 1, 2])

# Make sure the entry exists and answer its key.
func ensure(mut cache: Cache, name: str) -> int:
    if name in cache.index:
        return cache.index[name]
    append(mut cache.entries, load(name))
    cache.index[name] = len(cache.entries) - 1
    return len(cache.entries) - 1

# Read an entry in place, through its key.
func pin_count(cache: Cache, key: int) -> int:
    return len(cache.entries[key].pins)

func main(out: Stream) -> int:
    mut cache = Cache(index={}, entries=[])
    const first = ensure(mut cache, "U1")
    const second = ensure(mut cache, "J12")
    print(out, pin_count(cache, first), pin_count(cache, second), first, second)
    return 0
```

With a [`symbols.Table`](standard-library.md#symbols) for the keys, `ensure` interns the name and the symbol's `id` is the
entry's index. The same shape serves a parse that fills a [`spans.Sources`](standard-library.md#spans), a pool addressed by
handle and a memo of a pure function. `selka lint` points a copy in a loop at these forms (`L_COPY_IN_LOOP`:
[Copies in a loop](tooling/lint.md#copies-in-a-loop)).

## Explicit identity and immutable sharing

A `class` declaration is `E_VALUE_CLASS` and builtin `Cell[T]` is `E_VALUE_CELL`. Use records and recursive unions for finite
trees; a graph with cycles or observable identity uses `pool.Pool[T]`, `pool.Handle[T]` or another explicit id and store
([pool](standard-library.md#pool); `pool.get` copies the whole record).

```selka
# doc: expect-error E_VALUE_CLASS
class Node:
    next: Node?
```

```selka
# doc: expect-error E_VALUE_CELL
func read(slot: Cell[int]) -> int:
    return slot.value
```

## How it is implemented

Every dynamic allocation has one owner, and the compiler places destruction after the last use on every path; there is no
copy-on-write fallback. `selka build --release --stats`, `selka dump-ir` and `selka cost` expose its decisions.

## Limits

- Resources cannot be copied or hidden in ordinary managed containers. A capability is a shareable handle: copies of it share
  one provider ([io](io.md#records-that-hold-capabilities)).
- A text or bytes view keeps a named owner alive through its last use, and a loop's element is such an owner:
  `for net in nets: const tail = net.name[1:]` binds a view that holds `nets` while `tail` is used.
- A write to a local copy stays local unless it is returned or stored back.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/value-semantics.md).
