# The arithmetic lowering formulas (package C8.1)

This file writes down, for each integer operation whose lowering has a sign fix-up, a check or a
width-dependent constant, the LLVM instruction sequence `src/core/emit_llvm.zig` emits for it, as a
formula: the integer width, the signedness, the trap conditions and the arithmetic. The Lean
project in this directory (`Arith/Formulas.lean`) defines the same sequences once, proves them
equal to the operation's mathematical specification (`Arith/Spec.lean`) and renders them as text
(`templates.txt`); `src/core/arith_lowering_test.zig` compares what the emitter prints with that
text for every operation, type and check mode (409 cases, built as Core IR), and what the whole
compiler prints for 168 of them compiled from tiny source programs. So the sequences below are
checked three ways: the Lean formula is proved, the rendered text is what the formula says, and the
compiler's output is that text.

## How to read a formula

* `T` is the LLVM type `i8`, `i16`, `i32` or `i64`. The language's `i8`..`i64` and `u8`..`u64` share
  the type; the emitter chooses between signed and unsigned instructions (`sdiv`/`udiv`,
  `ashr`/`lshr`, `slt`/`ult`, `sext`/`zext`, `sadd.sat`/`uadd.sat`) from the language type.
  `W` is the width in bits (8, 16, 32, 64). `MIN` is `-2^(W-1)`.
* `a` and `b` are the operands; `tN` are the registers the sequence defines, numbered in order of
  definition. A literal operand (`0`, `-1`, `7`, `MIN`) is written inline, as the emitter prints it.
* `trapif c K` stands for the emitter's four-line trap idiom (`trapIf`, `emit_llvm.zig:1985`): a
  conditional branch on the `i1` register `c` to a cold block that calls `@myl_core_trap` and ends
  in `unreachable`, continuing in a fresh block when `c` is false. `K` is the trap kind the site
  records (`TrapKind`, `emit_llvm.zig:114`): `division_by_zero`, `overflow`, `invalid_shift`, `cast`,
  `float_conversion`, or `fact` (a `proven` check emitted under `--verify-facts` fails as `fact`,
  `site`, `emit_llvm.zig:1970`).
* The `sext`/`zext`/`bitcast` instructions that only widen an operand for the trap call's diagnostic
  arguments (`widened`, `emit_llvm.zig:2031`) are left out of the formulas and of the comparison:
  they are total instructions on the non-trap path.
* The blocks below are generated from the Lean formulas (`lake exe arith-templates --update-md
  FORMULAS.md`); the gate fails when one differs from what Lean renders. `templates.txt` has every
  width and mode.

## Check modes

Each instruction carries `check`: `exact` (traps in program order), `proven` (the fact pass showed
the failure impossible, `facts.zig` `provable`, line 1903) or `none`. `checkOf` (`emit_llvm.zig:1739`)
turns `proven` into `exact` under `--verify-facts`, and `site` then reports kind `fact`. The case ids
of `templates.txt` are `OP.TYPE.MODE`:

| Mode | Meaning |
| --- | --- |
| `exact` | `check = exact`, variable operands (the builder always emits this, `build.zig:2797-2811`) |
| `const`, `const-1` | `exact`, with the constant divisor `7` or `-1`: a test that cannot fire is not emitted |
| `none` | no check and no fact: only `convert` (a widening or a reinterpretation the builder asks for) |
| `proven` | the facts removed the check |
| `proven-verify` | a `proven` check emitted under `--verify-facts` |
| `narrow`, `narrow-const`, `proven-narrow` | the forms chosen from the facts' ranges (`u32` operands of a 64-bit division, an `i32` result of a 64-bit float conversion) |

## 1. Division and remainder: `div`, `rem`, `floor_div`, `floor_rem`

Specification (`specDiv`, `Arith/Spec.lean`; `docs/integer-operations.md`, "Truncating division",
`docs/python-syntax.md`): `div` and `rem` round toward zero (`divtrunc`, `remtrunc`), `floor_div` and
`floor_rem` toward negative infinity (`//` and `%` of Python). A zero divisor traps with
`division_by_zero`; a quotient outside the type (`MIN // -1` for the signed types) traps with
`overflow`; the remainder always fits, so `MIN % -1` is `0`.

Emitter: `division`, `src/core/emit_llvm.zig:2434-2500`, `floorAdjust`, `:2503-2524`.

### 1.1 Unsigned types (`:2454-2463`)

