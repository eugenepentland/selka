# Managed application collections

Ordinary dynamic lists allocate on a tracing heap. There are no allocator
parameters, no move operations and no collection borrow scopes: managed memory is
the only way application code allocates. [Managed arenas](arenas.md) are the one
escape hatch, and they change *when* managed objects are freed rather than how
they are written.

```mylang
# doc: expect 42
def main(out: Stream) -> int:
    values: list[int] = []
    alias = values
    alias.append(42)
    out.print(values[0])
    return 0
```

A list assignment or function argument copies a shared reference, so every alias
observes the same mutations. Appending grows capacity automatically. Reading
returns a value snapshot, including shared references in its fields; it never exposes an interior pointer into growable storage. Independent
containers require explicit construction and copying of their elements.

Use `list[Node]` for application collections and `nodes: list[Node] = []`
for an empty list. Read with `nodes[index]`, write with `nodes[index] = value`,
append with `nodes.append(value)`, and count with `len(nodes)`. These operations
currently use a named local or parameter as their receiver. An empty literal needs
an expected list type from an annotation, return type, or parameter.

Capacity is a reserve hint, not a fixed limit. Mutations return `None`. Invalid
indices trap with `R_LIST_BOUNDS`. Allocation failure terminates the execution
with cleanup, rather than returning a recoverable collection result. Keep
application cardinality checks where input limits are part of its contract.

List elements can be ordinary copyable values, records, and other managed lists.
Recursive graphs through list references are supported:

```text
record Node:
    value: int
    children: list[Node]
```

`record` retains value semantics, while `class` is a GC-managed reference record:
assignment, argument passing and field reads share one object, so a field write through
a class parameter reaches the caller's object. Capturing closures and managed hash maps
remain absent. Byte literals and the managed
[`bytes`](bytes.md) type keep their documented behavior. Owned resources, provider
capabilities, and must-handle results cannot be hidden inside freely aliased
lists. There are no interior pointers into managed storage. Host invocation, JSON encoding
of managed graphs, and QBE native emission reject unsupported managed boundaries;
ordinary scalar host calls from managed applications still work.

## Collection and allocation contracts

Each execution owns a single-threaded, nonmoving tracing heap. Managed objects
have stable identities. Locals, operands, intermediate values, and retained
aggregate snapshots maintain reference counts used for root discovery. Collection
subtracts edges internal to the managed graph (including aggregate wrappers),
marks reachable objects, and reclaims unreachable cycles. Dead edges are released
before any dead object header is freed. These counts protect temporary roots;
reference counting alone is not the reclamation algorithm.

Automatic collection runs at managed allocation safepoints according to a simple
object-count threshold. This prototype is not a tuned latency or byte-budget
policy. Host allocators still determine total memory availability.
`memory.gc.statistics` reports
created, reclaimed-during-collection, live/peak objects, live capacity slots, and
collection counts; final teardown zeroes live counts separately from reclamation.

Managed construction and append carry the transitive `managed_allocation` effect.
`noalloc` excludes it, meaning "performs no managed allocation". It does not
promise zero host allocation for value representation or runtime bookkeeping.
Reads and fixed-slot writes are permitted under that bound. Inside a
[`with arena() as name:`](arenas.md) block the same managed allocation happens; only
its release point moves. Managed mutation is not a promise of purity or exclusive
access.

`mylang run-project examples/gc-default/main.my --gc-stress` collects at every
managed construction/append safepoint. It should print `142`. Stress mode is a
rooting correctness check, not a performance mode. See the
[schematic instructions](../experiments/schematic/README.md) for the real migrated
application and normal/stress SVG comparison.

## Managed lists

`list[T]` is the growable sequence application code reaches for. Its storage lives
on the tracing heap, so there is no allocator argument to thread and no free to
write. Assignment and argument passing copy a reference rather than the contents,
so every alias observes the same appends and slot writes. Elements must be
copyable storable values — scalars, records, strings, byte strings and other
managed collections — which keeps owned resources, provider capabilities and
unchecked results out of freely aliased storage. Reading an element yields a
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

## List methods and indexing

