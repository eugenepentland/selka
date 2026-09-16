# Noncapturing function values

A function name can be copied into a local, record or array, passed to another
function, returned, and invoked through a local name:

```mylang
def increment(x: i64) -> i64 effects():
    return x + 1


def twice(f: def(i64) -> i64 effects(), x: i64) -> i64:
    return f(f(x))


def main() -> i64:
    f = increment
    return twice(f, 5)
```

Callable types declare value parameter types, value results and an explicit
effect ceiling. The named target must be a nongeneric free function with a
declared ceiling. Types and ceilings match exactly at value boundaries; a
wrapper can supply a different declared ceiling. The compiler checks the target's
body against its ceiling, and indirect calls add that ceiling to their caller's
effects. Callback values retain no authority or local state and allocate no guest
storage. Function identities are opaque, have no numeric conversion or equality,
and cannot cross portable data/host-value serialization boundaries.

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

Context now travels as an ordinary managed value: pass the `list`, `dict`, `str`
or record the callback needs as a parameter. Function values remain safe to store
or return because they capture nothing. Effect ceilings include indirect calls and
enforce `noalloc` in generic bodies. At most 16 total parameters and existing
instruction/frame budgets apply.
