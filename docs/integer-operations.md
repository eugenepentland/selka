# Explicit integer operations

All operations take two operands of the same builtin integer type (or a generic `integer` type) and return that type. Arguments evaluate once, left to right. They also work in scalar module constants.

`bit_and(a,b)`, `bit_or(a,b)` and `bit_xor(a,b)` operate on the declared-width two’s-complement representation.

`shift_left(a,count)` discards high bits. `shift_right(a,count)` uses arithmetic sign extension for signed integers and zero extension for unsigned integers. Counts must be nonnegative and strictly smaller than the operand width; otherwise execution traps with `R_INVALID_SHIFT`. Constant evaluation reports a located `E_CONSTANT_ARITHMETIC` error.

`wrapping_add`, `wrapping_sub` and `wrapping_mul` reduce mathematical results modulo 2 raised to the declared width. `saturating_add`, `saturating_sub` and `saturating_mul` clamp to the declared type’s bounds. Existing arithmetic operators retain checked-overflow behavior.

The QBE native backend uses widened intermediates and explicit unsigned bit manipulation. Behavior does not depend on host overflow settings. Floating-point types are a separate stage.

Validation: `zig test src/integer_operations_test.zig` runs width-boundary, constant/generic, allocation-failure and located trap checks in Debug and ReleaseFast.

## Fixed-width integers

`int` is the checked signed 64-bit type ordinary code uses. The fixed widths `i8`, `i16`, `i32` and `i64`, and `u8`, `u16`, `u32` and `u64`, are there for binary formats and host interfaces. A literal carries its width as a suffix, as in `200u8` or `-1000i32`; an unsuffixed literal adopts the integer type its context expects, so an annotated binding needs no suffix. Widths never mix inside one operation: `int(value)` widens a fixed-width value, and storing a wider value in a narrower binding is an `E_TYPE` error.

```mylang
# doc: expect 42
def main() -> int:
    counter = 9223372036854775807
    channel: u8 = 200
    offset: i32 = -1000i32
    if int(channel) != 200 or int(offset) != -1000:
        return 1
    if counter - 9223372036854775765 != 42:
        return 2
    return int(channel) - 158
```

## Integer literal spellings

Integer literals are Python's. Write decimal `255`, hexadecimal `0xFF` (or `0XFF`),
octal `0o377` and binary `0b1111_1111`; digits take either case, and single
underscores may separate digits (`1_000_000`, `0xDEAD_BEEF`) or follow the base
prefix (`0x_FF`). A width suffix goes directly after the last digit and combines
with every base: `0xFFu8`, `0b1010u16`, `0o17i32`, `1_000u32`. A suffix begins at
the first byte that is not a digit of the base. The suffix letters `i` and `u` are
digits of no base, so a hexadecimal literal never swallows its suffix, and no
underscore may sit between the last digit and the suffix (`1_u8` is an error).

A leading, trailing or doubled underscore (`1__0`, `1_`, `0_x`), a base prefix with
no digit (`0x`) and a digit outside the base (`0b12`, `0o8`) are `E_INTEGER_LITERAL`
errors, and a value that does not fit its type is `E_INTEGER_RANGE` in every base.
Unlike Python, decimal leading zeros are accepted and mean the decimal value (`007`
is 7), so write an octal mode as `0o755`. Imaginary literals such as `1j` are not
supported. `**`, `<<` and `>>` are not operators; use `math.pow`, `shift_left` and
`shift_right`. Array lengths (`[16]u8`) stay plain decimal without an underscore or
prefix.

An unsuffixed literal in any base takes the integer type its context expects when
its value fits, including in a `const` initializer, so `const MASK: u32 = 4278190080`
and `const LOW: u8 = 0xFF` need no suffix or cast. Beside a typed operand (`MASK + 1`)
a literal takes that operand's type. `mylang fmt` keeps the spelling you wrote.

```mylang
# doc: expect 42
const MASK: u32 = 0xFF00_0000

def main() -> int:
    low = 0x2A
    if i64(MASK) != 4278190080:
        return 1
    if 0o52 != low or 0b10_1010 != low or 1_000 != 1000:
        return 2
    return int(0x2Au8)
```

## Bitwise and shift helpers

These are the named spellings of the operations that have no operator. `bit_and`, `bit_or` and `bit_xor` take two operands of one integer type. `shift_left` and `shift_right` take the count in that same type, so shifting a `u8` counts in `u8`. A count that is negative or at least the operand width traps with `R_INVALID_SHIFT`, or reports `E_CONSTANT_ARITHMETIC` when it is a module constant.

```mylang
# doc: expect 42
def main() -> int:
    flags: u8 = 12u8
    if bit_and(flags, 10u8) != 8u8:
        return 1
    if bit_or(flags, 10u8) != 14u8:
        return 2
    if shift_left(flags, 4u8) != 192u8:
        return 3
    if shift_right(200u8, 3u8) != 25u8:
        return 4
    if shift_right(-16i32, 2i32) != -4i32:
        return 5
    return int(bit_xor(flags, 10u8)) * 7
```

## Wrapping and saturating arithmetic

`wrapping_add`, `wrapping_sub` and `wrapping_mul` reduce the mathematical result modulo the declared width. `saturating_add`, `saturating_sub` and `saturating_mul` clamp it to the declared type’s bounds instead. Both families take two operands of one integer type and return that type, so the overflow behavior is chosen at the operation rather than on the type; `+`, `-` and `*` are unaffected and still trap.

```mylang
# doc: expect 42
def main() -> int:
    level: u8 = 250u8
    if wrapping_add(level, 10u8) != 4u8:
        return 1
    if saturating_add(level, 10u8) != 255u8:
        return 2
    if wrapping_sub(0u8, 1u8) != 255u8:
        return 3
    if saturating_sub(3u8, 10u8) != 0u8:
        return 4
    if wrapping_mul(200u8, 2u8) != 144u8:
        return 5
    if saturating_mul(100i8, 100i8) != 127i8:
        return 6
    return int(saturating_add(level, 10u8)) - 213
```

## Truncating division

`//` rounds the quotient down and `%` follows that quotient. `divtrunc(a, b)` and `remtrunc(a, b)` round toward zero instead, the rounding C interfaces and most binary formats expect; the two agree whenever the operands share a sign and differ by one otherwise. Both take two operands of one integer type and trap on a zero divisor and on the signed minimum divided by `-1`. A local binding or a declared function of either name shadows the helper.

```mylang
# doc: expect 42
def main() -> int:
    total = -85
    if total // 2 != -43 or total % 2 != 1:
        return 1
    if remtrunc(total, 2) != -1:
        return 2
    if divtrunc(85, -2) != -42 or remtrunc(85, -2) != 1:
        return 3
    return -divtrunc(total, 2)
```
