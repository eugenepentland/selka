# Managed collections

Lists, dictionaries, sets, strings and byte buffers live in managed storage.
The compiler checks ownership and inserts direct destruction; source code has no
allocator parameters or explicit frees. Assignments and owned returns can move a
value, ordinary parameters borrow, and `.copy()` makes independent storage.

```mylang
# doc: expect 1
# doc: expect 2
func main(out: Stream) -> int:
    mut values: int[] = [1]
    mut alias = values.copy()
    alias.append(42)
    out.print(len(values))
    out.print(len(alias))
    return 0
```

The explicit copy lets `alias` grow while `values` remains usable and unchanged.
Appending grows capacity automatically. Managed element reads borrow from their
container; copy a selected child when an independent owner must escape. Use a
`mut` parameter with a marked call when a helper must change its caller's value.

Use `Node[]` for application collections and `mut nodes: Node[] = []`
for an empty list. Read with `nodes[index]`, write with `nodes[index] = value`,
append with `nodes.append(value)`, and count with `len(nodes)`. An empty literal
needs an expected list type from an annotation, return type, or parameter.

Capacity is a reserve hint, not a fixed limit. Mutations such as `append` return `Unit`; `pop` returns the removed element. Invalid
indices trap with `R_LIST_BOUNDS`. Allocation failure ends the program with
status 1 (`R_MEMORY_BUDGET` under a byte ceiling, `fatal: out of memory` without
one) rather than returning a recoverable collection result. Keep
application cardinality checks where input limits are part of its contract.

List elements can be ordinary copyable values, records, and other managed lists.
Recursive record types are supported, but stored values are independent; use
explicit pool handles for identity-bearing graphs:

```mylang
# doc: check
record Node:
    value: int
    children: Node[]
```

`record` and its mutable managed fields are values. The builtin `Cell` and `class`
are rejected; replace identity-bearing graphs with records plus stable ids in a pool
or object table. Capturing closures remain absent. Byte literals and the managed
[`bytes`](bytes.md) type keep their documented behavior. Owned resources and provider capabilities cannot be hidden inside copyable lists.
A list of Results still requires explicit handling of each selected result; a list
does not turn an error into success. Borrowed views cannot escape their owners.

## Releasing memory

Every dynamic allocation has one owner and compiler-inserted destruction.
Assignments of managed values move ownership; `.copy()` requests independent
storage. Read-only text and byte views borrow a named owner and may cross calls
under a single-input return contract. Mutation or moving that owner while a view
is still used is rejected. Files and dependent capabilities use scoped providers.
A returned dependent owner needs one unambiguous input provider; escaping a local
provider or an ambiguous provider choice is rejected. Sharing and `.snapshot()`
are unsupported.

`try` transfers the active payload of an owned `Result` or `Option` directly.
It does not make a deep copy. `match` on a fresh call result also transfers its
payload, so `match load(): case Ok(value): return value` needs no copy. Matching
a named value (`match saved`) or a field/index continues to borrow, even at its
last use. A fresh constructor, `.copy()` or `.pop()` result follows the
same transfer rule as a call, as do fresh results from text/byte decoding,
validation and numeric parsing. A named-field pattern on a fresh owned match
splits the whole payload: `case Pair.parts(left=a, right=b)` gives `a` and `b`
independent ownership. Fields bound to `_` or unused in the arm are destroyed.
The hidden payload is consumed as a whole; ordinary `record.field` access and
patterns on named values still borrow. Nested patterns also borrow their inner
intermediate value; whole-field transfer only splits the immediate fresh payload.
`.copy()` explicitly requests an independent owner.
See the [owned-payload](../experiments/owned-payload-20261011/README.md) and
[fresh-match](../experiments/owned-match-20261011/README.md) experiments.

