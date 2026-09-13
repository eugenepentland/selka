# Value-producing matches

Use a match expression when every case produces a value:

```my
result Read { ok: i64, err: i64 }
fn value(input: Read) -> i64 {
    return match input {
        Read.ok(number) => number,
        Read.err(code) => -code
    };
}
```

Expression arms contain expressions rather than statement blocks. A match
expression can appear in bindings, return values, call arguments, arithmetic,
and nested matches. The scrutinee evaluates once, exactly one arm evaluates,
and every arm must have the same result type. All variants need an explicit
arm; duplicate cases reject.

Payload patterns use the existing `Variant.name(binding)` form, or ignore the
payload. An owned payload can move into the result or be cleaned up after the
chosen arm. A result-bearing payload must be handled or transferred; ignoring it
does not erase its obligation. Outer ownership states must agree across all arms.

`?` propagation inside an arm retains the enclosing expression's pending obligations.
For example, an earlier fallible argument cannot be abandoned by a later
match arm propagating an error. Arena dependencies follow the produced value,
so returning a scratch-backed owned value through a match still rejects.

Ordinary and generic functions share these rules. Lowering uses exhaustive
variant dispatch and an internal result local, then yields that local. The VM
and the QBE native backend share the same lowering, including owned payload
cleanup.
