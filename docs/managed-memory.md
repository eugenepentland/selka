# Managed application collections

Ordinary dynamic lists use managed storage. The default runtime reclaims it by
reference counting with copy-on-write; the tracing collector (`--gc-runtime`)
remains available with the same collection API and value semantics. There are no allocator
parameters, no move operations and no collection borrow scopes: managed memory is
the only way application code allocates. [Managed arenas](arenas.md) are the one
escape hatch, and they change *when* managed objects are freed rather than how
they are written.

```mylang
# doc: value-semantics
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
parameter with a marked call when a helper must change its caller's value.

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
Recursive record types are supported, but stored values are independent; use
explicit pool handles for identity-bearing graphs:

```text
record Node:
    value: int
    children: list[Node]
```

`record` and its mutable managed fields are values. The builtin `Cell` and
legacy `class` are rejected; replace identity-bearing
graphs with records plus stable ids in a pool or object table. Capturing closures
remain absent. Byte literals and the managed
[`bytes`](bytes.md) type keep their documented behavior. Owned resources, provider
capabilities, and must-handle results cannot be hidden inside copyable
lists. There are no interior pointers into managed storage. Host invocation, JSON encoding
of managed graphs, and QBE native emission reject unsupported managed boundaries;
ordinary scalar host calls from managed applications still work.

## Runtime selection

Reference counting is the default runtime. A command that names no runtime
builds and runs with it; choose another on commands that check, build or execute
a program:

| Option | Runtime |
| --- | --- |
| (none), `--rc-runtime` | Reference counting with copy-on-write; the default |
| `--rc-runtime=stats` | The same RC runtime with ownership-operation counters |
| `--rc-runtime=sites` | The counted RC runtime, with every count charged to the call site that caused it ([ownership sites](tooling/ownership.md#ownership-sites)) |
| `--gc-runtime` | The tracing collector: the opt-out from reference counting |

`MYLANG_RUNTIME=gc-v1` (or `rc-v3`, `rc-v3-counting`, `rc-v3-sites`) selects a
runtime for a whole shell session or CI job; an explicit flag outranks it.

For example, `mylang run-project examples/gc-default/main.my --print-result`
prints `142` under RC, and adding `--gc-runtime` prints the same under the
collector. `mylang test tests/lang --rc-runtime=stats` exercises the language
tests with counted RC. Either backend supports the same selectors; add
`--release` for LLVM O3 with full LTO. The uninstrumented default is the one to
measure for production performance.

`--gc-stress` stresses the tracing collector, so it needs GC: on `run`,
`run-project`, `test`, `build --run` and `invoke` it selects `--gc-runtime`
when no runtime flag is given, and naming it together with an `--rc-runtime`
flag is a usage error. A program built for RC refuses `--gc-stress` in
`MYLANG_OPTIONS` with exit status 2 and a message naming `--gc-runtime`, rather
than running without the stress it asked for.

RC keeps managed objects alive while an owner or a compiler-maintained lifetime
hold still needs them. Releasing the last such reference retires the object and
releases its child references. The runtime does not trace cycles. Ordinary value
programs use independent values and pool ids for graphs, and cannot store a
recursive live view that would create a retained cycle. These rules are checked
by the value model, independently of the runtime selector.

Arenas remain available with RC: the same `with arena()` syntax groups managed
allocations for bulk release, with the existing escape checks and copy rules.
RC does not introduce allocator parameters, explicit free operations or new
ownership syntax. Memory limits and trap cleanup apply to both runtimes.

`--legacy-sharing` uses tracing GC. Combining it with an explicit RC selector is
a usage error; the RC default and an inherited RC selection are normalized to GC
for legacy code.
Runtime selection is a build property, so changing a running binary's environment
cannot turn a GC binary into an RC binary. See
[native runtime contracts](tooling/native-build.md#runtime-contracts) for artifact
and cache compatibility.

## Collection and allocation contracts

With the default RC runtime, a managed object is released when its last owner
goes away, so memory returns as soon as a value is dead rather than at a later
collection. With the GC runtime, each execution owns a single-threaded, nonmoving tracing
heap. The compiler registers typed roots for live locals, operands and
intermediate values. Collection follows these roots and managed edges to keep
reachable objects; unreachable objects, including cycles in legacy programs,
can be reclaimed. Minor collections also account for edges from older objects
into younger storage.

Automatic collection runs at managed allocation safepoints according to byte
thresholds and memory-budget pressure. Budget pressure requests a full collection
before an allocation is refused. Collection timing is an implementation detail,
not a guest-visible reclamation guarantee. Both runtimes enforce the documented
[execution memory ceilings](tooling/runtime-budgets.md).

Managed construction and append carry the transitive `managed_allocation` effect.
`noalloc` excludes it, meaning "performs no managed allocation". It does not
promise zero host allocation for value representation or runtime bookkeeping.
Reads and fixed-slot writes are permitted under that bound. Inside a
[`with arena() as name:`](arenas.md) block the same managed allocation happens; only
its release point moves. Managed mutation is not a promise of purity or exclusive
access.

`mylang run-project examples/gc-default/main.my --gc-stress --print-result`
runs under the collector (`--gc-stress` selects it) and collects at every
managed construction/append safepoint. It should print `142`. Stress mode is a
rooting correctness check, not a performance mode. See the
[schematic instructions](../experiments/schematic/README.md) for the real migrated
application and normal/stress SVG comparison.

## Managed lists

`list[T]` is the growable sequence application code reaches for. Its storage is
managed by the selected runtime, so there is no allocator argument to thread and
no free to
write. Assignment and argument passing preserve the value independently, with
copy-on-write backing where possible. Elements must be
copyable storable values — scalars, records, strings, byte strings and other
managed collections — which keeps owned resources, provider capabilities and
unchecked results out of copyable storage. Reading an element yields a
snapshot of that value, never an interior pointer into growable storage.

```mylang
# doc: value-semantics
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
those fields. The same behavior applies to a view held in a variable, returned
from a helper, or passed as a parameter. Assignment copies a dictionary value;
only a `mut` parameter and marked call write back to a caller.

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

