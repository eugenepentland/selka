/-!
# A model of IEEE binary64 values

A `double` is NaN, one of the two infinities, or a finite rational `num / den`. Every finite
binary64 number is such a rational (its denominator is a power of two); the model keeps the
rational instead of the 64 bits because the lowering only compares a double with constants,
truncates it toward zero, and converts it to an integer. `F64.ofBits` decodes an actual bit
pattern, so the constants the emitter prints (`0x41E0000000000000`) are tied to numbers.

`Valid` is the one fact about real doubles the proofs need beyond "a rational": a finite value
is an integer (`den = 1`) or has a numerator below `2^53`, so it is smaller than `2^52` in
absolute value. In particular no double lies strictly between `-2^63 - 1` and `-2^63`.
-/

namespace Arith

/-- A binary64 value. NaN carries no payload: the lowering never looks at one. -/
inductive F64 where
  | nan
  | negInf
  | posInf
  /-- The rational `num / den`; `den` is positive for every value `ofBits` produces. -/
  | fin (num : Int) (den : Nat)
  deriving DecidableEq, Repr

namespace F64

/-- Ordered `<` (LLVM `fcmp olt`): false when either operand is NaN. -/
def lt : F64 → F64 → Bool
  | .nan, _ => false
  | _, .nan => false
  | .negInf, .negInf => false
  | .negInf, _ => true
  | _, .negInf => false
  | .posInf, _ => false
  | _, .posInf => true
  | .fin n1 d1, .fin n2 d2 => decide (n1 * (d2 : Int) < n2 * (d1 : Int))

/-- Ordered `==` (LLVM `fcmp oeq`): false when either operand is NaN. -/
def eq : F64 → F64 → Bool
  | .negInf, .negInf => true
  | .posInf, .posInf => true
  | .fin n1 d1, .fin n2 d2 => decide (n1 * (d2 : Int) = n2 * (d1 : Int))
  | _, _ => false

/-- LLVM `fcmp ogt`. -/
def ogt (x y : F64) : Bool := lt y x
/-- LLVM `fcmp oge`. -/
def oge (x y : F64) : Bool := lt y x || eq x y
/-- LLVM `fcmp olt`. -/
def olt (x y : F64) : Bool := lt x y

/-- Truncation toward zero of a finite value; `none` for NaN and the infinities. -/
def trunc : F64 → Option Int
  | .fin n d => some (Int.tdiv n d)
  | _ => none

/-- The model's invariant for real binary64 values: a positive denominator, and an integer or a
numerator below `2^53` (the 53-bit significand). -/
def Valid : F64 → Prop
  | .fin n d => 0 < d ∧ (d = 1 ∨ n.natAbs < 2 ^ 53)
  | _ => True

/-- The finite value `t` (an integer). -/
def ofInt (t : Int) : F64 := .fin t 1

/-- `x` is finite and exactly the integer `t`. -/
def isInt (x : F64) (t : Int) : Bool :=
  match x with
  | .fin n d => decide (0 < d) && decide (n = t * (d : Int))
  | _ => false

/-- The finite value `± m * 2^ex`. -/
def finiteOf (neg : Bool) (m : Nat) (ex : Int) : F64 :=
  let sgn : Int := if neg then -1 else 1
  if 0 ≤ ex then .fin (sgn * (m * 2 ^ ex.toNat : Nat)) 1
  else .fin (sgn * (m : Int)) (2 ^ (-ex).toNat)

/-- Decode a binary64 bit pattern (sign, 11-bit exponent, 52-bit fraction). -/
def ofBits (b : BitVec 64) : F64 :=
  let neg : Bool := b.msb
  let e : Nat := (b.toNat / 2 ^ 52) % 2048
  let f : Nat := b.toNat % 2 ^ 52
  if e = 2047 then
    (if f = 0 then (if neg then .negInf else .posInf) else .nan)
  else
    finiteOf neg (if e = 0 then f else 2 ^ 52 + f) (((if e = 0 then 1 else e : Nat) : Int) - 1075)

theorem finiteOf_valid (neg : Bool) (m : Nat) (ex : Int) (hm : m < 2 ^ 53) :
    Valid (finiteOf neg m ex) := by
  unfold finiteOf
  dsimp only
  split
  · simp [Valid]
  · have : ((if neg = true then (-1 : Int) else 1) * (m : Int)).natAbs < 2 ^ 53 := by
      rw [Int.natAbs_mul]; split <;> simp <;> omega
    exact ⟨Nat.two_pow_pos _, Or.inr this⟩

theorem ofBits_valid (b : BitVec 64) : Valid (ofBits b) := by
  unfold ofBits
  dsimp only
  have hf : b.toNat % 2 ^ 52 < 2 ^ 52 := Nat.mod_lt _ (by decide)
  split
  · split
    · split <;> simp [Valid]
    · simp [Valid]
  · apply finiteOf_valid
    split <;> omega

end F64
end Arith
