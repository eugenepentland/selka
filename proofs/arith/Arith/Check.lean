import Lean
import Arith.Coverage

/-!
# Axiom audit

`#assert_axioms c₁ c₂ …` fails the build unless each constant depends only on Lean's three
standard axioms, `propext`, `Classical.choice` and `Quot.sound`. A `sorry` (`sorryAx`) and the
axiom of `native_decide` (`Lean.ofReduceBool`) are both refused. The development declares no
`axiom` of its own; see `AXIOMS.md` for what the theorems assume instead.
-/

open Lean Elab Command

/-- Fail unless every named constant depends only on `propext`, `Classical.choice`, `Quot.sound`. -/
elab "#assert_axioms " ids:ident* : command => do
  let allowed : List Name := [``propext, ``Classical.choice, ``Quot.sound]
  for id in ids do
    let name ← liftCoreM <| realizeGlobalConstNoOverloadWithInfo id
    let axioms ← collectAxioms name
    let extra := axioms.toList.filter (· ∉ allowed)
    unless extra.isEmpty do
      throwErrorAt id "{name} depends on the axioms {extra}"

namespace Arith

#assert_axioms
  ival_inRange ival_ofInt ofInt_ival
  divU_correct divSigned_correct divProven_correct divProvenVerified_correct divUNarrow_correct
  specDiv_unsigned specDiv_nonneg specDiv_neg_one
  shift_correct
  uaddSat_eq saddSat_eq saturatingAdd_correct
  convertGuard_correct convertMove_correct convert_exact convert_wrap convert_proven
  floatToInt_correct floatToIntProven_correct floatToInt64Narrow_correct f2iConsts_ok
  F64.ofBits_valid
  divU_w8 divSigned_w8 divProven_w8 divProvenVerified_w8 shift_checked_w8 shift_proven_w8
  saturatingAdd_w8 floatToInt_w8
  divU_w16 divSigned_w16 divProven_w16 divProvenVerified_w16 shift_checked_w16 shift_proven_w16
  saturatingAdd_w16 floatToInt_w16
  divU_w32 divSigned_w32 divProven_w32 divProvenVerified_w32 shift_checked_w32 shift_proven_w32
  saturatingAdd_w32 floatToInt_w32
  divU_w64 divSigned_w64 divProven_w64 divProvenVerified_w64 shift_checked_w64 shift_proven_w64
  saturatingAdd_w64 floatToInt_w64
  convert_exact_w8_w8 convert_exact_w8_w64 convert_exact_w64_w8 convert_exact_w64_w64

end Arith