Stored recursive types cannot contain a cycle through a live view. For example,
`record Entry` with a field `view: DictValues[int, Entry]` is rejected with
`E_LIVE_VIEW_CYCLE`: inserting an entry holding that view into its own dictionary
would keep the dictionary alive through itself. The check follows stored fields,
variant payloads, nonempty arrays, and collection keys and elements, including
generic instantiations. It conservatively rejects the recursive type even when
particular instances would refer to separate dictionaries. Store a `list(view)`
snapshot instead, or represent graph links with pool ids. Nonrecursive records
may retain and return live views, and recursive types without stored views remain
valid. This restriction closes a case that the earlier tracing runtime accepted;
the diagnostic `--legacy-sharing` mode retains that earlier behavior.

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
has no equality and is rejected with `E_TYPE`. Legacy `class` identity and
builtin `Cell` are available only in compatibility mode. There is
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
# doc: value-semantics
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
checked pass over a list, string, byte string or dictionary. It takes exactly one
generator and at most one filter, the filter runs before the expression, and the
binding exists only inside the comprehension and may not shadow an active name.
The source collection is unchanged, and the produced value has to be a copyable
storable list element. Nested generators, generator expressions and dictionary
comprehensions are not provided; write an ordinary `for` loop for those.

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

## The tracing collector

With `--gc-runtime`, the opt-out from the default reference counting, each
execution owns one single-threaded, nonmoving tracing
heap, so a live managed object's address does not move during collection.
Collection runs at managed allocation safepoints according to allocation pressure
and the execution memory budget. Nothing in the surface language frees an object:
[`with arena() as name:`](arenas.md) changes only *when* a region's objects are
released, not how they are written. `mylang run --gc-stress` selects the
collector and collects at every safepoint, which is a rooting correctness check
rather than a performance mode.

```mylang
# doc: gc-runtime
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
allocation without the program saying anything. Under the default RC runtime the
same program releases each of them at that return instead.

## Reclaiming cycles

Ordinary value programs cannot construct a mutable cycle through assignments
or container stores. Identity-bearing graphs use explicit pool handles. The
tracing collector still handles cycles made by programs run with
`--legacy-sharing` during the migration release.

The tracing collector starts from registered live roots and follows managed
edges, then reclaims unreachable objects. Edges within an unreachable cycle do
not make it reachable from a root, so the collector can reclaim the whole cycle.
In compatibility mode, records can hold collections whose shared references form
such a cycle. This legacy behavior requires GC; the RC runtime relies on the
ordinary value model's cycle restrictions instead.

```mylang
# doc: legacy-sharing
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

In compatibility mode, `left.peers` reaches `right.peers` and back again, so neither list can be freed by
dropping a count to zero; each round of the loop leaves a whole cycle unreachable
and the tracing pass collects it. The same program under `--gc-stress`, which
collects at every safepoint, returns the same answer.
