import Lean
import Facts.Connect
import Facts.Census
import Facts.Theorem
import Facts.Chain
import Facts.ChainLink

/-!
# Axiom audit

`#assert_axioms c₁ c₂ …` fails the build unless each constant depends only on Lean's three standard axioms,
`propext`, `Classical.choice` and `Quot.sound`. A `sorry` (`sorryAx`) and the axiom of `native_decide`
(`Lean.ofReduceBool`) are both refused. The development declares no `axiom` of its own; `AXIOMS.md` says what the
theorems assume instead.
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

namespace Facts

#assert_axioms
  -- the headline theorems (design section 7)
  fact_certificates_sound entry_inv reach_inv step_inv stated_intervals no_dead_entered proven_never_ub entry_args
  -- the link to the emitter's lowering proofs (C8)
  proven_row_facts lower_div lower_shift lower_convert lower_arith
  -- the pieces
  init_inv enter_inv inst_step_inv inst_valok inst_lst phi_lst init_lst phi_valok counter_enter
  factHolds_of_deriv deriveList_inst_sound joinLists_sound listPush_sound listSet_sound recordMake_sound
  view_sound operandSound_inv derive_contains
  -- groundwork for the reductions
  chain_sound operand_at eval_addsub chain_lo chain_hi chain_next counter_enter_x counted_preds_ne tripBound_spec
  counted_dom_latch phi_edge_index jEdges_spec jGrowth_phi chainProvedB_sound
  -- empty intervals (design change 15) and the counter's start
  operand_eq_raw emptyView_false ruleVacuous_false partsVacuous_false ub_reads_ints rowFacts_of_not_reads
  counter_start_next
  -- the checker is a function, so its verdict is computed
  checkModule

end Facts
