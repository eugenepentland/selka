import Arith.Spec
import Arith.BVFacts
import Arith.Convert

/-!
# `float_to_int`

With `check = exact` the emitter tests the double against two constants and traps when the test
fails; the converting instruction (`fptosi`/`fptoui`) follows. Both constants are doubles:

* the lower one is `lo - 1.0` (exclusive) when that is a double, i.e. for every width below 64;
  for `i64`, `lo - 1.0` rounds back to `lo`, so the test is inclusive (`oge`) against `lo` itself;
* the upper one is `hi + 1` (`2^(w-1)` or `2^w`), exclusive.

A truncated value fits iff it is above `lo - 1` and below `hi + 1`; an ordered comparison with NaN
is false, so NaN fails the test and traps. The proof is over the float model of F64.lean; the
hypotheses `hA`, `hH` say the printed hexadecimal constants decode to those integers (checked by
`decide` for the eight types at the end of this file), and `Valid x` says `x` is a real binary64
number.
-/

namespace Arith

/-- For a positive denominator, a strict lower bound `a < p/q` with `a < 0` is a lower bound on
the truncated quotient. -/
theorem lower_iff {a p q : Int} (hq : 0 < q) (ha : a < 0) :
    a * q < p ↔ a + 1 ≤ Int.tdiv p q := by
  by_cases hp : 0 ≤ p
  · have h1 : 0 ≤ Int.tdiv p q := Int.tdiv_nonneg hp (Int.le_of_lt hq)
    have h2 : a * q < 0 := Int.mul_neg_of_neg_of_pos ha hq
    constructor <;> intro _ <;> omega
  · have hp' : p < 0 := by omega
    have e : Int.tdiv p q = -((-p) / q) := by
      have h := Int.neg_tdiv (-p) q
      rw [Int.neg_neg] at h
      rw [h, Int.tdiv_eq_ediv_of_nonneg (by omega)]
    rw [e]
    have key := Int.ediv_lt_iff_lt_mul (a := -p) (b := -a) hq
    have e2 : (-a) * q = -(a * q) := Int.neg_mul a q
    constructor
    · intro h
      have h' : (-p) / q < -a := key.2 (by omega)
      omega
    · intro h
      have h' : (-p) / q < -a := by omega
      have := key.1 h'
      omega

/-- For a positive denominator, a strict upper bound `p/q < b` with `b > 0` bounds the truncated
quotient by `b - 1`. -/
theorem upper_iff {b p q : Int} (hq : 0 < q) (hb : 0 < b) :
    p < b * q ↔ Int.tdiv p q ≤ b - 1 := by
  by_cases hp : 0 ≤ p
  · rw [Int.tdiv_eq_ediv_of_nonneg hp]
    have := Int.ediv_lt_iff_lt_mul (a := p) (b := b) hq
    constructor
    · intro h
      have := this.2 h
      omega
    · intro h
      exact this.1 (by omega)
  · have hp' : p < 0 := by omega
    have h1 : Int.tdiv p q ≤ 0 := by
      have e : Int.tdiv p q = -((-p) / q) := by
        have h := Int.neg_tdiv (-p) q
        rw [Int.neg_neg] at h
        rw [h, Int.tdiv_eq_ediv_of_nonneg (by omega)]
      rw [e]
      have : 0 ≤ (-p) / q := Int.ediv_nonneg (by omega) (Int.le_of_lt hq)
      omega
    have h2 : 0 < b * q := Int.mul_pos hb hq
    constructor <;> intro _ <;> omega