`udiv`/`urem`, preceded by the zero test unless the divisor is a nonzero constant (`:2456`). For an
unsigned type `//` equals truncation, so `div` and `floor_div` (and `rem`, `floor_rem`) are the same
sequence.

<!-- case floor_div.u32.exact -->
```text
t1 = icmp eq i32 b, 0
trapif t1 division_by_zero
t2 = udiv i32 a, b
ret i32 t2
```

<!-- case rem.u32.const -->
```text
t1 = urem i32 a, 7
ret i32 t1
```

Theorem `divU_correct` (`Arith/DivUnsigned.lean`): for every width, with the zero test absent only
when `b <> 0`, the sequence is `specDiv k false n a b`.

### 1.2 Signed types, truncating (`:2465-2495`)

The zero test (unless the divisor is a nonzero constant, `:2466`). For a variable divisor or the
constant `-1` (`:2476`): `m = (b == -1)`; for the quotient `div`, the one overflow `MIN / -1` is
tested (`mn = a == MIN`, `ov = mn and m`, trap `overflow`); then the divisor is replaced by `1` where
`b == -1` (`select`), so `sdiv`/`srem` never see the pair LLVM leaves undefined, and the quotient is
replaced by `0 - a` where `b == -1` (the remainder needs no replacement, it is `0` either way). A
constant divisor other than `0` and `-1` needs none of this and is one `sdiv`/`srem`.

<!-- case div.i32.exact -->
```text
t1 = icmp eq i32 b, 0
trapif t1 division_by_zero
t2 = icmp eq i32 b, -1
t3 = icmp eq i32 a, -2147483648
t4 = and i1 t3, t2
trapif t4 overflow
t5 = select i1 t2, i32 1, i32 b
t6 = sdiv i32 a, t5
t7 = sub i32 0, a
t8 = select i1 t2, i32 t7, i32 t6
ret i32 t8
```

<!-- case rem.i32.exact -->
```text
t1 = icmp eq i32 b, 0
trapif t1 division_by_zero
t2 = icmp eq i32 b, -1
t3 = select i1 t2, i32 1, i32 b
t4 = srem i32 a, t3
ret i32 t4
```

<!-- case div.i32.const -->
```text
t1 = sdiv i32 a, 7
ret i32 t1
```

<!-- case div.i32.const-1 -->
```text
t1 = icmp eq i32 -1, -1
t2 = icmp eq i32 a, -2147483648
t3 = and i1 t2, t1
trapif t3 overflow
t4 = select i1 t1, i32 1, i32 -1
t5 = sdiv i32 a, t4
t6 = sub i32 0, a
t7 = select i1 t1, i32 t6, i32 t5
ret i32 t7
```

### 1.3 Signed types, flooring (`floorAdjust`)

Python's floor division from the truncating instructions: `q = a sdiv safe`, `r = a srem safe`;
the result differs from truncation exactly when `r != 0` and `r` and `b` have opposite signs
(`(r xor b) < 0`, `fix`): the quotient is `q - fix`, the remainder `r + (fix ? b : 0)`. `safe` is `b`,
or `1` where `b == -1` as in 1.2.

<!-- case floor_div.i32.exact -->
```text
t1 = icmp eq i32 b, 0
trapif t1 division_by_zero
t2 = icmp eq i32 b, -1
t3 = icmp eq i32 a, -2147483648
t4 = and i1 t3, t2
trapif t4 overflow
t5 = select i1 t2, i32 1, i32 b
t6 = sdiv i32 a, t5
t7 = srem i32 a, t5
t8 = icmp ne i32 t7, 0
t9 = xor i32 t7, b
t10 = icmp slt i32 t9, 0
t11 = and i1 t8, t10
t12 = zext i1 t11 to i32
t13 = sub i32 t6, t12
t14 = sub i32 0, a
t15 = select i1 t2, i32 t14, i32 t13
ret i32 t15
```

<!-- case floor_rem.i32.exact -->
```text
t1 = icmp eq i32 b, 0
trapif t1 division_by_zero
t2 = icmp eq i32 b, -1
t3 = select i1 t2, i32 1, i32 b
t4 = sdiv i32 a, t3
t5 = srem i32 a, t3
t6 = icmp ne i32 t5, 0
t7 = xor i32 t5, b
t8 = icmp slt i32 t7, 0
t9 = and i1 t6, t8
t10 = select i1 t9, i32 b, i32 0
t11 = add i32 t5, t10
ret i32 t11
```

