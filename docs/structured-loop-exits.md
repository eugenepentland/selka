# Structured loop exits

`break` leaves the nearest enclosing `while` loop. `continue` starts that
loop's next condition check. Both work in ordinary and generic functions,
including inside `if`, `match` and `with` blocks.

```my
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

Each exit releases the owned values it leaves before jumping. Results created
inside the iteration must still be handled, transferred, returned, or explicitly
acknowledged before either exit. Exit statements reject outside loops; statements
following an unconditional exit in the same block are unreachable errors.

Outer ownership is deliberately conservative: both exits require the same
ownership and partial-move state for bindings that existed before the iteration.
Consuming an outer owner just before a `break` is currently rejected, even when a
more precise loop analysis could establish that the owner will not be used again.
Loop return analysis still permits the condition to be initially false; a return
after the loop remains necessary when the function could fall through.

Lowering uses the existing checked jumps and local drops, so every
exit path shares the same cleanup sequence.
The formatter, source maps, generic checker and duplicate analysis preserve the
new statements.
