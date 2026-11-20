# Binary64 floating point

`float` is the binary64 type, with decimal literals, the usual operators and `float(integer)` / `int(float)` conversion.
The [standard `math` module](standard-library.md#math) supplies classification, rounding, roots and `sin`/`cos` in radians.

```selka
# doc: expect 42
func main() -> int:
    if 0.1 + 0.2 == 0.3:
        return 1
    mut nan = 0.0 / 0.0
    if nan == nan or not (nan != nan):
        return 2
    if 1.0 / 0.0 <= 1.7976931348623157e308:
        return 3
    if 0.0 - 0.0 != 0.0:
        return 4
    return int(21.0 * 2.0)
```

Float literals are Python's: `1.5`, `.5`, `5.`, `1e10`, `2.5E-3`, underscores between digits (`1_000.5`, `1e1_0`) and
leading zeros (`007.5`); `x.5` stays member access. A float takes no integer suffix, a hexadecimal, octal or binary
spelling is an integer, and `1.5j` is rejected. A malformed spelling (`1_.5`, `1e`, `1.5_`) is `E_FLOAT_LITERAL`.

## Semantics

- `+`, `-`, `*` and `/` are separate IEEE binary64 operations: no fused contraction, no reassociation. Overflow gives a
  signed infinity, division by zero an infinity or a NaN, and underflow keeps subnormals. A NaN you can observe is the
  canonical quiet NaN `0x7ff8000000000000` ([NaN payloads](#nan-payloads)).
- Comparisons are numeric. Positive and negative zero compare equal and every comparison with a NaN is false, so
  `value != value` tests for NaN (as `math.is_nan` does). `//` rounds the quotient down and `%` follows it.
- `float(value)` rounds an integer to nearest, ties to even.

## Integer conversions

`i8(value)`, `i16(value)`, `i32(value)`, `i64(value)` and the unsigned `u8`/`u16`/`u32`/`u64` casts accept a float. They
truncate toward zero, then check that the result fits the target: `i8(-128.5)` is -128 and `u8(-0.5)` is 0; `i8(-129.0)`
and `u8(-1.0)` trap. NaN, either infinity and an out-of-range result trap with `R_FLOAT_CONVERSION` at the cast.
`int(value)` is `i64(value)`.

| To | Use |
| --- | --- |
| convert without the trap | `math.to_int(value)` is `None` where `int(value)` would trap; `math.to_int_saturating(value)` clamps to the signed 64-bit range (NaN gives 0) |
| print with an exponent instead of hundreds of digits | `strings.format_shortest(value)` ([`math`](standard-library.md#math), [`strings`](standard-library.md#strings)) |

```selka
# doc: expect 42
func main() -> int:
    if i8(-128.5) != -128i8 or u8(-0.5) != 0u8:
        return 1
    return int(u64(42.75))
```

## NaN payloads

A NaN's payload and sign are never observable: every comparison with any NaN is false, and every place a float's bits leave
the value sees the canonical quiet NaN `0x7ff8000000000000`:

- text (`str`, `print`, f-strings, `byte_buffer.append_float`) spells every NaN `nan`, never `-nan`;
- a float passed to an `extern func` crosses as the canonical pattern;
- equality of lists, records, fixed arrays and options compares floats numerically, and sorting puts every NaN after the
  ordered values.

A float's bits are read only through `math.bits` and written through `math.from_bits`, which canonicalize NaN. Dictionary
keys are integers or `str`, and the wire, codec and typed-JSON boundaries reject `float`.

```selka
# doc: expect nan nan True False
func main(out: Stream) -> int:
    mut zero = 0.0
    mut nan = zero / zero
    mut flipped = -nan
    print(out, str(nan), f"{flipped}", flipped != flipped, [nan] == [flipped])
    return 0
```

## Rounding, roots and powers

- `math.trunc`, `math.floor`, `math.ceil` and `math.round` return integral-valued floats and pass infinities and NaNs
  through; `math.round` rounds halves away from zero. `math.fabs` maps both zeros to positive zero. `math.pow` takes an
  integer exponent. `math.sqrt` is the correctly rounded square root.
- Prelude `sqrt`, `floor`, `ceil`, `trunc` and `abs` take one `float` and answer a `float`; a local of the same name
  shadows each. A module function with one of these names that its own module calls bare is `E_BUILTIN_FUNCTION_NAME` (the
  repair renames it). `round`, `exp`, `log`, `pow` and the trigonometric functions have no prelude spelling.

## Bit patterns

`math.bits(value)` answers the IEEE binary64 pattern of a `float` as a `u64`, and `math.from_bits(pattern)` builds the
`float` a `u64` names. Every NaN answers the canonical quiet NaN. `math.f32_bits` and `math.f32_from_bits` do the same for
`f32` with a `u32` pattern.

```selka
# doc: expect 42
import math

func main() -> int:
    if math.bits(1.5) != 4609434218613702656u64 or math.from_bits(4609434218613702656u64) != 1.5:
        return 1
    if math.f32_bits(1.5f32) != 1069547520u32 or math.f32_from_bits(1069547520u32) != 1.5f32:
        return 2
    if math.bits(0.0 / 0.0) != 9221120237041090560u64:
        return 3
    return 42
```

## binary32: f32

`f32` is the IEEE binary32 type. A literal carries the suffix `f32` after a decimal point or an exponent: `0.5f32`,
`1e3f32` (`1f32` is an integer spelling and refused). A suffix-less float literal takes `f32` from its context: `x * 0.1`
with `x: f32` is `x * 0.1f32`. Every operation rounds to binary32, and overflow gives an infinity.

```selka
# doc: expect 42
func main() -> int:
    const sum = 0.1f32 + 0.2f32
    if sum != 0.3f32 or float(sum) != 0.30000001192092896:
        return 1
    if 3.0e38f32 * 10.0f32 <= 3.0e38f32:
        return 2
    return int(f32(7.0) * 6)
```

An `f32` and a `float` are different types: an operation that meets both is `E_FLOAT_WIDTH`, repaired by widening with
`float(...)` (exact). An integer operand of an `f32` operation (other than an unsuffixed literal) is the same error,
repaired with `f32(...)`.

- `f32(value)` takes a `float`, an `f32` or an integer and rounds to nearest; `float(value)` widens an `f32`. `int(value)`
  and the integer casts accept an `f32`.
- `f32[]`, `FixedArray[f32, N]` and record fields store four bytes per element.
- `str(0.1f32)` is `0.1` (shortest round-trip binary32 decimal), `str(float(0.1f32))` is `0.10000000149011612`.
  `parse_f32(text)` reads the `parse_float` grammar and rounds straight to binary32.
- Math functions take `float`; the prelude `sqrt`, `floor`, `ceil`, `trunc`, `abs`, `min` and `max` also take `f32`.

```selka
# doc: expect 42
func main() -> int:
    const narrow: f32 = 1.5f32
    const wide: float = 2.0
    const total = float(narrow) + wide
    const back = f32(total) * 2.0f32
    return int(float(back) * 6.0)
```

## Fused multiply-add and hypot

`math.fma(a, b, c)` computes `a * b + c` with one rounding (IEEE fused multiply-add); `math.f32_fma` does the same for
`f32`. `math.hypot(x, y)` is `sqrt(x * x + y * y)` without unnecessary overflow or underflow and answers the bits of Zig's
`std.math.hypot`, so a program ported from Zig gets identical results; `math.f32_hypot` is Zig's binary32 form.

```selka
# doc: expect 42
import math

func main() -> int:
    const eps = 1.0 / 1073741824.0
    const x = 1.0 + eps
    const c = -(1.0 + 2.0 * eps)
    if math.fma(x, x, c) != eps * eps or x * x + c != 0.0:
        return 1
    return 42
```

## Zig-exact log10, exp, atan2 and pow_float

`math.log10`, `math.exp`, `math.atan2` and `math.pow_float` answer the bits of the pinned Zig toolchain's `std.math.log10`,
`exp`, `atan2` and `pow`, and `math.f32_log10`, `math.f32_exp`, `math.f32_atan2` and `math.f32_pow_float` do the same for
`f32`: a program ported from Zig gets identical results, special values included. None calls the C library.
`math.pow(base, exponent)` with an integer exponent is separate.

Special cases are Zig's: `log10(0.0)` is minus infinity, `log10` of a negative value NaN; `exp` of a large argument infinity,
of a very negative one zero; `atan2(-0.0, -1.0)` is minus pi; `pow_float(x, 0.0)` and `pow_float(1.0, y)` are one, a negative
base with a non-integer exponent is NaN, and an infinite or zero base follows Zig's `pow.zig`. A NaN result is canonical.

```selka
# doc: expect 42
import math

func main() -> int:
    if math.log10(1000.0) != 3.0:
        return 1
    # Zig's exp(1.0) is one unit in the last place above the correctly rounded e.
    if math.bits(math.exp(1.0)) != 4613303445314885482u64:
        return 2
    if math.bits(math.atan2(1.0, 1.0)) != 4605249457297304856u64:
        return 3
    if math.pow_float(2.0, 10.0) != 1024.0 or math.f32_pow_float(2.0f32, 10.0f32) != 1024.0f32:
        return 4
    return 42
```

## Zig-exact ln, atan, acos, asin, tan, expm1, sinh, cosh, tanh, cbrt, sin and cos

`math.ln`, `atan`, `acos`, `asin`, `tan`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt`, `sin` and `cos` take and answer a `float`
and answer the bits of the pinned Zig toolchain's `@log`, `std.math.atan`, `acos`, `asin`, `@tan`, `std.math.expm1`,
`sinh`, `cosh`, `tanh`, `cbrt`, `@sin` and `@cos`. None calls the C library. Every finite argument is reduced without a
trap: `math.sin(1.0e300)` answers Zig's bits. There are no `f32_` forms.

Special cases are Zig's: `ln(0.0)` is minus infinity, `ln` of a negative value NaN; `acos` and `asin` above magnitude one
NaN; `sin`, `tan`, `asin`, `sinh`, `tanh`, `expm1` and `cbrt` of `-0.0` are minus zero, `cos(-0.0)` and `cosh(-0.0)` one;
`sin`, `cos` and `tan` of an infinity NaN; `expm1(-inf)` is minus one; `cosh` and `sinh` overflow past about 710.47. A NaN
result is canonical.

```selka
# doc: expect 42
import math

func main() -> int:
    if math.bits(math.sin(1.0)) != 4605754516372524270u64:
        return 1
    # An argument past 2^20 * pi/2 takes the Payne-Hanek reduction.
    if math.bits(math.cos(1.0e300)) != 13826729873758864577u64:
        return 2
    # pi/2 is not exactly pi/2, so Zig's tangent is large and finite.
    if math.bits(math.tan(math.pi() / 2.0)) != 4849535219099880885u64:
        return 3
    if math.cbrt(27.0) != 3.0 or math.ln(2.0) != 0.6931471805599453:
        return 4
    if math.expm1(-math.infinity()) != -1.0 or math.tanh(math.infinity()) != 1.0:
        return 5
    return 42
```

## Intrinsics and the execution environment

The raw `f64_add`, `f64_sqrt`, `f64_from_u64`, `f64_to_u64` spellings are `E_REMOVED_SPELLING`. A float conversion that
fails in a module constant is a located diagnostic where a running program would trap with `R_FLOAT_CONVERSION`.

Native floating arithmetic needs round-to-nearest and gradual underflow; a program traps with `R_FLOAT_ENVIRONMENT` if the
embedding process changes rounding or flushes subnormals. Manual C builds need `-lm`.

## Prelude float helpers

`sqrt`, `floor`, `ceil`, `trunc` and `abs` need no import. Each takes one `float` and answers a `float`; a non-float
argument is `E_TYPE`. `round`, `pow`, the classification predicates and the other rounding modes live in the
[standard `math` module](standard-library.md#math).

```selka
# doc: expect 42
func main() -> int:
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

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/floating-point.md).
