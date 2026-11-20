# Managed collections

Lists, dictionaries, sets, strings and byte buffers live in managed storage.
Checked ownership is the only model: each dynamic allocation has one owner, ordinary
parameters borrow, and the compiler destroys owned storage after its last use.
Application code needs no allocator or explicit free.

Every use of a managed value is one of four verbs:

| Verb | In an expression | In a signature |
| --- | --- | --- |
| lend | the bare name: `size(values)`, `const view = values` | a plain parameter; a result under `from values` |
| lend for writing | `mut name`: `append(mut values, 3)` | a `mut` parameter |
| give | `own name`: `keep(own values)`, `mut next = own values` | an `own` parameter; a result without `from` |
| duplicate | `copy(name)`: `mut next = copy(values)` | none: the copy is a fresh value |

Three rules say what they may do. **Escape**: a lent value cannot be stored or given
anywhere that outlives its lender. **Exclusion**: a lender cannot change or be given away
while something it lent is in use, and a loan for writing is the only loan. **Gone**: after
`own`, the name cannot be used until it is assigned again. A value built from lent parts is
itself lent. `own` marks moves from named managed bindings: `mut next = own values`
transfers the owner, while `const next = values` borrows read-only. Use `copy(value)` when
both values must remain independently usable.

The [ownership rules](ownership-rules.md#the-model), also available with
`selka docs ownership`, open with this model and file every numbered rule under one of
the three rules, the current limits, the applications to resources, task groups and
pending Results, or an appendix of accepted behaviour. They also give the checking layers
and the diagnostic code map for the current compiler.

```selka
# doc: expect 1
# doc: expect 2
func main(out: Stream) -> int:
    mut values: int[] = [1]
    mut alias = copy(values)
    append(mut alias, 42)
    print(out, len(values))
    print(out, len(alias))
    return 0
```

The explicit copy above leaves `values` usable after `alias` changes. Appending
grows capacity automatically. Reading a managed element borrows its storage;
copy it when an independent owner must outlive or change the collection. Use a
`mut` parameter with a marked call when a helper must change its caller's value
([value semantics](value-semantics.md)).

Use `Node[]` for application collections and `mut nodes: Node[] = []`
for an empty list. Read with `nodes[index]`, write with `nodes[index] = value`,
append with `append(mut nodes, value)`, and count with `len(nodes)`. An empty literal
needs an expected list type from an annotation, return type, or parameter.

Capacity is a reserve hint, not a fixed limit. Mutations such as `append` return `Unit`; `pop` returns the removed element. Invalid
indices trap with `R_LIST_BOUNDS`. Allocation failure ends the program with
status 1 (`R_MEMORY_BUDGET` under a byte ceiling, `fatal: out of memory` without
one) rather than returning a recoverable collection result. Keep
application cardinality checks where input limits are part of its contract.

List elements can be ordinary copyable values, records, and other managed lists.
Recursive record types are supported, but stored values are independent; use
explicit pool handles for identity-bearing graphs:

```selka
# doc: check
record Node:
    value: int
    children: Node[]
```

`record` and its mutable managed fields are values. The builtin `Cell` and `class`
are rejected; replace identity-bearing graphs with records plus stable ids in a pool
or object table. Capturing closures remain absent. Byte literals and the managed
[`bytes`](bytes.md) type keep their documented behavior. Owned resources and
must-handle results cannot be hidden inside copyable lists; a capability is a shareable
handle and may be. There
are no interior pointers into managed storage.

## Releasing memory

The compiler inserts direct destruction for owned allocations. Assignments and
container stores mark named managed inputs with `own`; `copy(value)` requests
independent storage. A bare `return value` or `fail value` needs no marker, while
named inputs inside a returned or failed constructor still do, as in
`return Some(own value)`. A constructor whose managed fields all borrow places owns
nothing and is never destroyed: it is a borrow of those places
([B9](ownership-rules.md#b9--const-place-bindings-borrow)).
A slice of text or bytes is a read-only view of a named owner: it borrows the
owner's storage. Text, bytes and list slices can return under an explicit
`from` contract. Mutation or moving an owner while its view is still used is rejected.
The prototype `TextView`, `ByteView`, `.borrow()` and `.view()` spellings were
removed; a slice is what a view is. Files use `with` scopes; a capability is a
handle the runtime keeps until the process or the test trial ends, so nothing destroys it. There is no implicit sharing or copy-on-write fallback.

`try` transfers the active payload of an owned `Result` or `Option` directly.
It does not make a deep copy. `match` on a fresh call result also transfers its
payload, so `match load(): case Ok(value): return value` needs no copy. Matching
a named value (`match saved`) or a field/index continues to borrow, even at its
last use; `match own saved` consumes an owned local or `own` parameter instead, so
its payload transfers as a fresh result's does
([consuming matches](match-expressions.md#consuming-matches)). A fresh constructor, `copy(value)`, `lists.pop` or `lists.exchange` result follows the
same transfer rule as a call, as do fresh results from text/byte decoding,
validation and numeric parsing, and from file reads and directory listings
(`match fs.read_file(path): case Ok(data): return data` needs no copy, and
`return Some(own data)` or a bare return from a `bytes fails str` function transfers it the same way). A named-field pattern on a fresh owned match
splits the whole payload: `case parts(left=a, right=b)` gives `a` and `b`
independent ownership. Fields bound to `_` or unused in the arm are destroyed.
The hidden payload is consumed as a whole; ordinary `record.field` reads and
patterns on named values still borrow. An explicit `own record.field` (or
`own payload.field` of a consumed payload) consumes
the whole record and destroys its other fields; copy the field to keep the record
usable. Nested patterns also borrow their inner
intermediate value; the immediate fresh payload is split. To own a payload that lies two or more layers down, bind the layer and
match it with `match own`, one layer at a time (`case Ok(inner):`, then `match own inner:` with `case Some(v):` and `own v`); the
refusal of a `v` that only borrows writes this out for the pattern it finds, or offers `copy(v)`.
`copy(value)` explicitly requests an independent owner. When the copy carries no
value — the use only reads it, or it is the value's last use — the checker says
so with `W_NEEDLESS_COPY` and the edit that deletes the call, and
[`selka lint`](tooling/lint.md#needless-copies) reports it as
`L_NEEDLESS_COPY`. See the owned-payload and fresh-match experiments (the design records
`experiments/owned-payload-20261011/README.md` and `experiments/owned-match-20261011/README.md`).

JSON `get` and `at` borrow the input container: the selected member or element is
read in place, and nothing is copied. `as_str`, `as_list` and `as_dict` borrow the
payload of the value they are given. Missing keys, wrong variants and out-of-range
indices return `None` without copying the container. Write `copy(...)` around the
call to keep an answer past the next change to its document. A match can read the
borrowed result in place; its payloads retain the document's lifetime.
See the JSON lookup and field-transfer measurements (the design record
`experiments/zero-rc-batch-20261011/README.md`) for examples, allocation counts, and runtime comparisons.

Owned storage is destroyed when its last use ends: a local after its final use,
a temporary after its expression, and a stored child when its parent is destroyed.
The last use is a real one, a read, a call or a move that does something with the value:
the end of its block is not a use, and neither is a discard written at the end,
`_ = own value`, which does not keep the value alive: the compiler destroys it after the
last use above that line. A value whose end is visible from outside (an open file, a poller and the
listener inside it, a connection) therefore closes after its last other use, which can be
above a call written earlier than the discard. To hold one open on purpose, use it
where it must still be alive, or close it where it should end
([an example](standard-library.md#in-memory-network)).
The compiler places cleanup on every control-flow path
([ownership](ownership-rules.md)); application code never adjusts counts.
Heap allocation and explicit copies still have a cost. Use pool handles for
identity-bearing graphs and ordinary owned values for finite trees.

```selka
# doc: expect 1225
func batch(size: int) -> int:
    mut scratch: str[] = []
    for index in range(size):
        append(mut scratch, f"item {index}")
    return len(scratch)

func main() -> int:
    mut kept: int[] = []
    for step in range(50):
        append(mut kept, batch(step))
    mut total = 0
    for value in kept:
        total += value
    return total
```

Every `scratch` list and every interpolated string in that program is released when
`batch` returns. Dictionary views are ephemeral; stored snapshots use explicit
`list(...)` materialization, and view types cannot appear in parameter, return,
field or element annotations.

`@noalloc` promises that a function performs no managed allocation. `build`,
`run`, `build --run` and `test` fail with `E_NOALLOC_ALLOCATES` when
ownership-expanded Core finds a may-allocate site, including a transitive or
unresolved call. `lint --gate` also blocks the `noalloc-allocates` rule. Plain
`check` validates source types and ownership without computing this whole-program
allocation contract. The promise excludes runtime bookkeeping. Explicit copies
and collection growth can allocate; mutation alone does not imply allocation.
Every process that runs a program under `selka run` or `selka test` has a byte
ceiling ([guest memory ceilings](tooling/runtime-budgets.md#guest-memory-ceilings)).

`with arena():` blocks, which once released a phase's objects in bulk, were retired
([retired arenas](#retired-arenas)). The tracing collector and its `--gc-runtime` and
`--gc-stress` switches were retired with them.

## Retired arenas

`with arena():` regions released every managed object a phase of work allocated in
one step. They were retired in stage S5 of the new compiler core (2026-10): every
object is now released as soon as its last owner goes away, so a region has nothing
left to free early.

A `with arena():` or `with arena() as name:` block is rejected with
`E_ARENA_REMOVED`. Use ordinary statements. The diagnostic keeps its structured
repair even when another semantic error is present. The old escape checks
(`E_ARENA_ESCAPE`, `E_ARENA_BINDING`) are gone.
`selka fix` migrates a file: it deletes the `with arena():` line, dedents the
block's body by one level and rewrites `name.escape(value)` to `value`
([fix](tooling/fix.md)).

```selka
# doc: expect-error E_ARENA_REMOVED
func main() -> int:
    with arena():
        return 0
```

When removing the scope would collide with another binding, or an arena name
is shadowed, the diagnostic leaves the repair to the author. It does not guess
which variable an escape call meant.

## Managed lists

`T[]` is the growable sequence application code reaches for. Its storage is
managed, so there is no allocator argument to thread and no free to write.
`mut next = own values` transfers ownership and ordinary parameters borrow;
`copy(value)` makes an independent value. Elements must be
copyable storable values — scalars, records, strings, byte strings and other
managed collections — which keeps owned resources and
unchecked results out of copyable storage; a capability is a scalar handle and may be an element. Reading an element borrows managed contents; `copy(value)` produces an independent
owner. It never exposes an unchecked interior pointer into growable storage.

```selka
# doc: expect 42
func widen(mut target: int[]) -> Unit:
    append(mut target, 2)

func main() -> int:
    mut values: int[] = [40]
    mut alias = copy(values)
    widen(mut alias)
    return values[0] + alias[1]
```

Here `widen(mut alias)` changes `alias` to `[40, 2]`; `values` remains `[40]`.

## List methods and indexing

A list answers the everyday vocabulary. `append(value)` and `extend(other)` add
one element or copy another list's elements to the end; `insert(index, value)`
inserts at a nonnegative position, clamping a position past the end to the
length; `pop()` removes and returns the final element and `pop(index)` removes and
returns an indexed element; `exchange(index, replacement)` replaces an existing
element and returns its former value without changing length or order;
`remove(value)` deletes the first equal element;
`reverse()` reverses in place; `sort()` orders integer, `float`, `str` or `bytes`
elements ascending, and `sort(key=f, reverse=True)` orders any list by a key, in
place and stably ([keyed sorting](python-syntax.md#keyed-sorting)); `copy()` returns a fresh list with independently owned managed children; `clear()` empties the list; and
`index(value)` returns the first equal position. Length stays the free function
`len(values)`. Mutators other than `pop` and `exchange` return unit. A discarded
`pop`, `exchange` or `index` result needs its own binding or `_ =`.
In checked ownership mode, `exchange` moves the replacement into the list and
transfers the former element to its result. It evaluates the index and replacement
once in that order, then updates the receiver. Negative indices and an
out-of-range exchange trap with `R_LIST_BOUNDS`. The prelude's `take(mut place)` and
`exchange(mut place, value)` do the same for any place: a local, a record field, an element
(`exchange(mut rows[i], value)`), a field of one (`take(mut rows[i].items)`) or a `match mut`
binding ([taking and exchanging a value](value-semantics.md#taking-and-exchanging-a-value)).

```selka
# doc: expect 42
import lists

func main() -> int:
    mut rows = [[1], [2, 3]]
    mut old = lists.exchange(mut rows, len(rows) - 1, [8])
    append(mut old, 4)
    assert rows == [[1], [8]]
    assert old == [2, 3, 4]
    return 42
```

An element whose payload is a record inside a union can be updated in place
with the same exchange. A union payload cannot be assigned through its element,
and an element read cannot be moved out by index, so the element is exchanged
for a cheap placeholder variant. The arm then owns the payload, updates it, and
an indexed store puts the updated value back. The payload's list field is moved
along with it, not copied.

```selka
# doc: expect 42
import lists

record Account:
    balance: int
    holds: int[]


enum Slot:
    empty
    account(value: Account)


func main() -> int:
    mut slots = [Slot.empty, Slot.account(value=Account(balance=40, holds=[]))]
    # Take the account out of its slot, update it in place, and store it back.
    match lists.exchange(mut slots, 1, Slot.empty):
        case account(value=payload):
            mut updated = own payload
            updated.balance = updated.balance + 2
            append(mut updated.holds, 7)
            slots[1] = Slot.account(value=own updated)
        case _:
            assert False, "slot 1 was empty"
    match slots[1]:
        case account(value=payload):
            assert len(payload.holds) == 1
            return payload.balance
        case _:
            return 0
```

Two of those writes also exist as prelude functions that take the list first:
`append(mut values, value)` and `sort(mut values)`. The marker is the point — `append(mut
values, value)` says on its own line that `values` changes, exactly as a `mut` parameter
does, and it reaches a list held in a field or a slot where a method cannot. `sort(mut
values)` is the plain ascending in-place order, and
`sort(mut values, key=key_function, reverse=True)` is the keyed and reversed form,
which takes the same named operands.

```selka
# doc: expect [1, 2, 3]
record Shelf:
    books: int[]


func main(out: Stream) -> int:
    mut shelf = Shelf(books=[])
    append(mut shelf.books, 3)
    append(mut shelf.books, 1)
    append(mut shelf.books, 2)
    sort(mut shelf.books)
    print(out, shelf.books)
    return 0
```
An absent `remove` or `index` traps with
`R_LIST_VALUE`, `pop` on an empty list traps with `R_LIST_BOUNDS`, and `sort`
without a key rejects an element type that is not an integer, `float`, `str` or `bytes`. The legacy `push` is
gone: it reports `E_REMOVED_SPELLING` and names `append`.

`values[index]` reads a slot and `values[index] = value` overwrites one, so an
indexed write never grows the list. A computed negative index or an
index outside the list traps with a located `R_LIST_BOUNDS` instead of returning a
default, and a constant negative index is `E_NEGATIVE_INDEX_REMOVED`. Receivers may be arbitrary expressions and nested indexes work; the
receiver, the index and the assigned value are each evaluated exactly once, and a
Python-surface indexed write evaluates the assigned value before the target it
writes into. `values += other` extends the receiver value; an earlier copy
retains its contents. Ordering helpers also live in the
[`sort` module](standard-library.md#sort), which returns new lists and leaves its
input untouched.

```selka
# doc: expect 42
import lists

func main() -> int:
    mut scores: int[] = [30, 10, 20]
    sort(mut scores)
    append(mut scores, 40)
    lists.insert(mut scores, 0, 5)
    lists.remove(mut scores, 5)
    lists.reverse(mut scores)
    lists.extend(mut scores, [7])
    _ = lists.pop_at(mut scores, 0)
    mut window = copy(scores)
    append(mut window, 100)
    if len(scores) != 4 or len(window) != 5:
        return 1
    if scores[0] != 30 or scores[len(scores) - 1] != 7:
        return 2
    if lists.index_of(scores, 20) != 1:
        return 3
    lists.clear(mut scores)
    if len(scores) != 0:
        return 4
    return window[0] + window[len(window) - 1] - 88
```

### Concatenating lists

`left + right` on two lists of one element type is a new list holding copies of the elements of `left`, then of `right`, as
`"ab" + "cd"` is new text. Both operands are evaluated once, left first, and neither changes; the result is independent
storage, and a managed element (a `str`, a record, a nested list) is copied, not shared. Two lists of different element types
are `E_TYPE`. `values += other` still extends `values` in place, and `+` is the only arithmetic or ordering a list has: `-`,
`*` and `<` are `E_TEXT_OPERATOR`. A generic function body cannot yet add two `T[]` values; call `lists.extend` on a copy there.

```selka
# doc: expect 42
record Label:
    text: str


func main() -> int:
    const evens = [2, 4]
    const odds = [1, 3]
    mut all = evens + odds + [5]
    append(mut all, 6)
    if all != [2, 4, 1, 3, 5, 6] or len(evens) != 2 or len(odds) != 2:
        return 1
    const tagged = [Label(text="a")] + [Label(text="b")]
    if tagged[0].text != "a" or tagged[1].text != "b":
        return 2
    return 42
```

## Inferred literals and slices

A nonempty list literal infers one homogeneous element type from its elements, so
an annotation is only needed when the literal cannot speak for itself. `[]` has
nothing to infer from: it takes its type from an annotation, field, parameter or
return type, and otherwise reports `E_LIST_INFERENCE`. `values[start:end]` copies
the selected elements into a fresh list; storing that slice in an owned local is
refused until it is written as `copy(values[start:end])`. A computed negative endpoint traps with
`R_LIST_BOUNDS` and a constant one is `E_NEGATIVE_INDEX_REMOVED`; endpoints above the length clamp to the length, a reversed interval produces an empty list, and
an omitted endpoint means the start or the end. The new list and its managed
elements remain independent on later writes.

```selka
# doc: expect 42
func main() -> int:
    mut readings = [3, 12, 7, 20]
    mut empty: int[] = []
    mut window = copy(readings[1:3])
    window[0] = 0
    if readings[1] != 12:
        return 1
    if len(readings[2:99]) != 2:
        return 2
    if len(readings[3:1]) != 0:
        return 3
    if len(readings[max(len(readings) - 2, 0):]) != 2:
        return 4
    return window[1] * 6 + len(empty)
```

## Insertion-ordered dictionaries

`dict[K, V]` keeps its entries in the order their keys were first inserted, and
rewriting an existing key leaves that key in its original position. A key is any
[hashable](sets.md#hashable-keys) value — an integer, `bool`, `str`, `bytes`, or a
record, union, enum, `Option` or fixed array built only from those —
hashed and compared structurally. The table owns each inserted key. A store
`counts[key] = value` with a key written as a place (a name, a field or an element) only reads
the key: the table copies it when the key is new and keeps the copy it already has when the key
is present, so only the value is replaced and a hit allocates nothing. A key that is a fresh
value, `copy(key)` or `own key` is taken as it is, and `own key` moves a named key in so
nothing is copied. A `float`, list, dict,
set, `byte_buffer` or function key is rejected with `E_DICT_KEY` naming the
offending part. Values are any copyable storable
type, including lists and other dictionaries. `counts[key]` traps with
`R_MISSING_KEY` when the key is absent, so `dicts.get(counts, key, fallback)` is the
lookup that always answers. `dicts.keys(counts)`, `dicts.values(counts)` and `dicts.items(counts)`
return live typed views without allocating. Use `list(dicts.keys(counts))` or
`list(dicts.values(counts))` when an independent snapshot is required. `dicts.pop(mut counts, key)` removes and returns
the value and `dicts.pop_default(mut counts, key, fallback)` answers the fallback when absent;
`dicts.update(mut counts, other)` replaces existing values in place and appends new keys;
`dicts.setdefault(mut counts, key, fallback)` returns the existing value or stores the
fallback; `copy(counts)` returns an independent dictionary; and
`dicts.clear(mut counts)` empties it. `dicts.pop(mut counts, key)` without a fallback traps with
`R_MISSING_KEY`. `dicts.items(counts)` yields `DictItem[K, V]` value records with `key`
and `value` fields. A two-name loop `for name, value in dicts.items(counts)` unpacks
those fields. A dictionary held by a named binding moves only with `own`;
use `copy(value)` to retain two independent values. Only a `mut` parameter and
marked call write back to a caller.

Dictionary views are ephemeral. Use `dicts.keys(d)`, `dicts.values(d)` and `dicts.items(d)`
directly as loop sources, or immediately with `len`, `in`,
`list`, `set` or `sorted`. `enumerate(dicts.items(d))` is also a loop source.
They borrow the dictionary without allocating a snapshot. The checker rejects
mutations that overlap the iteration's read borrow. Materialize a separate list
before iterating when the original dictionary must change.

Binding, returning, rebinding, storing or passing a view to a user function is
`E_VIEW_STORED`. `selka fix` wraps a stored projection in `list(...)` where
that migration is certain. The resulting list is an independent snapshot of
the current keys, values or `DictItem` records in insertion order:
`kept = list(dicts.values(mapping))`. Store and pass these lists in records,
collections and helper functions. `list(dicts.items(mapping))[index]` provides
positional item access; the view itself is not indexable.

The prelude names `DictKeys[K, V]`, `DictValues[K, V]` and `DictItems[K, V]`
describe these transient projections. `DictItem[K, V]` remains an ordinary
storable value record. A recursive structure should use ordinary snapshot
lists or pool ids; the former retained-view identity protocol is retired.

A name, field or element key is borrowed, so the table never holds the caller's key and the caller
keeps using it. Copy on insert applies to the store `table[key] = value`, to `dicts.setdefault`, `dicts.add` and `dicts.append_to`,
and to `sets.include`: a call whose key is already there allocates nothing. A key an owned local passes at its last use is
copied on a miss, which a move would not do; write the call with the key as it is, and the copy is the cost of the miss.

```selka
# doc: expect 42
func tally(words: str[]) -> dict[str, int]:
    mut counts: dict[str, int] = {}
    for word in words:
        counts[word] = len(word) + len(counts)
    return counts


func main() -> int:
    const words: str[] = ["pear", "fig", "pear", "plum"]
    const counts = tally(words)
    return len(counts) * 10 + counts["pear"] + counts["fig"] + counts["plum"] - 4 + len(words) - 4
```

```selka
# doc: expect 42
import dicts

func main() -> int:
    mut mapping = {"a": 10, "b": 20}
    mut old_values = list(dicts.values(mapping))
    mapping["b"] = 31
    mut total = 0
    for key, value in dicts.items(mapping):
        total += value
    return total + old_values[1] - 19
```

```selka
# doc: expect 42
import dicts

func main() -> int:
    mut counts: dict[str, int] = {}
    counts["pear"] = 2
    counts["apple"] = 6
    counts["pear"] = counts["pear"] + 1
    dicts.update(mut counts, {"plum": 4})
    _ = dicts.setdefault(mut counts, "fig", 5)
    if dicts.setdefault(mut counts, "fig", 9) != 5:
        return 1
    if dicts.pop(mut counts, "plum") != 4:
        return 2
    if dicts.pop_default(mut counts, "kiwi", 7) != 7:
        return 3
    mut order: str[] = []
    for name in counts:
        append(mut order, copy(name))
    if order[0] != "pear":
        return 4
    if dicts.get(counts, "plum", 0) != 0:
        return 5
    mut keys: str[] = []
    mut total = 0
    for name, value in dicts.items(counts):
        append(mut keys, copy(name))
        total += value
    if keys[0] != "pear" or keys[1] != "apple" or keys[2] != "fig":
        return 7
    mut copy = copy(counts)
    dicts.clear(mut copy)
    if len(copy) != 0 or len(counts) != 3:
        return 6
    return total * 3
```

## Iterating collections

`for name in source` visits a list's elements, a string's Unicode scalar values,
a [byte string](bytes.md)'s octets as `int`, and a dictionary's keys in insertion
order. `for key, value in dicts.items(counts)` visits each dictionary entry, binding the
key and its value in insertion order. `for index, value in enumerate(source)` adds
the position, and
`for index in range(end)`, `range(start, end)` or `range(start, end, step)` counts
integers (a negative step counts down; see
[stepped ranges](range-iteration.md#stepped-ranges)). `break` and `continue` carry their Python meanings. Iteration over a managed collection holds a read borrow, so checked ownership
rejects overlapping mutation or transfer. The generated runtime length checks
remain a defensive backstop and report `R_LIST_ITERATION_MUTATION` if their
invariants are violated.

```selka
# doc: expect 19
import strings

func main() -> int:
    mut words = ["alpha", "beta"]
    mut letters = 0
    for word in words:
        for letter in strings.chars(word):
            letters += 1
    mut weighted = 0
    for index, word in enumerate(words):
        weighted += index * strings.char_count(word)
    mut octets = 0
    for octet in b"\x01\x02":
        octets += octet
    mut counts: dict[str, int] = {"a": 1, "b": 2}
    mut keyed = ""
    for key in counts:
        keyed = keyed + key
    if keyed != "ab":
        return 1
    mut stepped = 0
    for number in range(1, 5):
        if number == 3:
            continue
        if number == 4:
            break
        stepped += number
    return letters + weighted + octets + stepped
```

## Membership and value equality

`in` and `not in` ask a container about its contents: a dictionary for a key,
a set for an element, a string for a substring, and a byte string for a single octet or a
contiguous subsequence. A list has no `in`: `2 in xs` is
`E_LIST_MEMBERSHIP_REMOVED`, so search it with `lists.contains(xs, 2)`. The needle is evaluated
before the container, and each is evaluated exactly once. Either operand may be anything `==` takes,
a field of a call's result included (`"empty" in parse(args).problem`): the operator only reads its
operands, and the call's result lives to the end of the statement. `==` and `!=` compare
contents rather than identities, recursing through nested lists, dictionaries,
plain records, fixed arrays, unions, `Result` and `Option` values; dictionary
equality ignores insertion order. A type that reaches a callback or resource
has no equality and is rejected with `E_TYPE`. There is
no identity comparison operator, so two separately built lists holding equal
elements are equal.

```selka
import lists
# doc: expect 42
func main() -> int:
    mut left: int[] = [1, 2, 3]
    mut right: int[] = [1, 2, 3]
    if left != right:
        return 1
    if not lists.contains(left, 2):
        return 2
    if lists.contains(left, 9):
        return 3
    mut nested: int[][] = [copy(left)]
    mut twin: int[][] = [own right]
    if nested != twin:
        return 4
    mut counts: dict[str, int] = {"a": 1, "b": 2}
    mut other: dict[str, int] = {"b": 2, "a": 1}
    if counts != other:
        return 5
    if "a" not in counts:
        return 6
    if "ell" not in "hello":
        return 7
    if "zz" in "hello":
        return 8
    return len(left) * 14
```

```selka
# doc: expect 1
record Parsed:
    problem: str
func parse(text: str) -> Parsed:
    return Parsed(problem="empty " + text)
func main() -> int:
    if "group" in parse("group name").problem and "x" not in parse("y").problem:
        return 1
    return 0
```

```selka
# doc: expect-error E_LIST_MEMBERSHIP_REMOVED
func main() -> int:
    mut values: int[] = [1, 2, 3]
    if 2 in values:
        return 1
    return 0
```

Aggregates compare the same way. Records, fixed arrays, unions, `Result` and
`Option` compare structurally. Use a pool handle when identity must be compared:

```selka
# doc: expect 42
record Point:
    x: int
    y: int


enum Shape:
    empty
    radius(value: int)
    point(value: Point)


record Node:
    value: int


func main() -> int:
    if Point(x=1, y=2) != Point(x=1, y=2):
        return 1
    if Shape.radius(value=4) == Shape.point(value=Point(x=4, y=0)):
        return 2
    if Node(value=1) != Node(value=1):
        return 3
    mut first = Node(value=1)
    if first != first:
        return 4
    return 42
```

## List comprehensions

Comprehensions receive `E_COMPREHENSION_REMOVED`. Build a fresh managed list
with a typed empty accumulator, a `for` loop and `append`; put filtering in an
`if` statement inside the loop. The source evaluates before iteration, and each
filter runs before its produced value. Nested loops support destructuring and
multiple sources. The examples below use this statement form.

```selka
# doc: expect 20
func main() -> int:
    mut gather_result_55: int[] = []
    for i in range(0, 5):
        const gather_value_55: int = i * i
        append(mut gather_result_55, gather_value_55)
    mut squares = own gather_result_55
    mut total = 0
    for s in squares:
        total = total + s
    return total - 10
```

```selka
# doc: expect 21
import strings

func main() -> int:
    mut readings: int[] = [3, 12, 7, 20]
    mut doubled: int[] = []
    for value in readings:
        append(mut doubled, value * 2)
    mut large: int[] = []
    for value in readings:
        if value > 10:
            append(mut large, value)
    mut labels: str[] = []
    for value in large:
        append(mut labels, str(value))
    mut initials: str[] = []
    for letter in strings.chars("selka"):
        if letter != "m":
            append(mut initials, own letter)
    mut counts: dict[str, int] = {"a": 1, "bb": 2}
    mut widths: int[] = []
    for key in counts:
        append(mut widths, strings.char_count(key))
    if len(doubled) != 4:
        return 1
    if labels[0] != "12":
        return 2
    if len(initials) != 5:
        return 3
    if len(readings) != 4:
        return 4
    return doubled[0] + large[0] + widths[0] + widths[1]
```

## Checked ownership

Plain `selka check`, `run`, `build` and `test` use checked ownership.
Lists, strings, bytes, and mutable byte buffers have one owner. Assignment and
container insertion move a named managed value only with `own`; a bare owned
return needs no marker. Ordinary parameters borrow,
and `mut` parameters borrow exclusively; a move-only value, a resource, needs a
parameter that says `own` (it takes the value) or `mut` (it borrows it). Use `copy(value)` when both values must
remain independently usable. Copies of lists also duplicate owned children in
records and fixed arrays.

A parameter has one of three modes, and the call site marks it. `own` takes the argument:
the caller's binding is unusable after the line, and the callee may store, return or move
the value with no copy, destroying it at its scope end otherwise. The marker is required
exactly where a named binding of a value that owns storage is given away and refused on a
fresh value or a scalar (`E_OWN_MARKER`), so `append(mut rows, 1)` and `make([1, 2])` carry no marker while
`order_by_key(own samples)` does. The element of `append` requires `own` when it is a named
binding the caller owns, so `append(mut rows, row)` is refused until it reads `append(mut
rows, own row)`; a borrowed name is refused with `copy(...)` instead. The standard library's
storing functions (`append` and `sets.add`) take their element `own`, and they copy nothing. `dicts.add`,
`dicts.append_to`, `sets.include` and the store `table[key] = value` take the key
borrowed and copy it only when it is new (`dicts.append_to` still takes its item `own`). A plain parameter of a move-only type is refused with
`E_OWN_PARAMETER`, because it would take the value without saying so (a plain parameter of a `@linear` record is
instead a read-only loan, [linear records](records-and-unions.md#linear-records)); its repair writes
`own`. A `mut` parameter is an exclusive borrow for every type, a resource included: an
accept loop can pass its listener `mut` and use it again, and a resource the callee keeps
must be declared `own`. `L_COPY_FOR_STORE` reports a parameter copied into storage, which is
the site to consider taking `own`. A project check (`selka check DIR`) warns with
`W_COPY_FOR_STORE` where that change is certain, and `selka fix` makes it: the function is
neither generic, recursive nor named as a value, the parameter has no default and no
`from` names it, the copy is the parameter's last use, and every caller in the project passes
there a new value (a literal, a call's result, a constructor, a concatenation or a `copy(...)`) or
the bare name of an owned local or `own` parameter that it does not use again. The repair writes
`own` before the parameter, `own name` for the copy, and `own` before each such name at its call,
in whatever file the caller is. A `public` function is repaired too, with its signature changed, when two things hold: the project's
`selka.json` sets no `interface_files`, and its modules have more than one top-level name (`rows`, `rows_test`
and `main` are three, `NAME.selka` with `NAME/` is one), which a package root cannot have, and a package root is
the only way another project imports a module. A package, a project with `interface_files` and a check of one
file keep their public signatures. The warning of a public function says that its signature changes:

```selka
# doc: expect alpha
record Row:
    name: str
    size: int


# Before `selka fix`: func make_row(name: str, size: int) -> Row:
#                          return Row(name=copy(name), size=size)
func make_row(own name: str, size: int) -> Row:
    return Row(name=own name, size=size)


func main(out: Stream) -> int:
    const row = make_row("alpha", 1)
    print(out, row.name)
    return 0
```

A caller that passes a name it uses again, a plain parameter of its own, a field, a loop
element or a pattern binding keeps the copy where it is, and the lint advice stays.

A plain list parameter whose elements a loop copies into storage, and that nothing reads after
the loop, takes the same repair: `own` before the parameter, `for x in own xs:` so the loop
takes each element, `own x` (or `own x.f`) for the copy, and `own` before each caller's name.
Where a caller keeps its list, the `W_COPY_MOVE` hint names the loop instead:

```selka
# doc: expect 3
# Before `selka fix`: func joined(words: str[]) -> str[]:
#                          for w in words:
#                              append(mut out, copy(w))
func joined(own words: str[]) -> str[]:
    mut out: str[] = ["start"]
    for w in own words:
        append(mut out, own w)
    return out


func main(out: Stream) -> int:
    const words = ["p", "q"]
    print(out, len(joined(own words)))
    return 0
```

```text
mut text = "hello" + str(7)
const saved = copy(text)
text += "!"
# saved remains "hello7"; text is "hello7!"
```

Cleanup directly destroys owned storage without reference counts. Literals have
static storage; modifying a literal first creates writable storage. Heap
allocation and growth still occur. A text or bytes slice is a view and allocates
nothing: a plain parameter receives it without a copy, and it is copied only
where `copy(...)` is written. See [Slices are views](#slices-are-views).

Checked ownership supports owned dictionaries, sets, recursive values, scoped resources,
and synchronous `parallel.map`. It rejects `.snapshot()`, the retired `.view()` spelling,
escaping task handles, arbitrary managed foreign calls, and unaudited runtime APIs.
`check` validates source ownership; `build` also checks backend and runtime
support. An unsupported shape is diagnosed instead of falling back to RC.
The old `--experimental-zero-rc` and `--experimental-single-owner` selectors
are rejected with exit status 2: reference counting was removed. Drop them from
commands. `.snapshot()` and the hybrid single-owner mode were removed too.
The prototype stages and measurements (the design record
`experiments/zero-rc-20261011/README.md`) are historical records.


## Declared borrowed results

Write `from` after a function's result type to return a read-only borrow of its
parameters. The named sources must be plain or `mut` parameters with managed
storage. Every value return must come from those sources. Callers use the
signature even when the function body is unavailable.

```selka
# doc: expect 42
func tail(values: int[]) -> int[] from values:
    return values[1:]

func main() -> int:
    mut values = [10, 40, 2]
    const rest = tail(values)
    return rest[0] + rest[1]
```

Several sources are written `-> T from first, second`; the formatter orders
them by parameter position. The result keeps all their owners alive until its
last use. The clause also supports optional and fallible successes, for example
`-> Json? from doc fails ParseError`. Write `from` before `fails`. Function types
cannot declare `from`. A function without a value result has no `from` clause. `Some(place)` can return a borrow,
and `None` is an empty alternative; errors keep their ordinary ownership.

`E_BORROW_UNDECLARED` names a returned borrow missing from the signature, and
`selka fix` adds its source. `E_BORROW_SOURCE` rejects an unknown source, an
`own` parameter or a parameter that cannot hold managed storage. It also refuses
a duplicate source with a fix deleting that name, and a nongeneric result with no
managed successful value with a fix deleting the clause, as well as a nongeneric
clause in which no source can lend the result: a source lends only storage it holds
(a list of bytes cannot lend `int[]`), and a plain text or bytes parameter is a view,
which lends only text or bytes of its own kind. A source that cannot lend beside one
that can is dropped. A generic declaration is judged at each instance: an instance
whose sources cannot lend its result is refused at the call that made it, with the
clause's removal when no source's type names a type parameter. Generic parameters that
specialize to scalar results retain the declaration and ignore borrowing in that instance.
A `from` function returning fresh storage is `E_BORROW_MIXED`; make every return
borrow, or copy the borrowed returns and remove `from` to return owned values. `None`,
a literal such as `""` and the empty list `[]` are not fresh storage, so an accessor may
return one of them beside its borrows.

A project check (`selka check DIR`) warns `W_COPY_RETURNED` where every return of a function copies a place of one
parameter and no caller in the project keeps the result (a caller the ownership check refuses with the result `from`, one that
returns it included, withholds the warning, as does a function named as a value), and `selka fix` declares the result `from`
that parameter and returns the places themselves. A `public` function is repaired too, with its signature changed, under the two
conditions given for `W_COPY_FOR_STORE` above (no `interface_files`, more than one top-level name): the warning says that its
signature changes, and a package, a project with `interface_files` and a check of one file keep their public signatures.

A borrowed result can be read in place or bound with `const`. Use `copy(...)`
when it must be stored or kept independently of its sources. A function with a
`from` result cannot be passed as a function value. Interface files and API
comparison include the clause: adding a source or removing the final source is
breaking. Narrowing to a nonempty subset is compatible when the rest of the
contract stays the same.

### Slices are views

A slice `s[start:end]` is a read-only view of its source's text or octets.
Endpoints are Unicode scalar positions for `str` and byte positions for `bytes`
and `str` slices; negative positions trap and endpoints above the length clamp.
A view holds a pointer and a length. Creating one performs no allocation or RC.
`len()` reads it directly; text length and indexing scan UTF-8. Byte indexing
returns a scalar.

The prototype `.borrow(start, end)`, `.view(start, end)`, `TextView` and `ByteView`
spellings were removed. They report `E_BORROW_VIEWS_REMOVED`; `selka fix`
rewrites range calls to `s[start:end]` and type names to `str` or `bytes` where
the edit is certain.

```text
func segment(source: str, start: int) -> str from source:
    return source[start:start + 3]

func example(out: Stream):
    mut text = "aλz" + str(7)
    const part = segment(text, 1)
    print(out, part)                 # λz7; the slice borrows text
    const saved = copy(part)        # independent owned str
    text += "!"
    print(out, saved)                # allowed
    # print(out, part)               # compile error: the source changed
```

A function can return a text, bytes or list slice of a named `from` source.
Sources may be plain or `mut` parameters, and there is no fixed source-count
limit. The compiler keeps those owners alive through the last use of derived
views, including through function calls. This contract comes from the signature
and does not depend on inlining. See the
[ownership reference](ownership-rules.md#v1--slices-are-views).

A slice binding is immutable and read-only. A view cannot be stored in a
container, a record or a callback: store `copy(value)` of it instead. A slice
bound with `const` carries this rule too:
binding it first does not make it storable, for text, bytes and lists alike,
and `selka fix` puts the copy on the binding. A loop may create fresh views in
its body. Invalidating a view that remains live is refused, including when its
next use follows a loop. Ordinary slices support their type's read operations,
including slicing, indexing, `len()`, copying and supported text or byte
operations. The separate restrictions on the retired typed views no longer
apply. `.view(start, end)` is a retired spelling with the slice repair above.

See the Stage 2 measurements and examples (the design record
`experiments/zero-rc-views-20261011/README.md`).


### Explicit values and scoped parallel work

`copy(value)` also accepts records, enums, options and fixed arrays. It recursively
duplicates owned children; scalar copies preserve their value. Resources and
move-only values cannot be copied.

```text
import parallel

func render(value: int) -> str:
    return "item-" + str(value)

func example(out: Stream):
    const input = [1, 2, 3]
    const output = parallel.map(input, render)
    print(out, input[0], output[0])
```

`parallel.map` borrows each input element, runs the callbacks through the task
scheduler, and joins every task before returning the results in input order.
The caller can use its input again immediately. A callback returning managed
input data must explicitly copy it; returning new data transfers it to the
output. Nested maps, ordinary error enums, empty inputs and discarded outputs
follow the same cleanup rules. An uncaught fatal trap terminates the process.

This initial API takes a function value with one read-only parameter. It has no
closure captures, detached work or escaping task handles, and does not support
Unit elements. The implementation creates task, capture and result storage for each element; it is
intended for testing ownership and parallel work, not for accelerating tiny
callbacks. Heap allocation and scheduling synchronization remain.

### Borrowed constants

`const name = place` binds a read-only borrow with no copy for every managed place:
a bare local, a plain or `own` parameter, a field, an element or a dictionary value.
The place it names cannot change or move while the binding is live, through its last use in
its block; another field of the same record can (see below). The binding can be read, printed, compared and passed to read-only
parameters. It cannot become owning storage or an owned return, or be passed
`mut` or `own`, without an explicit ownership change or copy. Borrowed returns
remain governed by the function's `from` contract.

For a bare owner, write `const name = own owner` to transfer ownership at the
initializer, or `const name = copy(place)` for independent storage. An `own`
parameter's unmarked alias also borrows; owning the parameter does not make its
aliases owners. A `mut` local needs its own value, so a named managed source
requires `mut name = own owner` or a written copy. Fresh calls, constructors,
literals and operator results need no marker, and neither do scalars.

```text
func second(rows: int[][]) -> int:
    const row = rows[1]        # borrows rows: no copy
    return len(row)            # the last use of row

func grow(rows: int[][]) -> int[]:
    const row = rows[1]
    return copy(row)           # a store or return of the borrow needs copy(...)
```

A borrow holds the place, not the whole record that owns it. `const item = self.items[i]` holds `self.items`,
so a write to `self.links`, `self.count` or `self.inner.n` is allowed while `item` is live, and `item` can be read after
it. Writing `self.items`, an element of it, or the whole of `self` (including passing `mut self` to a call) overlaps
the borrow and is refused. Two elements of one list are not told apart: the borrow holds the list. See
[R2](ownership-rules.md#r2--loans-block-changes) for the rule.

```selka
# doc: expect 13
record Report:
    lines: str[]
    seen: int[]
    total: int
func scan(mut report: Report):
    for i in range(len(report.lines)):
        const line = report.lines[i]
        append(mut report.seen, len(line))
        report.total = report.total + len(line)
func main() -> int:
    mut report = Report(lines=["ab", "cde", "fghij"], seen=[], total=0)
    scan(mut report)
    return report.total + len(report.seen)
```

## Written copies (rule C)

Every copy a program makes at run time must be written by the source. A copy is written when the source
spells `copy(value)`, or names a new value whose meaning is a new storage form: `+` on text and bytes, the pieces
of `split`, the bytes or octets of `encode()`, `sorted(xs, key=...)`, and `bytes(buf)`, the snapshot of a buffer.
A builder never makes a copy the source did not name. Where the source does not name one (a slice of a list
given to an owned parameter, `parallel.map` over a slice or a borrowed list parameter, a buffer written from its
own octets), the checker refuses the program with the copy's certain repair, `copy(...)`, or with the overlap
message, so that no copy stays hidden.

Every guest build also checks its final module, beside the IR verifier and the ownership validator: a copy the
source did not write is an internal error `E_CORE_HIDDEN_COPY`, whose note names `--no-validate` as the way out
([certificate validators](tooling/native-build.md#certificate-validators)). The check counts the frame block and the
dictionary-key copy and refuses neither (decision Q8 is open). The reads that take a text or bytes view in place are
the ones that keep it quiet: a `in` probe of a view needle or container, a whitespace split of a view, and a view used
as a dictionary key. `cost --sites` labels the same sites written, a named operation or implicit. See
`docs/tooling/cost.md`.

## Ownership history

Reference counting and copy-on-write were retired on 17 October 2026, after
checked ownership became the default. Their rules are historical; current code
uses moves, borrows, explicit copies and direct destruction. Historical
experiments retain their original commands and measurements.
