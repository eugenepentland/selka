# What the arithmetic theorems assume

**The development declares no Lean `axiom`.** `Arith/Check.lean` runs `#assert_axioms` over every
theorem the other files state, in the build: it fails unless the theorem depends on nothing beyond
`propext`, `Classical.choice` and `Quot.sound` (the axioms `simp`, `omega` and `decide` use). A
`sorry` (`sorryAx`) and `native_decide` (`Lean.ofReduceBool`) are therefore refused. The decoded
float constants are checked with `decide +kernel`, which evaluates in the kernel and adds no axiom.

What the theorems do assume is below. Each item is either a definition of the model (true of the
model by construction, false of the real system only if the model is wrong) or a hypothesis of a
theorem.

| # | Assumption | Where | Kind |
| --- | --- | --- | --- |
| M1 | LLVM's integer instructions mean what `Arith/Exec.lean` says: `add`/`sub`/`mul` wrap and give poison with `nsw`/`nuw` on overflow; `udiv`/`urem` by zero and `sdiv`/`srem` by zero or of `MIN` by `-1` are undefined behaviour (LangRef: `srem` of `MIN` by `-1` is undefined too); `shl`/`lshr`/`ashr` by `n` or more is poison; `icmp`, `select`, `and`, `xor`, `zext`, `sext`, `trunc` are total. | `Exec.lean` | definition (LangRef) |
| M2 | A poison value is not allowed to exist at all: an instruction that would create one ends the modelled run in the state `poison`. LLVM lets a poison value live until it reaches a branch, a division or a store, so the model rejects more than LLVM does; "never reaches `poison`" is the stronger claim that no instruction of the sequence produces poison, used or not. | `Exec.lean` | definition (stricter than LLVM) |
| M3 | A trap is defined behaviour. `trapIf k c` is the emitter's `br i1 c, label %trap, label %next` with a cold block that calls `@myl_core_trap` (declared `noreturn`) and ends in `unreachable`: if `c`, the program stops with kind `k`. That the runtime function does stop the program is the runtime's contract, not a Lean statement. The diagnostic operands the call carries are not modelled. | `Isa.trapIf`, `FORMULAS.md` | definition + runtime |
| M4 | `@llvm.uadd.sat` and `@llvm.sadd.sat` are modelled as hardware computes them (wrap, detect the carry or the sign overflow from the operand and result bits, saturate) rather than by the clamp the specification states, so the theorem is not a restatement. | `Exec.lean` (`uaddSatBV`, `saddSatBV`) | definition |
| M5 | A `double` is NaN, an infinity, or a rational `num/den` (`Arith/F64.lean`); `fcmp o*` is the ordered comparison (false with a NaN); `fptosi`/`fptoui` truncate toward zero and are poison unless the operand is finite and the truncation fits (LangRef). Nothing arithmetic is done on doubles, so no rounding is modelled. | `F64.lean`, `Exec.lean` | definition (LangRef, IEEE 754) |
| M6 | A real binary64 number is `Valid` in the model: a positive denominator, and an integer or a numerator below `2^53`. This is what makes `oge x, -2^63` and `ogt x, -2^63-1` the same test for the `i64` conversion. `F64.ofBits_valid` proves every bit pattern decodes to a valid value, so this is a theorem about the decoding, and the hypothesis `hx` of `floatToInt_correct` is discharged for any actual double. | `F64.lean` | theorem + hypothesis of `floatToInt_correct` |
| M7 | The constants the emitter prints for `float_to_int` are the eight pairs of `f2iConsts`; `f2iConsts_ok` decodes each (IEEE 754 binary64, `F64.ofBits`) and checks it is the integer the proof needs. | `FloatToInt.lean` | theorem (by kernel evaluation) |
| H1 | A test the emitter omits for a constant divisor cannot fire: `zc = false` implies `b <> 0`, `mc = false` implies `b <> -1` (`divSigned_correct`, `divU_correct`, `divUNarrow_correct`). The emitter omits the zero test for a constant divisor other than `0` and the `b = -1` handling for a constant other than `-1` (`division`, `emit_llvm.zig:2455`, `:2465`, `:2476`), and its constants are sign-extended (`allOnes`, `build.zig`). | `DivUnsigned.lean`, `DivSigned.lean` | hypothesis |
| H2 | The `check = proven` forms hold under the facts: `divProven_correct` needs `0 <= a` and `0 < b`, `shift_correct` (unguarded) needs `0 <= count < n`, `convert_proven` needs the value representable, `floatToIntProven_correct` and `floatToInt64Narrow_correct` need the operand finite with a truncation that fits the type (the `i32` for the narrowed `i64` form), `divUNarrow_correct` needs both operands below `2^32`. These are exactly what `facts.zig` `provable` establishes (`:1903-1949`, `fitsU32`, `fitsI32`). Whether the fact analysis is right is not proved here: that is package C7. Under `--verify-facts` the fact is tested and its failure traps with kind `fact` (`divProvenVerified_correct`, the `proven-verify` templates). | the theorems named | hypothesis |
| H3 | Signed division needs width `n >= 2` (the emitter's `1` replacing `-1` is `-1` itself in `i1`). The language's widths are 8 to 64. | `divSigned_correct` | hypothesis |
| E1 | The formulas are what the emitter emits. This is a statement about Zig code that no Lean theorem can make. It is checked, not proved: `src/core/arith_lowering_test.zig` emits one function per case (409: every operation, type and check mode; 168 of them also compiled from source programs) and compares its instructions with `templates.txt`, which the gate action `arith-proof` requires to be exactly what `Arith/Formulas.lean` renders. The comparison ignores registers' names, the `!prof`/`!dbg` attachments, and the `sext`/`zext`/`bitcast` instructions that only prepare a trap's diagnostic operands. | `arith_lowering_test.zig`, `arith_proof.py` | tested |
| E2 | LLVM compiles the IR it is given as its semantics say (the optimizer and back end are not modelled). | n/a | standard |

## Not covered

* Vector (`Simd`) integer operations, `add`/`sub`/`mul`/`neg` with overflow checks, and
  `int_to_float` and the float arithmetic: only the operations named above.
* `saturating_sub` and `saturating_mul`, which are runtime calls (`myl_core_saturating_integer`).
* An `f32` operand of `float_to_int` is widened to binary64 first (an exact `fpext`) and then
  follows the proved sequence; the widening is not part of these formulas.
* The reported operands of a trap (the values printed in the diagnostic).
* The widths: 8, 16, 32 and 64 only (the language's integer types); the theorems are generic in the
  width and use `n >= 2` or `0 < n`, so they hold for any width, but no other width is emitted.
