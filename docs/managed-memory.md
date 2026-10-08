# Managed collections

Lists, dictionaries, sets, strings and byte buffers live in managed storage. There
are no allocator parameters, no free operations and no borrow scopes: managed memory
is the only way application code allocates. The runtime reference-counts each
object once and copies on write, so an object is released the moment its last owner
goes away, and collections are values: assigning one, passing it or storing it
behaves as a copy.

```mylang
# doc: expect 1
# doc: expect 2
def main(out: Stream) -> int:
    values: list[int] = [1]
    alias = values
    alias.append(42)
    out.print(len(values))
    out.print(len(alias))
    return 0
```

A list assignment or function argument transfers a value. The implementation
may share backing storage until a write, but writing `alias` leaves `values`
unchanged. Appending grows capacity automatically. Reading returns a value
snapshot, never an interior pointer into growable storage. Use a `mut`
parameter with a marked call when a helper must change its caller's value
([value semantics](value-semantics.md)).

Use `list[Node]` for application collections and `nodes: list[Node] = []`
for an empty list. Read with `nodes[index]`, write with `nodes[index] = value`,
append with `nodes.append(value)`, and count with `len(nodes)`. An empty literal
needs an expected list type from an annotation, return type, or parameter.

Capacity is a reserve hint, not a fixed limit. Mutations return `None`. Invalid
indices trap with `R_LIST_BOUNDS`. Allocation failure ends the program with
status 1 (`R_MEMORY_BUDGET` under a byte ceiling, `fatal: out of memory` without
one) rather than returning a recoverable collection result. Keep
application cardinality checks where input limits are part of its contract.

List elements can be ordinary copyable values, records, and other managed lists.
Recursive record types are supported, but stored values are independent; use
explicit pool handles for identity-bearing graphs:

```text
record Node:
    value: int
    children: list[Node]
```

`record` and its mutable managed fields are values. The builtin `Cell` and `class`
are rejected; replace identity-bearing graphs with records plus stable ids in a pool
or object table. Capturing closures remain absent. Byte literals and the managed
[`bytes`](bytes.md) type keep their documented behavior. Owned resources, provider
capabilities, and must-handle results cannot be hidden inside copyable lists. There
are no interior pointers into managed storage.

## Releasing memory

A managed object is released when its last owner goes away: a local at the end of
its last use, a temporary right after the expression that made it, a list element
when its list is released. The compiler places every count and release
([ownership](tooling/ownership.md)); the program never says anything. Because values
are independent, assignments and container stores cannot build a cycle, so nothing
needs tracing, and identity-bearing graphs use pool handles.

```mylang
# doc: expect 1225
def batch(size: int) -> int:
    scratch: list[str] = []
    for index in range(size):
        scratch.append(f"item {index}")
    return len(scratch)

def main() -> int:
    kept: list[int] = []
    for step in range(50):
        kept.append(batch(step))
    total = 0
    for value in kept:
        total += value
    return total
```

Every `scratch` list and every interpolated string in that program is released when
`batch` returns. Dictionary views are ephemeral; stored snapshots use explicit
`list(...)` materialization, and view types cannot appear in parameter, return,
field or element annotations.

