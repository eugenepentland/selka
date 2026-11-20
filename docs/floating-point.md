# Binary64 floating point

`float` is the language's binary64 type. It is an ordinary numeric type with
decimal literals, the usual operators and comparisons, and `float(integer)` /
`int(float)` conversion. The [standard `math` module](standard-library.md#math)
supplies classification, rounding, roots and the native `sin`/`cos` operations
for angles in radians.

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

Float literals are Python's: `1.5`, a leading dot `.5`, a trailing dot `5.`,
exponents `1e10` and `2.5E-3`, and single underscores between digits in the mantissa
and the exponent (`1_000.5`, `1e1_0`); leading zeros are allowed (`007.5`). `.5` is a
float wherever an operand does not end directly before the dot, so `x.5` and `f().5`
stay member access, and `5.name` keeps the `5` apart from `.name`. A float takes no
integer suffix, a hexadecimal, octal or binary spelling is always an integer, and an
imaginary literal such as `1.5j` is rejected because there are no complex numbers.
A malformed spelling (`1_.5`, `1e`, `1.5_`) is an `E_FLOAT_LITERAL` error at the
literal.

```selka
# doc: expect 42
func main() -> int:
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
To convert without the trap, `math.to_int(value)` answers `None` where `int(value)` would trap and
`math.to_int_saturating(value)` clamps to the signed 64-bit range (NaN gives 0); to print a float with an
exponent where `str` would print hundreds of digits, `strings.format_shortest(value)`
([the `math` module](standard-library.md#math), [the `strings` module](standard-library.md#strings)).

```selka
# doc: expect 42
func main() -> int:
    if i8(-128.5) != -128i8 or u8(-0.5) != 0u8:
        return 1
    return int(u64(42.75))
```

```selka
# doc: expect 42
import math

func main() -> int:
    mut root = sqrt(1764.0)
    if math.is_nan(root) or not math.is_finite(root):
        return 1
    if floor(root + 0.5) != root or trunc(0.0 - 1.9) != 0.0 - 1.0:
        return 2
    mut negative = 0.0 - 5.0
    if negative // 2.0 != 0.0 - 3.0 or negative % 2.0 != 1.0:
        return 3
    return int(round(41.5))
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
- a float argument passed to an `extern func` crosses as the canonical pattern, so
  `copysign(1.0, -(0.0 / 0.0))` in C answers `1.0`;
- equality of lists, records, fixed arrays and options compares floats
  numerically, and sorting orders every NaN after the ordered values whatever its
  sign.

A float's representation is read only through `math.bits` and written through
`math.from_bits`, which canonicalize NaN; the raw `f64_*` spellings are removed.
Dictionary keys are integers or `str`, and the wire, codec and typed-JSON boundaries reject `float`, so
no hash or encoding sees a float's bits either. Canonicalizing at these points
instead of after every operation keeps float loops free of a compare, branch and
call per operation, and results stay identical across machines, because a NaN is
canonical before anything could see that two processors produced different
payloads.

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

`math.trunc`, `math.floor`, `math.ceil` and `math.round` return integral-valued
floats and pass infinities and NaNs through unchanged; `math.round` rounds halves
away from zero. `math.fabs` maps both zeros to positive zero. `math.pow` takes an
integer exponent and squares repeatedly.

`math.sqrt` calls the compiler-internal binary64 square root on its ordinary
`float` argument, so it is the correctly rounded square root and is exact for
values whose root is exactly representable.

Prelude `sqrt`, `floor`, `ceil`, `trunc` and `abs` take one `float` and answer a
`float`, running the host binary64 operation directly, so ordinary guest code never
handles a `u64` bit pattern. A local binding of the same name shadows each of them. A bare
`sqrt(...)`, `floor(...)`, `ceil(...)`, `trunc(...)` or `abs(...)` is always the prelude
operation: a module function with one of these names is refused when its own module calls it
bare (`E_BUILTIN_FUNCTION_NAME`, whose repair renames it). The standard library's own
`math.sqrt` is exempt and is reached by its qualified name. `round`,
`exp`, `log`, `pow` and the trigonometric functions have no prelude spelling.

## Bit patterns

`math.bits(value)` answers the IEEE binary64 pattern of a `float` as a `u64`,
and `math.from_bits(pattern)` builds the `float` a `u64` pattern names. Every
NaN answers the canonical quiet NaN, so `bits` observes nothing a NaN's payload
could tell apart. `math.f32_bits` and `math.f32_from_bits` do the same for `f32`
with a `u32` pattern.

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

`f32` is the IEEE binary32 type. A binary32 literal carries the suffix `f32`
after a decimal point or an exponent, as in `0.5f32`, `1.0f32` or `1e3f32`; the
suffix-less `1f32` is refused because it is an integer spelling. A suffix-less
float literal takes `f32` from its context, as an unsuffixed integer takes an
integer type, so `x * 0.1` with `x: f32` is `x * 0.1f32`, and an unsuffixed literal
beside any `f32` operand, a call's result as much as a name, is an `f32`: `f32(x) * 2`
is `f32(x) * 2.0f32`. Every operation
rounds to binary32: `0.1f32 + 0.2f32` is `0.3f32` exactly, and overflow gives
an infinity.

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

An `f32` and a `float` are different types, and an operation that meets both is
refused with `E_FLOAT_WIDTH`. The repair widens the `f32` operand with `float(...)`,
which is exact. Convert in the other direction with `f32(...)`, which rounds to the
nearest binary32 value. An integer operand of an `f32` operation (other than an
unsuffixed literal, which becomes an `f32`) is refused for the same code, with the repair `f32(...)`, because an implicit conversion would round
large integers silently.

```selka
# doc: expect 42
func main() -> int:
    const narrow: f32 = 1.5f32
    const wide: float = 2.0
    const total = float(narrow) + wide
    const back = f32(total) * 2.0f32
    return int(float(back) * 6.0)
```

The conversions are explicit: `f32(value)` takes a `float`, an `f32` (unchanged) or
an integer, and `float(value)` takes an `f32`, which widens exactly. `int(value)`
and the fixed-width integer casts accept an `f32` and truncate it like a `float`.
A binary32 value's storage is four bytes: `f32[]`, `FixedArray[f32, N]` and record
fields hold it at that stride, so an array of `f32` is half the size of one of
`float`.

Text spells a binary32 value by its shortest round-trip decimal for binary32, so
`str(0.1f32)` is `0.1` while `str(float(0.1f32))` is `0.10000000149011612`. A format
specification applies to `f32` as it does to `float`, and a specification with no
precision prints the binary32 digits. `parse_f32(text)` reads the same grammar as `parse_float` and rounds the decimal
straight to binary32, so `"0.1"` parses to exactly `0.1f32`.

```selka
# doc: expect 42
func main() -> int:
    if str(0.1f32) != "0.1" or str(float(0.1f32)) != "0.10000000149011612":
        return 1
    if f"{1.25f32:.3f}" != "1.250":
        return 2
    if parse_f32("0.1") != Some(0.1f32) or parse_f32("x") is not None:
        return 3
    return 42
```

Math functions take `float`. The prelude roots and `abs`, `min` and `max` also
take `f32`, and answer an `f32`: `sqrt`, `floor`, `ceil` and `trunc`.

## Fused multiply-add and hypot

`math.fma(a, b, c)` computes `a * b + c` with one rounding, the IEEE fused
multiply-add, and `math.f32_fma` does the same for `f32`. The separate `*` and `+`
of `a * b + c` round twice, so the fused form is the way to get the exact product
into a sum.

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

`math.hypot(x, y)` is `sqrt(x * x + y * y)` without unnecessary overflow or underflow,
and it answers the bits of Zig's `std.math.hypot`: it uses the same scaling bounds and the
same fused correction step, so a program ported from Zig gets identical results.
`math.f32_hypot` is Zig's binary32 form, which forms the squares and their sum in
binary64 and rounds the root once to binary32.

```selka
# doc: expect 42
import math

func main() -> int:
    if math.bits(math.hypot(3.0, 4.0)) != 4617315517961601024u64:
        return 1
    if math.f32_bits(math.f32_hypot(1.0e30f32, 1.0e30f32)) != 1905183888u32:
        return 2
    return 42
```

## Zig-exact log10, exp, atan2 and pow_float

`math.log10`, `math.exp`, `math.atan2` and `math.pow_float` answer the bits of the pinned Zig toolchain's
`std.math.log10`, `exp`, `atan2` and `pow` for `float` (binary64), and `math.f32_log10`, `math.f32_exp`,
`math.f32_atan2` and `math.f32_pow_float` do the same for `f32`, so a program ported from Zig gets identical results,
special values included. Each is the algorithm Zig runs, operation for operation (musl's `log10`, `exp` and `log` as
Zig's `compiler_rt` carries them, `atan` and `atan2`, and Go's `pow`), written in Selka with no reordering and no fused
multiply-add; none calls the C library, whose results differ from Zig's in the last bit for some arguments. The
special cases are Zig's: `log10(0.0)` is minus infinity and `log10` of a negative value is NaN; `exp` of a large
argument is infinity and of a very negative one is zero; `atan2(-0.0, -1.0)` is minus pi; `pow_float(x, 0.0)` and
`pow_float(1.0, y)` are one for every `x` and `y`, a negative base with a non-integer exponent is NaN, and an
infinite or zero base follows the case table in Zig's `pow.zig`. A NaN result is the canonical NaN.
`math.pow(base, exponent)` with an integer exponent is unchanged.

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

`tests/lang/math_zig_exact.selka` checks 1,674 of the 256,712 results the reference capture holds, and
`experiments/g3-pre-s1-fixes-20261105/math/` has the generator, the Zig program that captures the results and the
Selka program that compares every one of them.

## Zig-exact ln, atan, acos, asin, tan, expm1, sinh, cosh, tanh, cbrt, sin and cos

`math.ln`, `atan`, `acos`, `asin`, `tan`, `expm1`, `sinh`, `cosh`, `tanh`, `cbrt`, `sin` and `cos` take and answer a `float`
(binary64) and answer the bits of the pinned Zig toolchain's `@log`, `std.math.atan`, `std.math.acos`, `std.math.asin`,
`@tan`, `std.math.expm1`, `std.math.sinh`, `std.math.cosh`, `std.math.tanh`, `std.math.cbrt`, `@sin` and `@cos`, special values
included. As with the four above, each is the algorithm Zig runs, operation for operation (the table-driven `log` of
`compiler_rt`, musl's `atan`, `acos`, `asin`, `expm1`, `sinh`, `cosh` and `tanh`, FreeBSD's `cbrt`, and `compiler_rt`'s `sin`,
`cos` and `tan` with their `__sin`, `__cos` and `__tan` kernels), written in Selka with no reordering and no fused
multiply-add; none calls the C library, which differs from Zig in the last bit for 3% to 55% of the arguments depending on the
function. `sin` and `cos` changed in place: they were evaluated by the C library, and now differ from their old results by one
unit in the last place for about 3% of the arguments.

The argument reduction is Zig's `rem_pio2`, the Payne-Hanek reduction included (`rem_pio2_large`, from the 690-word table of
2/pi), so every finite argument up to the largest `float` is reduced without a trap: `math.sin(1.0e300)` and
`math.cos(1.7976931348623157e308)` answer Zig's bits. The special cases are Zig's: `ln(0.0)` is minus infinity and `ln` of a
negative value is NaN; `acos` and `asin` of a magnitude above one are NaN; `sin(-0.0)`, `tan(-0.0)`, `asin(-0.0)`, `sinh(-0.0)`,
`tanh(-0.0)`, `expm1(-0.0)` and `cbrt(-0.0)` are minus zero while `cos(-0.0)` and `cosh(-0.0)` are one; `sin`, `cos` and `tan`
of an infinity are NaN; `expm1(-inf)` is minus one and `tanh(+-inf)` is plus or minus one; `cosh` and `sinh` overflow to
infinity past about 710.47. A NaN result is the canonical NaN. There are no `f32_` forms of these.

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

`tests/lang/math_zig_exact.selka` checks 2,969 of the 1,201,814 results the reference capture holds, and
`experiments/math-exact-20261106/` has the Zig program that captures the results (`capture.zig`), the Selka program that
compares every one of them (`verify_math.selka`) and the script that runs both (`run.sh`).

## Intrinsics and the execution environment

The raw `f64_add`, `f64_sqrt`, `f64_from_u64`, `f64_to_u64` and related
spellings that took and returned `u64` bit patterns are removed and rejected with
`E_REMOVED_SPELLING`, so no program handles a float's bit pattern. A conversion in
a module constant reports a located constant-arithmetic diagnostic where the
running program would trap with `R_FLOAT_CONVERSION`.

Native floating arithmetic uses strict host binary64 operations.
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
