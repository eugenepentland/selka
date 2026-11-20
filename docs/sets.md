# Sets

`set[T]` holds each distinct value of a hashable type once. It keeps its elements in
the order they were first added, answers `in`, `add`, `remove` and `discard` in
expected constant time, and prints the way Python prints a set. Like a list or a
dictionary it has one owner. Assignment can move that owner; use `copy(value)` when
both values must remain independently usable. A function that changes its caller's
set declares the parameter `mut`,
and the call site marks the argument with `mut`.

## Set literals and construction

`{a, b, c}` builds a set from its elements in source order; a repeated element keeps
the position it was first added at. `{}` is the empty dict, as in Python, so an empty
set is `set()` with its type coming from an annotation, a parameter, a field or a
return type. `set(iterable)` copies the elements of a list, `str` (its characters),
`bytes` (its octets as `int`), dictionary (its keys), dictionary view, fixed array,
`range(...)` or another set. To collect filtered or transformed elements, create
a typed empty set and call `add` inside explicit `for` and `if` statements.
Set comprehensions receive `E_COMPREHENSION_REMOVED`.

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

A set renders inside an f-string, a list or a dictionary exactly as it prints on its
own, so an empty set is `set()` there too. `set()` with no context has no element
type to build, so `x = set()` alone is `E_SET_INFERENCE`.

## Set functions

`sets.add(mut s, own x)` inserts an element it takes over, and `sets.include(mut s, x)` inserts one it only
reads: the set copies `x` when it is new, and a present `x` allocates nothing and stays with the caller.
`sets.remove(mut s, x)` deletes one and traps with `R_MISSING_KEY`
when it is absent, exactly as `d[key]` does for a missing key, while `sets.discard(mut s, x)`
leaves a missing element absent. `sets.pop(mut s)` removes and returns the most recently added
element and traps with `R_MISSING_KEY` on an empty set. `sets.clear(mut s)` empties the set,
the prelude's `copy(s)` returns an independent owned copy, and `sets.update(mut s, other)` adds every
element of another set or of a list. `sets.union`, `intersection`, `difference` and
`symmetric_difference` return a new set, and `sets.subset`, `superset` and `disjoint` answer a
`bool`; each takes two sets of the same type. A set is not indexable and the `dicts` functions
refuse it. `len(s)`, `x in s`, `x not in s`, `for x in s`, `enumerate(s)`, `list(s)`,
`sorted(s)`, `sum`, `min`, `max`, `any` and `all` all see the elements in insertion
order. Iteration borrows the set for reading; the checker rejects overlapping
mutation while that borrow is live.

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

`a | b`, `a & b`, `a - b` and `a ^ b` are union, intersection, difference and
symmetric difference. Each evaluates the left operand and then the right one once,
and builds a new set holding the left operand's surviving elements in its order
followed by the right operand's new elements in theirs. `a <= b` and `a < b` test for
a subset and a proper subset, `a >= b` and `a > b` for a superset, and `a == b`
compares contents without regard to insertion order. The operators take two sets of
the same element type. A non-set operand is rejected with `E_SET_OPERATOR` naming
the bitwise builtin, `bit_or(a, b)`, `bit_and(a, b)` or `bit_xor(a, b)`; integers
themselves have no bit operators and are refused with `E_BIT_OPERATOR_REMOVED`,
whose fix writes that call. A set has no augmented form such as `|=`: rebind the
name with `s = s | t` or call `sets.update(mut s, t)`.

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

A dictionary key and a set element are hashed and compared by value, so they must be
values whose contents cannot change once stored and whose equality is reflexive:
every integer kind, `bool`, `str`, `bytes`, and the value types built only from
those — records, unions, enums, `Option` values and fixed arrays. A
table owns its stored keys. Scalar-only keys copy by value; inserting a managed
key moves it. Use `copy(value)` when the original must remain independently usable.
Hashing is structural and deterministic: it reads
exactly what `==` compares, field by field and case by case, with fixed constants and
no per-process seed, so a dictionary or set behaves the same on every run.

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

A key type that cannot be hashed is rejected where the dictionary or set is built,
with `E_DICT_KEY` or `E_SET_ELEMENT` naming the offending part: `float`, because NaN
is not equal to itself; a mutable `list`, `dict`, `set` or `byte_buffer` value,
whose contents can change after it is stored; a
function value, which has no equality; and a capability, file or resource. A record
with a `float` field nested in it is refused with the path to that field, such as
`Reading.at.x`. Inside a generic function a type parameter used as
a key or element must promise `integer`, while `str` and concrete hashable types are
accepted as they are.

## Representation and cost

A set is a dictionary from its elements to unit: the same insertion-ordered entry
list and open-addressing hash index, with owned backing storage. Membership, `add`, `remove` and `discard` probe the index
once. Removing an element from the middle takes its slot out of the index and leaves
its entry to be squeezed out the next time the entries are read in order, so a
removal moves nothing; `dicts.pop(mut d, key)` shares that path. The combining operators
and the subset tests walk one operand and probe the other, so they are linear in the
operands' sizes.
