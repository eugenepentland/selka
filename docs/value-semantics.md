# Value semantics

Collections and records are independent values. Checked ownership implements
that rule with moves, read-only borrows, explicit copies and compiler-inserted
destruction. Plain `check`, `run`, `build` and `test` use this model.

Every use of a managed value is one of four verbs: **lend** (the bare name; an ordinary
parameter borrows), **lend for writing** (`mut name`; a `mut` parameter), **give**
(`own name`; an `own` parameter) and **duplicate** (`copy(name)`). Three rules govern them.
**Escape**: a lent value cannot be stored or given anywhere that outlives its lender.
**Exclusion**: a lender cannot change or be given away while something it lent is in use,
and a loan for writing is the only loan. **Gone**: after `own`, the name cannot be used
until it is assigned again. The sections below teach them one use at a time; the
[ownership reference](ownership-rules.md#the-model) states the model with its spellings
and files every numbered rule under one of its headings.

Moving managed storage from a named binding requires `own`: `mut next = own previous`
transfers its owner. `const next = previous` instead borrows read-only. Only when
both values must stay independently usable is `copy(value)` needed. A function changes
its caller's value through a `mut` parameter, marked `mut` at the call site.

```selka
# doc: expect 12
func main() -> int:
    mut a = [1]
    mut b = copy(a)
    append(mut b, 2)
    return len(a) * 10 + len(b)
```

This returns `12`: appending to `b` leaves `a` with one element. Without the
explicit copy, `mut b = a` needs an `own` marker (`E_OWN_MARKER`). Writing
`mut b = own a` transfers `a`, and a later read of `a` is rejected.
Ordinary parameters borrow their arguments, so calling a read-only helper does
not consume the caller's value.

The old `--experimental-zero-rc` and `--experimental-single-owner` selectors
are rejected with status 2 because reference counting was removed. The earlier
`--value-semantics` and `--legacy-sharing` switches remain rejected with status 2.

## The rules

**Named moves are explicit.** Write `own` when a managed binding moves into another
binding, an assignment, a field, a container, a constructor or an owning argument:
`const next = own previous`, `rows[i] = own row`, `Row(items=own items)`,
`Some(own items)`, `[own first, own second]` and `take(own items)`. A bare
`return items` needs no marker; `return own items` is refused. A constructor in a
return still marks its named managed inputs, as in `return Some(own items)`.
Fresh values from calls, literals, operators and `copy(...)`, and scalar values,
never take `own`. Missing or misplaced markers report `E_OWN_MARKER`.

**A `const` place borrows.** `const next = previous` borrows even when `previous`
is a local owner or an `own` parameter. The borrow lasts through `next`'s last use
in its block, so its owner cannot change or move while `next` remains live. To give
`next` ownership, write `const next = own previous` or `const next = copy(previous)`.
An `own` marker on a later use cannot turn a borrowed binding into an owner.

**A record of borrows is a borrow.** A constructor whose managed fields all read
places without `own`, `Spot(net=bank.power, x=1)`, copies and moves nothing: the
record borrows its fields' owners until its last use, as a `const` of a place does.
It may be a read-only call argument, a `const` or a `mut` local, or a result under
`from`; storing or moving it needs `copy(...)` or `own` on its fields. See
[B9](ownership-rules.md#b9--const-place-bindings-borrow).

**A field transfer consumes its record.** `own record.items` transfers `items`,
makes the whole record unavailable and destroys its other fields at that point.
One statement may move several fields of one owned record, each once
(`total(own p.lo, own p.hi)`): the record is consumed at the first of them and only
the fields no move names are destroyed there. Use `copy(record.items)` when the
record must remain usable. Updating a field in place keeps the record's ownership.

**Borrowed results are declared.** `-> T from first, second` declares the possible
plain or `mut` parameter sources. Some standard library accessors use this contract
(`json.get`, `json.at`, `json.as_str`). A caller reads the result in place, binds it
with `const`, or returns it onward under its own matching `from` contract. Only
storing it as an owner, moving it or passing it `mut` or `own` needs `copy(...)`
around the call. See [Borrowed constants](managed-memory.md#borrowed-constants).

**A copy owns independent storage.** Move (`own`) what its owner is finished with;
copy a borrowed parameter, field or element only when both must live on. Copies
recursively duplicate owned children; scalar copies preserve their values.

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

A parameter itself stays read-only: `xs.append(9)` in `appended` is
`E_MUTATION_MARKER`. Use a `mut` parameter when the caller should observe the
change, or copy into a mutable local when it should remain independent.

**`mut` parameters update caller storage.** A field assignment, supported nested
collection update or whole-value rebinding through a `mut` parameter reaches
the caller. Scalar `mut` parameters follow the same rule.

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

A writable call must not overlap another active borrow of its argument. If a
helper needs an independent earlier value, take the copy before the call.
F-string holes follow the same loan rules: a later mutation cannot invalidate an
earlier managed hole. Materialize the earlier text or copy its value before the
mutation.

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

**Finish an overlapping call before updating its receiver.** A statement such as
`items[selected(mut items)] = 9` overlaps its mutable argument with the receiver
being updated. Save the call result, then select from the current receiver:

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

Two mutable arguments must address disjoint storage. When a shape cannot be
proved safe, copy one value into a local, call the helper, and store it back.
Loop and match bindings borrow their source: consume an owned source with
`for x in own xs:` or `match own name:`, whose bindings own their payloads; copy
a binding only if the source lives on. Where a `match name:` statement (or `const x = name else:`) copies a payload and `name` is an owned local that
nothing reads after it, `selka fix` writes `match own name:` and `own payload` itself. A `mut` local assigned more than once, each time from a place
(`mut net = port.name`, then `if ...: net = port.net`) borrows like a `const` of a
place, so a default chosen by a condition needs no copy unless the local is changed
or kept ([B9](ownership-rules.md#b9--const-place-bindings-borrow)). Writing into an unnamed returned temporary is
`E_VALUE_TEMPORARY_WRITE`: bind the result first, then change or store it. An element of a new list, one a call
returns or a literal, needs no copy where a value is taken: `const piece = strings.split(text, sep)[1]` moves the
element out and drops the rest of the list
([B7](ownership-rules.md#b7--no-moving-out-of-a-container)). A read that keeps nothing of a record constructor's field,
`len(Name(text=own t).text)`, checks as it does for a call's result: the record lives to the end of the statement and is
destroyed there with its other fields, and so does a text slice read in the same way, `len(Name(text=own t).text[0:2])`.
Binding the field (`const text = Name(text=own t).text`), or binding, storing or returning its slice, would keep the temporary
and stays refused, with the `copy(...)` that keeps both, or the record bound to a local first. In the same way `maybe().unwrap_or("")`, on the option a
call returns and with a default of its own, gives an owned value where a value is taken; `o.unwrap_or(d)` on a local
option borrows it, and `options.take_or(own o, d)` moves the value out
([R6](ownership-rules.md#r6--borrowed-selections)).

## Taking and exchanging a value

`take(mut place)` moves the value out of a writable place and leaves that type's default value in
its place: an empty list, dictionary, set, text or bytes, `None` for an optional, or, for a record
whose fields all have defaults, the record those defaults build (what `Block()` builds).
`exchange(mut place, value)` moves the old value out and puts `value` in, for a value of any type:
a record, a union, a scalar or a collection. Either way the moved value is the call's result,
owned by the caller, and nothing is copied. A place is a local, a record field of one (a field of
a field works too), a list element `xs[i]`, a field of one `xs[i].f`, an element of an element
`grid[i][j]`, or a `match mut` payload binding and its fields. A template body may use both on a
place of a generic type, and each specialization decides the default value.

The place is borrowed `mut`, as `append` borrows its list: the marker is required, `own` there is
refused with the repair `mut`, and no other argument takes `mut`. The replacement of `exchange`
moves in under the ordinary rule for a move (B2): a fresh value (a literal, a call result,
`copy(value)`) takes no marker, and a named value takes `own`, as in `exchange(mut holder.items,
own fresh)` and `append(mut rows, own piece)`. A replacement built from the place itself
(`exchange(mut xs, own xs)`) is refused, because the replacement is built before the place is
read and moving the owner leaves nothing to write. An element place is written the way
`rows[i] = value` writes it: the index is checked (`R_LIST_BOUNDS`) before anything moves, and a
live borrow of the list, a loop over it or a running `match mut` arm on it holds the whole list,
so the take is refused while it lasts (`E_SINGLE_OWNER_OVERLAP`). An exchange inside a writer's
argument may write another field of the record that holds the writer's receiver, as
`append(mut builder.done, exchange(mut builder.block, Block()))` does; two elements of one list
stay refused there, even at different literal indices.

`selka fix` writes a `take` for a copy of a field or an element of a local that nothing reads again; a `const` local
becomes `mut` in the same repair, one edit for the declaration however many of its fields are taken. A parameter, a loop
variable, a pattern binding and a local a view reads keep the copy
([Moves instead of copies](tooling/lint.md#moves-instead-of-copies)).

Refused: an unmarked argument, a binding that is not `mut`, a place that a live borrow holds, a
dictionary value `d[k]` (move it out with `d.pop(k)` until the dictionary exchange lands), an
octet of text, a call result, and a value of another type (`E_ASSIGNMENT_TARGET`, `E_TYPE`).
`take` of a type with no default (`int`, a record with a field that has none, a union) is
`E_TAKE_TYPE`, whose message names the `exchange` to write instead, and neither moves a resource,
a capability or a pending result. A bare `take(...)` or `exchange(...)` is always the prelude
function: a module function with either name is refused when its module calls it bare
(`E_BUILTIN_FUNCTION_NAME`).

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

A named replacement moves in with `own`, and an optional place leaves `None` behind:

```selka
# doc: expect 42
record Slot:
    pending: int[]?
    items: int[]

func main() -> int:
    mut slot = Slot(pending=Some([1, 2]), items=[3])
    const fresh = [4, 5, 6]
    const old = exchange(mut slot.items, own fresh)
    const waiting = take(mut slot.pending)
    if waiting is None or slot.pending is not None:
        return 0
    return len(old) + len(slot.items) + 38
```

An element, a field of one, a record with defaults and a `match mut` binding are places too:

```selka
# doc: expect 7
record Block:
    items: int[] = []
    name: str = "block"


record Builder:
    block: Block = Block()
    done: Block[] = []


func finish(mut builder: Builder):
    # The record field moves out whole and its defaults stay behind.
    const old = exchange(mut builder.block, Block())
    append(mut builder.done, own old)


func main() -> int:
    mut builder = Builder()
    append(mut builder.block.items, 1)
    finish(mut builder)
    append(mut builder.block.items, 2)
    finish(mut builder)
    # An element's field moves out of the list in place.
    const first = exchange(mut builder.done[0].items, [5, 6])
    mut rows = [[1, 2, 3], [4]]
    const row = take(mut rows[0])
    const whole = take(mut builder)
    return len(first) + len(row) + len(whole.done) + len(rows[0]) + len(builder.done) + len(whole.done[0].items) - 1
```

## Consuming a list in a loop

`for x in own xs:` takes the list and gives each element to the body as its owner: `own x`
moves it into a list, a dictionary, a record or a return, and nothing is copied. A loop
variable of an ordinary `for` borrows its element, so storing it needs `copy(x)`, left for
a list that must live on. The list must be one the function owns: an owned local, an `own`
parameter, or the new list a call returns (`for row in own rows():`), which the loop owns exactly
as if it had been bound to a local on the line before.

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

`selka fix` rewrites `for x in xs:` with `append(mut out, copy(x))` to this form when `xs` is an owned local or an `own`
parameter that nothing else reads, and `selka lint` points at it for a plain parameter or a field.

The elements come out in order. One the body does not move is dropped at the end of its
iteration, and a `break`, `return` or `fail` drops the ones the loop has not reached. The list's
name is moved from the loop on, so a use of it inside the body or after the loop is
`E_SINGLE_OWNER_MOVED`; a `mut` local can be assigned a new list afterwards. A `mut` or borrowed
parameter, a field (`own h.items`), a `const` binding of a place, a dictionary and two names
(`for i, x in own xs:`) are refused, most as `E_ITERATION` with the line to write instead:
`mut items = take(mut values)` for a `mut` parameter's list, `mut items = copy(values)` for a
borrowed one. A call whose result is lent by its argument (declared `from` it) is refused as
`E_SINGLE_OWNER_BORROW`, which says so and offers `for x in own copy(first(xss)):`. A list literal
cannot follow `own` here: `own [0]` already reads element 0 of a local named `own`.

```selka
# doc: expect 3
record Row:
    name: str


func rows() -> Row[]:
    return [Row(name="a"), Row(name="bb")]


func main() -> int:
    mut names: str[] = []
    for row in own rows():
        append(mut names, own row.name)
    return len(names[0]) + len(names[1])
```

## Setting a list aside for a loop

`for x in r.items:` borrows `r.items` until the loop ends, so a call inside it that may change `r`
(`note(x, mut r)`) is `E_SINGLE_OWNER_OVERLAP`. When the call changes only another field, pass that field
(`note(x, mut r.total)`). When it needs the whole record, `for x in detach r.items:` moves the list out of
its place for the loop and puts it back at every exit: when the loop runs out, at `break`, `return` and
`fail`, and when a `try` in it fails. Inside the loop `r.items` holds its type's empty value, as after
`take(mut r.items)`, so the body may change `r` and lend it with `mut`; nothing is copied.

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

`run` returns 2 at the third item, after the list is back: `2 + 3 + 3`.

- **The place** is a field of a `mut` local, a `mut` parameter or a `match mut` binding, through list
  elements (`detach groups[at].items`); each index is a number or a name the loop cannot change. A
  dictionary value, a call, a plain value, two loop names, and a place that an enclosing `detach` loop has
  set aside (or one inside it) are `E_ITERATION`. The loop variable is read-only, as in any `for` loop.
- **What leaves.** The value of a `return` or `fail` is computed first, then the list is put back, then
  the value leaves; so a `return len(r.items)` inside the loop sees the empty list. A value that borrows
  the loop variable or the list (`return x`, `return x.name`) is `E_SINGLE_OWNER_OVERLAP`: return
  `copy(...)` of it, or a position, and read the element after the loop.
- **`try`** in the loop is a declaration's value or a statement of its own (`const value = try f()`,
  `try f()`); `x = try f()`, `return try f()` and a `try` in a call's argument are `E_TRY_POSITION`. In a
  function that returns an optional, write `const value = f() else: return None` instead of `try`.
  `on fail:` clauses run before the list is put back.
- **A place written while set aside.** If the body, or a function it calls, puts a new list in the place
  (`append(mut r.items, x)` through `r`), putting the loop's list back would lose one of the two, so the
  put-back traps `R_ASSERT` with a message that names the place and the loop's line. Collect new elements
  in a list of their own and add them after the loop.

```selka
# doc: expect 6
record Env:
    items: int[]
    total: int = 0


func checked(n: int) -> int fails str:
    if n > 5:
        fail "too big"
    return n


func add_all(mut env: Env) -> Unit fails str:
    for item in detach env.items:
        const value = try checked(item)
        env.total += value


func main() -> int:
    mut env = Env(items=[1, 2, 7])
    match add_all(mut env):
        case Ok(_):
            pass
        case Err(_):
            pass
    return env.total + len(env.items)
```

The `try` fails at 7; the list is back before the error leaves, so `env.items` still holds three items.

## Long-lived data: hold the key, not the borrow

A record that leaves its function cannot hold a borrow (a local record may hold whole values and places, never a slice:
[Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer)), so a structure that points into something else (the
tokens of a file, the names of a design, the entries of a cache) either copies what it points to or holds a name for it. The first is
the slow path, and it is what a port from a language with slices and pointers writes by reflex. The second is the default for data
that outlives the code that made it, in four forms:

| The data points to | Hold | Read it |
| --- | --- | --- |
| text of a file that lives as long as the program | a [`spans.Span`](standard-library.md#spans) | `spans.text(sources, span)` |
| a name repeated in many places | a [`symbols.Symbol`](standard-library.md#symbols) | `symbols.name(table, symbol)` |
| an entry of a table that grows (a cache, a pool of records) | the entry's key: an index or a `Symbol` | `table.entries[key.id]`, in place |
| a value that is only used inside one function | nothing: borrow it | the borrow, until its last use |

[Keeping pieces of a buffer](ownership-rules.md#keeping-pieces-of-a-buffer) takes one parser through these forms in order, from a slice
that is read and dropped, through `from`, spans and a move, to `copy` last, with the refusal that sends you to each.

A cache is a table. The call that fills it answers the key of the entry, not the entry, and the caller reads the entry through the
key when it needs it. A key is an integer, so the caller can hold two of them across any number of `mut` calls on the cache; a
borrow of an entry is invalidated by the next call that may write the cache, which is why `lookup(mut cache, name)` that fills the
cache and lends the entry in one call can be written, but its caller cannot hold two of its results:

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

With a [`symbols.Table`](standard-library.md#symbols) for the keys, the dictionary of names disappears: `ensure` interns the name,
and the symbol's `id` is the index of the entry (`tests/lang/symbol_tables.selka` has the whole cache). The same shape serves a
parse that fills a [`spans.Sources`](standard-library.md#spans) and answers the file number, a pool of records addressed by handle,
and a memo of a pure function. Whatever the table holds, what the rest of the program stores is the key.

`selka lint` points a copy in a loop at these forms: `L_COPY_IN_LOOP` says `spans.Span` for a slice of text kept in a record,
`symbols` for the same name copied on every iteration, and a move for a source that is not read again
([Copies in a loop](tooling/lint.md#copies-in-a-loop)).

## Explicit identity and immutable sharing

A `class` declaration is `E_VALUE_CLASS`, and builtin `Cell[T]` is `E_VALUE_CELL`.
Use records and recursive unions for finite trees. A graph with cycles or
observable identity uses `pool.Pool[T]`, `pool.Handle[T]` or another explicit id
and store (a handle's `index` is a readable slot number, and `pool.get` copies the whole record: see
[pool](standard-library.md#pool)). Immutable text and byte parameters borrow just like collections;
keeping a second owner requires an explicit copy.

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

## Contracts

`old(copy(xs))` in an `@ensures` clause captures an independent value, and the copy
is written: a bare `old(xs)` of a managed value is refused ([contracts](contracts.md)). `@noalloc` is a build-time assertion on
ownership-expanded Core: a possible managed allocation is an
`E_NOALLOC_ALLOCATES` error. Explicit copies can allocate.

## How it is implemented

Every dynamic allocation has one owner. Marked stores and owned returns transfer
that owner; read-only calls borrow it, and `mut` calls borrow exclusively. The
compiler places direct destruction on every path after an owner's last use,
including early returns and checked error propagation. It rejects a later use
of a moved value, an escaping borrow or overlapping mutation. There is no
copy-on-write fallback.

A release build can eliminate an explicit copy when the source dies and the
result can take over its storage. This preserves the program's values while
reducing allocation. `selka build --release --stats`, `selka dump-ir` and
`selka cost` expose static compiler decisions; runtime counters describe
executed allocations, copies and destruction (`docs/tooling/ownership.md`).

## Limits

- Resources cannot be copied or hidden in ordinary managed containers. Keep them in
  their supported scopes. A capability is a shareable handle: copies of it share one
  provider, as copies of the real filesystem see one tree ([io](io.md#records-that-hold-capabilities)).
- Read-only text and byte views keep a named owner alive through their last use;
  changing or moving that owner while a view is used is rejected. A loop's element is such an owner:
  `for net in nets: const tail = net.name[1:]` binds a view that holds `nets` while `tail` is used.
- A write to a local copy stays local unless it is returned or stored back.

## Ownership history

Reference counting and copy-on-write were retired on 17 October 2026, following
the checked ownership default. The earlier
reference-counting design (`docs/adr/D9-value-semantics-then-rc.md`) and its automatic
copy-on-write rules are retained as history. Current programs use explicit
copies where two independent owners are required.
