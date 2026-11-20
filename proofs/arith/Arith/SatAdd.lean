import Arith.Spec
import Arith.BVFacts

/-!
# `saturating_add`

The emitter calls `@llvm.uadd.sat.iN` or `@llvm.sadd.sat.iN` by the type's signedness. The model
gives the intrinsics their hardware definitions (`uaddSatBV`, `saddSatBV`: wrap, detect the
carry/overflow from the operand and result bits, saturate); the theorem proves them equal to
"the exact sum, clamped to the type", for every width.
-/

namespace Arith

variable {n : Nat}

theorem uaddSat_eq (hn : 0 < n) (a b : BitVec n) :
    uaddSatBV a b = BitVec.ofInt n (max (lo false n) (min (hi false n) (ival false a + ival false b))) := by
  have hP : (2 : Int) ^ n = 2 * 2 ^ (n - 1) := two_pow_eq hn
  have ha : (a.toNat : Int) < 2 ^ n := by exact_mod_cast a.isLt
  have hb : (b.toNat : Int) < 2 ^ n := by exact_mod_cast b.isLt
  have hsum : (a + b).toNat = (a.toNat + b.toNat) % 2 ^ n := BitVec.toNat_add a b
  unfold uaddSatBV
  simp only [lo, hi, ival_false, Bool.false_eq_true, ↓reduceIte]
  by_cases hc : a.toNat + b.toNat < 2 ^ n
  · have : (a + b).toNat = a.toNat + b.toNat := by rw [hsum, Nat.mod_eq_of_lt hc]
    have hnot : ¬ (a + b).ult a = true := by
      simp [BitVec.ult]; omega
    have hc' : (a.toNat : Int) + b.toNat < 2 ^ n := by exact_mod_cast hc
    simp only [hnot, Bool.false_eq_true, ↓reduceIte]
    rw [show max (0 : Int) (min (2 ^ n - 1) (a.toNat + b.toNat)) = (a.toNat + b.toNat : Nat) by
      push_cast; omega]
    apply BitVec.eq_of_toNat_eq
    rw [ofInt_ofNat_toNat hc, this]
  · have hc2 : a.toNat + b.toNat < 2 * 2 ^ n := by have := a.isLt; have := b.isLt; omega
    have : (a + b).toNat = a.toNat + b.toNat - 2 ^ n := by
      rw [hsum]
      have : (a.toNat + b.toNat) % 2 ^ n = (a.toNat + b.toNat - 2 ^ n) % 2 ^ n := by
        rw [Nat.mod_eq_sub_mod (by omega)]
      rw [this, Nat.mod_eq_of_lt (by omega)]
    have hlt : (a + b).ult a = true := by
      simp [BitVec.ult]; omega
    have hc' : (a.toNat : Int) + b.toNat ≥ 2 ^ n := by exact_mod_cast (by omega : a.toNat + b.toNat ≥ 2 ^ n)
    simp only [hlt, ↓reduceIte]
    have h1 : 1 ≤ 2 ^ n := Nat.one_le_two_pow
    have h2 : (((2 ^ n - 1 : Nat)) : Int) = (2 : Int) ^ n - 1 := by
      have : ((2 ^ n - 1 : Nat) : Int) + 1 = ((2 ^ n : Nat) : Int) := by omega
      push_cast at this; omega
    rw [show max (0 : Int) (min (2 ^ n - 1) (a.toNat + b.toNat)) = ((2 ^ n - 1 : Nat) : Int) by
      rw [h2]; omega]
    apply BitVec.eq_of_toNat_eq
    rw [ofInt_ofNat_toNat (by have := Nat.one_le_two_pow (n := n); omega)]
    simp

