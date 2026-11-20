import Arith.Spec
import Arith.BVFacts

/-!
# `convert` between integer types

With `check = exact` the emitter tests the source against the target's bounds (only the bounds the
source type can violate) and then moves the bits: `add 0` (equal widths), `sext`/`zext` (wider)
or `trunc` (narrower). The theorems: the checked form is `specConvert`; the unchecked form is the
value reduced modulo `2^wt`; under the `proven` fact (the value is representable) they agree.
-/

namespace Arith

variable {n wf wt : Nat}

theorem slt_ofInt {w : Nat} (hw : 0 < w) (x : BitVec w) (v : Int) (hv : inRange true w v) :
    x.slt (BitVec.ofInt w v) = decide (x.toInt < v) := by
  have h := ival_ofInt true hw hv
  rw [ival_true] at h
  rw [Bool.eq_iff_iff, BitVec.slt_iff_toInt_lt, h]; simp

theorem slt_ofInt' {w : Nat} (hw : 0 < w) (x : BitVec w) (v : Int) (hv : inRange true w v) :
    (BitVec.ofInt w v).slt x = decide (v < x.toInt) := by
  have h := ival_ofInt true hw hv
  rw [ival_true] at h
  rw [Bool.eq_iff_iff, BitVec.slt_iff_toInt_lt, h]; simp

theorem ult_ofInt' {w : Nat} (hw : 0 < w) (x : BitVec w) (v : Int) (hv : inRange false w v) :
    (BitVec.ofInt w v).ult x = decide (v < (x.toNat : Int)) := by
  have := ival_ofInt false hw hv
  rw [ival_false] at this
  rw [Bool.eq_iff_iff, BitVec.ult_iff_toNat_lt]
  simp only [decide_eq_true_eq]; omega

theorem lo_nonpos (s : Bool) (n : Nat) : lo s n ≤ 0 := by
  have := pow_pred_pos n
  cases s <;> simp [lo] <;> omega

theorem hi_nonneg (s : Bool) (hn : 0 < n) : 0 ≤ hi s n := by
  have := pow_pred_pos n
  have := two_pow_eq hn
  cases s <;> simp [hi] <;> omega

theorem convertGuard_correct (hwf : 0 < wf) (hwt : 0 < wt) (sf st : Bool) (kind : Trap)
    (x : BitVec wf) :
    convertGuard Isa.exec sf st wf wt kind x =
      if inRange st wt (ival sf x) then .ok () else .trap kind := by
  have hv := ival_inRange sf hwf x
  have hl := lo_nonpos st wt
  have hh := hi_nonneg st hwt
  have hlf := lo_nonpos sf wf
  have hhf := hi_nonneg sf hwf
  unfold inRange at hv
  unfold convertGuard
  cases sf
  · have h0 : lo false wf = 0 := by simp [lo]
    have hL : ¬ lo false wf < lo st wt := by omega
    by_cases hH : hi st wt < hi false wf
    · have hr : inRange false wf (hi st wt) := by unfold inRange; omega
      have e := ult_ofInt' hwf x _ hr
      simp only [hL, hH, ↓reduceIte, Pred.eval, exec_icmp, exec_iconst, exec_trapIf, Bool.false_eq_true,
        e, Exec.bind_ok]
      by_cases h : hi st wt < (x.toNat : Int)
      · have : ¬ inRange st wt (ival false x) := by unfold inRange; simp only [ival_false]; omega
        simp [h, this]
      · have : inRange st wt (ival false x) := by
          unfold inRange; simp only [ival_false] at *; omega
        simp [h, this]
    · have : inRange st wt (ival false x) := by unfold inRange; omega
      simp [hL, hH, this]
  · by_cases hL : lo true wf < lo st wt
    · have hrl : inRange true wf (lo st wt) := by unfold inRange; omega
      have el := slt_ofInt hwf x _ hrl
      by_cases hH : hi st wt < hi true wf
      · have hrh : inRange true wf (hi st wt) := by unfold inRange; omega
        have eh := slt_ofInt' hwf x _ hrh
        simp only [hL, hH, ↓reduceIte, Pred.eval, exec_icmp, exec_iconst, exec_or1, exec_trapIf,
          Exec.bind_ok, el, eh]
        by_cases h1 : x.toInt < lo st wt <;> by_cases h2 : hi st wt < x.toInt
        · have : ¬ inRange st wt (ival true x) := by unfold inRange; simp only [ival_true]; omega
          simp [h1, h2, this]
        · have : ¬ inRange st wt (ival true x) := by unfold inRange; simp only [ival_true]; omega
          simp [h1, h2, this]
        · have : ¬ inRange st wt (ival true x) := by unfold inRange; simp only [ival_true]; omega
          simp [h1, h2, this]
        · have : inRange st wt (ival true x) := by unfold inRange; simp only [ival_true] at *; omega
          simp [h1, h2, this]
      · simp only [hL, hH, ↓reduceIte, Pred.eval, exec_icmp, exec_iconst, exec_trapIf, el, Exec.bind_ok]
        by_cases h1 : x.toInt < lo st wt
        · have : ¬ inRange st wt (ival true x) := by unfold inRange; simp only [ival_true]; omega
          simp [h1, this]
        · have : inRange st wt (ival true x) := by unfold inRange; simp only [ival_true] at *; omega
          simp [h1, this]
    · by_cases hH : hi st wt < hi true wf
      · have hrh : inRange true wf (hi st wt) := by unfold inRange; omega
        have eh := slt_ofInt' hwf x _ hrh
        simp only [hL, hH, ↓reduceIte, Pred.eval, exec_icmp, exec_iconst, exec_trapIf, eh, Exec.bind_ok]
        by_cases h2 : hi st wt < x.toInt
        · have : ¬ inRange st wt (ival true x) := by unfold inRange; simp only [ival_true]; omega
          simp [h2, this]
        · have : inRange st wt (ival true x) := by unfold inRange; simp only [ival_true] at *; omega
          simp [h2, this]
      · have : inRange st wt (ival true x) := by unfold inRange; omega
        simp [hL, hH, this]