Theorem `divSigned_correct` (`Arith/DivSigned.lean`): for every width `n >= 2` and every operation
`k`, with `zc = false` only when `b <> 0` and `mc = false` only when `b <> -1`, the sequence is
`specDiv k true n a b`: it traps exactly when the specification does (`division_by_zero`, then
`overflow`) and on the other inputs returns the specified value; no `sdiv`/`srem` operand pair is
undefined behaviour and no instruction is poison. (`n >= 2` is needed: in `i1`, `1 == -1`.) The proof
goes through `needsFix`, the sign test of `floorAdjust`, which `fdiv_eq_tdiv_fix` and
`fmod_eq_tmod_fix` (`Arith/IntFacts.lean`) show equal to the difference between flooring and
truncation.

### 1.4 `proven` divisions (`:2441-2463`)

The fact is `a >= 0 and b > 0` (`facts.zig:1932`). The sequence is `udiv`/`urem` with no test, for
signed and unsigned types alike. Under `--verify-facts` the fact is tested first (an unsigned operand
cannot be negative, so only `b == 0` is tested) and a violation traps with kind `fact`.

<!-- case floor_div.i32.proven -->
```text
t1 = udiv i32 a, b
ret i32 t1
```

<!-- case floor_div.i32.proven-verify -->
```text
t1 = icmp slt i32 a, 0
t2 = icmp sle i32 b, 0
t3 = or i1 t1, t2
trapif t3 fact
t4 = udiv i32 a, b
ret i32 t4
```

<!-- case floor_div.u32.proven-verify -->
```text
t1 = icmp eq i32 b, 0
trapif t1 fact
t2 = udiv i32 a, b
ret i32 t2
```

Theorems `divProven_correct` (under the fact, the sequence is `specDiv`, which does not trap) and
`divProvenVerified_correct` (`Arith/DivProven.lean`).

### 1.5 64-bit divisions on operands the facts put in `u32` (`narrowDivision`, `:3936`)

When both operands of a 64-bit unsigned (or `proven` signed) division lie in `[0, 2^32)`, each is
masked to its low 32 bits, which changes nothing, so that LLVM can use the 32-bit reciprocal.

<!-- case rem.u64.narrow -->
```text
t1 = icmp eq i64 b, 0
trapif t1 division_by_zero
t2 = and i64 a, 4294967295
t3 = and i64 b, 4294967295
t4 = urem i64 t2, t3
ret i64 t4
```

<!-- case div.i64.proven-narrow -->
```text
t1 = and i64 a, 4294967295
t2 = and i64 b, 4294967295
t3 = udiv i64 t1, t2
ret i64 t3
```

Theorem `divUNarrow_correct`: with `a.toNat < 2^32` and `b.toNat < 2^32` the masked sequence is
`specDiv`.

## 2. Shifts: `shift_left`, `shift_right`

Specification (`specShift`; `docs/integer-operations.md`, "Bitwise and shift helpers"): the count has
the operand's type; a count that is negative or at least the width traps with `invalid_shift`;
otherwise `shift_left` is `a * 2^c` with the high bits discarded, and `shift_right` is `a / 2^c` rounded
down (arithmetic for a signed type, logical for an unsigned one).

Emitter: `emit_number.instruction`, `src/core/emit_number.zig:189-196`. One unsigned comparison
`count >= W` rejects a negative signed count as well as a large one; then `shl`, `ashr` (signed) or
`lshr` (unsigned). LLVM defines a shift by `W` or more as poison, which the guard excludes; a
`proven` shift has no guard and the fact is `0 <= count < W` (`facts.zig:1922`).

<!-- case shift_left.i8.exact -->
```text
t1 = icmp uge i8 b, 8
trapif t1 invalid_shift
t2 = shl i8 a, b
ret i8 t2
```

<!-- case shift_right.i16.exact -->
```text
t1 = icmp uge i16 b, 16
trapif t1 invalid_shift
t2 = ashr i16 a, b
ret i16 t2
```

<!-- case shift_right.u32.exact -->
```text
t1 = icmp uge i32 b, 32
trapif t1 invalid_shift
t2 = lshr i32 a, b
ret i32 t2
```

<!-- case shift_left.i32.proven -->
```text
t1 = shl i32 a, b
ret i32 t1
```

