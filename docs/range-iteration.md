# Integer range iteration

`for index in range(start, end):` visits a half-open ascending integer range:

```selka
func main() -> i64:
    mut total = 0
    for i in range(0, 10):
        if i == 2:
            continue
        total += i
        if total > 20:
            break
    return total
```

- The bounds evaluate once, left to right, before the loop, and have the same integer type (generic bounds require
  `integer`). Empty and reversed ranges run zero times. The upper endpoint is excluded, so the last increment never
  overflows.
- The iteration binding exists only inside the body and is read-only. To change a value locally, copy it into a `mut`
  binding; the iteration count is unchanged.

```selka
# doc: expect 5
func main() -> i64:
    mut runs = 0
    for i in range(5):
        mut local = i
        local = 10
        runs += local // 10
    return runs
```

- Every `for` form has read-only bindings: an `enumerate` position, an element, `reversed`, `zip` and a destructured
  pair. `continue` and `break` clean up the exited scopes; nested loops get their own nearest one.
- A range loop follows the ownership rules and result obligations of a `while` loop. The first iteration may never occur,
  so a range loop alone does not prove a function returns.

## Stepped ranges

`range(start, stop, step)` counts from `start` by `step`, as Python's `range` does: upward while below `stop` for a
positive step, downward while above it for a negative one, so `range(10, 0, -3)` visits 10, 7, 4 and 1. All three bounds
share one integer type and evaluate once, left to right. The step that would overflow ends the loop instead of trapping.

A literal zero step is `E_RANGE_STEP`; a zero step computed at run time traps `R_ASSERT` with
`range() arg 3 must not be zero` before the first iteration. `list(range(...))` accepts the same three arguments.

```selka
# doc: expect 42
func main() -> int:
    mut total = 0
    for i in range(0, 10, 2):
        total += i
    mut down: int[] = []
    for j in range(9, -1, -4):
        append(mut down, j)
    if down != [9, 5, 1]:
        return 0
    mut squares: int[] = []
    for k in range(1, 10, 4):
        append(mut squares, k * k)
    if squares != [1, 25, 81]:
        return 0
    if list(range(7, 0, -3)) != [7, 4, 1]:
        return 1
    return total + 22
```
