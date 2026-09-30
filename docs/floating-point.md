# Binary64 floating point

`float` is the language's binary64 type. It is an ordinary numeric type with
decimal literals, the usual operators and comparisons, and `float(integer)` /
`int(float)` conversion. The [standard `math` module](standard-library.md#math)
supplies classification, rounding, roots and the native `sin`/`cos` operations
for angles in radians.

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

Float literals are Python's: `1.5`, a leading dot `.5`, a trailing dot `5.`,
exponents `1e10` and `2.5E-3`, and single underscores between digits in the mantissa
and the exponent (`1_000.5`, `1e1_0`); leading zeros are allowed (`007.5`). `.5` is a
float wherever an operand does not end directly before the dot, so `x.5` and `f().5`
stay member access, and `5.name` keeps the `5` apart from `.name`. A float takes no
integer suffix, a hexadecimal, octal or binary spelling is always an integer, and an
imaginary literal such as `1.5j` is rejected because there are no complex numbers.
A malformed spelling (`1_.5`, `1e`, `1.5_`) is an `E_FLOAT_LITERAL` error at the
literal.

```mylang
# doc: expect 42
def main() -> int:
    if .5 + .25 != 0.75 or 5. != 5.0:
        return 1
    if 1_000.5 != 1000.5 or 1e1_0 != 10000000000.0 or 1.e2 != 100.0:
        return 2
    return int(84.0 * .5)
```

## Semantics

`+`, `-`, `*` and `/` are separate IEEE binary64 operations; no fused contraction
or reassociation is allowed. Overflow produces a signed infinity, division by zero
produces an infinity or a NaN exactly as IEEE specifies, and underflow preserves
subnormals. A NaN you can observe is the canonical quiet NaN `0x7ff8000000000000`;
see [NaN payloads](#nan-payloads).

`==`, `!=`, `<`, `<=`, `>` and `>=` are numeric comparisons. Positive and negative
zero compare equal, and every comparison with a NaN is false, so `value != value`
is the test for NaN and is what `math.is_nan` performs. `//` rounds the quotient
down and `%` follows that quotient.

`float(value)` rounds an integer to nearest, ties to even.

## Integer conversions

`i8(value)`, `i16(value)`, `i32(value)`, `i64(value)` and the unsigned
`u8`/`u16`/`u32`/`u64` casts accept a float. They truncate toward zero, then
check that the truncated value fits the target. Thus `i8(-128.5)` is -128 and
`u8(-0.5)` is 0; `i8(-129.0)` and `u8(-1.0)` trap. NaN, either infinity and
an out-of-range truncated result trap with `R_FLOAT_CONVERSION` at the cast.
The range check happens before the native integer conversion. `int(value)`
is the same conversion as `i64(value)`, with signed 64-bit bounds.

```mylang
# doc: expect 42
def main() -> int:
    if i8(-128.5) != -128i8 or u8(-0.5) != 0u8:
        return 1
    return int(u64(42.75))
```

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

## NaN payloads

A NaN's payload and sign are never observable. Arithmetic, the prelude helpers and
a foreign function's result propagate NaNs the way IEEE and the hardware do, so
`0.0 / 0.0`, its negation and `sqrt(-1.0)` may carry different bits while the
program runs, exactly as they do in C, Zig or Rust. Nothing a program can do tells
them apart: every comparison with any NaN is false, and every place a float's bits
leave the value sees the canonical quiet NaN `0x7ff8000000000000`:

- text: `str`, `print`, f-strings and `byte_buffer.append_float` spell every NaN
  `nan`, never `-nan`;
- a float argument passed to an `extern def` crosses as the canonical pattern, so
  `copysign(1.0, -(0.0 / 0.0))` in C answers `1.0`, and a float copied to a
  `host def` callback, at any depth inside a record, array or variant, carries
  the canonical pattern in its node's bits;
- equality of lists, records, fixed arrays and options compares floats
  numerically, and sorting orders every NaN after the ordered values whatever its
  sign.

No guest spelling reads a float's representation: `float` is a private builtin
domain and the raw `f64_*` spellings are removed. Dictionary keys are integers or
`str`, and the wire, codec, typed-JSON and `invoke` boundaries reject `float`, so
no hash or encoding sees a float's bits either. Canonicalizing at these points
instead of after every operation keeps float loops free of a compare, branch and
call per operation, and results stay identical across machines, because a NaN is
canonical before anything could see that two processors produced different
payloads.

```mylang
# doc: expect nan nan True False
def main(out: Stream) -> int:
    zero = 0.0
    nan = zero / zero
    flipped = -nan
    out.print(str(nan), f"{flipped}", flipped != flipped, [nan] == [flipped])
    return 0
```

## Rounding, roots and powers

`math.trunc`, `math.floor`, `math.ceil` and `math.round` return integral-valued
floats and pass infinities and NaNs through unchanged; `math.round` rounds halves
away from zero. `math.fabs` maps both zeros to positive zero. `math.pow` takes an
integer exponent and squares repeatedly.

`math.sqrt` calls the compiler-internal binary64 square root on its ordinary
`float` argument, so it is the correctly rounded square root and is exact for
values whose root is exactly representable. There are no transcendental functions
yet.

Prelude `sqrt`, `floor`, `ceil`, `trunc` and `abs` take one `float` and answer a
`float`, running the host binary64 operation directly, so ordinary guest code never
handles a `u64` bit pattern. A local binding or a declared function of the same name
shadows each of them, which is how `math.sqrt` keeps its own definition. `round`,
`exp`, `log`, `pow` and the trigonometric functions have no prelude spelling.

## Intrinsics and the execution environment

The raw `f64_add`, `f64_sqrt`, `f64_from_u64`, `f64_to_u64` and related
spellings that took and returned `u64` bit patterns are removed and rejected with
`E_REMOVED_SPELLING`, so no program handles a float's bit pattern. A conversion in
a module constant reports a located constant-arithmetic diagnostic where the
running program would trap with `R_FLOAT_CONVERSION`.

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