theorem bmod_pow_eq (hn : 0 < n) (S c : Int) (h1 : -(2 : Int) ^ (n - 1) ≤ c) (h2 : c < 2 ^ (n - 1))
    (hd : c - S = 0 ∨ c - S = 2 ^ n ∨ c - S = -(2 ^ n)) : Int.bmod S (2 ^ n) = c := by
  have hP := two_pow_eq hn
  have hM := pow_pred_pos n
  rw [Int.bmod_eq_iff (by have := Nat.two_pow_pos n; exact this)]
  refine ⟨?_, ?_, ?_⟩
  · have : ((2 ^ n : Nat) : Int) / 2 = 2 ^ (n - 1) := by push_cast; omega
    omega
  · have : (((2 ^ n : Nat) : Int) + 1) / 2 = 2 ^ (n - 1) := by push_cast; omega
    omega
  · rcases hd with h | h | h
    · rw [h]; exact Int.dvd_zero _
    · rw [h]; push_cast; exact Int.dvd_refl _
    · rw [h]; push_cast; exact Int.dvd_neg.2 (Int.dvd_refl _)

/-- The wrapped sum read as a signed number: the exact sum, or the exact sum shifted by one period
when it left the range. -/
theorem toInt_add_cases (hn : 0 < n) (a b : BitVec n) :
    ((-(2 : Int) ^ (n - 1) ≤ a.toInt + b.toInt ∧ a.toInt + b.toInt < 2 ^ (n - 1)) →
        (a + b).toInt = a.toInt + b.toInt) ∧
    (2 ^ (n - 1) ≤ a.toInt + b.toInt → (a + b).toInt = a.toInt + b.toInt - 2 ^ n) ∧
    (a.toInt + b.toInt < -(2 : Int) ^ (n - 1) → (a + b).toInt = a.toInt + b.toInt + 2 ^ n) := by
  obtain ⟨h1, h2⟩ := sbounds hn a
  obtain ⟨h3, h4⟩ := sbounds hn b
  have hP := two_pow_eq hn
  rw [BitVec.toInt_add]
  refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩
  · exact bmod_pow_eq hn _ (a.toInt + b.toInt) h.1 h.2 (Or.inl (by omega))
  · exact bmod_pow_eq hn _ (a.toInt + b.toInt - 2 ^ n) (by omega) (by omega) (Or.inr (Or.inr (by omega)))
  · exact bmod_pow_eq hn _ (a.toInt + b.toInt + 2 ^ n) (by omega) (by omega) (Or.inr (Or.inl (by omega)))

theorem saddSat_eq (hn : 0 < n) (a b : BitVec n) :
    saddSatBV a b = BitVec.ofInt n (max (lo true n) (min (hi true n) (ival true a + ival true b))) := by
  obtain ⟨h1, h2⟩ := sbounds hn a
  obtain ⟨h3, h4⟩ := sbounds hn b
  have hP := two_pow_eq hn
  have hM := pow_pred_pos n
  obtain ⟨c1, c2, c3⟩ := toInt_add_cases hn a b
  have ma := BitVec.msb_eq_toInt (x := a)
  have mb := BitVec.msb_eq_toInt (x := b)
  have mr := BitVec.msb_eq_toInt (x := a + b)
  apply BitVec.eq_of_toInt_eq
  rw [BitVec.toInt_ofInt]
  simp only [lo, hi, ival_true, ↓reduceIte]
  rw [Int.bmod_eq_of_le (by push_cast; omega) (by push_cast; omega)]
  unfold saddSatBV
  rcases hma : a.msb with _ | _ <;> rcases hmb : b.msb with _ | _ <;>
    rcases hmr : (a + b).msb with _ | _ <;>
    simp only [hma, hmb, hmr] at ma mb mr ⊢ <;>
    simp [-BitVec.toInt_add, toInt_intMin' hn] at ma mb mr ⊢ <;> omega

theorem saturatingAdd_correct (hn : 0 < n) (s : Bool) (a b : BitVec n) :
    saturatingAdd Isa.exec n s a b = specSatAdd s n a b := by
  cases s
  · simp only [saturatingAdd, specSatAdd, Bool.false_eq_true, ↓reduceIte, exec_uaddSat, uaddSat_eq hn]
  · simp only [saturatingAdd, specSatAdd, ↓reduceIte, exec_saddSat, saddSat_eq hn]

end Arith
