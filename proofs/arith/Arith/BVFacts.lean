import Arith.Basic
import Arith.IntFacts

/-!
# Bit vector facts the signed lowerings need

The signed instructions `sdiv`/`srem` are specified by `BitVec`'s SMT-LIB definitions; these lemmas
tie them to `Int.tdiv`/`Int.tmod` of the two's complement values, and tie the literals the emitter
prints (`-1`, `MIN`) to the bit vectors the model compares with.
-/

namespace Arith

variable {n : Nat}

theorem pow_pred_pos (n : Nat) : (0 : Int) < 2 ^ (n - 1) := by
  have := Nat.two_pow_pos (n - 1)
  exact_mod_cast this

theorem two_pow_eq (hn : 0 < n) : (2 : Int) ^ n = 2 * 2 ^ (n - 1) := by
  obtain ⟨k, rfl⟩ : ∃ k, n = k + 1 := ⟨n - 1, by omega⟩
  simp [Int.pow_succ]; omega

theorem toInt_intMin' (hn : 0 < n) : (BitVec.intMin n).toInt = -(2 : Int) ^ (n - 1) :=
  BitVec.toInt_intMin_of_pos hn

theorem eq_intMin_iff (hn : 0 < n) (a : BitVec n) :
    a = BitVec.intMin n ↔ a.toInt = -(2 : Int) ^ (n - 1) := by
  rw [← toInt_intMin' hn, BitVec.toInt_inj]

theorem toInt_neg_one (hn : 0 < n) : (-1#n).toInt = -1 := by
  rw [BitVec.neg_one_eq_allOnes, BitVec.toInt_allOnes]; simp [hn]

theorem eq_neg_one_iff (hn : 0 < n) (b : BitVec n) : b = -1#n ↔ b.toInt = -1 := by
  rw [← toInt_neg_one hn, BitVec.toInt_inj]

theorem ofInt_neg_one (hn : 0 < n) : BitVec.ofInt n (-1) = -1#n := by
  apply BitVec.eq_of_toInt_eq
  rw [toInt_neg_one hn, BitVec.toInt_ofInt]
  have := two_pow_eq hn
  have : (0 : Int) < 2 ^ (n - 1) := pow_pred_pos n
  apply Int.bmod_eq_of_le <;> push_cast <;> omega

theorem ofInt_intMin (hn : 0 < n) : BitVec.ofInt n (-((2 : Int) ^ (n - 1))) = BitVec.intMin n := by
  apply BitVec.eq_of_toInt_eq
  rw [toInt_intMin' hn, BitVec.toInt_ofInt]
  have := two_pow_eq hn
  have : (0 : Int) < 2 ^ (n - 1) := pow_pred_pos n
  apply Int.bmod_eq_of_le <;> push_cast <;> omega

/-- Two's complement values lie in `[-2^(n-1), 2^(n-1) - 1]`. -/
theorem sbounds (hn : 0 < n) (x : BitVec n) :
    -(2 : Int) ^ (n - 1) ≤ x.toInt ∧ x.toInt ≤ 2 ^ (n - 1) - 1 := by
  have := ival_inRange true hn x
  simpa [inRange, lo, hi, ival_true] using this

theorem ival_eq_toNat {s : Bool} (a : BitVec n) (h : 0 ≤ ival s a) : ival s a = (a.toNat : Int) := by
  cases s
  · rfl
  · simp only [ival_true] at h ⊢
    have hm : a.msb = false := by rw [BitVec.msb_eq_toInt]; simp; omega
    rw [BitVec.toInt_eq_toNat_of_msb hm]

/-- `sdiv` is the truncating quotient of the two's complement values, wrapped to the width. -/
theorem sdiv_eq_ofInt (a b : BitVec n) :
    a.sdiv b = BitVec.ofInt n (Int.tdiv a.toInt b.toInt) := by
  apply BitVec.eq_of_toInt_eq
  rw [BitVec.toInt_sdiv, BitVec.toInt_ofInt]

/-- `srem` is the truncating remainder of the two's complement values (it always fits). -/
theorem srem_eq_ofInt (hn : 0 < n) (a b : BitVec n) (hb : b ≠ 0#n) :
    a.srem b = BitVec.ofInt n (Int.tmod a.toInt b.toInt) := by
  apply BitVec.eq_of_toInt_eq
  rw [BitVec.toInt_srem, BitVec.toInt_ofInt]
  have hy0 : b.toInt ≠ 0 := by rw [Ne, ← ival_true, ival_eq_zero]; exact hb
  have hb1 := ival_inRange true hn b
  have h2 := two_pow_eq hn
  have := pow_pred_pos n
  have hr := tmod_range (M := 2 ^ (n - 1)) (x := a.toInt) (by simp [inRange, lo, hi, ival_true] at hb1; omega)
    (by simp [inRange, lo, hi, ival_true] at hb1; omega) hy0
  symm; apply Int.bmod_eq_of_le <;> push_cast <;> omega

/-- The sign bit of a bit vector is the sign of its two's complement value. -/
theorem slt_zero_iff (x : BitVec n) : x.slt 0#n = decide (x.toInt < 0) := by
  rw [← BitVec.msb_eq_toInt]
  apply Bool.eq_iff_iff.2
  simp [BitVec.slt_zero_iff_msb_cond]

end Arith
