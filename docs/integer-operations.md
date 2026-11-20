# Explicit integer operations

All operations take two operands of the same builtin integer type (or a generic `integer` type) and return that type. Arguments evaluate once, left to right. They also work in scalar module constants.

`bit_and(a,b)`, `bit_or(a,b)` and `bit_xor(a,b)` operate on the declared-width two’s-complement representation.

`shift_left(a,count)` discards high bits. `shift_right(a,count)` uses arithmetic sign extension for signed integers and zero extension for unsigned integers. Counts must be nonnegative and strictly smaller than the operand width; otherwise execution traps with `R_INVALID_SHIFT`. Constant evaluation reports a located `E_CONSTANT_ARITHMETIC` error.

`wrapping_add`, `wrapping_sub` and `wrapping_mul` reduce mathematical results modulo 2 raised to the declared width. `saturating_add`, `saturating_sub` and `saturating_mul` clamp to the declared type’s bounds. Existing arithmetic operators retain checked-overflow behavior.

Debug and release builds compute them identically, and behavior does not depend on host overflow settings. Floating-point types are a separate stage.

Validation: `zig test src/integer_operations_test.zig` runs width-boundary, constant/generic, allocation-failure and located trap checks in Debug and ReleaseFast.

## The calls

These are prelude names: they need no `import`, and `T` is one builtin integer type (`int`, `i8` to `i64`, `u8` to `u64`)
for every operand and the result. Look one up with `selka reference --query wrapping_add`.

