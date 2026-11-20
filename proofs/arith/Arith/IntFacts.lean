/-!
# Facts about `Int` division

Truncating (`tdiv`, `tmod`) and flooring (`fdiv`, `fmod`) division of integers in the range
`[-M, M - 1]` (two's complement of width `n`, `M = 2^(n-1)`): when the quotient fits, the
relation between the two roundings, and the sign test the emitter uses to switch from one to the
other.
-/

namespace Arith

/-- Whether the signs of the truncated remainder and of the divisor differ with a nonzero
remainder: the condition under which flooring rounds one lower than truncation. -/
def needsFix (x y : Int) : Prop :=
  Int.tmod x y ≠ 0 ∧ ((Int.tmod x y < 0) ↔ ¬ (y < 0))

instance (x y : Int) : Decidable (needsFix x y) := inferInstanceAs (Decidable (_ ∧ _))

theorem tmod_neg_iff {x y : Int} (hd : ¬ y ∣ x) : Int.tmod x y < 0 ↔ x < 0 := by
  have hs : Int.sign (Int.tmod x y) = Int.sign x := by rw [Int.sign_tmod]; simp [hd]
  have h1 := Int.sign_eq_neg_one_iff_neg (a := Int.tmod x y)
  have h2 := Int.sign_eq_neg_one_iff_neg (a := x)
  rw [← h1, ← h2, hs]

theorem fdiv_eq_tdiv_fix {x y : Int} (hy : y ≠ 0) :
    Int.fdiv x y = Int.tdiv x y - (if needsFix x y then 1 else 0) := by
  by_cases hd : y ∣ x
  · have h0 : Int.tmod x y = 0 := Int.tmod_eq_zero_of_dvd hd
    simp [Int.fdiv_eq_tdiv, hd, needsFix, h0]
  · have hne : Int.tmod x y ≠ 0 := fun h => hd (Int.dvd_of_tmod_eq_zero h)
    have hlt := tmod_neg_iff hd
    have hsy : (0 < y → y.sign = 1) ∧ (y < 0 → y.sign = -1) :=
      ⟨Int.sign_eq_one_of_pos, Int.sign_eq_neg_one_of_neg⟩
    rw [Int.fdiv_eq_tdiv]
    simp only [hd, needsFix, hne, ne_eq, not_false_eq_true, true_and, ↓reduceIte, hlt]
    have hy2 : 0 < y ∨ y < 0 := by omega
    by_cases hx : x < 0 <;> by_cases hy' : y < 0 <;> simp [hx, hy'] <;> omega

theorem fmod_eq_tmod_fix {x y : Int} (hy : y ≠ 0) :
    Int.fmod x y = Int.tmod x y + (if needsFix x y then y else 0) := by
  by_cases hd : y ∣ x
  · have h0 : Int.tmod x y = 0 := Int.tmod_eq_zero_of_dvd hd
    simp [Int.fmod_eq_tmod, hd, needsFix, h0]
  · have hne : Int.tmod x y ≠ 0 := fun h => hd (Int.dvd_of_tmod_eq_zero h)
    have hlt := tmod_neg_iff hd
    rw [Int.fmod_eq_tmod]
    simp only [hd, needsFix, hne, ne_eq, not_false_eq_true, true_and, ↓reduceIte, hlt]
    have hy2 : 0 < y ∨ y < 0 := by omega
    by_cases hx : x < 0 <;> by_cases hy' : y < 0 <;> simp [hx, hy'] <;> omega

section Ranges
variable {M x y : Int}

theorem tdiv_range (hx1 : -M ≤ x) (hx2 : x ≤ M - 1) (hy1 : -M ≤ y) (hy2 : y ≤ M - 1)
    (hy0 : y ≠ 0) (hnot : ¬ (x = -M ∧ y = -1)) : -M ≤ Int.tdiv x y ∧ Int.tdiv x y ≤ M - 1 := by
  by_cases h1 : y = 1
  · subst h1; simp; omega
  by_cases h2 : y = -1
  · subst h2
    have : x ≠ -M := fun h => hnot ⟨h, rfl⟩
    have e : Int.tdiv x (-1) = -x := by simp [Int.tdiv_neg]
    rw [e]; omega
  have hy : 2 ≤ y.natAbs := by omega
  have habs : (Int.tdiv x y).natAbs = x.natAbs / y.natAbs := Int.natAbs_tdiv x y
  have hle : x.natAbs / y.natAbs ≤ x.natAbs / 2 := Nat.div_le_div_left hy (by decide)
  omega

theorem tmod_range (hy1 : -M ≤ y) (hy2 : y ≤ M - 1) (hy0 : y ≠ 0) :
    -M ≤ Int.tmod x y ∧ Int.tmod x y ≤ M - 1 := by
  have habs : (Int.tmod x y).natAbs = x.natAbs % y.natAbs := Int.natAbs_tmod x y
  have hlt : x.natAbs % y.natAbs < y.natAbs := Nat.mod_lt _ (by omega)
  omega

theorem fdiv_range (hx1 : -M ≤ x) (hx2 : x ≤ M - 1) (hy1 : -M ≤ y) (hy2 : y ≤ M - 1)
    (hy0 : y ≠ 0) (hnot : ¬ (x = -M ∧ y = -1)) : -M ≤ Int.fdiv x y ∧ Int.fdiv x y ≤ M - 1 := by
  have ht := tdiv_range hx1 hx2 hy1 hy2 hy0 hnot
  rw [fdiv_eq_tdiv_fix hy0]
  by_cases h1 : y = 1
  · subst h1; simp [needsFix]; omega
  by_cases h2 : y = -1
  · subst h2
    have : x ≠ -M := fun h => hnot ⟨h, rfl⟩
    simp [needsFix, Int.tmod_eq_zero_of_dvd]
    omega
  have hy : 2 ≤ y.natAbs := by omega
  have habs : (Int.tdiv x y).natAbs = x.natAbs / y.natAbs := Int.natAbs_tdiv x y
  have hle : x.natAbs / y.natAbs ≤ x.natAbs / 2 := Nat.div_le_div_left hy (by decide)
  split <;> omega

theorem fmod_range (hy1 : -M ≤ y) (hy2 : y ≤ M - 1) (hy0 : y ≠ 0) :
    -M ≤ Int.fmod x y ∧ Int.fmod x y ≤ M - 1 := by
  have h1 := Int.fmod_eq_emod (a := x) (b := y)
  have h2 := Int.emod_nonneg x hy0
  have h3 := Int.emod_lt x hy0
  by_cases hd : y ∣ x
  · have : x % y = 0 := Int.emod_eq_zero_of_dvd hd
    simp [hd] at h1; omega
  · by_cases hp : 0 ≤ y
    · simp [hp] at h1; omega
    · simp [hp, hd] at h1; omega

end Ranges

end Arith
