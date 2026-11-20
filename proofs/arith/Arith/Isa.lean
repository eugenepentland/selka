import Arith.Basic
import Arith.F64

/-!
# The instruction set the formulas are written against

The formulas of `FORMULAS.md` are straight-line sequences of LLVM instructions. They are written
once, in Lean, against an abstract instruction set `Isa M R`:

* `Isa.exec` (Exec.lean) gives each instruction LLVM's semantics on `BitVec n`, with poison and
  undefined behaviour explicit; the theorems are about that reading;
* `Isa.print` (Print.lean) renders each instruction as the LLVM text the emitter prints, so the
  same Lean definition produces the template `emit_llvm.zig` is pinned to (`templates.txt`).

A register of type `i1`, `iN` or `double` has type `R .i1`, `R (.int n)` or `R .double`.
-/

namespace Arith

/-- The LLVM types the lowerings use. -/
inductive Ty where
  | i1
  | int (n : Nat)
  | double
  deriving DecidableEq, Repr

/-- Integer comparison predicates of `icmp`. -/
inductive Pred where
  | eq | ne | ult | ule | ugt | uge | slt | sle | sgt | sge
  deriving DecidableEq, Repr

/-- Ordered floating-point comparison predicates of `fcmp` (the ones the lowerings use). -/
inductive FPred where
  | ogt | oge | olt
  deriving DecidableEq, Repr

/-- What a trap site reports (`TrapKind` in `src/core/emit_llvm.zig`). -/
inductive Trap where
  | overflow | divisionByZero | floatConversion | cast | fact | invalidShift
  deriving DecidableEq, Repr

/-- The instruction set: constants and the instructions the lowerings of `floor_div`, `floor_rem`,
`div`, `rem`, `shift_left`, `shift_right`, `convert`, `float_to_int` and `saturating_add` use.

`trapIf k c` is the emitter's idiom `br i1 c, label %trap, label %next` followed by the cold
block that calls `@myl_core_trap` and ends in `unreachable`: control either continues (`c`
false) or the program traps with kind `k` (`c` true). -/
structure Isa (M : Type → Type) (R : Ty → Type) where
  /-- An integer literal operand `iN v`. -/
  iconst : (n : Nat) → Int → R (.int n)
  /-- The literal `true`. -/
  bconst : Bool → R .i1
  /-- A `double` literal given by its 64 bits (`0x…`). -/
  dconst : BitVec 64 → R .double
  icmp : Pred → (n : Nat) → R (.int n) → R (.int n) → M (R .i1)
  and : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  xor : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  and1 : R .i1 → R .i1 → M (R .i1)
  or1 : R .i1 → R .i1 → M (R .i1)
  xor1 : R .i1 → R .i1 → M (R .i1)
  select : (n : Nat) → R .i1 → R (.int n) → R (.int n) → M (R (.int n))
  /-- `add`/`sub`/`mul` with optional `nsw` and `nuw` flags. -/
  add : (n : Nat) → Bool → Bool → R (.int n) → R (.int n) → M (R (.int n))
  sub : (n : Nat) → Bool → Bool → R (.int n) → R (.int n) → M (R (.int n))
  mul : (n : Nat) → Bool → Bool → R (.int n) → R (.int n) → M (R (.int n))
  udiv : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  sdiv : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  urem : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  srem : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  shl : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  lshr : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  ashr : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  /-- `zext iN x to iM`, `sext`, `trunc`. -/
  zext : (n m : Nat) → R (.int n) → M (R (.int m))
  sext : (n m : Nat) → R (.int n) → M (R (.int m))
  trunc : (n m : Nat) → R (.int n) → M (R (.int m))
  /-- `zext i1 c to iM`. -/
  zext1 : (m : Nat) → R .i1 → M (R (.int m))
  /-- `@llvm.uadd.sat.iN` and `@llvm.sadd.sat.iN`. -/
  uaddSat : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  saddSat : (n : Nat) → R (.int n) → R (.int n) → M (R (.int n))
  fcmp : FPred → R .double → R .double → M (R .i1)
  /-- `fptosi double x to iM` and `fptoui`. -/
  fptosi : (m : Nat) → R .double → M (R (.int m))
  fptoui : (m : Nat) → R .double → M (R (.int m))
  trapIf : Trap → R .i1 → M Unit

end Arith
