/-!
# Integer facts the transfer rules use

Pure lemmas about multiplication, shifts, division and remainder on `Int`, each the statement that the interval a
rule of design §4 computes contains the exact result.
-/

namespace Facts

/-! ### Products -/

theorem mul_between {a b c d x y : Int} (hx1 : a ≤ x) (hx2 : x ≤ b) (hy1 : c ≤ y) (hy2 : y ≤ d) :
    min (min (a * c) (a * d)) (min (b * c) (b * d)) ≤ x * y ∧
      x * y ≤ max (max (a * c) (a * d)) (max (b * c) (b * d)) := by
  constructor
  · by_cases hy : 0 ≤ y
    · have h1 : a * y ≤ x * y := Int.mul_le_mul_of_nonneg_right hx1 hy
      by_cases ha : 0 ≤ a
      · have h2 : a * c ≤ a * y := Int.mul_le_mul_of_nonneg_left hy1 ha
        omega
      · have h2 : a * d ≤ a * y := Int.mul_le_mul_of_nonpos_left (by omega) hy2
        omega
    · have hy' : y ≤ 0 := by omega
      have h1 : b * y ≤ x * y := Int.mul_le_mul_of_nonpos_right hx2 hy'
      by_cases hb : 0 ≤ b
      · have h2 : b * c ≤ b * y := Int.mul_le_mul_of_nonneg_left hy1 hb
        omega
      · have h2 : b * d ≤ b * y := Int.mul_le_mul_of_nonpos_left (by omega) hy2
        omega
  · by_cases hy : 0 ≤ y
    · have h1 : x * y ≤ b * y := Int.mul_le_mul_of_nonneg_right hx2 hy
      by_cases hb : 0 ≤ b
      · have h2 : b * y ≤ b * d := Int.mul_le_mul_of_nonneg_left hy2 hb
        omega
      · have h2 : b * y ≤ b * c := Int.mul_le_mul_of_nonpos_left (by omega) hy1
        omega
    · have hy' : y ≤ 0 := by omega
      have h1 : x * y ≤ a * y := Int.mul_le_mul_of_nonpos_right hx1 hy'
      by_cases ha : 0 ≤ a
      · have h2 : a * y ≤ a * d := Int.mul_le_mul_of_nonneg_left hy2 ha
        omega
      · have h2 : a * y ≤ a * c := Int.mul_le_mul_of_nonpos_left (by omega) hy1
        omega

/-! ### Shifts -/

theorem two_pow_pos' (t : Nat) : (0 : Int) < ((2 ^ t : Nat) : Int) := by
  have := Nat.two_pow_pos t
  omega