theorem isInt_fin {A : F64} {a : Int} (h : A.isInt a = true) :
    ∃ ad : Nat, 0 < ad ∧ A = F64.fin (a * ad) ad := by
  cases A with
  | fin n d =>
    simp only [F64.isInt, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨h1, h2⟩ := h
    exact ⟨d, h1, by rw [h2]⟩
  | nan => simp [F64.isInt] at h
  | negInf => simp [F64.isInt] at h
  | posInf => simp [F64.isInt] at h

theorem mul_cancel_pos {u v c : Int} (hc : 0 < c) : u * c < v * c ↔ u < v := Int.mul_lt_mul_right hc

theorem mul_cancel_eq {u v c : Int} (hc : 0 < c) : u * c = v * c ↔ u = v := by
  constructor
  · intro h
    have h1 : u * c ≤ v * c := by omega
    have h2 : v * c ≤ u * c := by omega
    have := (Int.mul_le_mul_right hc).1 h1
    have := (Int.mul_le_mul_right hc).1 h2
    omega
  · intro h; rw [h]

/-- Comparing a finite double with a constant that is the integer `a`. -/
theorem ogt_fin {p : Int} {q : Nat} {a : Int} {ad : Nat} (had : 0 < ad) :
    F64.ogt (.fin p q) (.fin (a * ad) ad) = decide (a * q < p) := by
  simp only [F64.ogt, F64.lt]
  have e : a * (ad : Int) * q = a * q * ad := by
    rw [Int.mul_assoc, Int.mul_comm (ad : Int) (q : Int), ← Int.mul_assoc]
  rw [e]
  exact decide_eq_decide.2 (mul_cancel_pos (c := (ad : Int)) (by exact_mod_cast had))

theorem olt_fin {p : Int} {q : Nat} {b : Int} {bd : Nat} (hbd : 0 < bd) :
    F64.olt (.fin p q) (.fin (b * bd) bd) = decide (p < b * q) := by
  simp only [F64.olt, F64.lt]
  have e : b * (bd : Int) * q = b * q * bd := by
    rw [Int.mul_assoc, Int.mul_comm (bd : Int) (q : Int), ← Int.mul_assoc]
  rw [e]
  exact decide_eq_decide.2 (mul_cancel_pos (c := (bd : Int)) (by exact_mod_cast hbd))

theorem oge_fin {p : Int} {q : Nat} {a : Int} {ad : Nat} (had : 0 < ad) :
    F64.oge (.fin p q) (.fin (a * ad) ad) = decide (a * q ≤ p) := by
  simp only [F64.oge, F64.lt, F64.eq]
  have e : a * (ad : Int) * q = a * q * ad := by
    rw [Int.mul_assoc, Int.mul_comm (ad : Int) (q : Int), ← Int.mul_assoc]
  rw [e]
  have hc : (0 : Int) < ad := by exact_mod_cast had
  by_cases h : a * q < p
  · have := (mul_cancel_pos hc).2 h
    simp [this]; omega
  · have h' : ¬ a * q * ad < p * ad := fun hh => h ((mul_cancel_pos hc).1 hh)
    by_cases h2 : a * q = p
    · simp [h2]
    · have : ¬ p * ad = a * q * ad := fun hh => h2 ((mul_cancel_eq hc).1 hh.symm)
      simp [h', this]; omega

theorem neg_mul_le_self {c q : Int} (hc : c ≤ 0) (hq : 1 ≤ q) : c * q ≤ c := by
  have := Int.mul_le_mul_of_nonpos_left hc hq
  simpa using this

/-- The two comparisons say exactly that the truncated value lies in the type. -/
theorem fits_iff {m : Nat} (hm : 0 < m) (s inclusive : Bool)
    (hinc : inclusive = true → lo s m ≤ -(2 ^ 53)) (p : Int) (q : Nat) (hq : 0 < q)
    (hv : (q : Nat) = 1 ∨ p.natAbs < 2 ^ 53) :
    ((if inclusive then decide (lo s m * q ≤ p) else decide ((lo s m - 1) * q < p)) &&
        decide (p < (hi s m + 1) * q)) = true ↔ inRange s m (Int.tdiv p q) := by
  have hl := lo_nonpos s m
  have hh := hi_nonneg s hm
  have hq' : (0 : Int) < q := by exact_mod_cast hq
  have hA : (lo s m - 1) * q < p ↔ lo s m ≤ Int.tdiv p q := by
    have := lower_iff (a := lo s m - 1) (p := p) hq' (by omega)
    rw [this]; omega
  have hB : p < (hi s m + 1) * q ↔ Int.tdiv p q ≤ hi s m := by
    have := upper_iff (b := hi s m + 1) (p := p) hq' (by omega)
    rw [this]; omega
  unfold inRange
  cases inclusive
  · simp only [Bool.false_eq_true, ↓reduceIte, Bool.and_eq_true, decide_eq_true_eq]
    rw [hA, hB]
  · have h53 := hinc rfl
    simp only [↓reduceIte, Bool.and_eq_true, decide_eq_true_eq]
    rw [hB]
    have key : lo s m * q ≤ p ↔ (lo s m - 1) * q < p := by
      rcases hv with h1 | h1
      · subst h1; simp; omega
      · have hq1 : (1 : Int) ≤ q := by omega
        have a1 := neg_mul_le_self (c := lo s m) hl hq1
        have a2 := neg_mul_le_self (c := lo s m - 1) (by omega) hq1
        have : (p.natAbs : Int) < 2 ^ 53 := by exact_mod_cast h1
        have h2 : -(p.natAbs : Int) ≤ p := by omega
        constructor <;> intro _ <;> omega
    rw [key, hA]

theorem floatToInt_correct {m : Nat} (hm : 0 < m) (kind : Trap) (s inclusive : Bool) (aboveBits hiBits : BitVec 64)
    (x : F64) (hx : F64.Valid x)
    (hA : (F64.ofBits aboveBits).isInt (if inclusive then lo s m else lo s m - 1) = true)
    (hH : (F64.ofBits hiBits).isInt (hi s m + 1) = true)
    (hinc : inclusive = true → lo s m ≤ -(2 ^ 53)) :
    floatToInt Isa.exec kind s inclusive m aboveBits hiBits x = specFloatToInt kind s m x := by
  obtain ⟨ad, had, hA'⟩ := isInt_fin hA
  obtain ⟨hd, hhd, hH'⟩ := isInt_fin hH
  unfold floatToInt specFloatToInt
  simp only [exec_dconst, hA', hH', exec_fcmp, exec_and1, exec_xor1, exec_bconst, exec_trapIf,
    Exec.bind_ok]
  cases x with
  | nan =>
    cases inclusive <;> simp [FPred.eval, F64.ogt, F64.oge, F64.olt, F64.lt, F64.eq, F64.trunc]
  | negInf =>
    cases inclusive <;> simp [FPred.eval, F64.ogt, F64.oge, F64.olt, F64.lt, F64.eq, F64.trunc]
  | posInf =>
    cases inclusive <;> simp [FPred.eval, F64.ogt, F64.oge, F64.olt, F64.lt, F64.eq, F64.trunc]
  | fin p q =>
    simp only [F64.Valid] at hx
    obtain ⟨hq, hv⟩ := hx
    have hfits := fits_iff hm s inclusive hinc p q hq (by
      rcases hv with h | h
      · exact Or.inl h
      · exact Or.inr h)
    have hq' : 0 < q := hq
    have e1 : ((if inclusive = true then FPred.oge else FPred.ogt).eval (F64.fin p q)
        (F64.fin ((if inclusive = true then lo s m else lo s m - 1) * ad) ad)) =
        (if inclusive then decide (lo s m * q ≤ p) else decide ((lo s m - 1) * q < p)) := by
      cases inclusive <;> simp [FPred.eval, ogt_fin had, oge_fin had]
    have e2 : FPred.olt.eval (F64.fin p q) (F64.fin ((hi s m + 1) * hd) hd) =
        decide (p < (hi s m + 1) * q) := by
      simp [FPred.eval, olt_fin hhd]
    rw [e1, e2]
    by_cases hfit : inRange s m (Int.tdiv p q)
    · have h1 := hfits.2 hfit
      cases s <;> simp [h1, hfit, fpToInt, F64.trunc]
    · have h1 : ¬ ((if inclusive then decide (lo s m * q ≤ p) else decide ((lo s m - 1) * q < p)) &&
          decide (p < (hi s m + 1) * q)) = true := fun h => hfit (hfits.1 h)
      simp only [Bool.not_eq_true] at h1
      simp [h1, hfit, F64.trunc]

/-- `check = proven` (without verification): the bare `fptosi`/`fptoui`. The fact is that the operand
is finite and its truncation fits; then LLVM defines the conversion (no poison) and it is the
specification. -/
theorem floatToIntProven_correct (kind : Trap) (s : Bool) (m : Nat) (x : F64) (t : Int)
    (ht : x.trunc = some t) (hr : inRange s m t) :
    floatToIntProven Isa.exec s m x = specFloatToInt kind s m x := by
  cases s <;> simp [floatToIntProven, fpToInt, specFloatToInt, ht, hr]

/-- `check = proven` for `i64` when the facts put the result in `i32`: `fptosi` to `i32`, then
`sext`. -/
theorem floatToInt64Narrow_correct (kind : Trap) (x : F64) (t : Int) (ht : x.trunc = some t)
    (hr : inRange true 32 t) :
    floatToInt64Narrow Isa.exec x = specFloatToInt kind true 64 x := by
  have h64 : inRange true 64 t := by
    unfold inRange lo hi at hr ⊢
    simp at hr ⊢
    omega
  have hv := ival_ofInt true (by decide : 0 < 32) hr
  simp only [ival_true] at hv
  simp [floatToInt64Narrow, fpToInt, specFloatToInt, ht, hr, h64, signExtend_eq_ofInt (by decide : 0 < 32)
    (by decide : 32 ≤ 64), hv]

/-! ### The constants the emitter prints

`floatToInt` takes the lower and upper bound as bit patterns. These are the eight pairs
`emit_llvm.zig` computes (`lo - 1.0` or `lo`, and `2^(w-1)` or `2^w`, as IEEE binary64) written out,
and the theorem below decodes each with `F64.ofBits` and checks it is the integer the proof needs.
`templates.txt` prints the same patterns from this table, so the Zig test compares the emitter's
constants with them. -/

/-- `(lower bound bits, upper bound bits, lower bound inclusive)` for the target `(signed, width)`. -/
def f2iConsts (s : Bool) (m : Nat) : BitVec 64 × BitVec 64 × Bool :=
  match s, m with
  | true, 8 => (0xC060200000000000#64, 0x4060000000000000#64, false)
  | true, 16 => (0xC0E0002000000000#64, 0x40E0000000000000#64, false)
  | true, 32 => (0xC1E0000000200000#64, 0x41E0000000000000#64, false)
  | true, 64 => (0xC3E0000000000000#64, 0x43E0000000000000#64, true)
  | false, 8 => (0xBFF0000000000000#64, 0x4070000000000000#64, false)
  | false, 16 => (0xBFF0000000000000#64, 0x40F0000000000000#64, false)
  | false, 32 => (0xBFF0000000000000#64, 0x41F0000000000000#64, false)
  | false, 64 => (0xBFF0000000000000#64, 0x43F0000000000000#64, false)
  | _, _ => (0#64, 0#64, false)

/-- Every row of the table decodes to the bounds the proof needs: the lower constant is `lo - 1`
(or `lo`, inclusive, when `lo` is at most `-2^53`, so `lo - 1.0` is not a double) and the upper one
`hi + 1`. -/
theorem f2iConsts_ok (s : Bool) (m : Nat) (hm : m = 8 ∨ m = 16 ∨ m = 32 ∨ m = 64) :
    (F64.ofBits (f2iConsts s m).1).isInt (if (f2iConsts s m).2.2 then lo s m else lo s m - 1) = true ∧
    (F64.ofBits (f2iConsts s m).2.1).isInt (hi s m + 1) = true ∧
    ((f2iConsts s m).2.2 = true → lo s m ≤ -(2 ^ 53)) := by
  rcases hm with rfl | rfl | rfl | rfl <;> cases s <;> decide +kernel

end Arith
