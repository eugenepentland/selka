# Sets

`set[T]` holds each distinct value of a hashable type once. It keeps its elements in
the order they were first added, answers `in`, `add`, `remove` and `discard` in
expected constant time, and prints the way Python prints a set. Like a list or a
dictionary it lives on the tracing heap. Assignment gives the destination an
independent value, even if the implementation shares backing storage until a
write. A function that changes its caller's set declares the parameter `mut`,
and the call site marks the argument with `mut`.

## Set literals and construction

`{a, b, c}` builds a set from its elements in source order; a repeated element keeps
the position it was first added at. `{}` is the empty dict, as in Python, so an empty
set is `set()` with its type coming from an annotation, a parameter, a field or a
return type. `set(iterable)` copies the elements of a list, `str` (its characters),
`bytes` (its octets as `int`), dictionary (its keys), dictionary view, fixed array,
`range(...)` or another set, and `{value for name in source if condition}` is the set
comprehension, with the same single generator and optional filter a list
comprehension takes.

```mylang
# doc: expect {2, 3, 5, 7} {'b', 'a'} {0, 1, 9, 16} set() {'a', 'b'}
# doc: expect 4 2
def main(out: Stream) -> int:
    primes = {2, 3, 5, 7, 3}
    seen: set[str] = set()
    seen.add("b")
    seen.add("a")
    seen.add("b")
    squares = {n * n for n in range(5) if n != 2}
    empty: set[int] = set()
    out.print(primes, seen, squares, empty, set("abba"))
    out.print(len(primes), len(seen))
    return 0
```

A set renders inside an f-string, a list or a dictionary exactly as it prints on its
own, so an empty set is `set()` there too. `set()` with no context has no element
type to build, so `x = set()` alone is `E_SET_INFERENCE`.

## Set methods

`add(x)` inserts an element; `remove(x)` deletes one and traps with `R_MISSING_KEY`
when it is absent, exactly as `d[key]` does for a missing key, while `discard(x)`
leaves a missing element absent. `pop()` removes and returns the most recently added
element and traps with `R_MISSING_KEY` on an empty set. `clear()` empties the set,
`copy()` returns a fresh shallow copy, and `update(other)` adds every element of
another set. `union`, `intersection`, `difference` and `symmetric_difference` return a
new set, and `issubset`, `issuperset` and `isdisjoint` answer a `bool`; each takes
another set of the same type. A set is not indexable and has none of the dictionary
methods. `len(s)`, `x in s`, `x not in s`, `for x in s`, `enumerate(s)`, `list(s)`,
`sorted(s)`, `sum`, `min`, `max`, `any` and `all` all see the elements in insertion
order. Changing the set's size while a loop walks it traps with
`R_LIST_ITERATION_MUTATION`, as it does for a list or a dictionary.

```mylang
# doc: expect 42
def tag(names: mut set[str], name: str) -> None:
    names.add(name)

def main() -> int:
    names = {"ada", "bob"}
    alias = names
    tag(mut alias, "cy")
    if "cy" in names:
        return 1
    alias.discard("zed")
    alias.remove("bob")
    newest = alias.pop()
    if newest != "cy" or "cy" in alias:
        return 1
    backup = alias.copy()
    alias.update({"dee", "eve"})
    alias.clear()
    total = 0
    for name in backup:
        total += len(name)
    return total * 14
```

## Set operators

`a | b`, `a & b`, `a - b` and `a ^ b` are union, intersection, difference and
symmetric difference. Each evaluates the left operand and then the right one once,
and builds a new set holding the left operand's surviving elements in its order
followed by the right operand's new elements in theirs. `a <= b` and `a < b` test for
a subset and a proper subset, `a >= b` and `a > b` for a superset, and `a == b`
compares contents without regard to insertion order. The operators take two sets of
the same element type. On integers `|`, `&` and `^` are rejected with
`E_SET_OPERATOR` naming the bitwise builtin, `bit_or(a, b)`, `bit_and(a, b)` or
`bit_xor(a, b)`, and a set has no augmented form such as `|=`: rebind the name with
`s = s | t` or call `s.update(t)`.

```mylang
# doc: expect {1, 2, 3, 4, 6, 5} {2, 4} {1, 3} {1, 3, 6, 5}
# doc: expect True False True True
def main(out: Stream) -> int:
    left = {1, 2, 3, 4}
    right = {6, 4, 2, 5}
    out.print(left | right, left & right, left - right, left ^ right)
    out.print({2, 3} < left, left <= right, left.isdisjoint({9}), {3, 1, 2} == {1, 2, 3})
    return 0
```

## Hashable keys

A dictionary key and a set element are hashed and compared by value, so they must be
values whose contents cannot change once stored and whose equality is reflexive:
every integer kind, `bool`, `str`, `bytes`, and the value types built only from
those — tuples, records, unions, enums, domains, `Option` values and fixed arrays. A
key is copied into the table, so reassigning a field of the variable it came from
never changes what the table holds. Hashing is structural and deterministic: it reads
exactly what `==` compares, field by field and case by case, with fixed constants and
no per-process seed, so a dictionary or set behaves the same on every run.

```mylang
# doc: expect 42
record Cell:
    row: int
    col: int

union Shape:
    dot,
    circle: int,
    label: str

def main() -> int:
    walls: set[Cell] = {Cell(row=0, col=1), Cell(row=2, col=3)}
    names: dict[tuple[int, str], int] = {(1, "a"): 40}
    shapes = {Shape.circle(2), Shape.label("x"), Shape.dot}
    start = Cell(row=0, col=1)
    marked: set[Cell] = {start}
    start.col = 9
    if Cell(row=0, col=1) not in walls or Cell(row=0, col=1) not in marked:
        return 1
    if Shape.label("x") not in shapes or Shape.circle(3) in shapes:
        return 2
    return names[(1, "a")] + len(marked) + len(walls) - 1
```

A key type that cannot be hashed is rejected where the dictionary or set is built,
with `E_DICT_KEY` or `E_SET_ELEMENT` naming the offending part: `float`, because NaN
is not equal to itself; a `list`, `dict`, `set`, `byte_buffer` or `class` value,
because it is a shared reference whose contents can change after it is stored; a
function value, which has no equality; and a capability, file or resource. A record
with a `float` field nested in it is refused with the path to that field, such as
`Reading.at.x`. Inside a generic function a type parameter used as
a key or element must promise `integer`, while `str` and concrete hashable types are
accepted as they are.

## Representation and cost

A set is a dictionary from its elements to unit: the same insertion-ordered entry
list and open-addressing hash index, the same tracing, the same arena escape copy and
the same store barrier. Membership, `add`, `remove` and `discard` probe the index
once. Removing an element from the middle takes its slot out of the index and leaves
its entry to be squeezed out the next time the entries are read in order, so a
removal moves nothing; `dict.pop(key)` shares that path. The combining operators
and the subset tests walk one operand and probe the other, so they are linear in the
operands' sizes.
