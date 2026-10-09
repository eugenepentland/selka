# A1 integer widths and checked casts

Implemented: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, and `u64` in local,
parameter, result, and record-field types. Boolean and nominal record types
remain distinct. Fixed arrays and checked indexing are the remaining A1 work.

## Literal and conversion rules

Unsuffixed literals retain the scalar MVP's `i64` rules. An adjacent suffix
selects another width: `127i8`, `65535u16`, `18446744073709551615u64`.
Separators, bases, and floating-point literals are not supported. Unknown
suffixes are source errors. The type names and `cast` are reserved keywords.

A positive literal must fit its selected type. The signed minimum-magnitude
exception applies independently to each signed width: `-128i8` and
`-(128i8)` are valid, `128i8` is not, and `--128i8` traps on execution.

`T(expression)` converts between integer types with a runtime range check.
It neither truncates bits nor reinterprets signedness. It evaluates its operand
first and preserves operand traps. `u8(255)` succeeds;
`u8(256)`, `u8(-1)`, and `i64(18446744073709551615u64)`
trap with `R_OVERFLOW`. Checking does not execute these casts. An out-of-range
suffixed literal instead fails semantic checking with `E_INTEGER_RANGE`.

There are no implicit width conversions, including from unsuffixed literals.
Write `let value: u8 = 1u8;` or `let value = u8(1);`.
Casts involving booleans or records are rejected; casts do not bypass declared
complete-conversion or nominal record checks. `main` still returns `i64`.

## Operations

Integer arithmetic, ordering, and equality require matching operand types.
Arithmetic results retain that type and trap outside its range. `+=` and `-=`
retain the mutable binding's width. Logical operators still require booleans.
Division truncates toward zero; zero divisors trap. Signed minimum divided by
`-1` traps, while its remainder is zero. Unsigned subtraction below zero and
negation of nonzero unsigned values trap; unsigned negative zero is zero.

The VM stores wider intermediates internally and explicitly checks guest bounds.
This does not add an `i128` guest type or expose physical VM layout. Overflowing
host intermediates are detected with overflow-reporting operations; even the
product of two maximum `u64` values becomes a guest diagnostic in ReleaseFast.

## Evidence

- Every width's minimum/maximum and one-past literal cases are tested.
- Signed/unsigned arithmetic and cast boundaries, zero division/remainder,
  minimum remainder, and full-range `u64` division execute through the compiler.
- Exhaustive `i8` and `u8` addition/multiplication pairs check their bounds.
- Record fields, function arguments/results, compound assignment, and declared
  complete conversions retain integer width identities.
- Duplicate discovery `exact-v3` retains width and cast-target differences.
- The actual CLI exercises the editable `examples/integers.selka`, returning
  `6148914691236516950`, plus source-error and runtime-overflow distinctions.
- Allocation-failure testing covers widths/casts through records, execution,
  disassembly, and discovery. Failure injection forces allocation fallback to
  avoid host-dependent resize counts.

The complete suite passes 79/79 tests in Debug and ReleaseFast on Guardian's
pinned Zig `0.17.0-dev.1683+5ceec001b` snapshot. This milestone completes the
integer-width portion of A1; it does not complete the pending roadmap.
