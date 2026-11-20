# Structured loop exits

`break` leaves the nearest enclosing `while` loop; `continue` starts its next condition check. Both work in ordinary and
generic functions, inside `if`, `match` and `with` blocks too.

```selka
func sum() -> i64:
    mut total = 0
    mut i = 0
    while i < 10:
        i += 1
        if i == 2:
            continue
        total += i
        if total > 20:
            break
    return total
```

- Each exit releases the owned values it leaves before jumping. Results created inside the iteration must still be
  handled, transferred, returned or explicitly acknowledged before either exit.
- An exit outside a loop is an error, as is a statement after an unconditional exit.
- Outer ownership is conservative: both exits require the same ownership and partial-move state for bindings that
  existed before the iteration. Consuming an outer owner just before a `break` is rejected.
- The condition may be false at the start: a function that can fall through still needs a return after the loop.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/structured-loop-exits.md).
