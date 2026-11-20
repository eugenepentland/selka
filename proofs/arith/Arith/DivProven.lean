import Arith.DivSigned

/-!
# The `proven` and narrowed division forms

* `divProven`: `udiv`/`urem` of operands the facts show non-negative with a positive divisor
  (`facts.zig` `provable`: `x.lo >= 0 and d.lo > 0`), for a signed or an unsigned type. The theorem
  states the fact as its hypothesis: under it the sequence is the specification and never traps.
* `divProvenVerified`: the same under `--verify-facts`, which tests the fact first and traps with
  kind `fact` when it does not hold.
* `divUNarrow`: `u64` division the facts put in `u32`: each operand masked to 32 bits.
-/

namespace Arith

variable {n : Nat}

/-- For a non-negative dividend and a positive divisor the specification is `udiv`/`urem`. -/
theorem specDiv_nonneg (hn : 0 < n) (s : Bool) (k : DivKind) (a b : BitVec n)
    (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    specDiv k s n a b = .ok (if k.isRem then a % b else a / b) := by
  have hbx := ival_eq_toNat (s := s) a hx
  have hby := ival_eq_toNat (s := s) b (Int.le_of_lt hy)
  have hxr := ival_inRange s hn a
  have hpos : (0 : Int) < b.toNat := by omega
  have hdiv : inRange s n ((a.toNat : Int) / b.toNat) := by
    have := Int.ediv_le_self (b.toNat : Int) (Int.natCast_nonneg a.toNat)
    have := Int.ediv_nonneg (Int.natCast_nonneg a.toNat) (Int.le_of_lt hpos)
    simp only [inRange, lo, hi] at hxr ⊢
    cases s <;> simp at hxr ⊢ <;> omega
  have hmod : inRange s n ((a.toNat : Int) % b.toNat) := by
    have e : (a.toNat : Int) % b.toNat = ((a.toNat % b.toNat : Nat) : Int) := by push_cast; rfl
    have := Nat.mod_le a.toNat b.toNat
    simp only [inRange, lo, hi] at hxr ⊢
    rw [e]
    cases s <;> simp at hxr ⊢ <;> omega
  have hne : ival s b ≠ 0 := by omega
  unfold specDiv
  simp only [hne, ↓reduceIte]
  rw [hbx, hby]
  cases k <;>
    simp [DivKind.isRem, divRes, Int.tdiv_eq_ediv_of_nonneg (Int.natCast_nonneg _),
      Int.fdiv_eq_ediv_of_nonneg _ (Int.le_of_lt hpos), Int.tmod_eq_emod_of_nonneg (Int.natCast_nonneg _),
      Int.fmod_eq_emod_of_nonneg _ (Int.le_of_lt hpos), hdiv, hmod, ofInt_natCast_div, ofInt_natCast_mod]

theorem divProven_correct (hn : 0 < n) (s : Bool) (k : DivKind) (a b : BitVec n)
    (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    divProven Isa.exec n k.isRem a b = specDiv k s n a b := by
  have hne : b ≠ 0#n := by
    intro h; have := (ival_eq_zero s b).2 h; omega
  rw [specDiv_nonneg hn s k a b hx hy]
  unfold divProven
  cases hk : k.isRem <;> simp [hne]

theorem slt_zero_true (x : BitVec n) : x.slt 0#n = true ↔ x.toInt < 0 := by
  rw [BitVec.slt_iff_toInt_lt, BitVec.toInt_zero]

theorem sle_zero_true (x : BitVec n) : x.sle 0#n = true ↔ x.toInt ≤ 0 := by
  rw [BitVec.sle_iff_toInt_le, BitVec.toInt_zero]

/-- Under `--verify-facts` a `proven` division tests the fact first: a negative dividend or a
non-positive divisor traps with kind `fact`; otherwise it is the specification. -/
theorem divProvenVerified_correct (hn : 0 < n) (s : Bool) (k : DivKind) (a b : BitVec n) :
    divProvenVerified Isa.exec n s k.isRem a b =
      if ival s a < 0 ∨ ival s b ≤ 0 then .trap .fact else specDiv k s n a b := by
  unfold divProvenVerified
  cases s
  · by_cases hb : b = 0#n
    · subst hb
      simp [Pred.eval, ival_false]
    · have hy : 0 < ival false b := by
        have : ¬ ival false b = 0 := fun h => hb ((ival_eq_zero false b).1 h)
        simp only [ival_false] at this ⊢; omega
      have hx : 0 ≤ ival false a := by simp [ival_false]
      have hy' : ¬ ival false b ≤ 0 := by omega
      have hx' : ¬ ival false a < 0 := by omega
      simp [Pred.eval, hb, hx', hy', ← divProven_correct hn false k a b hx hy]
  · have e : (ival true a < 0 ∨ ival true b ≤ 0) ↔ (a.toInt < 0 ∨ b.toInt ≤ 0) := by simp [ival_true]
    simp [Pred.eval, slt_zero_true, sle_zero_true]
    by_cases h : ival true a < 0 ∨ ival true b ≤ 0
    · simp [h, e.1 h]
    · have hx : 0 ≤ ival true a := by omega
      have hy : 0 < ival true b := by omega
      simp [h, (not_congr e).1 h, ← divProven_correct hn true k a b hx hy]

theorem and_mask32 (a : BitVec 64) (h : a.toNat < 2 ^ 32) : a &&& BitVec.ofInt 64 4294967295 = a := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_and]
  have : (BitVec.ofInt 64 4294967295).toNat = 2 ^ 32 - 1 := by
    rw [BitVec.toNat_ofInt]; decide
  rw [this, Nat.and_two_pow_sub_one_eq_mod, Nat.mod_eq_of_lt h]

/-- Masking operands already below `2^32` changes nothing, so the narrowed `u64` division is the
plain unsigned division. -/
theorem divUNarrow_correct (k : DivKind) (zc : Bool) (a b : BitVec 64)
    (ha : a.toNat < 2 ^ 32) (hb : b.toNat < 2 ^ 32) (hz : zc = false → b ≠ 0#64) :
    divUNarrow Isa.exec k.isRem zc a b = specDiv k false 64 a b := by
  rw [← divU_correct k zc a b hz]
  unfold divUNarrow divU
  simp only [exec_iconst, exec_and, and_mask32 a ha, and_mask32 b hb]
  rfl

end Arith
