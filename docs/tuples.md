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

```mylang
# doc: expect 11
def split_first(text: str, sep: str) -> tuple[str, str]:
    at = text.find(sep)
    if at < 0:
        return text, ""
    return text[0:at], text[at + 1:len(text)]

def main() -> int:
    head, rest = split_first("key=value", "=")
    total = len(head) + len(rest)
    pairs: list[tuple[int, str]] = [(1, "a"), (2, "b")]
    for number, letter in pairs:
        total = total + number
    return total
```

This returns `11`: `head` is `"key"` and `rest` is `"value"`, then the loop adds `1` and
`2`. The value is evaluated once and bound before any name is written, so the swap
idiom works with no helper:

```mylang
# doc: expect 21
def main() -> int:
    a = 1
    b = 2
    a, b = b, a
    return a * 10 + b
```

This returns `21`. A name you do not need is written `_`, which binds nothing and reads
nothing: `head, _ = split_first("key=value", "=")` binds only `head`.

### Element and field targets

A target can also be an element or a field — `xs[i]`, `table[key]`, `point.x`,
`grid[r][c]` — so two elements swap the way two names do. The whole value is still
evaluated first; then each target, in order, evaluates its own receiver and index and
takes its value exactly as `target = value` would.

```mylang
# doc: expect 3142
record Point:
    x: int
    y: int

def main() -> int:
    values: [4]int = [1, 2, 3, 4]
    values[0], values[2] = values[2], values[0]
    items = [4, 1]
    items[0], items[-1] = items[-1], items[0]
    point = Point(x=0, y=0)
    point.x, point.y = items[0], items[1]
    return values[0] * 1000 + point.x * 100 + point.y * 10 + values[-3]
```

This returns `3142`: the array swap puts `3` first, the list swap turns `[4, 1]` into
`[1, 4]`, the two fields take those values, and `values[-3]` is the untouched `2`.

A tuple holding a managed value is itself managed-bearing, so a `list` inside a tuple
confines the tuple to an arena block exactly as the list alone would, and `escape`
copies the whole tuple out:

```mylang
# doc: expect 117
def pair_with(value: int) -> tuple[int, list[int]]:
    seen: list[int] = []
    seen.append(value)
    return 1, seen

def main() -> int:
    kept: tuple[int, list[int]] = (0, [])
    with arena() as scratch:
        kept = scratch.escape(pair_with(7))
    number, values = kept
    return number * 100 + len(values) * 10 + values[0]
```

This returns `117`: `kept` holds the escaped tuple, its list still has one element, and
that element is `7`.

Two things a tuple deliberately is not. It is not a dictionary key — keys are still
`int` and `str` only — and it is not ordinary data at the host or JSON boundary, where a
signature or codec naming a tuple is rejected like any other managed graph. `DictItem`,
`zip` and `enumerate` are unchanged: `for key, value in mapping.items()` still
destructures the `DictItem` record, and `for a, b in zip(xs, ys)` still walks the two
sources directly rather than building tuples.

For the syntax these examples use, see the
[Python-style application guide](python-syntax.md); for the records a larger group
should become, see [records, unions and enums](records-and-unions.md).
