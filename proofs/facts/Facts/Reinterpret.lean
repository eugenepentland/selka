import Facts.Trans

/-!
# Passing an argument

An argument passed to a parameter of another type keeps its bits; `reinterpret` is the interval the callee sees.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem wrapTo_mem {t : Ty} {lim : Interval} (h : t.range = some lim) (x : Int) : lim.contains (wrapTo t x) := by
  unfold wrapTo
  rw [h]
  simp only []
  have hw : 0 < lim.hi - lim.lo + 1 := by
    obtain ⟨hn, h1, h2⟩ := range_eq_arith h
    rw [h1, h2]
    unfold Arith.lo Arith.hi
    have : (0 : Int) < 2 ^ (t.bits - 1) := by
      have := Nat.two_pow_pos (t.bits - 1)
      exact_mod_cast this
    have h3 : (0 : Int) < 2 ^ t.bits := by
      have := Nat.two_pow_pos t.bits
      exact_mod_cast this
    cases t.signed <;> simp <;> omega
  have a1 := Int.emod_nonneg (x - lim.lo) (show lim.hi - lim.lo + 1 ≠ 0 by omega)
  have a2 := Int.emod_lt_of_pos (x - lim.lo) hw
  exact ⟨by omega, by omega⟩

theorem wrapTo_of_contains {t : Ty} {lim : Interval} (h : t.range = some lim) {x : Int} (hx : lim.contains x) :
    wrapTo t x = x := by
  unfold wrapTo
  rw [h]
  simp only []
  obtain ⟨h1, h2⟩ := hx
  have hw : 0 < lim.hi - lim.lo + 1 := by omega
  have : (x - lim.lo) % (lim.hi - lim.lo + 1) = x - lim.lo := Int.emod_eq_of_lt (by omega) (by omega)
  rw [this]
  omega

theorem pow_half {b : Nat} (hb : 0 < b) : (2 : Int) ^ b = 2 * (2 : Int) ^ (b - 1) := by
  obtain ⟨m, hm⟩ : ∃ m, b = m + 1 := ⟨b - 1, by omega⟩
  rw [hm]; simp [Int.pow_succ]; omega

theorem reshift_sound {to : Ty} {limits r : Interval} {n : Int} (hT : to.range = some limits) (hn : r.contains n)
    (hrng : (to.signed = true → 0 ≤ n ∧ n < (2 : Int) ^ to.bits) ∧
      (to.signed = false → -((2 : Int) ^ (to.bits - 1)) ≤ n ∧ n < (2 : Int) ^ (to.bits - 1))) :
    (reshift r to limits).contains (wrapTo to n) := by
  obtain ⟨hpos, hT1, hT2⟩ := range_eq_arith hT
  have hspan := pow_half hpos
  have hposp : (0 : Int) < 2 ^ (to.bits - 1) := by
    have := Nat.two_pow_pos (to.bits - 1)
    exact_mod_cast this
  unfold reshift
  by_cases hts : to.signed = true
  · have hlo : limits.lo = -((2 : Int) ^ (to.bits - 1)) := by
      rw [hT1]; unfold Arith.lo; simp [hts]
    have hhi : limits.hi = (2 : Int) ^ (to.bits - 1) - 1 := by
      rw [hT2]; unfold Arith.hi; simp [hts]
    simp only [hts, ite_true]
    have hhalf : (2 : Int) ^ to.bits / 2 = 2 ^ (to.bits - 1) := by omega
    rw [hhalf]
    obtain ⟨hn1, hn2⟩ := hn
    obtain ⟨hr1, hr2⟩ := (hrng.1 hts)
    by_cases hge : r.lo ≥ 2 ^ (to.bits - 1)
    · simp only [hge, ite_true]
      have hwr : wrapTo to n = n - 2 ^ to.bits := by
        unfold wrapTo
        rw [hT]
        simp only []
        have hM : limits.hi - limits.lo + 1 = (2 : Int) ^ to.bits := by omega
        rw [hM]
        have hx : (n - limits.lo) % (2 : Int) ^ to.bits = n - limits.lo - 2 ^ to.bits := by
          have h1 : n - limits.lo - 2 ^ to.bits + 2 ^ to.bits * 1 = n - limits.lo := by omega
          have h2 : (n - limits.lo - 2 ^ to.bits) % 2 ^ to.bits = n - limits.lo - 2 ^ to.bits :=
            Int.emod_eq_of_lt (by omega) (by omega)
          calc (n - limits.lo) % (2 : Int) ^ to.bits
              = (n - limits.lo - 2 ^ to.bits + 2 ^ to.bits * 1) % 2 ^ to.bits := by rw [h1]
            _ = (n - limits.lo - 2 ^ to.bits) % 2 ^ to.bits := Int.add_mul_emod_self_left _ _ _
            _ = n - limits.lo - 2 ^ to.bits := h2
        rw [hx]; omega
      rw [hwr]
      show r.lo - 2 ^ to.bits ≤ n - 2 ^ to.bits ∧ n - 2 ^ to.bits ≤ r.hi - 2 ^ to.bits
      omega
    · simp only [hge, ite_false]
      exact wrapTo_mem hT n
  · have hfs : to.signed = false := by simpa using hts
    have hlo : limits.lo = 0 := by
      rw [hT1]; unfold Arith.lo; simp [hfs]
    have hhi : limits.hi = (2 : Int) ^ to.bits - 1 := by
      rw [hT2]; unfold Arith.hi; simp [hfs]
    simp only [hfs, Bool.false_eq_true, ite_false]
    obtain ⟨hn1, hn2⟩ := hn
    obtain ⟨hr1, hr2⟩ := (hrng.2 hfs)
    by_cases hneg : r.hi < 0
    · simp only [hneg, ite_true]
      have hwr : wrapTo to n = n + 2 ^ to.bits := by
        unfold wrapTo
        rw [hT]
        simp only []
        have hM : limits.hi - limits.lo + 1 = (2 : Int) ^ to.bits := by omega
        rw [hM, hlo]
        have hx : (n - 0) % (2 : Int) ^ to.bits = n + 2 ^ to.bits := by
          have h1 : n + 2 ^ to.bits + 2 ^ to.bits * (-1) = n - 0 := by omega
          have h2 : (n + 2 ^ to.bits) % 2 ^ to.bits = n + 2 ^ to.bits :=
            Int.emod_eq_of_lt (by omega) (by omega)
          calc (n - 0) % (2 : Int) ^ to.bits
              = (n + 2 ^ to.bits + 2 ^ to.bits * (-1)) % 2 ^ to.bits := by rw [h1]
            _ = (n + 2 ^ to.bits) % 2 ^ to.bits := Int.add_mul_emod_self_left _ _ _
            _ = n + 2 ^ to.bits := h2
        rw [hx]; omega
      rw [hwr]
      show r.lo + 2 ^ to.bits ≤ n + 2 ^ to.bits ∧ n + 2 ^ to.bits ≤ r.hi + 2 ^ to.bits
      omega
    · simp only [hneg, ite_false]
      exact wrapTo_mem hT n

