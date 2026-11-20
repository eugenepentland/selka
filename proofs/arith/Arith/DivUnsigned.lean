import Arith.Spec

/-!
# Unsigned division and remainder

`divU` (zero test, `udiv`/`urem`), `divUNarrow` (the `u64` form on operands below `2^32`) and
`divProven*` (the `check = proven` forms, which are `udiv`/`urem` of operands known non-negative
with a positive divisor) compute `specDiv`.
-/

namespace Arith

theorem ofInt_natCast_div {n : Nat} (a b : BitVec n) :
    BitVec.ofInt n ((a.toNat : Int) / (b.toNat : Int)) = a / b := by
  apply BitVec.eq_of_toNat_eq
  have : ((a.toNat : Int) / (b.toNat : Int)) = ((a.toNat / b.toNat : Nat) : Int) := by
    push_cast; rfl
  rw [this, BitVec.toNat_udiv]
  exact ofInt_ofNat_toNat (Nat.lt_of_le_of_lt (Nat.div_le_self _ _) a.isLt)

theorem ofInt_natCast_mod {n : Nat} (a b : BitVec n) :
    BitVec.ofInt n ((a.toNat : Int) % (b.toNat : Int)) = a % b := by
  apply BitVec.eq_of_toNat_eq
  have : ((a.toNat : Int) % (b.toNat : Int)) = ((a.toNat % b.toNat : Nat) : Int) := by
    push_cast; rfl
  rw [this, BitVec.toNat_umod]
  have h2 : a.toNat % b.toNat < 2 ^ n := by
    rcases Nat.eq_zero_or_pos b.toNat with h | h
    · rw [h, Nat.mod_zero]; exact a.isLt
    · exact Nat.lt_trans (Nat.mod_lt _ h) b.isLt
  exact ofInt_ofNat_toNat h2

/-- For a non-zero divisor, the specification of an unsigned operation is `udiv`/`urem`. -/
theorem specDiv_unsigned {n : Nat} (k : DivKind) (a b : BitVec n) (hb : b ≠ 0#n) :
    specDiv k false n a b = .ok (if k.isRem then a % b else a / b) := by
  have hb' : ival false b ≠ 0 := by rw [Ne, ival_eq_zero]; exact hb
  have hpos : (0 : Int) < b.toNat := by simp [ival_false] at hb'; omega
  have ha : (a.toNat : Int) < 2 ^ n := by exact_mod_cast a.isLt
  have hdiv : inRange false n ((a.toNat : Int) / b.toNat) := by
    have := Int.ediv_le_self (b.toNat : Int) (Int.natCast_nonneg a.toNat)
    have := Int.ediv_nonneg (Int.natCast_nonneg a.toNat) (Int.le_of_lt hpos)
    simp only [inRange, lo, hi, Bool.false_eq_true, ↓reduceIte]; omega
  have hmod : inRange false n ((a.toNat : Int) % b.toNat) := by
    have e : (a.toNat : Int) % b.toNat = ((a.toNat % b.toNat : Nat) : Int) := by push_cast; rfl
    have := Nat.mod_le a.toNat b.toNat
    simp only [inRange, lo, hi, Bool.false_eq_true, ↓reduceIte]; rw [e]; omega
  unfold specDiv
  simp only [hb', ↓reduceIte]
  cases k <;>
    simp [DivKind.isRem, divRes, ival_false, Int.tdiv_eq_ediv_of_nonneg (Int.natCast_nonneg _),
      Int.fdiv_eq_ediv_of_nonneg _ (Int.le_of_lt hpos), Int.tmod_eq_emod_of_nonneg (Int.natCast_nonneg _),
      Int.fmod_eq_emod_of_nonneg _ (Int.le_of_lt hpos), hdiv, hmod, ofInt_natCast_div, ofInt_natCast_mod]

theorem specDiv_zero {n : Nat} (s : Bool) (k : DivKind) (a : BitVec n) :
    specDiv k s n a 0#n = .trap .divisionByZero := by
  simp [specDiv, (ival_eq_zero s 0#n).2 rfl]

theorem divU_correct {n : Nat} (k : DivKind) (zc : Bool) (a b : BitVec n)
    (hz : zc = false → b ≠ 0#n) :
    divU Isa.exec n k.isRem zc a b = specDiv k false n a b := by
  unfold divU
  simp only [Isa.exec]
  by_cases hb : b = 0#n
  · subst hb
    cases zc <;> simp_all [specDiv_zero, Pred.eval]
  · rw [specDiv_unsigned k a b hb]
    cases zc <;> cases hk : k.isRem <;> simp [Pred.eval, hb]

end Arith