<!-- case shift_left.i32.proven-verify -->
```text
t1 = icmp uge i32 b, 32
trapif t1 fact
t2 = shl i32 a, b
ret i32 t2
```

Theorem `shift_correct` (`Arith/Shift.lean`), every width: guarded, the sequence is `specShift`;
unguarded, it is `specShift` under the fact (so `shl`/`ashr`/`lshr` are never poison).

## 3. `saturating_add`

Specification (`specSatAdd`; `docs/integer-operations.md`, "Wrapping and saturating arithmetic"): the
exact sum clamped to the type's bounds; it never traps.

Emitter: `src/core/emit_number.zig:185-187`: the LLVM intrinsic of the type's signedness. (`saturating_sub`
and `saturating_mul` are runtime calls, `build.zig:2845`, and are not covered.)

<!-- case saturating_add.i16 -->
```text
t1 = call i16 @llvm.sadd.sat.i16(i16 a, i16 b)
ret i16 t1
```

<!-- case saturating_add.u8 -->
```text
t1 = call i8 @llvm.uadd.sat.i8(i8 a, i8 b)
ret i8 t1
```

Theorems `uaddSat_eq`, `saddSat_eq`, `saturatingAdd_correct` (`Arith/SatAdd.lean`): the intrinsics are
modelled as hardware computes them (`uaddSatBV`, `saddSatBV` in `Arith/Exec.lean`: wrap, detect the
carry or sign overflow from the operand and result bits, saturate) and proved equal to the clamped sum.

## 4. `convert` (`i8(x)`, `u64(x)`, `int(x)`, ...)

Specification (`specConvert`; `docs/floating-point.md`, "Integer conversions" for the float case,
`build.zig:3277` for the integer one): the value is kept; a value the target type cannot represent
traps with `cast`. A conversion every source value survives carries `check = none`
(`build.zig:3276`); the others `exact`.

Emitter: `convert`, `src/core/emit_llvm.zig:2526-2563`. With `exact`: a test against the target's
minimum when it is above the source's (`slt`, only a signed source can need it) and against the target's
maximum when it is below the source's (`sgt` for a signed source, `ugt` for an unsigned one), joined
by `or`, one trap `cast`; then the bits move: `add 0` for equal widths, `sext` (signed source) or
`zext` (unsigned source) to a wider type, `trunc` to a narrower one. The literals are the target's
bounds, printed in the source type.

<!-- case convert.i64.u8.exact -->
```text
t1 = icmp slt i64 a, 0
t2 = icmp sgt i64 a, 255
t3 = or i1 t1, t2
trapif t3 cast
t4 = trunc i64 a to i8
ret i8 t4
```

<!-- case convert.i8.u64.exact -->
```text
t1 = icmp slt i8 a, 0
trapif t1 cast
t2 = sext i8 a to i64
ret i64 t2
```

<!-- case convert.u64.i64.exact -->
```text
t1 = icmp ugt i64 a, 9223372036854775807
trapif t1 cast
t2 = add i64 a, 0
ret i64 t2
```

<!-- case convert.i32.u32.exact -->
```text
t1 = icmp slt i32 a, 0
trapif t1 cast
t2 = add i32 a, 0
ret i32 t2
```

<!-- case convert.u8.i32.exact -->
```text
t1 = zext i8 a to i32
ret i32 t1
```

<!-- case convert.i32.i16.none -->
```text
t1 = trunc i32 a to i16
ret i16 t1
```

Theorems `convertGuard_correct`, `convertMove_correct`, `convert_exact`, `convert_wrap`,
`convert_proven` (`Arith/Convert.lean`), every pair of widths: guarded, the sequence is `specConvert`;
unguarded, it is the value reduced modulo `2^wt`; under the `proven` fact (the value is
representable) the two agree.

## 5. `float_to_int` (`i32(x)`, `u8(x)`, ... of a float)

Specification (`specFloatToInt`; `docs/floating-point.md`, "Integer conversions"): truncate toward
zero, then require the result to fit; NaN, either infinity and an out-of-range truncated result trap
with `float_conversion` (an `f32` operand is first widened exactly, `build.zig:3245`).