JSON `get` and `at` borrow the input container and copy only the selected value.
Missing keys, wrong variants and out-of-range indices return `None` without
copying the container. `as_list` and `as_dict` still return independent copies.
See the [JSON lookup and field-transfer measurements](../experiments/zero-rc-batch-20261011/README.md)
for historical examples, allocation counts, and runtime comparisons. These old
measurements are not results for the current compiler.

The zero-RC runtime has no reference-count field, retain/release functions, or
count-based uniqueness checks. Heap allocation and ordinary destruction still
occur. The header remains 32 bytes because of alignment, and explicit copies can
increase allocation. The installed compiler components have a separate
qualification boundary recorded in the closeout report; an ordinary guest default
change alone does not qualify the whole package as RC-free.

A managed object is destroyed when its owner goes away: a local at the end of
its last use, a temporary right after the expression that made it, a list element
when its list is destroyed. The compiler places destruction
([ownership](tooling/ownership.md)); the program never says anything. Because values
are independent, assignments and container stores cannot build a cycle, so nothing
needs tracing, and identity-bearing graphs use pool handles.

```mylang
# doc: expect 1225
func batch(size: int) -> int:
    mut scratch: str[] = []
    for index in range(size):
        scratch.append(f"item {index}")
    return len(scratch)

func main() -> int:
    mut kept: int[] = []
    for step in range(50):
        kept.append(batch(step))
    mut total = 0
    for value in kept:
        total += value
    return total
```

Every `scratch` list and every interpolated string in that program is released when
`batch` returns. Dictionary views are ephemeral; stored snapshots use explicit
`list(...)` materialization, and view types cannot appear in parameter, return,
field or element annotations.

Managed construction and append carry the transitive `managed_allocation` effect.
`noalloc` promises "performs no managed allocation". Builds and runs warn with
`W_NOALLOC_ALLOCATES` when ownership-expanded Core finds a may-allocate site;
`lint --gate` blocks on the corresponding `noalloc-allocates` rule. `check` does
not compute this contract. The promise excludes runtime bookkeeping. Reads can
be allocation-free; independent copies and operations such as text encoding or
buffer reversal may allocate even when their result has the same length. Managed
mutation is not a promise of purity. Mutable borrows remain exclusive.
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

A `with arena():` or `with arena() as name:` block is rejected with
`E_ARENA_REMOVED`. Use ordinary statements. The diagnostic keeps its structured
repair even when another semantic error is present. The old escape checks
(`E_ARENA_ESCAPE`, `E_ARENA_BINDING`) are gone.
`mylang fix` migrates a file: it deletes the `with arena():` line, dedents the
block's body by one level and rewrites `name.escape(value)` to `value`
([fix](tooling/fix.md)).

```mylang
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
Assignment can move the owner; ordinary arguments borrow. Elements can include
scalars, records, strings, byte strings, managed collections and Results. Resources
and provider capabilities remain outside ordinary list storage. A selected managed
element borrows the container; `.copy()` creates an independent value when needed.

```mylang
# doc: expect 42
func widen(mut target: int[]) -> Unit:
    target.append(2)

