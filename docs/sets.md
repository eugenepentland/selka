# Sets

`set[T]` holds each distinct value of a hashable type once, in the order first added. `in`, `add`, `remove` and `discard`
take expected constant time, and a set prints the way Python prints one. Like a list or a dictionary it has one owner:
assignment can move it, and `copy(value)` keeps both usable. A function that changes a set takes it as `mut`.

## Set literals and construction

`{a, b, c}` builds a set in source order; a repeated element keeps its first position. `{}` is the empty dict, as in
Python, so an empty set is `set()` with its type from an annotation, a parameter, a field or a return type. A bare
`x = set()` has no element type: `E_SET_INFERENCE`.

`set(iterable)` copies the elements of a list, `str` (its characters), `bytes` (its octets as `int`), a dictionary (its
keys), a dictionary view, a fixed array, `range(...)` or another set. To collect filtered or transformed elements, make a
typed empty set and `add` inside `for` and `if` statements; a set comprehension is `E_COMPREHENSION_REMOVED`.

```selka
# doc: expect {2, 3, 5, 7} {'b', 'a'} {0, 1, 9, 16} set() {'a', 'b'}
# doc: expect 4 2
import sets

func main(out: Stream) -> int:
    mut primes = {2, 3, 5, 7, 3}
    mut seen: set[str] = set()
    sets.add(mut seen, "b")
    sets.add(mut seen, "a")
    sets.add(mut seen, "b")
    mut gather_result: set[int] = set()
    for n in range(0, 5):
        if n != 2:
            const gather_value: int = n * n
            sets.add(mut gather_result, gather_value)
    mut squares = own gather_result
    mut empty: set[int] = set()
    print(out, primes, seen, squares, empty, set("abba"))
    print(out, len(primes), len(seen))
    return 0
```

## Set functions

| Function | What it does |
| --- | --- |
| `sets.add(mut s, own x)` | inserts an element it takes over |
| `sets.include(mut s, x)` | inserts one it only reads: copies `x` when new |
| `sets.remove(mut s, x)` | deletes `x`; traps `R_MISSING_KEY` when absent |
| `sets.discard(mut s, x)` | deletes `x`; a missing one stays absent |
| `sets.pop(mut s)` | removes and returns the newest element; `R_MISSING_KEY` when empty |
| `sets.clear(mut s)` | empties the set |
| `copy(s)` | the prelude's independent owned copy |
| `sets.update(mut s, other)` | adds every element of another set or of a list |
| `sets.union`, `intersection`, `difference`, `symmetric_difference` | a new set from two sets of one type |
| `sets.subset`, `superset`, `disjoint` | a `bool` for two sets of one type |

A set is not indexable, and the `dicts` functions refuse it. `len`, `in`, `for`, `enumerate`, `list`, `sorted`, `sum`,
`min`, `max`, `any` and `all` see the elements in insertion order. Iteration borrows the set for reading; the checker
rejects overlapping mutation.

```selka
# doc: expect 42
import sets
import strings

func tag(mut names: set[str], name: str) -> Unit:
    sets.include(mut names, name)

func main() -> int:
    mut names = {"ada", "bob"}
    mut alias = copy(names)
    tag(mut alias, "cy")
    if "cy" in names:
        return 1
    sets.discard(mut alias, "zed")
    sets.remove(mut alias, "bob")
    mut newest = sets.pop(mut alias)
    if newest != "cy" or "cy" in alias:
        return 1
    mut backup = copy(alias)
    sets.update(mut alias, {"dee", "eve"})
    sets.clear(mut alias)
    mut total = 0
    for name in backup:
        total += strings.char_count(name)
    return total * 14
```

## Set operators

`a | b`, `a & b`, `a - b` and `a ^ b` are union, intersection, difference and symmetric difference. Each builds a new set
of the left operand's surviving elements, then the right operand's new ones. `a <= b` and `a < b` test subset and proper
subset, `a >= b` and `a > b` superset, and `a == b` compares contents regardless of order. Both operands are sets of one
element type.

A non-set operand is `E_SET_OPERATOR`, naming the bitwise builtin `bit_or(a, b)`, `bit_and(a, b)` or `bit_xor(a, b)`.
Integers have no bit operators: `E_BIT_OPERATOR_REMOVED`, whose fix writes that call. A set has no `|=`: write
`s = s | t` or `sets.update(mut s, t)`.

```selka
# doc: expect {1, 2, 3, 4, 6, 5} {2, 4} {1, 3} {1, 3, 6, 5}
# doc: expect True False True True
import sets

func main(out: Stream) -> int:
    mut left = {1, 2, 3, 4}
    mut right = {6, 4, 2, 5}
    print(out, left | right, left & right, left - right, left ^ right)
    print(out, {2, 3} < left, left <= right, sets.disjoint(left, {9}), {3, 1, 2} == {1, 2, 3})
    return 0
```

## Hashable keys

A dictionary key and a set element are hashed and compared by value: every integer kind, `bool`, `str`, `bytes`, and
value types built only from those (records, unions, enums, `Option` values and fixed arrays). A table owns its stored
keys: scalar-only keys copy, and inserting a managed key moves it, so use `copy(value)` to keep the original. Hashing is
structural and deterministic, the same on every run.

```selka
# doc: expect 42
record Cell:
    row: int
    col: int

record NameKey:
    number: int
    text: str

enum Shape:
    dot
    circle(value: int)
    label(value: str)

func main() -> int:
    mut walls: set[Cell] = {Cell(row=0, col=1), Cell(row=2, col=3)}
    mut names: dict[NameKey, int] = {NameKey(number=1, text="a"): 40}
    mut shapes = {Shape.circle(value=2), Shape.label(value="x"), Shape.dot}
    mut start = Cell(row=0, col=1)
    mut marked: set[Cell] = {start}
    start.col = 9
    if Cell(row=0, col=1) not in walls or Cell(row=0, col=1) not in marked:
        return 1
    if Shape.label(value="x") not in shapes or Shape.circle(value=3) in shapes:
        return 2
    return names[NameKey(number=1, text="a")] + len(marked) + len(walls) - 1
```

An unhashable key is rejected where the dictionary or set is built (`E_DICT_KEY`, `E_SET_ELEMENT`), naming the part:

- `float` (NaN is not equal to itself), also nested: a record with a `float` field is refused with its path, such as
  `Reading.at.x`;
- a mutable `list`, `dict`, `set` or `byte_buffer`;
- a function value, which has no equality, and a capability, file or resource.

In a generic function a type parameter used as a key or element must promise `integer`.

## Representation and cost

Membership, `add`, `remove` and `discard` probe a hash index once. The combining operators and the subset tests are
linear in the operands' sizes.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/sets.md).
