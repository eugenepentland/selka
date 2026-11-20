import Arith.Exec
import Arith.Formulas

/-!
# The operations' specifications

What the language says each operation computes, on mathematical integers (`Int`), together with
when it traps. A specification is an `Exec` outcome (`ok r` or `trap k`) so the theorems read
`formula … = spec …`: the lowering gives exactly the specified result, traps exactly when and as
the specification says, and, since it is an equality with `ok`/`trap`, never `ub` or `poison`.
-/

namespace Arith

/-- The exact mathematical result of the four division-like operations on integers
(the divisor is nonzero where it matters): truncation, remainder of truncation, floor, floor
remainder. -/
def divRes : DivKind → Int → Int → Int
  | .div, x, y => Int.tdiv x y
  | .rem, x, y => Int.tmod x y
  | .floorDiv, x, y => Int.fdiv x y
  | .floorRem, x, y => Int.fmod x y

/-- `div`/`rem` (round toward zero, `divtrunc`/`remtrunc`) and `floor_div`/`floor_rem` (round toward
negative infinity, Python's `//` and `%`) on the type `(s, n)`: a zero divisor traps with
`division_by_zero`, a result outside the type (`MIN // -1`) with `overflow`, otherwise the exact
mathematical result. A remainder always fits, so `MIN % -1` is `0`. -/
def specDiv (k : DivKind) (s : Bool) (n : Nat) (a b : BitVec n) : Exec (BitVec n) :=
  if ival s b = 0 then .trap .divisionByZero
  else if inRange s n (divRes k (ival s a) (ival s b)) then
    .ok (BitVec.ofInt n (divRes k (ival s a) (ival s b)))
  else .trap .overflow

/-- `shift_left(a, c)` and `shift_right(a, c)` on the type `(s, n)` (the count has the same type): a
count that is negative or at least the width traps with `kind` (`invalid_shift`, or `fact` for a
verified `proven` shift); otherwise a left shift is the product with `2^c` with the high bits
discarded (reduction modulo `2^n`), and a right shift the quotient by `2^c` rounded down
(arithmetic for a signed type, logical for an unsigned one). -/
def specShift (kind : Trap) (left s : Bool) (n : Nat) (a c : BitVec n) : Exec (BitVec n) :=
  if ival s c < 0 ∨ (n : Int) ≤ ival s c then .trap kind
  else if left then .ok (BitVec.ofInt n (ival s a * 2 ^ (ival s c).toNat))
  else .ok (BitVec.ofInt n (ival s a / 2 ^ (ival s c).toNat))

/-- `saturating_add(a, b)` on the type `(s, n)`: the exact sum, clamped to the type's bounds. It
never traps. -/
def specSatAdd (s : Bool) (n : Nat) (a b : BitVec n) : Exec (BitVec n) :=
  .ok (BitVec.ofInt n (max (lo s n) (min (hi s n) (ival s a + ival s b))))

/-- `convert` (a cast between integer types, `i8(x)`, `u64(x)`, …) of a source of type `(sf, wf)` to
`(st, wt)`: the value is kept, and a value the target cannot represent traps with `kind` (`cast`,
or `fact` for a verified `proven` conversion). -/
def specConvert (kind : Trap) (sf st : Bool) (wf wt : Nat) (x : BitVec wf) : Exec (BitVec wt) :=
  if inRange st wt (ival sf x) then .ok (BitVec.ofInt wt (ival sf x)) else .trap kind

/-- `float_to_int` (`i8(x)` … `u64(x)` of a float): the value is truncated toward zero and must fit
the target; NaN, either infinity and a truncation outside the type trap (`kind` is
`float_conversion`, or `fact` for a verified `proven` conversion). -/
def specFloatToInt (kind : Trap) (s : Bool) (m : Nat) (x : F64) : Exec (BitVec m) :=
  match x.trunc with
  | some t => if inRange s m t then .ok (BitVec.ofInt m t) else .trap kind
  | none => .trap kind

end Arith
