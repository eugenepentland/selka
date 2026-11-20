import Facts.Static

/-!
# What an accepted function gives

The checks F2 to F7 each look at every item of the function; when the checker finds no fault, each item passed.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem orElse_none {α : Type} {a b : Option α} : (a <|> b) = none ↔ a = none ∧ b = none := by
  cases a <;> cases b <;> simp [HOrElse.hOrElse, OrElse.orElse, Option.orElse]

section Accepted
variable {c : Ctx}

theorem Ctx.ff_parts (h : c.firstFault = none) :
    c.deadFault = none ∧ c.intervalOuts.findSome? Out.fault? = none ∧ c.listOuts.findSome? Out.fault? = none ∧
    c.interFault = none ∧ c.provenOuts.findSome? Out.fault? = none := by
  unfold Ctx.firstFault at h
  simp only [orElse_none] at h
  exact h

/-- Every instruction of a reached block passed F2. -/
theorem Ctx.inst_ok (h : c.firstFault = none) {B : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[B]? = some b)
    (hr : c.reached[B]? = some true) (hi : i ∈ b.insts) : (c.instOut i B).fault? = none := by
  have := (Ctx.ff_parts h).2.1
  rw [List.findSome?_eq_none_iff] at this
  apply this
  unfold Ctx.intervalOuts
  simp only [List.mem_append, List.mem_flatMap, List.mem_map, List.mem_range]
  right
  refine ⟨B, arr_lt_of_get? hb, ?_⟩
  have hr' : (c.reached[B]?.getD false) = true := by rw [hr]; rfl
  simp only [hr', Bool.not_true, Bool.false_eq_true, ite_false, List.mem_append, List.mem_map]
  right
  rw [arr_get!_of_get? hb]
  exact ⟨i, hi, rfl⟩

/-- Every constant and parameter passed F2. -/
theorem Ctx.pre_ok (h : c.firstFault = none) {i : Inst} (hi : i ∈ c.f.pre) : (c.instOut i 0).fault? = none := by
  have := (Ctx.ff_parts h).2.1
  rw [List.findSome?_eq_none_iff] at this
  apply this
  unfold Ctx.intervalOuts
  simp only [List.mem_append, List.mem_map]
  left
  exact ⟨i, hi, rfl⟩

/-- Every phi of a reached block passed F3. -/
theorem Ctx.phi_ok (h : c.firstFault = none) {B : Nat} {b : Block} {p : Phi} (hb : c.f.blocks[B]? = some b)
    (hr : c.reached[B]? = some true) (hp : p ∈ b.phis) : (c.phiOut p B).fault? = none := by
  have := (Ctx.ff_parts h).2.1
  rw [List.findSome?_eq_none_iff] at this
  apply this
  unfold Ctx.intervalOuts
  simp only [List.mem_append, List.mem_flatMap, List.mem_map, List.mem_range]
  right
  refine ⟨B, arr_lt_of_get? hb, ?_⟩
  have hr' : (c.reached[B]?.getD false) = true := by rw [hr]; rfl
  simp only [hr', Bool.not_true, Bool.false_eq_true, ite_false, List.mem_append, List.mem_map]
  left
  rw [arr_get!_of_get? hb]
  exact ⟨p, hp, rfl⟩

theorem Out.fault_none_ne {o : Out} (h : o.fault? = none) (f : Fault) : o ≠ .bad f := by
  intro e
  subst e
  simp [Out.fault?] at h

/-- A block the function states dead is not reached, and no live edge enters it. -/
theorem Ctx.dead_ok (h : c.firstFault = none) {B : Nat} {b : Block} (hb : c.f.blocks[B]? = some b)
    (hd : b.dead = true) : c.reached[B]? ≠ some true := by
  have := (Ctx.ff_parts h).1
  unfold Ctx.deadFault at this
  rw [List.findSome?_eq_none_iff] at this
  have h1 := this B (List.mem_range.mpr (arr_lt_of_get? hb))
  rw [arr_get!_of_get? hb] at h1
  simp only [hd, Bool.not_true, ite_false, ite_true] at h1
  intro hr
  have hr' : (c.reached[B]?.getD false) = true := by rw [hr]; rfl
  simp [hr'] at h1

/-- The inter-procedural checks passed in every reached block. -/
theorem Ctx.inter_ok (h : c.firstFault = none) {B : Nat} {b : Block} (hb : c.f.blocks[B]? = some b)
    (hr : c.reached[B]? = some true) : c.interOut b B = none := by
  have := (Ctx.ff_parts h).2.2.2.1
  unfold Ctx.interFault at this
  rw [List.findSome?_eq_none_iff] at this
  have h1 := this B (List.mem_range.mpr (arr_lt_of_get? hb))
  have hr' : (c.reached[B]?.getD false) = true := by rw [hr]; rfl
  simp only [hr', Bool.not_true, Bool.false_eq_true, ite_false] at h1
  rw [arr_get!_of_get? hb] at h1
  exact h1

/-- Every `proven` instruction of a reached block passed F7. -/
theorem Ctx.proven_ok (h : c.firstFault = none) {B : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[B]? = some b)
    (hr : c.reached[B]? = some true) (hi : i ∈ b.insts) (hp : i.check = .proven) :
    (c.provenOut i B).fault? = none := by
  have := (Ctx.ff_parts h).2.2.2.2
  rw [List.findSome?_eq_none_iff] at this
  apply this
  unfold Ctx.provenOuts
  simp only [List.mem_flatMap, List.mem_map, List.mem_range, List.mem_filter]
  refine ⟨B, arr_lt_of_get? hb, ?_⟩
  have hr' : (c.reached[B]?.getD false) = true := by rw [hr]; rfl
  simp only [hr', Bool.not_true, Bool.false_eq_true, ite_false, List.mem_map, List.mem_filter]
  rw [arr_get!_of_get? hb]
  exact ⟨i, ⟨hi, by simp [hp]⟩, rfl⟩

end Accepted

end Facts
