# Tuples

A tuple is an immutable, fixed-arity group of two to eight values. It is written
`(a, b)`, and `return a, b` and `x, y = a, b` accept the bare form. A tuple has no
fields, no indexing, no methods and no `len`: the only way to reach its values is to
destructure it, which is what keeps a group of two or three values from becoming an
undeclared record.

The type spelling is `tuple[T1, ..., Tn]`. It is structural, not nominal, so
`tuple[int, str]` is the same type in every module and in every position — a parameter,
a return type, a list element, a dictionary value, a record field, or an `Option` or
`Result` payload. Two tuples are equal when their elements are equal, element by
element, and a tuple prints as `(1, 'a')`.

## Tuples

```selka
# doc: expect 11
func split_first(text: str, sep: str) -> tuple[str, str]:
    mut at = text.find(sep)
    if at < 0:
        return text, ""
    return text[0:at], text[at + 1:len(text)]

func main() -> int:
    const head, rest = split_first("key=value", "=")
    mut total = len(head) + len(rest)
    mut pairs: tuple[int, str][] = [(1, "a"), (2, "b")]
    for number, letter in pairs:
        total = total + number
    return total
```

This returns `11`: `head` is `"key"` and `rest` is `"value"`, then the loop adds `1` and
`2`. The value is evaluated once and bound before any name is written, so the swap
idiom works with no helper:

```selka
# doc: expect 21
func main() -> int:
    mut a = 1
    mut b = 2
    a, b = b, a
    return a * 10 + b
```

This returns `21`. A name you do not need is written `_`, which binds nothing and reads
nothing: `const head, _ = split_first("key=value", "=")` binds only `head`.

### Element and field targets

A target can also be an element or a field — `xs[i]`, `table[key]`, `point.x`,
`grid[r][c]` — so two elements swap the way two names do. The whole value is still
evaluated first; then each target, in order, evaluates its own receiver and index and
takes its value exactly as `target = value` would.

```selka
# doc: expect 3142
record Point:
    x: int
    y: int

func main() -> int:
    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
    values[0], values[2] = values[2], values[0]
    mut items = [4, 1]
    items[0], items[-1] = items[-1], items[0]
    mut point = Point(x=0, y=0)
    point.x, point.y = items[0], items[1]
    return values[0] * 1000 + point.x * 100 + point.y * 10 + values[-3]
```

This returns `3142`: the array swap puts `3` first, the list swap turns `[4, 1]` into
`[1, 4]`, the two fields take those values, and `values[-3]` is the untouched `2`.

A tuple holding a managed value is a value like the list it holds: copying the
tuple and changing the copy's list leaves the original's list unchanged.

```selka
# doc: expect 117
func pair_with(value: int) -> tuple[int, int[]]:
    mut seen: int[] = []
    seen.append(value)
    return 1, seen

func main() -> int:
    mut kept = pair_with(7)
    mut copy = kept
    mut number, values = copy
    values.append(8)
    const _, original = kept
    return number * 100 + len(original) * 10 + original[0]
```

This returns `117`: appending to the list taken from `copy` leaves `kept`'s list with
one element, and that element is `7`.

A tuple of hashable values is a hashable dictionary key and set element
([hashable keys](sets.md#hashable-keys)). `DictItem`,
`zip` and `enumerate` are unchanged: `for key, value in mapping.items()` still
destructures the `DictItem` record, and `for a, b in zip(xs, ys)` still walks the two
sources directly rather than building tuples.

For the syntax these examples use, see the
[Python-style application guide](python-syntax.md); for the records a larger group
should become, see [records, unions and enums](records-and-unions.md).