/-- The interval of an argument as the callee sees it contains the argument reread at the parameter's type. -/
theorem reinterpret_sound {r : Interval} {from_ to : Ty} {n : Int} {limF : Interval} (hn : r.contains n)
    (hF : from_.range = some limF) (hnF : limF.contains n) : (reinterpret r from_ to).contains (wrapTo to n) := by
  unfold reinterpret
  cases hT : to.range with
  | none =>
    simp only []
    unfold wrapTo
    rw [hT]
    exact hn
  | some limT =>
    simp only []
    by_cases hw : r.within limT = true
    · simp only [hw, ite_true]
      have hnT : limT.contains n := within_contains hw hn
      rw [wrapTo_of_contains hT hnT]
      exact hn
    · simp only [hw, ite_false]
      by_cases hb : (from_.bits != to.bits || from_.signed == to.signed) = true
      · simp only [hb, ite_true]
        exact wrapTo_mem hT n
      · simp only [hb, ite_false]
        have hbits : from_.bits = to.bits := by
          by_cases h : from_.bits = to.bits
          · exact h
          · exact absurd (by simp [h]) hb
        have hsign : from_.signed ≠ to.signed := by
          intro h
          exact hb (by simp [h])
        obtain ⟨hpos, hF1, hF2⟩ := range_eq_arith hF
        obtain ⟨hpos2, hT1, hT2⟩ := range_eq_arith hT
        have hspan := pow_half hpos2
        refine reshift_sound hT hn ⟨?_, ?_⟩
        · intro hts
          have hfs : from_.signed = false := by
            cases h : from_.signed
            · rfl
            · exact absurd (by rw [h, hts]) hsign
          have h1 := hnF.1
          have h2 := hnF.2
          rw [hF1, hbits] at h1
          rw [hF2, hbits] at h2
          unfold Arith.lo at h1
          unfold Arith.hi at h2
          rw [hfs] at h1 h2
          simp only [Bool.false_eq_true, ite_false] at h1 h2
          exact ⟨h1, by omega⟩
        · intro hfs
          have hts : from_.signed = true := by
            cases h : from_.signed
            · exact absurd (by rw [h, hfs]) hsign
            · rfl
          have h1 := hnF.1
          have h2 := hnF.2
          rw [hF1, hbits] at h1
          rw [hF2, hbits] at h2
          unfold Arith.lo at h1
          unfold Arith.hi at h2
          rw [hts] at h1 h2
          simp only [ite_true] at h1 h2
          exact ⟨h1, by omega⟩

end Facts
