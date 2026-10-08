# Integer range iteration

`for index in range(start, end):` visits a half-open ascending integer range:

```my
def main() -> i64:
    total = 0
    for i in range(0, 10):
        if i == 2:
            continue
        total += i
        if total > 20:
            break
    return total
```

The bounds evaluate once, left to right, before the loop begins. They must have
the same integer type; generic bounds require `integer`. Empty and reversed
ranges perform no iterations. The upper endpoint is excluded, so incrementing
the final iteration never needs to exceed the upper endpoint's representable
value.

The iteration binding exists only inside the loop body. As in Python, the loop
rebinds it from its own hidden count at the top of every iteration, so the body
may assign it without changing which iteration comes next or how many run:

```mylang
# doc: expect 5
def main() -> i64:
    runs = 0
    for i in range(5):
        i = 10
        runs += i // 10
    return runs
```

The same holds for every `for` form — an `enumerate` position, a collection or
fixed-array element, `reversed`, `zip` and a destructured pair. A loop whose body
never assigns its variable counts on that variable directly, so the rule costs
nothing there. Each `continue` cleans up the exited scopes and increments the
index before testing the bound again. `break` cleans up those scopes and skips
the increment. Nested loops always receive their own nearest `break` or
`continue`.

Range loops use the same conservative outer-ownership rules and result
obligations as while loops. They support owned values; exited resources are released before incrementing. The first iteration
may never occur, so a range loop alone does not prove a function returns.

This form covers integer ranges. Collection iteration can currently use indices
with explicit reads; iterator protocols are not implied by this syntax.

## Stepped ranges

`range(start, stop, step)` counts from `start` by `step`, exactly as Python's
`range` does: upward while below `stop` for a positive step, downward while above
it for a negative one, so `range(10, 0, -3)` visits 10, 7, 4 and 1. All three
bounds share one integer type and evaluate once, left to right. The counter
never steps past the end of its own type — the step that would overflow ends the
loop instead of trapping, because the value it would produce lies beyond `stop`
anyway. A literal zero step is `E_RANGE_STEP`, and a zero step computed at run
time traps `R_ASSERT` with CPython's message `range() arg 3 must not be zero`
before the first iteration. A comprehension and `list(range(...))` accept the
same three arguments.

```mylang
# doc: expect 42
def main() -> int:
    total = 0
    for i in range(0, 10, 2):
        total += i
    down: list[int] = []
    for j in range(9, -1, -4):
        down.append(j)
    if down != [9, 5, 1] or [k * k for k in range(1, 10, 4)] != [1, 25, 81]:
        return 0
    if list(range(7, 0, -3)) != [7, 4, 1]:
        return 1
    return total + 22
```
