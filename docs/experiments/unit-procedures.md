# Unit procedures

Use `-> unit` for a function whose purpose is its effects. Call it as a normal
statement. A bare `return;` exits early; reaching the end returns unit naturally.

```mylang
// doc: expect 42
fn add(values: List<i64>, value: i64) -> unit {
    values.push(value)
}

fn main() -> i64 {
    let values: List<i64> = []
    add(values, 42)
    return values[0]
}
```

The distinct builtin `unit` has one zero-payload value. It is not an integer,
Boolean, or capability. It can flow through ordinary generic
functions, callbacks, locals, and aggregate/result payloads. There is no unit
literal: `return;` or a unit-returning call produces it. Type aliases can name it.
The identifier `unit` stays available for existing functions such as
`std_unit::unit()`; type positions resolve the builtin. Existing `std_unit::Unit`
is a separate nominal value and remains compatible with existing code.

Only unit expressions may stand alone. Integers and other ordinary values are
discarded explicitly with `_ = expression` when unused. Fallible results always
require handling, even when their success payload is unit. `operation()?;` is
allowed when the successful value is unit and the enclosing function can propagate
that result. Unit return/fallthrough uses ordinary ownership and effect rules.
`main` still returns `i64`.

The bytecode VM implements unit calls and returns through a zero-payload
`Value.unit` and `PUSH_UNIT` instruction. No dummy integer appears in the language
API. The example [`examples/unit.my`](../../examples/unit.my) exercises unit-returning
list mutation, recursion and a unit-returning callback.

Public language schemas report `kind: unit`. Current copied data, JSON, manifest,
and host invocation ABIs do not encode unit or graphs containing it;
they reject those signatures explicitly. Public module-to-module unit calls work.
Use the existing nominal `std_unit::Unit` when a no-payload success value must
cross one of these existing wire boundaries.

Guardian's type-size ratchet pins only `runtime_values.Value` at eight variants;
all other types retain the seven-field cap, and adding a ninth Value variant is
a new review decision. This avoids nesting scalar tags solely to satisfy a
structural metric on the VM's hot path.
