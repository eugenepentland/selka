# Binary64 through std_math

Import `std_math` and use its nominal `F64` type. This compatibility API provides floating arithmetic through named functions. New code can use builtin `float`, decimal literals, and ordinary operators as described in the [Python-style guide](python-syntax.md). `F64` retains its explicit bit-codec contract and is distinct from ordinary `float`.

```mylang
module main;
import std_math as m;
fn main() -> i64 {
    let root = m::sqrt(m::from_i64(1764));
    match m::to_i64(root) {
        m::Signed.ok(value) => { return value; },
        m::Signed.err(code) => { return code; }
    }
}
```

`from_u64` and `from_i64` convert integers to binary64 using round-to-nearest, ties-to-even. `from_bits` and `bits` preserve every representation bit, including signed zero and NaN payloads. Rational values can be constructed with `div(from_i64(numerator), from_i64(denominator))`.

`add`, `sub`, `mul` and `div` perform separate IEEE binary64 operations; no fused contraction or reassociation is allowed. Overflow produces signed infinity, division by zero produces infinity or NaN as IEEE specifies, and underflow preserves subnormals. Arithmetic NaNs become the canonical quiet NaN `0x7ff8000000000000`. `sqrt` computes the binary64 square root; negative finite input produces canonical NaN. `floor`, `ceil` and `trunc` return integral-valued F64 values, retaining signed zero. `abs` and `neg` canonicalize NaNs too. Transcendental functions are not included in this stage.

Use `eq`, `lt` and `le` for numeric comparisons. Positive and negative zero compare equal; all comparisons with NaN return false. `is_nan` and `is_finite` classify values. Ordinary domain `==` compares representation bits: it distinguishes signed zero and can equate identical NaN payloads. Generic equality therefore also uses representation equality.

`to_u64` and `to_i64` first truncate toward zero, then validate the destination range. They return `Unsigned` or `Signed` results with error code 1 for a nonfinite or out-of-range truncated value. For example, negative fractional values strictly between -1 and 0 convert to unsigned zero. Raw `f64_to_u64` traps with `R_FLOAT_CONVERSION`; module constants report located constant-arithmetic diagnostics instead.

The declared domain codec transports the exact unsigned 64-bit representation. Typed JSON uses the existing canonical decimal **string**, not a JSON floating number. A noncanonical NaN payload can round-trip unchanged; subsequent floating arithmetic canonicalizes it. Private storage is accessed through the domain's factories and accessors. All standard math functions are noalloc.

Low-level `f64_*` intrinsics accept `u64` bit patterns and are available to implement these wrappers; `f64_from_u64` consumes a numeric integer and `f64_to_u64` returns one. They work in scalar constants and in ordinary/generic function bodies with concrete u64 arguments. They do not add a new primitive type or alter nominal type numbering.

VM floating arithmetic uses strict host binary64 operations. Supported execution requires round-to-nearest and gradual underflow; embedders must preserve that environment. Native emission includes math support only when required, rejects fast-math and nonbinary64 C implementations, and traps with `R_FLOAT_ENVIRONMENT` if the embedding process changes rounding or flushes subnormals. The native build helper links libm; manual C builds need `-lm`.

Validation: focused Zig tests cover ties, subnormals, infinities, canonical NaNs, signed zeros, checked conversions, constants, library allocation failures and exact codec round-trips. `tests/native_float_operations.py` compares edge-case results and located conversion traps between the VM and native C at O0/O2 with undefined-behavior sanitization. These tests establish parity on the tested host, not certification of every native target.
