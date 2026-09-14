# Binary64 floating point

`float` is the language's binary64 type. It is an ordinary numeric type with
decimal literals, the usual operators and comparisons, and `float(integer)` /
`int(float)` conversion. The [standard `math` module](standard-library.md#math)
supplies the classification, rounding and root operations that are not operators.

```mylang
# doc: expect 42
def main() -> int:
    if 0.1 + 0.2 == 0.3:
        return 1
    nan = 0.0 / 0.0
    if nan == nan or not (nan != nan):
        return 2
    if 1.0 / 0.0 <= 1.7976931348623157e308:
        return 3
    if 0.0 - 0.0 != 0.0:
        return 4
    return int(21.0 * 2.0)
```

## Semantics

`+`, `-`, `*` and `/` are separate IEEE binary64 operations; no fused contraction
or reassociation is allowed. Overflow produces a signed infinity, division by zero
produces an infinity or a NaN exactly as IEEE specifies, and underflow preserves
subnormals. Arithmetic NaNs become the canonical quiet NaN `0x7ff8000000000000`.

`==`, `!=`, `<`, `<=`, `>` and `>=` are numeric comparisons. Positive and negative
zero compare equal, and every comparison with a NaN is false, so `value != value`
is the test for NaN and is what `math.is_nan` performs. `//` rounds the quotient
down and `%` follows that quotient.

`int(value)` truncates toward zero and traps with `R_FLOAT_CONVERSION` outside the
signed 64-bit range, so range-check a computed magnitude before converting.
`float(value)` rounds an integer to nearest, ties to even.

```mylang
# doc: expect 42
module main
import math

def main() -> int:
    root = math.sqrt(1764.0)
    if math.is_nan(root) or not math.is_finite(root):
        return 1
    if math.floor(root + 0.5) != root or math.trunc(0.0 - 1.9) != 0.0 - 1.0:
        return 2
    negative = 0.0 - 5.0
    if negative // 2.0 != 0.0 - 3.0 or negative % 2.0 != 1.0:
        return 3
    return int(math.round(41.5))
```

## Rounding, roots and powers

`math.trunc`, `math.floor`, `math.ceil` and `math.round` return integral-valued
floats and pass infinities and NaNs through unchanged; `math.round` rounds halves
away from zero. `math.fabs` maps both zeros to positive zero. `math.pow` takes an
integer exponent and squares repeatedly.

`math.sqrt` calls the binary64 `f64_sqrt` intrinsic on its ordinary `float`
argument, so it is the correctly rounded square root and is exact for values whose
root is exactly representable. The `f64_*` intrinsics accept a `float` directly for
`sqrt`, `floor`, `ceil`, `trunc`, `abs` and `neg`; the `u64` spellings still own raw
bit patterns. There are no transcendental functions yet.

Prelude `sqrt`, `floor`, `ceil`, `trunc` and `abs` take one `float` and answer a
`float`, running the host binary64 operation directly, so ordinary guest code never
handles a `u64` bit pattern. A local binding or a declared function of the same name
shadows each of them, which is how `math.sqrt` keeps its own definition. `round`,
`exp`, `log`, `pow` and the trigonometric functions have no prelude spelling.

## Intrinsics and the execution environment

The low-level `f64_add`, `f64_sqrt`, `f64_from_u64`, `f64_to_u64` and related
intrinsics accept and return `u64` bit patterns. They remain available for code
that owns a representation directly, work in scalar constants and in ordinary and
generic function bodies with concrete `u64` arguments, and add no new primitive
type. Raw `f64_to_u64` traps with `R_FLOAT_CONVERSION` on a nonfinite or
out-of-range value; module constants report located constant-arithmetic
diagnostics instead.

Virtual-machine floating arithmetic uses strict host binary64 operations.
Supported execution requires round-to-nearest and gradual underflow; embedders
must preserve that environment. Native emission includes math support only when
required, rejects fast-math and nonbinary64 C implementations, and traps with
`R_FLOAT_ENVIRONMENT` if the embedding process changes rounding or flushes
subnormals. The native build helper links libm; manual C builds need `-lm`.

Validation: focused Zig tests cover ties, subnormals, infinities, canonical NaNs,
signed zeros, checked conversions, constants and library allocation failures.
These tests establish behavior on the tested host, not certification of every
native target.

## Prelude float helpers

`sqrt`, `floor`, `ceil`, `trunc` and `abs` are the float operations reachable
without an import, alongside the `float(value)` and `int(value)` conversions.
Each takes one `float` and answers a `float`; a non-float argument is an `E_TYPE`
error. Nonfinite inputs pass through the same rules the operators use, so the
square root of a NaN is a NaN and compares equal to nothing. `round`, `pow`, the
classification predicates and the rounding modes not listed here live in the
[standard `math` module](standard-library.md#math).

```mylang
# doc: expect 42
def main() -> int:
    if sqrt(2.25) != 1.5:
        return 1
    if floor(-1.5) != -2.0 or ceil(-1.5) != -1.0:
        return 2
    if trunc(-1.9) != -1.0 or abs(-2.5) != 2.5:
        return 3
    if sqrt(0.0 / 0.0) == sqrt(0.0 / 0.0):
        return 4
    return int(abs(float(-42)))
```
