import Arith.DivProven
import Arith.Shift
import Arith.SatAdd
import Arith.Convert
import Arith.FloatToInt

/-!
# The theorems at the widths the emitter uses

The theorems of the other files are generic in the width. This file instantiates each at
`8`, `16`, `32` and `64` (the signed type `iN` and the unsigned type `uN` are the two readings of
`ival`), which discharges their side conditions (`0 < n`, `2 ≤ n`) by `decide`. Each statement is the
theorem itself, written out so the width and the signedness are visible.

Naming: `FAMILY_wN`; the family names the formula in `Formulas.lean`.
-/

namespace Arith

section W8

/-- `div`/`rem`/`floor_div`/`floor_rem` on `u8` with the zero test. -/
theorem divU_w8 (k : DivKind) (zc : Bool) (a b : BitVec 8) (hz : zc = false → b ≠ 0#8) :
    divU Isa.exec 8 k.isRem zc a b = specDiv k false 8 a b := divU_correct k zc a b hz

/-- The same four operations on `i8`. -/
theorem divSigned_w8 (k : DivKind) (zc mc : Bool) (a b : BitVec 8) (hz : zc = false → b ≠ 0#8)
    (hm : mc = false → b ≠ -1#8) :
    divSigned Isa.exec 8 k zc mc a b = specDiv k true 8 a b :=
  divSigned_correct (by decide) k zc mc a b hz hm

/-- A `proven` division of `i8` or `u8` (`s` is the signedness) under the fact. -/
theorem divProven_w8 (s : Bool) (k : DivKind) (a b : BitVec 8) (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    divProven Isa.exec 8 k.isRem a b = specDiv k s 8 a b := divProven_correct (by decide) s k a b hx hy

/-- A `proven` division verified under `--verify-facts`. -/
theorem divProvenVerified_w8 (s : Bool) (k : DivKind) (a b : BitVec 8) :
    divProvenVerified Isa.exec 8 s k.isRem a b =
      if ival s a < 0 ∨ ival s b ≤ 0 then .trap .fact else specDiv k s 8 a b :=
  divProvenVerified_correct (by decide) s k a b

/-- `shift_left`/`shift_right` on `i8` or `u8`, checked. -/
theorem shift_checked_w8 (left s : Bool) (a b : BitVec 8) :
    shift Isa.exec 8 left s true .invalidShift a b = specShift .invalidShift left s 8 a b :=
  shift_correct (by decide) left s true .invalidShift a b (by simp)

/-- `shift_left`/`shift_right` with the check removed by the fact `0 <= count < 8`. -/
theorem shift_proven_w8 (left s : Bool) (kind : Trap) (a b : BitVec 8)
    (h : ¬ (ival s b < 0 ∨ (8 : Int) ≤ ival s b)) :
    shift Isa.exec 8 left s false kind a b = specShift kind left s 8 a b :=
  shift_correct (by decide) left s false kind a b (fun _ => h)

/-- `saturating_add` on `i8` or `u8`. -/
theorem saturatingAdd_w8 (s : Bool) (a b : BitVec 8) :
    saturatingAdd Isa.exec 8 s a b = specSatAdd s 8 a b := saturatingAdd_correct (by decide) s a b

/-- `float_to_int` to `i8` or `u8`, checked, with the constants the emitter prints. -/
theorem floatToInt_w8 (s : Bool) (x : F64) (hx : F64.Valid x) :
    floatToInt Isa.exec .floatConversion s (f2iConsts s 8).2.2 8 (f2iConsts s 8).1 (f2iConsts s 8).2.1 x =
      specFloatToInt .floatConversion s 8 x := by
  obtain ⟨hA, hH, hI⟩ := f2iConsts_ok s 8 (by decide)
  exact floatToInt_correct (by decide) .floatConversion s _ _ _ x hx hA hH hI

end W8

section W16

/-- `div`/`rem`/`floor_div`/`floor_rem` on `u16` with the zero test. -/
theorem divU_w16 (k : DivKind) (zc : Bool) (a b : BitVec 16) (hz : zc = false → b ≠ 0#16) :
    divU Isa.exec 16 k.isRem zc a b = specDiv k false 16 a b := divU_correct k zc a b hz

/-- The same four operations on `i16`. -/
theorem divSigned_w16 (k : DivKind) (zc mc : Bool) (a b : BitVec 16) (hz : zc = false → b ≠ 0#16)
    (hm : mc = false → b ≠ -1#16) :
    divSigned Isa.exec 16 k zc mc a b = specDiv k true 16 a b :=
  divSigned_correct (by decide) k zc mc a b hz hm

/-- A `proven` division of `i16` or `u16` (`s` is the signedness) under the fact. -/
theorem divProven_w16 (s : Bool) (k : DivKind) (a b : BitVec 16) (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    divProven Isa.exec 16 k.isRem a b = specDiv k s 16 a b := divProven_correct (by decide) s k a b hx hy

/-- A `proven` division verified under `--verify-facts`. -/
theorem divProvenVerified_w16 (s : Bool) (k : DivKind) (a b : BitVec 16) :
    divProvenVerified Isa.exec 16 s k.isRem a b =
      if ival s a < 0 ∨ ival s b ≤ 0 then .trap .fact else specDiv k s 16 a b :=
  divProvenVerified_correct (by decide) s k a b

/-- `shift_left`/`shift_right` on `i16` or `u16`, checked. -/
theorem shift_checked_w16 (left s : Bool) (a b : BitVec 16) :
    shift Isa.exec 16 left s true .invalidShift a b = specShift .invalidShift left s 16 a b :=
  shift_correct (by decide) left s true .invalidShift a b (by simp)

/-- `shift_left`/`shift_right` with the check removed by the fact `0 <= count < 16`. -/
theorem shift_proven_w16 (left s : Bool) (kind : Trap) (a b : BitVec 16)
    (h : ¬ (ival s b < 0 ∨ (16 : Int) ≤ ival s b)) :
    shift Isa.exec 16 left s false kind a b = specShift kind left s 16 a b :=
  shift_correct (by decide) left s false kind a b (fun _ => h)

/-- `saturating_add` on `i16` or `u16`. -/
theorem saturatingAdd_w16 (s : Bool) (a b : BitVec 16) :
    saturatingAdd Isa.exec 16 s a b = specSatAdd s 16 a b := saturatingAdd_correct (by decide) s a b

/-- `float_to_int` to `i16` or `u16`, checked, with the constants the emitter prints. -/
theorem floatToInt_w16 (s : Bool) (x : F64) (hx : F64.Valid x) :
    floatToInt Isa.exec .floatConversion s (f2iConsts s 16).2.2 16 (f2iConsts s 16).1 (f2iConsts s 16).2.1 x =
      specFloatToInt .floatConversion s 16 x := by
  obtain ⟨hA, hH, hI⟩ := f2iConsts_ok s 16 (by decide)
  exact floatToInt_correct (by decide) .floatConversion s _ _ _ x hx hA hH hI

end W16

section W32

/-- `div`/`rem`/`floor_div`/`floor_rem` on `u32` with the zero test. -/
theorem divU_w32 (k : DivKind) (zc : Bool) (a b : BitVec 32) (hz : zc = false → b ≠ 0#32) :
    divU Isa.exec 32 k.isRem zc a b = specDiv k false 32 a b := divU_correct k zc a b hz

/-- The same four operations on `i32`. -/
theorem divSigned_w32 (k : DivKind) (zc mc : Bool) (a b : BitVec 32) (hz : zc = false → b ≠ 0#32)
    (hm : mc = false → b ≠ -1#32) :
    divSigned Isa.exec 32 k zc mc a b = specDiv k true 32 a b :=
  divSigned_correct (by decide) k zc mc a b hz hm

/-- A `proven` division of `i32` or `u32` (`s` is the signedness) under the fact. -/
theorem divProven_w32 (s : Bool) (k : DivKind) (a b : BitVec 32) (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    divProven Isa.exec 32 k.isRem a b = specDiv k s 32 a b := divProven_correct (by decide) s k a b hx hy

/-- A `proven` division verified under `--verify-facts`. -/
theorem divProvenVerified_w32 (s : Bool) (k : DivKind) (a b : BitVec 32) :
    divProvenVerified Isa.exec 32 s k.isRem a b =
      if ival s a < 0 ∨ ival s b ≤ 0 then .trap .fact else specDiv k s 32 a b :=
  divProvenVerified_correct (by decide) s k a b

/-- `shift_left`/`shift_right` on `i32` or `u32`, checked. -/
theorem shift_checked_w32 (left s : Bool) (a b : BitVec 32) :
    shift Isa.exec 32 left s true .invalidShift a b = specShift .invalidShift left s 32 a b :=
  shift_correct (by decide) left s true .invalidShift a b (by simp)

/-- `shift_left`/`shift_right` with the check removed by the fact `0 <= count < 32`. -/
theorem shift_proven_w32 (left s : Bool) (kind : Trap) (a b : BitVec 32)
    (h : ¬ (ival s b < 0 ∨ (32 : Int) ≤ ival s b)) :
    shift Isa.exec 32 left s false kind a b = specShift kind left s 32 a b :=
  shift_correct (by decide) left s false kind a b (fun _ => h)

/-- `saturating_add` on `i32` or `u32`. -/
theorem saturatingAdd_w32 (s : Bool) (a b : BitVec 32) :
    saturatingAdd Isa.exec 32 s a b = specSatAdd s 32 a b := saturatingAdd_correct (by decide) s a b

/-- `float_to_int` to `i32` or `u32`, checked, with the constants the emitter prints. -/
theorem floatToInt_w32 (s : Bool) (x : F64) (hx : F64.Valid x) :
    floatToInt Isa.exec .floatConversion s (f2iConsts s 32).2.2 32 (f2iConsts s 32).1 (f2iConsts s 32).2.1 x =
      specFloatToInt .floatConversion s 32 x := by
  obtain ⟨hA, hH, hI⟩ := f2iConsts_ok s 32 (by decide)
  exact floatToInt_correct (by decide) .floatConversion s _ _ _ x hx hA hH hI

end W32

section W64

/-- `div`/`rem`/`floor_div`/`floor_rem` on `u64` with the zero test. -/
theorem divU_w64 (k : DivKind) (zc : Bool) (a b : BitVec 64) (hz : zc = false → b ≠ 0#64) :
    divU Isa.exec 64 k.isRem zc a b = specDiv k false 64 a b := divU_correct k zc a b hz

/-- The same four operations on `i64`. -/
theorem divSigned_w64 (k : DivKind) (zc mc : Bool) (a b : BitVec 64) (hz : zc = false → b ≠ 0#64)
    (hm : mc = false → b ≠ -1#64) :
    divSigned Isa.exec 64 k zc mc a b = specDiv k true 64 a b :=
  divSigned_correct (by decide) k zc mc a b hz hm

/-- A `proven` division of `i64` or `u64` (`s` is the signedness) under the fact. -/
theorem divProven_w64 (s : Bool) (k : DivKind) (a b : BitVec 64) (hx : 0 ≤ ival s a) (hy : 0 < ival s b) :
    divProven Isa.exec 64 k.isRem a b = specDiv k s 64 a b := divProven_correct (by decide) s k a b hx hy

/-- A `proven` division verified under `--verify-facts`. -/
theorem divProvenVerified_w64 (s : Bool) (k : DivKind) (a b : BitVec 64) :
    divProvenVerified Isa.exec 64 s k.isRem a b =
      if ival s a < 0 ∨ ival s b ≤ 0 then .trap .fact else specDiv k s 64 a b :=
  divProvenVerified_correct (by decide) s k a b

/-- `shift_left`/`shift_right` on `i64` or `u64`, checked. -/
theorem shift_checked_w64 (left s : Bool) (a b : BitVec 64) :
    shift Isa.exec 64 left s true .invalidShift a b = specShift .invalidShift left s 64 a b :=
  shift_correct (by decide) left s true .invalidShift a b (by simp)

/-- `shift_left`/`shift_right` with the check removed by the fact `0 <= count < 64`. -/
theorem shift_proven_w64 (left s : Bool) (kind : Trap) (a b : BitVec 64)
    (h : ¬ (ival s b < 0 ∨ (64 : Int) ≤ ival s b)) :
    shift Isa.exec 64 left s false kind a b = specShift kind left s 64 a b :=
  shift_correct (by decide) left s false kind a b (fun _ => h)

/-- `saturating_add` on `i64` or `u64`. -/
theorem saturatingAdd_w64 (s : Bool) (a b : BitVec 64) :
    saturatingAdd Isa.exec 64 s a b = specSatAdd s 64 a b := saturatingAdd_correct (by decide) s a b

/-- `float_to_int` to `i64` or `u64`, checked, with the constants the emitter prints. -/
theorem floatToInt_w64 (s : Bool) (x : F64) (hx : F64.Valid x) :
    floatToInt Isa.exec .floatConversion s (f2iConsts s 64).2.2 64 (f2iConsts s 64).1 (f2iConsts s 64).2.1 x =
      specFloatToInt .floatConversion s 64 x := by
  obtain ⟨hA, hH, hI⟩ := f2iConsts_ok s 64 (by decide)
  exact floatToInt_correct (by decide) .floatConversion s _ _ _ x hx hA hH hI

end W64

/-- `convert` from a 8-bit type to a 8-bit type (either signedness), checked. -/
theorem convert_exact_w8_w8 (sf st : Bool) (kind : Trap) (x : BitVec 8) :
    convert Isa.exec sf st 8 8 true kind x = specConvert kind sf st 8 8 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 8-bit type to a 16-bit type (either signedness), checked. -/
theorem convert_exact_w8_w16 (sf st : Bool) (kind : Trap) (x : BitVec 8) :
    convert Isa.exec sf st 8 16 true kind x = specConvert kind sf st 8 16 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 8-bit type to a 32-bit type (either signedness), checked. -/
theorem convert_exact_w8_w32 (sf st : Bool) (kind : Trap) (x : BitVec 8) :
    convert Isa.exec sf st 8 32 true kind x = specConvert kind sf st 8 32 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 8-bit type to a 64-bit type (either signedness), checked. -/
theorem convert_exact_w8_w64 (sf st : Bool) (kind : Trap) (x : BitVec 8) :
    convert Isa.exec sf st 8 64 true kind x = specConvert kind sf st 8 64 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 16-bit type to a 8-bit type (either signedness), checked. -/
theorem convert_exact_w16_w8 (sf st : Bool) (kind : Trap) (x : BitVec 16) :
    convert Isa.exec sf st 16 8 true kind x = specConvert kind sf st 16 8 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 16-bit type to a 16-bit type (either signedness), checked. -/
theorem convert_exact_w16_w16 (sf st : Bool) (kind : Trap) (x : BitVec 16) :
    convert Isa.exec sf st 16 16 true kind x = specConvert kind sf st 16 16 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 16-bit type to a 32-bit type (either signedness), checked. -/
theorem convert_exact_w16_w32 (sf st : Bool) (kind : Trap) (x : BitVec 16) :
    convert Isa.exec sf st 16 32 true kind x = specConvert kind sf st 16 32 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 16-bit type to a 64-bit type (either signedness), checked. -/
theorem convert_exact_w16_w64 (sf st : Bool) (kind : Trap) (x : BitVec 16) :
    convert Isa.exec sf st 16 64 true kind x = specConvert kind sf st 16 64 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 32-bit type to a 8-bit type (either signedness), checked. -/
theorem convert_exact_w32_w8 (sf st : Bool) (kind : Trap) (x : BitVec 32) :
    convert Isa.exec sf st 32 8 true kind x = specConvert kind sf st 32 8 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 32-bit type to a 16-bit type (either signedness), checked. -/
theorem convert_exact_w32_w16 (sf st : Bool) (kind : Trap) (x : BitVec 32) :
    convert Isa.exec sf st 32 16 true kind x = specConvert kind sf st 32 16 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 32-bit type to a 32-bit type (either signedness), checked. -/
theorem convert_exact_w32_w32 (sf st : Bool) (kind : Trap) (x : BitVec 32) :
    convert Isa.exec sf st 32 32 true kind x = specConvert kind sf st 32 32 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 32-bit type to a 64-bit type (either signedness), checked. -/
theorem convert_exact_w32_w64 (sf st : Bool) (kind : Trap) (x : BitVec 32) :
    convert Isa.exec sf st 32 64 true kind x = specConvert kind sf st 32 64 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 64-bit type to a 8-bit type (either signedness), checked. -/
theorem convert_exact_w64_w8 (sf st : Bool) (kind : Trap) (x : BitVec 64) :
    convert Isa.exec sf st 64 8 true kind x = specConvert kind sf st 64 8 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 64-bit type to a 16-bit type (either signedness), checked. -/
theorem convert_exact_w64_w16 (sf st : Bool) (kind : Trap) (x : BitVec 64) :
    convert Isa.exec sf st 64 16 true kind x = specConvert kind sf st 64 16 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 64-bit type to a 32-bit type (either signedness), checked. -/
theorem convert_exact_w64_w32 (sf st : Bool) (kind : Trap) (x : BitVec 64) :
    convert Isa.exec sf st 64 32 true kind x = specConvert kind sf st 64 32 x :=
  convert_exact (by decide) (by decide) sf st kind x

/-- `convert` from a 64-bit type to a 64-bit type (either signedness), checked. -/
theorem convert_exact_w64_w64 (sf st : Bool) (kind : Trap) (x : BitVec 64) :
    convert Isa.exec sf st 64 64 true kind x = specConvert kind sf st 64 64 x :=
  convert_exact (by decide) (by decide) sf st kind x

end Arith
