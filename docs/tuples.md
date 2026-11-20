# Tuple removal

Tuples are removed. `tuple[A, B]`, `(a, b)`, multiple return values,
destructuring bindings, and tuple swaps report `E_TUPLE_REMOVED`.

Use a nominal record with explicit fields:

```selka
record Split:
    head: int
    rest: int

func split(n: int) -> Split:
    return Split(head=n, rest=n + 1)

func main() -> int:
    const result = split(4)
    return result.head + result.rest
```

`selka fix` repairs certain swaps, annotated tuple-returning functions and
their destructuring call sites, and tuple sort keys. It stages values before
writes to preserve evaluation order. Other tuple values require a manual record
replacement. Project-wide signature edits wait until all independent entry
points have enough information to migrate their consumers together.

Records with orderable fields work as `sorted` and `.sort` keys. Fields compare
in declaration order, recursively; reverse order preserves ties. Records with
hashable fields work as dictionary keys and set elements, retaining nominal
record identity.

Two-name `for` loops over `enumerate`, `zip` and dictionary `.items()` remain
supported without materializing tuples.

The historical tuple design (`docs/legacy/tuples.md`) describes the removed feature.
