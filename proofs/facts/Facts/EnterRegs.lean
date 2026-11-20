import Facts.Sem
import Facts.Wf

/-!
# Entering a block

`enterRegs` copies each phi's operand for the edge taken. This file states what that does to the register file:
nothing to values that are not phis of the block, and the old value of the operand to each phi.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem foldl_phiStep_other (r : Regs) (from_ : Nat) {w : Nat} :
    ∀ (ps : List Phi) (acc : Regs), (∀ p ∈ ps, p.value ≠ w) → ps.foldl (phiStep r from_) acc w = acc w := by
  intro ps
  induction ps with
  | nil => intro acc _; rfl
  | cons q rest ih =>
    intro acc h
    simp only [List.foldl_cons]
    rw [ih _ (fun p hp => h p (List.mem_cons_of_mem _ hp))]
    unfold phiStep
    cases phiNew r from_ q with
    | none => rfl
    | some v =>
      simp only []
      exact Regs.set_ne _ _ (fun e => h q (List.mem_cons_self ..) e.symm)

theorem foldl_phiStep_mem (r : Regs) (from_ : Nat) :
    ∀ (ps : List Phi) (acc : Regs), (ps.map (·.value)).Nodup → ∀ p ∈ ps,
      ps.foldl (phiStep r from_) acc p.value = (match phiNew r from_ p with | some v => some v | none => acc p.value) := by
  intro ps
  induction ps with
  | nil => intro _ _ p hp; cases hp
  | cons q rest ih =>
    intro acc hnd p hp
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hnd
    obtain ⟨hnotin, hrest⟩ := hnd
    simp only [List.foldl_cons]
    rcases List.mem_cons.mp hp with hpq | hpr
    · subst hpq
      rw [foldl_phiStep_other r from_ rest _ (fun p' hp' e => hnotin ⟨p', hp', e⟩)]
      unfold phiStep
      cases hn : phiNew r from_ p with
      | none => rfl
      | some v => simp [Regs.set]
    · have := ih (phiStep r from_ acc q) hrest p hpr
      have hne : q.value ≠ p.value := fun e => hnotin ⟨p, hpr, e.symm⟩
      have hstep : phiStep r from_ acc q p.value = acc p.value := by
        unfold phiStep
        cases phiNew r from_ q with
        | none => rfl
        | some v => simp only []; exact Regs.set_ne _ _ (fun e => hne e.symm)
      rw [hstep] at this
      exact this

/-- Entering a block leaves every register that is not a phi of the block as it was. -/
theorem enterRegs_other (r : Regs) (t : Block) (from_ : Nat) {w : Nat} (h : ∀ p ∈ t.phis, p.value ≠ w) :
    enterRegs r t from_ w = r w :=
  foldl_phiStep_other r from_ t.phis r h

/-- Entering a block gives each phi the old value of its operand for the edge taken. -/
theorem enterRegs_phi (r : Regs) (t : Block) (from_ : Nat) (hnd : (t.phis.map (·.value)).Nodup) {p : Phi}
    (hp : p ∈ t.phis) {val : Val} (hv : phiNew r from_ p = some val) : enterRegs r t from_ p.value = some val := by
  have := foldl_phiStep_mem r from_ t.phis r hnd p hp
  rw [hv] at this
  exact this

/-- The operand a phi takes, if it exists, is an operand of the edge from the block entered from. -/
theorem phiNew_edge {r : Regs} {from_ : Nat} {p : Phi} {val : Val} (h : phiNew r from_ p = some val) :
    ∃ e ∈ p.edges, e.block = from_ ∧ r e.value = some val := by
  unfold phiNew at h
  cases hf : p.edges.find? (·.block == from_) with
  | none => rw [hf] at h; cases h
  | some e =>
    rw [hf] at h
    have hm := List.mem_of_find?_eq_some hf
    have hb := List.find?_some hf
    simp only [beq_iff_eq] at hb
    exact ⟨e, hm, hb, h⟩

end Facts
