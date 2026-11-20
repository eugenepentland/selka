# Managed collections

Lists, dictionaries, sets, strings and byte buffers live in managed storage. Each allocation has one owner, ordinary
parameters borrow, and the compiler destroys owned storage after its last use: no allocator, no explicit free.

Every use of a managed value lends it (the bare name), lends it for writing (`mut name`), gives it (`own name`) or
duplicates it (`copy(name)`). The [ownership rules](ownership-rules.md#the-model), also printed by `selka docs ownership`,
state the model and every numbered rule with its diagnostic codes.

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

The explicit copy leaves `values` usable after `alias` changes. A helper changes its caller's value through a `mut`
parameter and a marked call ([value semantics](value-semantics.md)).

Use `Node[]` for collections and `mut nodes: Node[] = []` for an empty list . Read with `nodes[index]`, write with `nodes[index] = value`, append with
`append(mut nodes, value)`. A bad index traps with `R_LIST_BOUNDS`. Allocation failure ends the program with status 1
(`R_MEMORY_BUDGET` under a byte ceiling, `fatal: out of memory` without one). Recursive records work, but stored values are
independent: use pool handles for identity-bearing graphs. `class` and `Cell` are rejected, closures do not capture, and
managed storage has no interior pointers. Owned resources and must-handle results cannot sit in copyable lists (a
capability may).

```selka
# doc: check
record Node:
    value: int
    children: Node[]
```

## Releasing memory

The compiler destroys owned storage after its last use, a temporary after its expression and a stored child with its
parent. Assignments and container stores mark named inputs with `own`; a bare `return value` or
`fail value` needs no marker, but named inputs inside a returned constructor do (`return Some(own value)`). There is no
implicit sharing and no copy-on-write.

The end of a block is not a use, and neither is a discard `_ = own value`, so a value whose end is visible (an open file, a
poller, a connection) closes after its last other use.

| Form | Effect |
| --- | --- |
| `try x` on an owned `Result` or `Option` | transfers the payload, no copy |
| `match` on a fresh call, constructor, `copy(value)`, `lists.pop`, decode, parse or file-read result | transfers the payload: `match load(): case Ok(value): return value` needs no copy |
| `match saved`, a field or an index | borrows, even at its last use |
| `match own saved` of an owned local or `own` parameter | consumes it ([consuming matches](match-expressions.md#consuming-matches)) |
| `own record.field` | consumes the whole record; `copy` the field to keep the record |

A nested pattern borrows its inner value: bind the layer and `match own` it, one layer at a time. A `copy` that carries
nothing is `W_NEEDLESS_COPY` ([`selka lint`](tooling/lint.md#needless-copies) says `L_NEEDLESS_COPY`). JSON `get`, `at`,
`as_str`, `as_list` and `as_dict` borrow their input; wrap them in `copy(...)` to keep an answer past the next change to its
document.

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

`@noalloc` promises that a function performs no managed allocation. `build`, `run` and `test` fail with
`E_NOALLOC_ALLOCATES` when ownership-expanded Core finds a may-allocate site, a transitive or unresolved call included;
`lint --gate` also blocks the `noalloc-allocates` rule, and plain `check` does not compute this. Every `selka run` or `selka test` process has a
[byte ceiling](tooling/runtime-budgets.md#guest-memory-ceilings).

## Retired arenas

`with arena():` and `with arena() as name:` are `E_ARENA_REMOVED`: every object is released when its last owner goes. Use
ordinary statements. `selka fix` deletes the `with` line, dedents the body and rewrites `name.escape(value)` to `value`
([fix](tooling/fix.md)), and leaves the repair to you where that would collide with another binding.

```selka
# doc: expect-error E_ARENA_REMOVED
func main() -> int:
    with arena():
        return 0
```

## Managed lists

`T[]` is the growable sequence, with managed storage. Elements must be copyable storable values (a capability may be one). Reading an element borrows; `copy(value)` makes an independent owner.

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

## List methods and indexing

| Call | Does |
| --- | --- |
| `append(value)`, `extend(other)` | add one element, or another list's elements |
| `insert(index, value)` | insert at a nonnegative position, clamped to the length |
| `pop()`, `pop(index)` | remove and return the last, or an indexed, element |
| `exchange(index, replacement)` | replace an element, returning the former one |
| `remove(value)`, `index(value)` | delete, or find, the first equal element |
| `reverse()`, `clear()`, `copy()` | reverse in place, empty, copy with independently owned children |
| `sort()`, `sort(key=f, reverse=True)` | order `int`, `float`, `str` or `bytes` ascending, or any list by a key; in place and stable ([keyed sorting](python-syntax.md#keyed-sorting)) |

A discarded `pop`, `exchange` or `index` result needs its own binding or `_ =`. An absent
`remove` or `index` traps with `R_LIST_VALUE`; `pop` on an empty list and a bad `exchange` index trap with `R_LIST_BOUNDS`.
Python's `push` is `E_REMOVED_SPELLING`, naming `append`. The prelude's `take(mut place)` and `exchange(mut place, value)` do
the same for any place ([taking and exchanging](value-semantics.md#taking-and-exchanging-a-value)).

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

The prelude forms `append(mut values, value)` and `sort(mut values)` mark the change on the call line:

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

`values[index] = value` overwrites a slot and never grows the list. A computed negative or out-of-range index traps with
`R_LIST_BOUNDS`; a constant negative index is `E_NEGATIVE_INDEX_REMOVED`. The receiver, index and assigned value each evaluate once (a Python-surface indexed write evaluates the value before its
target). `values += other` extends the receiver, and an earlier copy keeps its contents.

### Concatenating lists

`left + right` on two lists of one element type is a new list holding copies of both, as `"ab" + "cd"` is new text; neither
operand changes. Two element types is `E_TYPE`. `-`, `*` and `<` on lists are `E_TEXT_OPERATOR`. A generic body cannot yet
add two `T[]` values: call `lists.extend` on a copy.

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

A nonempty list literal infers one element type; `[]` takes its type from an annotation, field, parameter or return type,
else `E_LIST_INFERENCE`. `values[start:end]` is a view of the selected elements, and `copy(values[start:end])` makes an
independent list. A computed negative endpoint traps with `R_LIST_BOUNDS`, a constant one is `E_NEGATIVE_INDEX_REMOVED`;
endpoints above the length clamp, a reversed interval gives an empty list, an omitted endpoint means the start or end.

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

`dict[K, V]` keeps entries in the order their keys were first inserted; rewriting a key keeps its position. A key is any
[hashable](sets.md#hashable-keys) value (an integer, `bool`, `str`, `bytes`, or a record, union, enum, `Option` or fixed
array built only from those), compared structurally; a `float`, list, dict, set, `byte_buffer` or function key is
`E_DICT_KEY`. `counts[key]` traps with `R_MISSING_KEY` when the key is absent.

| Call | Does |
| --- | --- |
| `dicts.get(counts, key, fallback)` | the lookup that always answers |
| `dicts.pop(mut counts, key)` | remove and return the value; traps `R_MISSING_KEY` when absent (`dicts.pop_default(mut counts, key, fallback)` answers `fallback`) |
| `dicts.update(mut counts, other)` | replace existing values in place, append new keys |
| `dicts.setdefault(mut counts, key, fallback)` | the existing value, or store and return the fallback |

| `dicts.keys(counts)`, `dicts.values(counts)`, `dicts.items(counts)` | live views; `items` yields `DictItem[K, V]` records with `key` and `value`  |

A key written as a place is only read: the table copies it when it is new and keeps its copy when present, so a hit
allocates nothing. A fresh value, `copy(key)` or `own key` is taken as it is. This holds for `table[key] = value`,
`dicts.setdefault`, `dicts.add`, `dicts.append_to` and `sets.include`.

Views are ephemeral and not indexable (`list(dicts.items(m))[i]` is positional): use them as loop sources
(`enumerate(dicts.items(d))` too) or with `len`, `in`, `list`, `set` or `sorted`. The checker rejects mutations that overlap the iteration, so materialize a list first to change the dictionary.
Binding, returning, storing or passing a view to a user function is `E_VIEW_STORED`; `selka fix` wraps it in `list(...)`
where certain.

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

`for name in source` visits a list's elements, a string's Unicode scalar values, a [byte string](bytes.md)'s octets as `int`
and a dictionary's keys in insertion order. `for key, value in dicts.items(counts)` visits each entry,
`for index, value in enumerate(source)` adds the position, and `range(end)`, `range(start, end)` and
`range(start, end, step)` count integers (a negative step counts down: [stepped ranges](range-iteration.md#stepped-ranges)).
Iterating a managed collection holds a read borrow, so overlapping
mutation or transfer is refused (a runtime backstop reports `R_LIST_ITERATION_MUTATION`). List comprehensions are
`E_COMPREHENSION_REMOVED`: build a list with a typed empty accumulator, a `for` loop and `append`.

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

## Membership and value equality

`in` and `not in` ask a container about its contents: a dictionary for a key, a set for an element, a string for a
substring, a byte string for an octet or a contiguous subsequence. A list has no `in` (`E_LIST_MEMBERSHIP_REMOVED`): use
`lists.contains(xs, 2)`. `==` and `!=` compare contents, not identities, recursing through lists, dictionaries, records,
fixed arrays, unions, `Result` and `Option` (dictionary equality ignores insertion order); a type that reaches a callback or
resource has no equality (`E_TYPE`). There is no identity operator: use a pool handle when identity matters.

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
# doc: expect-error E_LIST_MEMBERSHIP_REMOVED
func main() -> int:
    mut values: int[] = [1, 2, 3]
    if 2 in values:
        return 1
    return 0
```

## Checked ownership

Plain `selka check`, `run`, `build` and `test` use checked ownership. Assignment and container insertion move a named managed value only with `own`; `copy(value)` keeps both usable, and
copying a list also duplicates the owned children of records and fixed arrays.

A plain parameter borrows read-only. A `mut` parameter, marked `mut` at the call, is an exclusive borrow for every type, a
resource included. An `own` parameter, marked `own`, takes the value: the caller's binding is unusable after the line, and the
callee may store, return or move it, else it is destroyed at its scope end. `own` is refused on a fresh value or a scalar
(`E_OWN_MARKER`). `append` and `sets.add` take their element `own`, so `append(mut rows, row)` is refused until it reads
`append(mut rows, own row)` (a borrowed name gets `copy(...)`). A plain parameter of a move-only type is `E_OWN_PARAMETER`
(a plain `@linear` record parameter is a read-only loan: [linear records](records-and-unions.md#linear-records)); the repair
writes `own`.

`L_COPY_FOR_STORE` and `W_COPY_FOR_STORE` point at a parameter copied into storage, and `W_COPY_MOVE` at a loop that copies
a list's elements: `selka fix` makes the change where it is certain ([lint](tooling/lint.md#moves-instead-of-copies),
[fix](tooling/fix.md)).

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

A text or bytes slice is a view and allocates nothing ([Slices are views](#slices-are-views)). Checked ownership supports
owned dictionaries, sets, recursive values, scoped resources and synchronous `parallel.map`; `check` validates source
ownership and `build` also checks backend and runtime support. It rejects `.snapshot()`, `.view()`, escaping task handles,
arbitrary managed foreign calls and unaudited runtime APIs. `--experimental-zero-rc`, `--experimental-single-owner`,
`--value-semantics` and `--legacy-sharing` are rejected with exit status 2.

## Declared borrowed results

Write `from` after the result type to return a read-only borrow of parameters: `-> T from first, second`. The sources must be
plain or `mut` parameters with managed storage, and every value return must come from them. Callers use the signature even
when the body is unavailable, and the result keeps its sources alive until its last use. Optional and fallible successes work
(`-> Json? from doc fails ParseError`; write `from` before `fails`). Function types cannot declare `from`, and a function
with a `from` result cannot be a function value.

```selka
# doc: expect 42
func tail(values: int[]) -> int[] from values:
    return values[1:]

func main() -> int:
    mut values = [10, 40, 2]
    const rest = tail(values)
    return rest[0] + rest[1]
```

`E_BORROW_UNDECLARED` names a returned borrow missing from the signature (`selka fix` adds its source); `E_BORROW_SOURCE`
rejects an unknown or `own` source, a duplicate or a clause no source can lend (the fix deletes it); `E_BORROW_MIXED` is
fresh storage returned beside borrows (`None`, `""` and `[]` are not fresh): borrow every return, or copy them and remove
`from`. `W_COPY_RETURNED` suggests `from` where every return copies a parameter's place. Interface files and API comparison include the clause: adding a source or removing
the final one is breaking. The rules are R3 to R5 in the [ownership reference](ownership-rules.md#r4--borrowed-returns).

### Slices are views

A slice `s[start:end]` is a read-only view of its source's text or octets and allocates nothing. Endpoints are Unicode scalar
positions for `str` and byte positions for `bytes`; negative positions trap and endpoints above the length clamp.
`.borrow(a, b)`, `.view(a, b)`, `TextView` and `ByteView` are `E_BORROW_VIEWS_REMOVED`, and `selka fix` rewrites them to
`s[a:b]`, `str` or `bytes`.

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

A function can return a slice of a named `from` source. A slice binding is read-only and cannot be stored in a container,
record or callback: store `copy(value)` of it, also when it was bound with `const` first (`selka fix` puts the copy on the
binding). See [V1](ownership-rules.md#v1--slices-are-views).

### Explicit values and scoped parallel work

`copy(value)` also accepts records, enums, options and fixed arrays, duplicating owned children recursively; resources and
move-only values cannot be copied. `parallel.map` borrows each input element, joins every task and returns results in input
order, so the caller can use its input again at once; a callback must `copy` managed input data it returns. It takes a
function value with one read-only parameter, with no closure captures or escaping handles, and no `Unit` elements.

```text
import parallel

func render(value: int) -> str:
    return "item-" + str(value)

func example(out: Stream):
    const input = [1, 2, 3]
    const output = parallel.map(input, render)
    print(out, input[0], output[0])
```

### Borrowed constants

`const name = place` binds a read-only borrow with no copy to any managed place (a local, a plain or `own` parameter, a
field, an element, a dictionary value), through the binding's last use. It can be read, compared and passed to read-only
parameters; storing it, returning it as an owner or passing it `mut` or `own` needs `const name = own owner` or
`copy(place)`. A `mut` local needs its own value.

```text
func second(rows: int[][]) -> int:
    const row = rows[1]        # borrows rows: no copy
    return len(row)            # the last use of row

func grow(rows: int[][]) -> int[]:
    const row = rows[1]
    return copy(row)           # a store or return of the borrow needs copy(...)
```

A borrow holds the place, not the whole record: `const item = self.items[i]` holds `self.items`, so writing `self.links` or
`self.count` is allowed while `item` is live; writing `self.items`, an element of it or the whole of `self` (including
`mut self`) is refused ([R2](ownership-rules.md#r2--loans-block-changes)).

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

Every copy a program makes at run time is written in the source: `copy(value)`, or a new value whose meaning is a new storage
form (`+` on text and bytes, the pieces of `split`, `encode()`, `sorted(xs, key=...)`, `bytes(buf)`). Where the source names
none (a slice of a list given to an owned parameter, `parallel.map` over a slice, a buffer written from its own octets), the
checker refuses with the certain repair `copy(...)`. A guest build also refuses a copy the source did not write as
`E_CORE_HIDDEN_COPY`, whose note names `--no-validate` ([certificate validators](tooling/native-build.md#certificate-validators)).

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/managed-memory.md).
