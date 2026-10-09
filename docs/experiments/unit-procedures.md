# Unit procedures

Use `-> Unit`, or omit the return annotation, for a function whose purpose is its
effects. Call it as a normal statement. A bare `return` exits early; reaching the
end returns unit naturally. The canonical guide is [Functions and calls](../functions.md#unit-procedures).

```mylang
# doc: expect 42
func add(mut values: int[], value: int):
    values.append(value)


func main() -> int:
    mut values: int[] = []
    add(mut values, 42)
    return values[0]
```

The unit type has one zero-payload value. It is not an integer, Boolean, or
capability. It can flow through ordinary generic
functions, callbacks, locals, and aggregate/result payloads. The unit literal is `()`, and bare `return` or a unit-returning call also
produces it. Type aliases can name it with `Unit`; `None` denotes absence in an
optional value.

Only unit expressions may stand alone. Integers and other ordinary values are
discarded explicitly with `_ = expression` when unused. Fallible results always
require handling, even when their success payload is unit. `try operation()` is
allowed when the successful value is unit and the enclosing function can propagate
that result. Unit return/fallthrough uses ordinary ownership and effect rules.
`main` returns `int`, `Unit`, `int fails E`, or unit with `fails E`.

The native runtime implements unit calls and returns as a zero-payload value. No
dummy integer appears in the language API. The example
[`examples/unit.my`](../../examples/unit.my) exercises unit-returning
list mutation, recursion and a unit-returning callback.

Public language schemas report `kind: unit`. Current copied data, JSON, manifest,
and C interop ABIs do not encode unit or graphs containing it;
they reject those signatures explicitly. Public module-to-module unit calls work.
Use a nominal no-payload record when a success value must cross one of these wire
boundaries.
