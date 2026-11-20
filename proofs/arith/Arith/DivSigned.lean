import Arith.Spec
import Arith.BVFacts
import Arith.DivUnsigned

/-!
# Signed division and remainder

`divSigned` (zero test, `MIN / -1` test, division by `1` instead of `-1`, floor adjustment) computes
`specDiv` for the four operations at every width `n >= 2`.
-/

namespace Arith

variable {n : Nat}

theorem ofInt_sub (n : Nat) (x y : Int) : BitVec.ofInt n (x - y) = BitVec.ofInt n x - BitVec.ofInt n y := by
  rw [Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.sub_eq_add_neg]

theorem ofInt_zero' (n : Nat) : BitVec.ofInt n 0 = 0#n := by simp

theorem ofInt_one' (n : Nat) : BitVec.ofInt n 1 = 1#n := by simp

/-- The result of a division kind lies in the type unless it is the overflowing `MIN / -1`
(`divRes` of a remainder always fits). -/
theorem divRes_inRange (hn : 0 < n) (k : DivKind) (a b : BitVec n) (hb : b ≠ 0#n)
    (hnot : ¬ (a.toInt = -(2 : Int) ^ (n - 1) ∧ b.toInt = -1) ∨ k.isRem = true) :
    inRange true n (divRes k a.toInt b.toInt) := by
  have hy0 : b.toInt ≠ 0 := by rw [← ival_true, Ne, ival_eq_zero]; exact hb
  obtain ⟨hx1, hx2⟩ := sbounds hn a
  obtain ⟨hy1, hy2⟩ := sbounds hn b
  have hM := pow_pred_pos n
  cases k
  · have hnot' : ¬ (a.toInt = -(2 : Int) ^ (n - 1) ∧ b.toInt = -1) := by
      rcases hnot with h | h
      · exact h
      · simp [DivKind.isRem] at h
    have := tdiv_range hx1 hx2 hy1 hy2 hy0 hnot'
    simpa [inRange, lo, hi, divRes] using this
  · have := tmod_range (x := a.toInt) hy1 hy2 hy0
    simpa [inRange, lo, hi, divRes] using this
  · have hnot' : ¬ (a.toInt = -(2 : Int) ^ (n - 1) ∧ b.toInt = -1) := by
      rcases hnot with h | h
      · exact h
      · simp [DivKind.isRem] at h
    have := fdiv_range hx1 hx2 hy1 hy2 hy0 hnot'
    simpa [inRange, lo, hi, divRes] using this
  · have := fmod_range (x := a.toInt) hy1 hy2 hy0
    simpa [inRange, lo, hi, divRes] using this

/-- `MIN / -1` does not fit: the two quotient kinds overflow. -/
theorem divRes_overflow (k : DivKind) (hk : k.isRem = false) (a b : BitVec n)
    (ha : a.toInt = -(2 : Int) ^ (n - 1)) (hb : b.toInt = -1) :
    ¬ inRange true n (divRes k a.toInt b.toInt) := by
  have hM := pow_pred_pos n
  cases k <;> simp [DivKind.isRem] at hk <;>
    simp [inRange, lo, hi, divRes, ha, hb, Int.tdiv_neg, Int.fdiv_neg] <;> omega

theorem fixCond_iff (a b : BitVec n) :
    (¬ a.srem b = 0#n ∧ BitVec.slt (a.srem b ^^^ b) 0#n = true) ↔ needsFix a.toInt b.toInt := by
  have hr : (a.srem b).toInt = Int.tmod a.toInt b.toInt := BitVec.toInt_srem a b
  have h1 : ¬ a.srem b = 0#n ↔ Int.tmod a.toInt b.toInt ≠ 0 := by
    rw [← hr, ← ival_true, Ne, ival_eq_zero]
  have h2 : BitVec.slt (a.srem b ^^^ b) 0#n = true ↔ (Int.tmod a.toInt b.toInt < 0 ↔ ¬ b.toInt < 0) := by
    rw [BitVec.slt_zero_iff_msb_cond, BitVec.msb_xor, BitVec.msb_eq_toInt (x := a.srem b),
      BitVec.msb_eq_toInt (x := b), hr]
    cases h : decide (Int.tmod a.toInt b.toInt < 0) <;> cases h' : decide (b.toInt < 0) <;> simp_all
  unfold needsFix
  rw [h1, h2]

theorem floorAdjust_correct (hn : 2 ≤ n) (isRem : Bool) (a b : BitVec n) (hb : b ≠ 0#n)
    (hnot : ¬ (a = BitVec.intMin n ∧ b = -1#n)) :
    floorAdjust Isa.exec n isRem a b b =
      .ok (BitVec.ofInt n (if isRem then Int.fmod a.toInt b.toInt else Int.fdiv a.toInt b.toInt)) := by
  have hn0 : 0 < n := by omega
  have hy0 : b.toInt ≠ 0 := by rw [← ival_true, Ne, ival_eq_zero]; exact hb
  unfold floorAdjust
  simp only [Isa.exec, hb, hnot, Pred.eval, ofInt_zero', Exec.bind_ok]
  simp [fixCond_iff a b]
  cases isRem
  · simp only [Bool.false_eq_true, ↓reduceIte]
    rw [sdiv_eq_ofInt, fdiv_eq_tdiv_fix hy0]
    by_cases f : needsFix a.toInt b.toInt <;> simp [f, ofInt_sub]
  · simp only [↓reduceIte]
    rw [srem_eq_ofInt hn0 a b hb, fmod_eq_tmod_fix hy0]
    by_cases f : needsFix a.toInt b.toInt <;> simp [f, BitVec.ofInt_add]

theorem one_ne_zero_bv (hn : 2 ≤ n) : (1#n : BitVec n) ≠ 0#n := by
  intro h
  have := congrArg BitVec.toNat h
  simp [Nat.mod_eq_of_lt (show 1 < 2 ^ n from Nat.one_lt_two_pow (by omega))] at this

theorem one_ne_neg_one_bv (hn : 2 ≤ n) : (1#n : BitVec n) ≠ -1#n := by
  intro h
  have := congrArg BitVec.toInt h
  rw [toInt_neg_one (by omega)] at this
  have h1 : (1#n : BitVec n).toInt = 1 := by
    rw [BitVec.toInt_ofNat']
    have : (2 : Int) ^ n ≥ 4 := by
      obtain ⟨k, rfl⟩ : ∃ k, n = k + 2 := ⟨n - 2, by omega⟩
      have : (2 : Int) ^ k ≥ 1 := by exact_mod_cast Nat.one_le_two_pow (n := k)
      rw [Int.pow_add]; omega
    have e : ((1 : Nat) : Int) = 1 := rfl
    rw [e]
    apply Int.bmod_eq_of_le <;> push_cast <;> omega
  omega

/-- With the divisor replaced by `1` (the `b = -1` case), `floorAdjust` computes `a` for the quotient
and `0` for the remainder: the truncated remainder `a % 1` is zero, so nothing is adjusted. -/
theorem floorAdjust_one (hn : 2 ≤ n) (isRem : Bool) (a b : BitVec n) :
    floorAdjust Isa.exec n isRem a b 1#n = .ok (if isRem then 0#n else a) := by
  have h0 := one_ne_zero_bv hn
  have h1 := one_ne_neg_one_bv hn
  unfold floorAdjust
  simp [Isa.exec, h0, h1, Pred.eval]
  cases isRem <;> simp

/-- The truncating or flooring result with the real divisor, away from the overflowing pair. -/
theorem divSignedCore_correct (hn : 2 ≤ n) (k : DivKind) (a b : BitVec n) (hb : b ≠ 0#n)
    (hnot : ¬ (a = BitVec.intMin n ∧ b = -1#n)) :
    divSignedCore Isa.exec n k a b b = .ok (BitVec.ofInt n (divRes k a.toInt b.toInt)) := by
  have hn0 : 0 < n := by omega
  cases k
  · simp [divSignedCore, Isa.exec, hb, hnot, sdiv_eq_ofInt, divRes]
  · simp [divSignedCore, Isa.exec, hb, hnot, srem_eq_ofInt hn0 a b hb, divRes]
  · simp [divSignedCore, floorAdjust_correct hn false a b hb hnot, divRes]
  · simp [divSignedCore, floorAdjust_correct hn true a b hb hnot, divRes]

theorem divRes_neg_one (k : DivKind) (x : Int) :
    divRes k x (-1) = if k.isRem then 0 else -x := by
  have h1 : Int.tdiv x (-1) = -x := by simp [Int.tdiv_neg]
  have h2 : Int.tmod x (-1) = 0 := by simp
  have hneedsFix : ¬ needsFix x (-1) := by simp [needsFix, h2]
  cases k
  · simp [divRes, h1, DivKind.isRem]
  · simp [divRes, h2, DivKind.isRem]
  · simp [divRes, fdiv_eq_tdiv_fix (x := x) (y := -1) (by decide), hneedsFix, h1, DivKind.isRem]
  · simp [divRes, fmod_eq_tmod_fix (x := x) (y := -1) (by decide), hneedsFix, h2, DivKind.isRem]

theorem specDiv_neg_one (hn : 0 < n) (k : DivKind) (a : BitVec n) :
    specDiv k true n a (-1#n) =
      if k.isRem then .ok 0#n
      else if a = BitVec.intMin n then .trap .overflow else .ok (-a) := by
  have hM := pow_pred_pos n
  have hy : ival true (-1#n) = -1 := by rw [ival_true, toInt_neg_one hn]
  unfold specDiv
  rw [hy]
  simp only [show ((-1 : Int) = 0) = False by decide, ↓reduceIte, divRes_neg_one]
  obtain ⟨hx1, hx2⟩ := sbounds hn a
  by_cases hk : k.isRem = true
  · simp [hk, inRange, lo, hi]; omega
  · have hk' : k.isRem = false := by simpa using hk
    simp only [hk', Bool.false_eq_true, ↓reduceIte, ival_true]
    by_cases ha : a = BitVec.intMin n
    · have : a.toInt = -(2 : Int) ^ (n - 1) := (eq_intMin_iff hn a).1 ha
      have hr : ¬ inRange true n (-a.toInt) := by simp [inRange, lo, hi, this]; omega
      simp only [hr, ↓reduceIte]
      simp only [ha, ↓reduceIte]
    · have : a.toInt ≠ -(2 : Int) ^ (n - 1) := fun h => ha ((eq_intMin_iff hn a).2 h)
      have hr : inRange true n (-a.toInt) := by simp [inRange, lo, hi]; omega
      simp [ha, hr, BitVec.ofInt_neg]


theorem divSigned_correct (hn : 2 ≤ n) (k : DivKind) (zc mc : Bool) (a b : BitVec n)
    (hz : zc = false → b ≠ 0#n) (hm : mc = false → b ≠ -1#n) :
    divSigned Isa.exec n k zc mc a b = specDiv k true n a b := by
  have hn0 : 0 < n := by omega
  by_cases hb0 : b = 0#n
  · have hzc : zc = true := by
      cases h : zc
      · exact absurd hb0 (hz h)
      · rfl
    subst hzc
    simp [divSigned, Pred.eval, hb0, specDiv_zero]
  by_cases hb1 : b = -1#n
  · have hmc : mc = true := by
      cases h : mc
      · exact absurd hb1 (hm h)
      · rfl
    subst hmc
    subst hb1
    have hne := one_ne_neg_one_bv hn
    have h1 := one_ne_zero_bv hn
    rw [specDiv_neg_one hn0]
    unfold divSigned
    cases k <;> cases zc <;>
      simp [Pred.eval, divSignedCore, floorAdjust_one hn, h1, hne, ofInt_intMin hn0,
        ofInt_neg_one hn0, DivKind.isRem, hb0] <;>
      (by_cases h : a = BitVec.intMin n <;> simp [h])
  · have hy0 : b.toInt ≠ 0 := by rw [← ival_true, Ne, ival_eq_zero]; exact hb0
    have hnot : ¬ (a = BitVec.intMin n ∧ b = -1#n) := fun h => hb1 h.2
    have hok := divSignedCore_correct hn k a b hb0 hnot
    have hr : inRange true n (divRes k a.toInt b.toInt) :=
      divRes_inRange hn0 k a b hb0 (Or.inl (fun h => hb1 ((eq_neg_one_iff hn0 b).2 h.2)))
    have hspec : specDiv k true n a b = .ok (BitVec.ofInt n (divRes k a.toInt b.toInt)) := by
      simp [specDiv, ival_true, hy0, hr]
    rw [hspec]
    unfold divSigned
    cases zc <;> cases mc <;> cases hk : k.isRem <;>
      simp [Pred.eval, hok, hb0, hb1, ofInt_neg_one hn0]

end Arith