| Call | What it returns | Section |
| --- | --- | --- |
| `bit_and(a: T, b: T) -> T`, `bit_or(a: T, b: T) -> T`, `bit_xor(a: T, b: T) -> T` | the bitwise combination in the declared width | [bitwise and shift helpers](#bitwise-and-shift-helpers) |
| `bit_not(value: T) -> T` | the complement in the operand's own width | [bitwise and shift helpers](#bitwise-and-shift-helpers) |
| `shift_left(value: T, count: T) -> T`, `shift_right(value: T, count: T) -> T` | the shifted value; `count` is a `T` below the width, else `R_INVALID_SHIFT` | [bitwise and shift helpers](#bitwise-and-shift-helpers) |
| `wrapping_add(a: T, b: T) -> T`, `wrapping_sub(a: T, b: T) -> T`, `wrapping_mul(a: T, b: T) -> T` | the result modulo 2 to the width | [wrapping and saturating arithmetic](#wrapping-and-saturating-arithmetic) |
| `saturating_add(a: T, b: T) -> T`, `saturating_sub(a: T, b: T) -> T`, `saturating_mul(a: T, b: T) -> T` | the result clamped to the bounds of `T` | [wrapping and saturating arithmetic](#wrapping-and-saturating-arithmetic) |
| `divtrunc(a: T, b: T) -> T`, `remtrunc(a: T, b: T) -> T` | the quotient and remainder rounded toward zero | [truncating division](#truncating-division) |

`+`, `-` and `*` on an `int` trap with `R_OVERFLOW` when the result does not fit, and `**`, `<<`, `>>`, `&`, `|`, `^`
and `~` do not exist. To learn that an addition would overflow without trapping, add with `wrapping_add` and compare
signs, as the last example of [wrapping and saturating arithmetic](#wrapping-and-saturating-arithmetic) does.

## Fixed-width integers

`int` is the checked signed 64-bit type ordinary code uses. The fixed widths `i8`, `i16`, `i32` and `i64`, and `u8`, `u16`, `u32` and `u64`, are there for binary formats and host interfaces. A literal carries its width as a suffix, as in `200u8` or `-1000i32`; an unsuffixed literal adopts the integer type its context expects, so an annotated binding needs no suffix. Widths never mix inside one operation: `int(value)` widens a fixed-width value, and storing a wider value in a narrower binding is an `E_TYPE` error.

```selka
# doc: expect 42
func main() -> int:
    mut counter = 9223372036854775807
    mut channel: u8 = 200
    mut offset: i32 = -1000i32
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
As in Python 3, a decimal integer may not start with a zero unless every digit is zero:
`0`, `00` and `0_0` are fine, but `0755` is an `E_INTEGER_LITERAL` error that says to
write `0o755` for octal or `755` for decimal, so a C-style octal mode never silently
means 755. Floats keep leading zeros (`007.5`, `01e2`). Imaginary literals such as `1j`
are not supported. `**`, `<<` and `>>` are not operators; use `math.pow`,
`shift_left` and `shift_right`. An array length (`[16]u8`) and a const generic length
argument take any unsuffixed integer spelling (`[0x10]u8`, `[1_024]u8`,
`[0b1_0000]u8`) and all spellings of one value are the same type; a suffix (`[2u8]`)
or a decimal leading zero (`[02]u8`) is rejected.

An unsuffixed literal in any base takes the integer type its context expects when
its value fits, including in a `const` initializer, so `const MASK: u32 = 4278190080`
and `const LOW: u8 = 0xFF` need no suffix or cast. Beside a typed operand (`MASK + 1`)
a literal takes that operand's type, whatever the operand is: a name, a field, an
element, a call's result (`num(x) != 0` with `num` returning `i32`), a nested operator
(`x + 2147483647 + 1` with `x: i32`), a conversion, or an operand of an integer builtin
(`shift_right(bit_xor(x, shift_right(x, 29)), 24)` with `x: u64` counts in `u64`), and
on either side (`0 != num(x)`). The two values of `min` and `max` work the same way
(`max(num(x), 0)`). A literal that type cannot hold is refused at the literal with
`E_INTEGER_RANGE`, naming the operand beside it (`num(x) + 3000000000`); convert that
operand to a wider type first. A literal with no typed neighbour is `int` (or `float`),
and a type the context gives the whole expression (`const y: i64 = ...`) still comes
first. `selka fmt` keeps the spelling you wrote.

```selka
# doc: expect 42
const MASK: u32 = 0xFF00_0000

func widen(x: u32) -> u64:
    return u64(x)

func main() -> int:
    mut low = 0x2A
    if i64(MASK) != 4278190080 or shift_right(widen(MASK), 24) != 255 or 0 == widen(MASK):
        return 1
    if 0o52 != low or 0b10_1010 != low or 1_000 != 1000:
        return 2
    mut block: FixedArray[u8, 0x10] = FixedArray[u8, 16]([0u8, 1u8, 2u8, 3u8, 4u8, 5u8, 6u8, 7u8, 8u8, 9u8, 10u8, 11u8, 12u8, 13u8, 14u8, 15u8])
    if len(block) != 16 or block[15] != 15u8:
        return 3
    return int(0x2Au8)
```

## Bitwise and shift helpers

These are the only spellings of the bit operations: integers have no `&`, `|` or `^` operators, and the compiler refuses them with `E_BIT_OPERATOR_REMOVED` and the rewrite to the call (`bit_and`, `bit_or`, `bit_xor`). They have no shift operators either: `<<`, `>>` and the assignments `<<=` and `>>=` are refused with `E_EXPRESSION`; write `shift_left(value, count)` and `shift_right(value, count)`. The complement has no operator at all (`~` is refused as `E_REMOVED_SPELLING`, which names `bit_not(value)`); write `bit_not(value)`. `bit_and`, `bit_or` and `bit_xor` take two operands of one integer type, and `bit_not(value)` complements one operand in its own width, so `bit_not(0u8)` is `255u8` and `bit_not(7)` is `-8`. `shift_left` and `shift_right` take the count in that same type, so shifting a `u8` counts in `u8`. A count that is negative or at least the operand width traps with `R_INVALID_SHIFT`, or reports `E_CONSTANT_ARITHMETIC` when it is a module constant.

```selka
# doc: expect 42
func main() -> int:
    mut flags: u8 = 12u8
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
    if bit_not(flags) != 243u8 or bit_not(3u8) != 252u8:
        return 6
    if bit_not(-1i32) != 0i32:
        return 7
    return int(bit_xor(flags, 10u8)) * 7
```

## Wrapping and saturating arithmetic

`wrapping_add`, `wrapping_sub` and `wrapping_mul` reduce the mathematical result modulo the declared width. `saturating_add`, `saturating_sub` and `saturating_mul` clamp it to the declared type’s bounds instead. Both families take two operands of one integer type and return that type, so the overflow behavior is chosen at the operation rather than on the type; `+`, `-` and `*` are unaffected and still trap.

```selka
# doc: expect 42
func main() -> int:
    mut level: u8 = 250u8
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

To ask whether an `int` addition would overflow before it traps, add with `wrapping_add` and compare the signs: two
operands of one sign that give a result of the other sign overflowed.

```selka
# doc: expect 42
func add_overflows(a: int, b: int) -> bool:
    const sum = wrapping_add(a, b)
    return (a >= 0 and b >= 0 and sum < 0) or (a < 0 and b < 0 and sum >= 0)

func main() -> int:
    if not add_overflows(9223372036854775807, 1):
        return 1
    if add_overflows(-5, 5) or add_overflows(9223372036854775806, 1):
        return 2
    return 42
```

## Truncating division

`//` rounds the quotient down and `%` follows that quotient. `divtrunc(a, b)` and `remtrunc(a, b)` round toward zero instead, the rounding C interfaces and most binary formats expect; the two agree whenever the operands share a sign and differ by one otherwise. Both take two operands of one integer type and trap on a zero divisor and on the signed minimum divided by `-1`. A local binding or a declared function of either name shadows the helper.

```selka
# doc: expect 42
func main() -> int:
    mut total = -85
    if total // 2 != -43 or total % 2 != 1:
        return 1
    if remtrunc(total, 2) != -1:
        return 2
    if divtrunc(85, -2) != -42 or remtrunc(85, -2) != 1:
        return 3
    return -divtrunc(total, 2)
```