theorem pow_pred_mono {a b : Nat} (h : a ≤ b) : (2 : Int) ^ (a - 1) ≤ 2 ^ (b - 1) := by
  have : (2 : Nat) ^ (a - 1) ≤ 2 ^ (b - 1) := Nat.pow_le_pow_right (by decide) (by omega)
  exact_mod_cast this

theorem signExtend_eq_ofInt (hwf : 0 < wf) (hle : wf ≤ wt) (x : BitVec wf) :
    x.signExtend wt = BitVec.ofInt wt x.toInt := by
  have hwt : 0 < wt := by omega
  obtain ⟨h1, h2⟩ := sbounds hwf x
  have hm := pow_pred_mono hle
  have hr : inRange true wt x.toInt := by unfold inRange; simp only [lo, hi]; simp; omega
  have := ival_ofInt true hwt hr
  rw [ival_true] at this
  apply BitVec.eq_of_toInt_eq
  rw [this, BitVec.toInt_signExtend_of_le hle]

theorem setWidth_eq_ofInt_toNat (hle : wf ≤ wt) (x : BitVec wf) :
    x.setWidth wt = BitVec.ofInt wt (x.toNat : Int) := by
  apply BitVec.eq_of_toNat_eq
  have : x.toNat < 2 ^ wt := Nat.lt_of_lt_of_le x.isLt (Nat.pow_le_pow_right (by decide) hle)
  rw [BitVec.toNat_setWidth, Nat.mod_eq_of_lt this, ofInt_ofNat_toNat this]

theorem setWidth_ofInt_of_le (hle : wt ≤ wf) (v : Int) :
    (BitVec.ofInt wf v).setWidth wt = BitVec.ofInt wt v := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_setWidth, BitVec.toNat_ofInt, BitVec.toNat_ofInt]
  have hd : ((2 ^ wt : Nat) : Int) ∣ ((2 ^ wf : Nat) : Int) := by
    exact_mod_cast Nat.pow_dvd_pow 2 hle
  have hpos := Nat.two_pow_pos wf
  have hnn : 0 ≤ v % ((2 ^ wf : Nat) : Int) := Int.emod_nonneg _ (by omega)
  have := Int.emod_emod_of_dvd v hd
  rw [← this]
  have : ((v % ((2 ^ wf : Nat) : Int)) % ((2 ^ wt : Nat) : Int)).toNat
      = (v % ((2 ^ wf : Nat) : Int)).toNat % 2 ^ wt := by
    have h := Int.toNat_emod hnn (Int.natCast_nonneg (2 ^ wt))
    rw [Int.toNat_natCast] at h
    exact h
  rw [this]

theorem trunc_eq_ofInt (hle : wt ≤ wf) (s : Bool) (x : BitVec wf) :
    x.setWidth wt = BitVec.ofInt wt (ival s x) := by
  have h := setWidth_ofInt_of_le hle (ival s x)
  rw [ofInt_ival] at h
  exact h

theorem convertMove_correct (hwf : 0 < wf) (sf : Bool) (x : BitVec wf) :
    convertMove Isa.exec sf wf wt x = .ok (BitVec.ofInt wt (ival sf x)) := by
  unfold convertMove
  by_cases h : wt = wf
  · subst h
    simp [convertSame, ofInt_ival]
  · by_cases h2 : wf < wt
    · cases sf
      · simp only [h, h2, ↓reduceDIte, ↓reduceIte, convertWiden, Bool.false_eq_true, exec_zext,
          setWidth_eq_ofInt_toNat (Nat.le_of_lt h2), ival_false]
      · simp only [h, h2, ↓reduceDIte, ↓reduceIte, convertWiden, exec_sext,
          signExtend_eq_ofInt hwf (Nat.le_of_lt h2), ival_true]
    · have hle : wt ≤ wf := by omega
      simp only [h, h2, ↓reduceDIte, ↓reduceIte, convertNarrow, exec_trunc, trunc_eq_ofInt hle sf]

/-- `check = exact` (or `proven` verified, `kind = fact`): the specification. -/
theorem convert_exact (hwf : 0 < wf) (hwt : 0 < wt) (sf st : Bool) (kind : Trap) (x : BitVec wf) :
    convert Isa.exec sf st wf wt true kind x = specConvert kind sf st wf wt x := by
  unfold convert specConvert
  by_cases h : inRange st wt (ival sf x)
  · simp [convertGuard_correct hwf hwt, convertMove_correct hwf, h]
  · simp [convertGuard_correct hwf hwt, h]

/-- `check = none`: the value modulo `2^wt` (what the builder asks for when it wants the bits). -/
theorem convert_wrap (hwf : 0 < wf) (sf st : Bool) (kind : Trap) (x : BitVec wf) :
    convert Isa.exec sf st wf wt false kind x = .ok (BitVec.ofInt wt (ival sf x)) := by
  simp [convert, convertMove_correct hwf]

/-- `check = proven`: the fact says the value is representable, and then the bare bit movement is
the specification. -/
theorem convert_proven (hwf : 0 < wf) (sf st : Bool) (kind : Trap) (x : BitVec wf)
    (h : inRange st wt (ival sf x)) :
    convert Isa.exec sf st wf wt false kind x = specConvert kind sf st wf wt x := by
  rw [convert_wrap hwf]
  simp [specConvert, h]

end Arith