theorem shr_nonneg_step (a : Int) (t : Nat) (h : 0 ≤ a) : 0 ≤ a >>> t ∧ a >>> t ≤ a := by
  rw [Int.shiftRight_eq_div_pow]
  exact ⟨Int.ediv_nonneg h (Int.le_of_lt (two_pow_pos' t)), Int.ediv_le_self _ h⟩

theorem shr_neg_step (a : Int) (t : Nat) (h : a < 0) : a ≤ a >>> t ∧ a >>> t < 0 := by
  rw [Int.shiftRight_eq_div_pow]
  have hd : (1 : Int) ≤ ((2 ^ t : Nat) : Int) := by
    have : 1 ≤ 2 ^ t := Nat.one_le_two_pow
    omega
  constructor
  · apply Int.le_ediv_of_mul_le (by omega)
    have := Int.mul_le_mul_of_nonpos_left (a := a) (b := ((2 ^ t : Nat) : Int)) (c := 1) (by omega) hd
    omega
  · apply Int.ediv_lt_of_lt_mul (by omega)
    omega

theorem shr_between {a : Int} {lo s hi : Nat} (h1 : lo ≤ s) (h2 : s ≤ hi) :
    min (a >>> lo) (a >>> hi) ≤ a >>> s ∧ a >>> s ≤ max (a >>> lo) (a >>> hi) := by
  have e1 : a >>> s = a >>> lo >>> (s - lo) := by
    rw [← Int.shiftRight_add]; congr 1; omega
  have e2 : a >>> hi = a >>> s >>> (hi - s) := by
    rw [← Int.shiftRight_add]; congr 1; omega
  by_cases ha : 0 ≤ a
  · have s1 := shr_nonneg_step (a >>> lo) (s - lo) (shr_nonneg_step a lo ha).1
    have s2 := shr_nonneg_step (a >>> s) (hi - s) (by rw [e1]; exact s1.1)
    omega
  · have ha' : a < 0 := by omega
    have s1 := shr_neg_step (a >>> lo) (s - lo) (shr_neg_step a lo ha').2
    have s2 := shr_neg_step (a >>> s) (hi - s) (by rw [e1]; exact s1.2)
    omega

theorem shr_mono {a b : Int} (h : a ≤ b) (t : Nat) : a >>> t ≤ b >>> t := by
  rw [Int.shiftRight_eq_div_pow, Int.shiftRight_eq_div_pow]
  exact Int.ediv_le_ediv (two_pow_pos' t) h

/-- The interval of a right shift (the validator's `shift_right` row). -/
theorem shr_range {xl xh : Int} {x : Int} {lo hi s : Nat} (hx1 : xl ≤ x) (hx2 : x ≤ xh) (h1 : lo ≤ s) (h2 : s ≤ hi) :
    min (xl >>> lo) (xl >>> hi) ≤ x >>> s ∧ x >>> s ≤ max (xh >>> lo) (xh >>> hi) := by
  have a1 := shr_between (a := xl) h1 h2
  have a2 := shr_between (a := xh) h1 h2
  have m1 := shr_mono hx1 s
  have m2 := shr_mono hx2 s
  omega

/-! ### Division and remainder -/

theorem ediv_anti {a d1 d2 : Int} (ha : 0 ≤ a) (hd1 : 0 < d1) (hd : d1 ≤ d2) : a / d2 ≤ a / d1 := by
  have hd2 : 0 < d2 := by omega
  have h0 : 0 ≤ a / d2 := Int.ediv_nonneg ha (by omega)
  have h1 : a / d2 * d1 ≤ a / d2 * d2 := Int.mul_le_mul_of_nonneg_left hd h0
  have h2 := Int.ediv_mul_le a (show d2 ≠ 0 by omega)
  exact Int.le_ediv_of_mul_le hd1 (by omega)

/-- The interval of a quotient of nonnegative numbers by positive ones. -/
theorem div_range {xl xh dl dh x d : Int} (hxl : 0 ≤ xl) (hdl : 0 < dl) (hx1 : xl ≤ x) (hx2 : x ≤ xh)
    (hd1 : dl ≤ d) (hd2 : d ≤ dh) : xl / dh ≤ x / d ∧ x / d ≤ xh / dl := by
  constructor
  · have a1 : xl / d ≤ x / d := Int.ediv_le_ediv (by omega) hx1
    have a2 : xl / dh ≤ xl / d := ediv_anti hxl (by omega) hd2
    omega
  · have a1 : x / d ≤ xh / d := Int.ediv_le_ediv (by omega) hx2
    have a2 : xh / d ≤ xh / dl := ediv_anti (by omega) hdl hd1
    omega

theorem emod_range {x d : Int} (hx : 0 ≤ x) (hd : 0 < d) : 0 ≤ x % d ∧ x % d < d ∧ x % d ≤ x := by
  refine ⟨Int.emod_nonneg x (by omega), Int.emod_lt_of_pos x hd, ?_⟩
  rw [Int.emod_def]
  have : 0 ≤ d * (x / d) := Int.mul_nonneg (by omega) (Int.ediv_nonneg hx (by omega))
  omega

end Facts
