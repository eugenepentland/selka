# Noncapturing function values

The reference for function values is [functions](../functions.md#function-values) and
[callback authority](../functions.md#callback-authority); this page keeps the design
notes. A function name can be copied into a local, record or array, passed to another
function, returned, and invoked through a local name:

```mylang
func increment(x: int) -> int:
    return x + 1


func twice(f: func(int) -> int, x: int) -> int:
    return f(f(x))


func main() -> int:
    const f = increment
    return twice(f, 5)
```

Callable types declare value parameter types and value results, and nothing else:
there is no effect clause (`effects()` is rejected with `E_EFFECTS_REMOVED`).
Authority arrives through capability parameters, so a callback that prints takes a
`Stream` parameter. The named target must be a nongeneric free function
(`E_CALLBACK_TYPE` otherwise), and types match exactly at value boundaries
(`E_TYPE` otherwise). Callback values retain no authority or local state and
allocate no guest storage. Function identities are opaque, have no numeric
conversion and no `==` (compare with `same_function`), and cannot cross portable
data/host-value serialization boundaries.

Arguments and results retain ordinary handling rules: a returned result still
needs matching, propagation, or onward transfer. Generated native code checks
each dynamic target against the signature. Ordinary frame/instruction limits
and trap/OOM unwinding apply to callback recursion and aggregate results.

Callable values may also pass through type-only generic records or generic helpers
with concrete callback signatures.

This stage supports at most 16 total parameters and 4096 inferred signatures.
Captures, mutable callback parameters, generic function values, and arbitrary
expression-call syntax remain unsupported. Bind a callback field or returned
callback to a local before calling it.

Context travels as an ordinary managed value: pass the `list`, `dict`, `str` or
record the callback needs as a parameter. Function values remain safe to store or
return because they capture nothing. At most 16 total parameters and existing
instruction/frame budgets apply.