Managed construction and append carry the transitive `managed_allocation` effect.
`noalloc` excludes it, meaning "performs no managed allocation". It does not promise
zero allocation for runtime bookkeeping. Reads and fixed-slot writes are permitted
under that bound. Managed mutation is not a promise of purity or exclusive access.
Every process that runs a program under `mylang run` or `mylang test` has a byte
ceiling ([guest memory ceilings](tooling/runtime-budgets.md#guest-memory-ceilings)).

`with arena():` blocks, which once released a phase's objects in bulk, were retired
([retired arenas](#retired-arenas)). The tracing collector and its `--gc-runtime` and
`--gc-stress` switches were retired with them.

## Retired arenas

`with arena():` regions released every managed object a phase of work allocated in
one step. They were retired in stage S5 of the new compiler core (2026-10): every
object is now released as soon as its last owner goes away, so a region has nothing
left to free early.

A `with arena():` or `with arena() as name:` block still checks and runs as an
ordinary block, so existing programs keep their output, and it warns
`W_ARENA_RETIRED` at the `with` (a program with an error does not carry the
warning). The block has no rules of its own: the old escape checks
(`E_ARENA_ESCAPE`, `E_ARENA_BINDING`) are gone, and `name.escape(value)` is `value`.
`mylang fix` migrates a file: it deletes the `with arena():` line, dedents the
block's body by one level and rewrites `name.escape(value)` to `value`
([fix](tooling/fix.md)).

## Managed lists

`list[T]` is the growable sequence application code reaches for. Its storage is
managed, so there is no allocator argument to thread and no free to write. Assignment and argument passing preserve the value independently, with
copy-on-write backing where possible. Elements must be
copyable storable values — scalars, records, strings, byte strings and other
managed collections — which keeps owned resources, provider capabilities and
unchecked results out of copyable storage. Reading an element yields a
snapshot of that value, never an interior pointer into growable storage.

```mylang
# doc: expect 42
def widen(target: mut list[int]) -> None:
    target.append(2)

def main() -> int:
    values: list[int] = [40]
    alias = values
    widen(mut alias)
    return values[0] + alias[1]
```

Here `widen(mut alias)` changes `alias` to `[40, 2]`; `values` remains `[40]`.

## List methods and indexing

A list answers the everyday vocabulary. `append(value)` and `extend(other)` add
one element or copy another list's elements to the end; `insert(index, value)`
inserts at a position, counting a negative index from the end and clamping to the
bounds; `pop()` removes and returns the final element and `pop(index)` removes and
returns an indexed element; `remove(value)` deletes the first equal element;
`reverse()` reverses in place; `sort()` orders integer, `float`, `str` or `bytes`
elements ascending, and `sort(key=f, reverse=True)` orders any list by a key, in
place and stably ([keyed sorting](python-syntax.md#keyed-sorting)); `copy()` returns a fresh shallow list; `clear()` empties the list; and
`index(value)` returns the first equal position. Length stays the free function
`len(values)`. Every mutating method returns unit, so a discarded `pop` or `index`
result needs its own binding or `_ =`. An absent `remove` or `index` traps with
`R_LIST_VALUE`, `pop` on an empty list traps with `R_LIST_BOUNDS`, and `sort`
without a key rejects an element type that is not an integer, `float`, `str` or `bytes`. The legacy `push` is
gone: it reports `E_REMOVED_SPELLING` and names `append`.

`values[index]` reads a slot and `values[index] = value` overwrites one, so an
indexed write never grows the list. Negative indexes count from the end, and an
index outside the list traps with a located `R_LIST_BOUNDS` instead of returning a
default. Receivers may be arbitrary expressions and nested indexes work; the
receiver, the index and the assigned value are each evaluated exactly once, and a
Python-surface indexed write evaluates the assigned value before the target it
writes into. `values += other` extends the receiver value; an earlier copy
retains its contents. Ordering helpers also live in the
[`sort` module](standard-library.md#sort), which returns new lists and leaves its
input untouched.

```mylang
# doc: expect 42
def main() -> int:
    scores: list[int] = [30, 10, 20]
    scores.sort()
    scores.append(40)
    scores.insert(0, 5)
    scores.remove(5)
    scores.reverse()
    scores.extend([7])
    _ = scores.pop(0)
    window = scores.copy()
    window.append(100)
    if len(scores) != 4 or len(window) != 5:
        return 1
    if scores[0] != 30 or scores[-1] != 7:
        return 2
    if scores.index(20) != 1:
        return 3
    scores.clear()
    if len(scores) != 0:
        return 4
    return window[0] + window[-1] - 88
```

## Inferred literals and slices

A nonempty list literal infers one homogeneous element type from its elements, so
an annotation is only needed when the literal cannot speak for itself. `[]` has
nothing to infer from: it takes its type from an annotation, field, parameter or
return type, and otherwise reports `E_LIST_INFERENCE`. `values[start:end]` copies
the selected elements into a fresh list — negative endpoints count from the end,
both endpoints clamp to the list, a reversed interval produces an empty list, and
an omitted endpoint means the start or the end. The new list and its managed
elements remain independent on later writes.

```mylang
# doc: expect 42
def main() -> int:
    readings = [3, 12, 7, 20]
    empty: list[int] = []
    window = readings[1:3]
    window[0] = 0
    if readings[1] != 12:
        return 1
    if len(readings[2:99]) != 2:
        return 2
    if len(readings[3:1]) != 0:
        return 3
    if len(readings[-2:]) != 2:
        return 4
    return window[1] * 6 + len(empty)
```

## Insertion-ordered dictionaries

`dict[K, V]` keeps its entries in the order their keys were first inserted, and
rewriting an existing key leaves that key in its original position. A key is any
[hashable](sets.md#hashable-keys) value — an integer, `bool`, `str`, `bytes`, or a
tuple, record, union, enum, domain, `Option` or fixed array built only from those —
hashed and compared structurally and copied into the table; a `float`, list, dict,
set, `byte_buffer` or function key is rejected with `E_DICT_KEY` naming the
offending part. Values are any copyable storable
type, including lists and other dictionaries. `counts[key]` traps with
`R_MISSING_KEY` when the key is absent, so `counts.get(key, fallback)` is the
lookup that always answers. `counts.keys()`, `counts.values()` and `counts.items()`
return live typed views without allocating. Use `list(counts.keys())` or
`list(counts.values())` when an independent snapshot is required. `counts.pop(key)` removes and returns
the value and `counts.pop(key, fallback)` answers the fallback when absent;
`counts.update(other)` replaces existing values in place and appends new keys;
`counts.setdefault(key, fallback)` returns the existing value or stores the
fallback; `counts.copy()` returns a fresh shallow dictionary; and
`counts.clear()` empties it. `counts.pop(key)` without a fallback traps with
`R_MISSING_KEY`. `counts.items()` yields `DictItem[K, V]` value records with `key`
and `value` fields. A two-name loop `for name, value in counts.items()` unpacks
those fields. Assignment copies a dictionary value; only a `mut` parameter and marked call write back to a caller.

Dictionary views are ephemeral. Use `d.keys()`, `d.values()` and `d.items()`
directly as loop or comprehension sources, or immediately with `len`, `in`,
`list`, `set` or `sorted`. `enumerate(d.items())` is also a loop source.
They allocate no snapshot and observe value replacements as iteration reaches
each key. A size change during dictionary iteration traps.

Binding, returning, rebinding, storing or passing a view to a user function is
`E_VIEW_STORED`. `mylang fix` wraps a stored projection in `list(...)` where
that migration is certain. The resulting list is an independent snapshot of
the current keys, values or `DictItem` records in insertion order:
`kept = list(mapping.values())`. Store and pass these lists in records,
collections and helper functions. `list(mapping.items())[index]` provides
positional item access; the view itself is not indexable.

The prelude names `DictKeys[K, V]`, `DictValues[K, V]` and `DictItems[K, V]`
describe these transient projections. `DictItem[K, V]` remains an ordinary
storable value record. A recursive structure should use ordinary snapshot
lists or pool ids; the former retained-view identity protocol is retired.

```mylang
# doc: expect 42
def main() -> int:
    mapping = {"a": 10, "b": 20}
    old_values = list(mapping.values())
    mapping["b"] = 31
    total = 0
    for key, value in mapping.items():
        total += value
    return total + old_values[1] - 19
```

```mylang
# doc: expect 42
def main() -> int:
    counts: dict[str, int] = {}
    counts["pear"] = 2
    counts["apple"] = 6
    counts["pear"] = counts["pear"] + 1
    counts.update({"plum": 4})
    _ = counts.setdefault("fig", 5)
    if counts.setdefault("fig", 9) != 5:
        return 1
    if counts.pop("plum") != 4:
        return 2
    if counts.pop("kiwi", 7) != 7:
        return 3
    order: list[str] = []
    for name in counts:
        order.append(name)
    if order[0] != "pear":
        return 4
    if counts.get("plum", 0) != 0:
        return 5
    keys: list[str] = []
    total = 0
    for name, value in counts.items():
        keys.append(name)
        total += value
    if keys[0] != "pear" or keys[1] != "apple" or keys[2] != "fig":
        return 7
    copy = counts.copy()
    copy.clear()
    if len(copy) != 0 or len(counts) != 3:
        return 6
    return total * 3
```

## Iterating collections

`for name in source` visits a list's elements, a string's Unicode scalar values,
a [byte string](bytes.md)'s octets as `int`, and a dictionary's keys in insertion
order. `for key, value in counts.items()` visits each dictionary entry, binding the
key and its value in insertion order. `for index, value in enumerate(source)` adds
the position, and
`for index in range(end)` or `range(start, end)` counts integers; there is no step
argument. `break` and `continue` carry their Python meanings. A loop fixes its
bound when it starts and rechecks it before each step, so changing the
collection's length through the iterated place during iteration traps with
`R_LIST_ITERATION_MUTATION` rather than reading past the end.

```mylang
# doc: expect 19
def main() -> int:
    words = ["alpha", "beta"]
    letters = 0
    for word in words:
        for letter in word:
            letters += 1
    weighted = 0
    for index, word in enumerate(words):
        weighted += index * len(word)
    octets = 0
    for octet in b"\x01\x02":
        octets += octet
    counts: dict[str, int] = {"a": 1, "b": 2}
    keyed = ""
    for key in counts:
        keyed = keyed + key
    if keyed != "ab":
        return 1
    stepped = 0
    for number in range(1, 5):
        if number == 3:
            continue
        if number == 4:
            break
        stepped += number
    return letters + weighted + octets + stepped
```

## Membership and value equality

`in` and `not in` ask a container about its contents: a list is searched for an
equal element, a dictionary for a key, a string for a substring, and a byte
string for a single octet or a contiguous subsequence. The needle is evaluated
before the container, and each is evaluated exactly once. `==` and `!=` compare
contents rather than identities, recursing through nested lists, dictionaries,
plain records, fixed arrays, unions, `Result` and `Option` values; dictionary
equality ignores insertion order. A type that reaches a callback or resource
has no equality and is rejected with `E_TYPE`. There is
no identity comparison operator, so two separately built lists holding equal
elements are equal.

```mylang
# doc: expect 42
def main() -> int:
    left: list[int] = [1, 2, 3]
    right: list[int] = [1, 2, 3]
    if left != right:
        return 1
    if 2 not in left:
        return 2
    if 9 in left:
        return 3
    nested: list[list[int]] = [left]
    twin: list[list[int]] = [right]
    if nested != twin:
        return 4
    counts: dict[str, int] = {"a": 1, "b": 2}
    other: dict[str, int] = {"b": 2, "a": 1}
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

Aggregates compare the same way. Records, fixed arrays, unions, `Result` and
`Option` compare structurally. Use a pool handle when identity must be compared:

```mylang
# doc: expect 42
record Point:
    x: int
    y: int


union Shape:
    empty,
    radius: int,
    point: Point


record Node:
    value: int


def main() -> int:
    if Point(x=1, y=2) != Point(x=1, y=2):
        return 1
    if Shape.radius(4) == Shape.point(Point(x=4, y=0)):
        return 2
    if Node(value=1) != Node(value=1):
        return 3
    first = Node(value=1)
    if first != first:
        return 4
    return 42
```

## List comprehensions

`[expression for name in source if condition]` builds a fresh managed list in one
checked pass over a list, string, byte string or dictionary. With one clause and at
most one filter it reserves the source's length first; the filter runs before the
expression, and the binding exists only inside the comprehension and may not
shadow an active name.
The source collection is unchanged, and the produced value has to be a copyable
storable list element. Two iteration names, several `for` clauses, dictionary and
set comprehensions and generator arguments lower through their own loops; see
[the language guide](python-syntax.md#dict-and-set-comprehensions).

The set comprehension `{expression for name in source if condition}` follows the
same rules and builds a [set](sets.md#set-literals-and-construction) instead.

The source may also be an integer `range(...)`, exactly as in a `for` loop:
`range(end)` and `range(start, end)` walk a half-open ascending range and bind the
name to each integer value, so `[i * i for i in range(5)]` collects the first five
squares. The bounds share one integer type and evaluate once before the loop, and
an empty or reversed range yields an empty list.

```mylang
# doc: expect 20
def main() -> int:
    squares = [i * i for i in range(5)]
    total = 0
    for s in squares:
        total = total + s
    return total - 10
```

```mylang
# doc: expect 21
def main() -> int:
    readings: list[int] = [3, 12, 7, 20]
    doubled = [value * 2 for value in readings]
    large = [value for value in readings if value > 10]
    labels = [str(value) for value in large]
    initials = [letter for letter in "mylang" if letter != "m"]
    counts: dict[str, int] = {"a": 1, "bb": 2}
    widths = [len(key) for key in counts]
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