Emitter: `floatToInt`, `src/core/emit_llvm.zig:2565-2592`. Two ordered comparisons with constants that
are doubles, `and`, `xor true`, one trap, then `fptosi`/`fptoui`: the truncated value fits iff
`x > lo - 1` and `x < hi + 1`. The lower constant is `lo - 1.0` (`ogt`) except for `i64`, where
`lo - 1.0` rounds back to `lo` and the test is `oge x, lo`; an unsigned type uses `-1.0`. The upper
constant is `2^(W-1)` (signed) or `2^W` (unsigned). An ordered comparison with NaN is false, so NaN
fails the test.

<!-- case float_to_int.i32.exact -->
```text
t1 = fcmp ogt double a, 0xC1E0000000200000
t2 = fcmp olt double a, 0x41E0000000000000
t3 = and i1 t1, t2
t4 = xor i1 t3, true
trapif t4 float_conversion
t5 = fptosi double a to i32
ret i32 t5
```

<!-- case float_to_int.i64.exact -->
```text
t1 = fcmp oge double a, 0xC3E0000000000000
t2 = fcmp olt double a, 0x43E0000000000000
t3 = and i1 t1, t2
t4 = xor i1 t3, true
trapif t4 float_conversion
t5 = fptosi double a to i64
ret i64 t5
```

<!-- case float_to_int.u8.exact -->
```text
t1 = fcmp ogt double a, 0xBFF0000000000000
t2 = fcmp olt double a, 0x4070000000000000
t3 = and i1 t1, t2
t4 = xor i1 t3, true
trapif t4 float_conversion
t5 = fptoui double a to i8
ret i8 t5
```

<!-- case float_to_int.i32.proven -->
```text
t1 = fptosi double a to i32
ret i32 t1
```

<!-- case float_to_int.i64.proven-narrow -->
```text
t1 = fptosi double a to i32
t2 = sext i32 t1 to i64
ret i64 t2
```

The constants, as the emitter prints them (`f2iConsts`, `Arith/FloatToInt.lean`):

| Target | lower bound (bits) | meaning | upper bound (bits) | meaning |
| --- | --- | --- | --- | --- |
| `i8` | `0xC060200000000000` | `> -129` | `0x4060000000000000` | `< 128` |
| `i16` | `0xC0E0002000000000` | `> -32769` | `0x40E0000000000000` | `< 32768` |
| `i32` | `0xC1E0000000200000` | `> -2147483649` | `0x41E0000000000000` | `< 2147483648` |
| `i64` | `0xC3E0000000000000` | `>= -2^63` (inclusive) | `0x43E0000000000000` | `< 2^63` |
| `u8` | `0xBFF0000000000000` | `> -1` | `0x4070000000000000` | `< 256` |
| `u16` | `0xBFF0000000000000` | `> -1` | `0x40F0000000000000` | `< 65536` |
| `u32` | `0xBFF0000000000000` | `> -1` | `0x41F0000000000000` | `< 2^32` |
| `u64` | `0xBFF0000000000000` | `> -1` | `0x43F0000000000000` | `< 2^64` |

Theorem `floatToInt_correct` (`Arith/FloatToInt.lean`) over a float model (`Arith/F64.lean`: NaN, two
infinities and rationals, decoded from bits by `F64.ofBits`, with the one fact about real doubles the
`i64` case needs); `f2iConsts_ok` decodes each constant in the table above and checks it is the
integer the proof needs. `floatToIntProven_correct` and `floatToInt64Narrow_correct` cover the
`proven` forms under their facts.

## Where each statement is proved

| Operation | Formula (`Arith/Formulas.lean`) | Theorem | File |
| --- | --- | --- | --- |
| unsigned `div`/`rem` | `divU` | `divU_correct` | `DivUnsigned.lean` |
| signed `div`/`rem`/`floor_div`/`floor_rem` | `divSigned`, `floorAdjust` | `divSigned_correct` | `DivSigned.lean` |
| `proven` divisions | `divProven`, `divProvenVerified`, `divUNarrow` | `divProven_correct`, `divProvenVerified_correct`, `divUNarrow_correct` | `DivProven.lean` |
| `shift_left`/`shift_right` | `shift` | `shift_correct` | `Shift.lean` |
| `saturating_add` | `saturatingAdd` | `saturatingAdd_correct` | `SatAdd.lean` |
| `convert` | `convert` | `convert_exact`, `convert_wrap`, `convert_proven` | `Convert.lean` |
| `float_to_int` | `floatToInt` | `floatToInt_correct`, `f2iConsts_ok` | `FloatToInt.lean` |

`Coverage.lean` states each theorem at the widths 8, 16, 32 and 64.
