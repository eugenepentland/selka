# Tuple removal

Tuples are removed. `tuple[A, B]`, `(a, b)`, multiple return values, destructuring bindings and tuple swaps report
`E_TUPLE_REMOVED`. Use a nominal record with explicit fields:

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

- `selka fix` repairs certain swaps, annotated tuple-returning functions with their call sites, and tuple sort keys,
  staging values before writes to keep evaluation order. Other tuples need a manual record.
- Records with orderable fields work as `sorted` and `.sort` keys, compared in declaration order and recursively; reverse
  order preserves ties. Records with hashable fields work as dictionary keys and set elements.
- Two-name `for` loops over `enumerate`, `zip` and `.items()` still work.