A list answers the everyday vocabulary. `append(value)` and `extend(other)` add
one element or copy another list's elements to the end; `insert(index, value)`
inserts at a position, counting a negative index from the end and clamping to the
bounds; `pop()` removes and returns the final element and `pop(index)` removes and
returns an indexed element; `remove(value)` deletes the first equal element;
`reverse()` reverses in place; `sort()` orders integer, `float` or `str`
elements ascending, and `sort(key=f, reverse=True)` orders any list by a key, in
place and stably ([keyed sorting](python-syntax.md#keyed-sorting)); `copy()` returns a fresh shallow list; `clear()` empties the list; and
`index(value)` returns the first equal position. Length stays the free function
`len(values)`. Every mutating method returns unit, so a discarded `pop` or `index`
result needs its own binding or `_ =`. An absent `remove` or `index` traps with
`R_LIST_VALUE`, `pop` on an empty list traps with `R_LIST_BOUNDS`, and `sort`
without a key rejects an element type that is not an integer, `float` or `str`. The legacy `push` is
gone: it reports `E_REMOVED_SPELLING` and names `append`.

`values[index]` reads a slot and `values[index] = value` overwrites one, so an
indexed write never grows the list. Negative indexes count from the end, and an
index outside the list traps with a located `R_LIST_BOUNDS` instead of returning a
default. Receivers may be arbitrary expressions and nested indexes work; the
receiver, the index and the assigned value are each evaluated exactly once, and a
Python-surface indexed write evaluates the assigned value before the target it
writes into. `values += other` extends the receiver in place, so aliases observe
the added elements. Ordering helpers also live in the
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
an omitted endpoint means the start or the end. The copy is shallow: the new list
owns its own storage, but records and nested collections inside it are still
shared with the original.

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
rewriting an existing key leaves that key in its original position. Keys are
`int` or `str`; anything else is rejected with `E_DICT_KEY`, because those are the
types the runtime compares and hashes by value. Values are any copyable storable
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
those fields. The same behavior applies to a view held in a variable, returned
from a helper, or passed as a parameter. A dictionary is shared by assignment
exactly as a list is.

The view types are `DictKeys[K, V]`, `DictValues[K, V]` and `DictItems[K, V]`.
They retain their dictionary, report its current size through `len`, and iterate
without snapshot allocation. `list(view)` copies the current keys, values or
items in insertion order. Views support ordinary loops, comprehensions and
`enumerate`; snapshot lists of `DictItem` also support two-name unpacking. Views
are not indexable: use `list(view)[index]` for positional access.

These prelude record types may appear in function signatures and generic return
types. A view is managed-bearing because it retains its dictionary, so a view of
a dictionary allocated inside `with arena()` cannot escape that arena without an
arena copy of the reachable dictionary. Reading and iterating the view inside the
arena remain nonallocating.

Creating a view does not freeze contents or size. Value replacement is visible
when iteration reaches that key; changing the size during a loop traps under the
same rule as direct dictionary iteration. Code that previously used a snapshot
from `keys()` or `values()` must now request it with `list(...)`. Code that used
`items()` as a values-only list should use `list(mapping.values())`.

```mylang
# doc: expect 42
def main() -> int:
    mapping = {"a": 10, "b": 20}
    live = mapping.items()
    old_values = list(mapping.values())
    mapping["b"] = 31
    total = 0
    for key, value in live:
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
collection's length through an alias during iteration traps with
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
plain records, fixed arrays, unions, `Result` and `Option` values with cycle
detection so a self-referential graph still terminates; dictionary equality
ignores insertion order. A managed `class` is the one exception: it compares by
reference identity, so two separately built instances with equal fields are not
equal, while a value is always equal to itself. A type that reaches a callback,
`Cell` or resource has no equality at all and is rejected with `E_TYPE`. There is
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
`Option` compare structurally; a class compares by reference identity:

```mylang
# doc: expect 42
record Point:
    x: int
    y: int


union Shape:
    empty,
    radius: int,
    point: Point


class Node:
    value: int


def main() -> int:
    if Point(x=1, y=2) != Point(x=1, y=2):
        return 1
    if Shape.radius(4) == Shape.point(Point(x=4, y=0)):
        return 2
    if Node(value=1) == Node(value=1):
        return 3
    first = Node(value=1)
    if first != first:
        return 4
    return 42
```

## List comprehensions

`[expression for name in source if condition]` builds a fresh managed list in one
checked pass over a list, string, byte string or dictionary. It takes exactly one
generator and at most one filter, the filter runs before the expression, and the
binding exists only inside the comprehension and may not shadow an active name.
The source collection is unchanged, and the produced value has to be a copyable
storable list element. Nested generators, generator expressions, and dictionary
or set comprehensions are not provided; write an ordinary `for` loop for those.

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

## The tracing collector

Each execution owns one single-threaded, nonmoving tracing heap, so a managed
object keeps a stable identity for its whole lifetime and no address ever moves
under a running program. Collection runs at managed allocation safepoints on a
simple object-count threshold; this is a prototype policy rather than a tuned
latency or byte budget, and the host allocator still decides how much memory
exists at all. Nothing in the surface language frees an object:
[`with arena() as name:`](arenas.md) changes only *when* a region's objects are
released, not how they are written. `mylang run --gc-stress` collects at every
safepoint, which is a rooting correctness check rather than a performance mode.

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

Every `scratch` list and every interpolated string in that program is unreachable
as soon as `batch` returns, and the collector reclaims them during a later
allocation without the program saying anything.

## Reclaiming cycles

Reference counts on execution values exist to protect temporary roots — operands,
intermediate results and retained aggregate snapshots — across an allocation that
might collect. They are not the reclamation algorithm. Collection subtracts the
edges internal to the managed graph, marks what the remaining roots reach and
sweeps the rest, so a cycle nothing outside points at is reclaimed like any other
garbage, and sweeping releases every dead edge before freeing a single object
header. Records are values rather than references, so a cycle is always formed
through the managed collections their fields hold.

```mylang
# doc: expect 42
record Node:
    name: str
    peers: list[Node]

def linked() -> int:
    left = Node(name="left", peers=[])
    right = Node(name="right", peers=[])
    left.peers.append(right)
    right.peers.append(left)
    hop = left.peers[0]
    back = hop.peers[0]
    if back.name != "left":
        return 0
    return len(hop.peers) + len(left.peers)

def main() -> int:
    total = 0
    for step in range(20):
        total += linked()
    return total + 2
```

`left.peers` reaches `right.peers` and back again, so neither list can be freed by
dropping a count to zero; each round of the loop leaves a whole cycle unreachable
and the tracing pass collects it. The same program under `--gc-stress`, which
collects at every safepoint, returns the same answer.
