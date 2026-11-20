import Lean
import Cache.Theorem
import Cache.Stamp
import Cache.Seal
import Cache.Admit
import Cache.Plan

/-!
# Axiom audit

`#assert_axioms c₁ c₂ …` fails the build unless each constant depends only on Lean's three standard axioms,
`propext`, `Classical.choice` and `Quot.sound`. A `sorry` (`sorryAx`) and the axiom of `native_decide`
(`Lean.ofReduceBool`) are both refused. The development declares no `axiom` of its own; `AXIOMS.md` says what the
theorems assume instead (each is a hypothesis of a theorem, named there).
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

namespace Cache

#assert_axioms
  -- the headline: a warm build equals the clean build
  warm_eq_clean cold_eq_clean build_correct Stable.of_unsettled session_eq_clean session_aux CollisionFree.mono buildStep_spec rebuild_spec check_spec exec_spec inpOk_sound
  -- the clean build exists and is unique
  IsClean.unique IsClean.exists
  -- a step is a function of what it read
  Task.run_congr Task.run_holds
  -- the stat fast path follows from the clock model and the age test; without it there is a counterexample
  FsModel.stable racy_without_age_test
  -- a torn handle writes no record
  consistent_run

namespace Admit

#assert_axioms
  dirty_iff Dirty.of_reach closure_labels_eq admit_sound new_to_old old_to_new match_of_clean

end Admit

namespace Plan

#assert_axioms
  checkDirty_sound reused_iff

end Plan

end Cache
