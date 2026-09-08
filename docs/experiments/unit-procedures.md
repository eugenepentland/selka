# Unit procedures

Use `-> unit` for a function whose purpose is its effects. Call it as a normal
statement. A bare `return;` exits early; reaching the end returns unit naturally.

```mylang
fn set(value: &mut i64, replacement: i64) -> unit {
    write_ref(value, replacement);
}

fn main() -> i64 {
    let mut value = 0;
    borrow mut value as edit {
        set(edit, 42);
    }
    return value;
}
```

The distinct builtin `unit` has one zero-payload value. It is not an integer,
Boolean, capability, or borrowed reference. It can flow through ordinary generic
functions, callbacks, locals, and aggregate/result payloads. There is no unit
literal: `return;` or a unit-returning call produces it. Type aliases can name it.
The identifier `unit` stays available for existing functions such as
`std_unit::unit()`; type positions resolve the builtin. Existing `std_unit::Unit`
is a separate nominal value and remains compatible with existing code.

Only unit expressions may stand alone. Integers and other ordinary values still
require explicit `discard` when unused. Fallible results always require handling,
even when their success payload is unit. `try operation();` is allowed when the
successful value is unit and the enclosing function can propagate that result.
Unit return/fallthrough uses ordinary ownership, borrow, region, and effect rules.
Borrowed-reference functions still require an explicit reference return, including
references whose referent type is unit. `main` still returns `i64`.

Both the bytecode VM and C backend implement unit calls and returns. The VM has a
zero-payload `Value.unit` and `PUSH_UNIT` instruction; C uses an inert zero-payload
token in its existing untyped operand storage, with checked types distinguishing
it from integers. No dummy integer appears in the language API. The example
[`examples/unit.my`](../../examples/unit.my) exercises callbacks, recursion, and
borrowed mutation, and participates in native/VM budget-cutoff parity tests.

Public language schemas report `kind: unit`. Current copied data, JSON, manifest,
and host/native invocation ABIs do not encode unit or graphs containing it;
they reject those signatures explicitly. Public module-to-module unit calls work.
Use the existing nominal `std_unit::Unit` when a no-payload success value must
cross one of these existing wire boundaries.

Guardian's type-size ratchet pins only `runtime_values.Value` at eight variants;
all other types retain the seven-field cap, and adding a ninth Value variant is
a new review decision. This avoids nesting scalar tags solely to satisfy a
structural metric on the VM's hot path.