func main() -> int:
    mut values: int[] = [40]
    mut alias = values.copy()
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
place and stably ([keyed sorting](python-syntax.md#keyed-sorting)); `copy()` returns an independent list and recursively copies managed children; `clear()` empties the list; and
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
func main() -> int:
    mut scores: int[] = [30, 10, 20]
    scores.sort()
    scores.append(40)
    scores.insert(0, 5)
    scores.remove(5)
    scores.reverse()
    scores.extend([7])
    _ = scores.pop(0)
    mut window = scores.copy()
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
func main() -> int:
    mut readings = [3, 12, 7, 20]
    mut empty: int[] = []
    mut window = readings[1:3]
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
hashed and compared structurally and owned by the table; a `float`, list, dict,
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
fallback; `counts.copy()` returns an independent dictionary and recursively copies managed children; and
`counts.clear()` empties it. `counts.pop(key)` without a fallback traps with
`R_MISSING_KEY`. `counts.items()` yields `DictItem[K, V]` value records with `key`
and `value` fields. A two-name loop `for name, value in counts.items()` unpacks
those fields. Assignment can move a dictionary owner; use `.copy()` for an
independent dictionary. A `mut` parameter and marked call write back to a caller.

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
func main() -> int:
    mut mapping = {"a": 10, "b": 20}
    mut old_values = list(mapping.values())
    mapping["b"] = 31
    mut total = 0
    for key, value in mapping.items():
        total += value
    return total + old_values[1] - 19
```

```mylang
# doc: expect 42
func main() -> int:
    mut counts: dict[str, int] = {}
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
    mut order: str[] = []
    for name in counts:
        order.append(name.copy())
    if order[0] != "pear":
        return 4
    if counts.get("plum", 0) != 0:
        return 5
    mut keys: str[] = []
    mut total = 0
    for name, value in counts.items():
        keys.append(name.copy())
        total += value
    if keys[0] != "pear" or keys[1] != "apple" or keys[2] != "fig":
        return 7
    mut copy = counts.copy()
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
func main() -> int:
    mut words = ["alpha", "beta"]
    mut letters = 0
    for word in words:
        for letter in word:
            letters += 1
    mut weighted = 0
    for index, word in enumerate(words):
        weighted += index * len(word)
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
func main() -> int:
    mut left: int[] = [1, 2, 3]
    mut right: int[] = [1, 2, 3]
    if left != right:
        return 1
    if 2 not in left:
        return 2
    if 9 in left:
        return 3
    mut nested: int[][] = [left]
    mut twin: int[][] = [right]
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

Aggregates compare the same way. Records, fixed arrays, unions, `Result` and
`Option` compare structurally. Use a pool handle when identity must be compared:

```mylang
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

`[for name in source if condition yield expression]` builds a fresh managed list
in one checked pass over a list, string, byte string or dictionary. The source
evaluates first, then each optional Boolean filter before its produced expression.
Unfiltered results reserve the source length; filtered results grow as needed.
The readonly binding exists only inside the expression and may not shadow an
active name. Combine filters with Boolean `and`.

The source remains unchanged, and produced values must be copyable storable list
elements. List sequences accept one binder and one source; nested iteration or
destructuring requires explicit loops. Dict/set comprehensions and generator
arguments retain their existing forms; see
[the language guide](python-syntax.md#dict-and-set-comprehensions).

The source may also be an integer `range(...)`, exactly as in a `for` loop:
`range(end)` and `range(start, end)` walk a half-open ascending range and bind the
name to each integer value, so `[for i in range(5) yield i * i]` collects the first five
squares. The bounds share one integer type and evaluate once before the loop, and
an empty or reversed range yields an empty list.

```mylang
# doc: expect 20
func main() -> int:
    mut squares = [for i in range(5) yield i * i]
    mut total = 0
    for s in squares:
        total = total + s
    return total - 10
```

```mylang
# doc: expect 21
func main() -> int:
    mut readings: int[] = [3, 12, 7, 20]
    mut doubled = [for value in readings yield value * 2]
    mut large = [for value in readings if value > 10 yield value]
    mut labels = [for value in large yield str(value)]
    mut initials = [for letter in "mylang" if letter != "m" yield letter]
    mut counts: dict[str, int] = {"a": 1, "bb": 2}
    mut widths = [for key in counts yield len(key)]
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

Ordinary commands use checked ownership.
Lists, strings, bytes, and mutable byte buffers have one owner. Assignment,
container insertion, and owned return move a value; ordinary parameters borrow,
and `mut` parameters borrow exclusively. Use `.copy()` when both values must
remain independently usable. Copies of lists also duplicate owned children in
records and fixed arrays.

```mylang
# doc: expect hello7
# doc: expect hello7!
func main(out: Stream) -> int:
    mut text = "hello" + str(7)
    const saved = text.copy()
    text += "!"
    out.print(saved)
    out.print(text)
    return 0
```

Cleanup directly destroys owned storage without reference counts. Literals have
static storage; modifying a literal first creates writable storage. Heap
allocation and growth still occur. String slices produce owned results. Explicit
borrowed ranges avoid that materialization when a local view is sufficient.

The checked contract supports owned dictionaries, sets, recursive values, scoped resources,
and synchronous `parallel.map`. It rejects `.snapshot()`, retained byte `.view()`,
escaping task handles, arbitrary managed foreign calls, and unaudited runtime APIs.
`check` validates source ownership; `build` also checks backend and runtime
support. An unsupported shape is diagnosed instead of falling back to RC.
Historical [prototype stages and measurements](../experiments/zero-rc-20261011/README.md)
describe older revisions, not a current compatibility mode.


### Borrowed text and byte ranges

`.borrow(start, end)` produces a read-only
`TextView` from a string or `ByteView` from bytes/a byte buffer. Endpoints use
Unicode scalar positions for text and octet positions for bytes, with negative
indices and clamping. A view holds a pointer and length. Creating or borrowing
another range performs no allocation or RC. `len()` reads it directly; text
length and indexing scan UTF-8. Text character indexing returns an owned string
and can allocate for non-ASCII characters. Byte indexing returns a scalar.

```mylang
# doc: expect λz7
# doc: expect λz7
func segment(source: TextView, start: int) -> TextView:
    return source.borrow(start, start + 3)

func main(out: Stream) -> int:
    mut text = "aλz" + str(7)
    const full = text.borrow(0, len(text))
    const part = segment(full, 1)
    out.print(part)                  # λz7; no substring allocation
    const saved = part.copy()       # independent owned str
    text += "!"
    out.print(saved)                # allowed
    # out.print(part)               # compile error: owner changed
    return 0
```

The returned-view contract is visible in ordinary types: a function returning a
view has exactly one immutable view parameter, and returns a view derived from
that parameter. It cannot take `mut` parameters. No lifetime names are needed.
The compiler keeps the backing owner alive through the last use of any derived
view, including through function calls, without relying on inlining.

View bindings and parameters are immutable. Views cannot be
stored in containers, records, callbacks, or conditional-expression bindings.
Use branch returns in a view-returning helper instead. A loop may create fresh
views inside its body, but cannot invalidate a view created outside the loop.
This is conservative even when that outer view will not be used again. Supported
operations are `.borrow()`, indexing, `len()`, `.copy()`, and text printing.
Byte-view printing requires `.copy()`; other methods and direct view iteration
are not yet admitted. The original byte `.view()` operation remains distinct and
is refused by the checked ownership contract. Unsupported shapes have no RC fallback.

See [Stage 2 measurements and examples](../experiments/zero-rc-views-20261011/README.md).


### Explicit values and scoped parallel work

`.copy()` also accepts records, enums, options and fixed arrays. It recursively
duplicates owned children; scalar copies simply preserve their value. Resources
and move-only values cannot be copied.

```mylang
# doc: expect 1
# doc: expect item-1
import parallel

func render(value: int) -> str:
    return "item-" + str(value)

func main(out: Stream) -> int:
    const input = [1, 2, 3]
    const output = parallel.map(input, render)
    out.print(input[0])
    out.print(output[0])
    return 0
```

`parallel.map` borrows each input element, runs the callbacks through the task
scheduler, and joins every task before returning the results in input order.
The caller can use its input again immediately. A callback returning managed
input data must explicitly copy it; returning new data transfers it to the
output. Nested maps, ordinary error enums, empty inputs and discarded outputs
follow the same cleanup rules. An uncaught fatal trap terminates the process.

This initial API takes a function value with one read-only parameter. It has no
closure captures, detached work or escaping task handles, and does not support
Unit elements. Heap allocation and scheduling synchronization remain. Output
storage and independently owned callback results can grow with input size; a
reduction in scheduling overhead is not a claim of allocation-free parallel work.
