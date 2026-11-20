import InstSlots

/-!
# The checked half of A14: a take ends the views of its slot (C9.3)

Assumption A14 (`AXIOMS.md`) says the model has no cells per slot, so a take of a slot does not make a view of that slot
dangle in the model when the taken owner is dropped.  What the checker does about it is a statement about its own state,
and this file proves it: after a take of the slot `k` of the container `c`, **no view in `D` has the root `slot(c, k)` or
the wildcard root `slot(c, *)`** (`take_ends_slot_views`), so no such view is usable (`take_view_unusable`), and an
instruction that reads one fails the check, J4 `read-borrowed-usable` (`read_after_take_fails`).  The missing half is the
model's: that the runtime really hands the slot's storage to the taken owner, which the semantics does not represent
(sizing note `docs/design/c9-slots.md`).
-/

namespace Own

variable {cc : CCtx} {σ : AbsState} {i : Inst}

/-- The state after a take: no view in `D` has a root that ends at the take, that is, the slot taken or the wildcard slot
of the same container. -/
theorem take_ends_slot_views {c : ValId} {k : String} (htk : takenSlot cc i = some (c, k)) :
    ∀ w ∈ (instNext cc σ i).D, ∀ r ∈ Rget σ w, r ≠ Root.slot c k ∧ r ≠ Root.slot c "*" := by
  obtain ⟨_, _, _, hty⟩ := takenSlot_spec htk
  have hcls : i.cls = .project := by
    unfold isTakeI at hty
    simp only [Bool.and_eq_true, beq_iff_eq] at hty
    exact hty.1
  have hsd : cc.sd i = .owned ∨ cc.sd i = .emptied := by
    unfold isTakeI at hty
    simp only [Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at hty
    exact hty.2
  have hp : (i.cls == .parameter) = false := by simp [hcls]
  intro w hw r hr
  rcases (instNext_D hp w).1 hw with ⟨_, hends, _⟩ | ⟨d, hd, hb, _⟩
  · have h := hends (c, k) htk r hr
    constructor
    · rintro rfl; simp [Root.endsAt] at h
    · rintro rfl; simp [Root.endsAt] at h
  · exfalso
    have : cc.sd i = .borrowed := by simp only [CCtx.sd, hd]; exact hb
    rcases hsd with h | h <;> rw [h] at this <;> cases this

/-- A view of the taken slot is not usable after the take. -/
theorem take_view_unusable {c : ValId} {k : String} (htk : takenSlot cc i = some (c, k)) {w : ValId}
    (hw : cc.st w = .borrowed) (hr : Root.slot c k ∈ Rget σ w ∨ Root.slot c "*" ∈ Rget σ w) :
    usable cc (instNext cc σ i) w = false := by
  cases hu : usable cc (instNext cc σ i) w with
  | false => rfl
  | true =>
    exfalso
    obtain ⟨hD, _⟩ := usable_borrowed hw hu
    have := take_ends_slot_views (σ := σ) htk w hD
    rcases hr with h | h
    · exact (this _ h).1 rfl
    · exact (this _ h).2 rfl

/-- An instruction that reads a view of the slot just taken fails the check (J4 `read-borrowed-usable`), however the
view was reached, as long as the checker's roots for it name the slot. -/
theorem read_after_take_fails {c : ValId} {k : String} (htk : takenSlot cc i = some (c, k)) {j : Inst} {w : ValId}
    (hjw : w ∈ j.reads) (hw : cc.st w = .borrowed)
    (hr : Root.slot c k ∈ Rget σ w ∨ Root.slot c "*" ∈ Rget σ w) :
    instFail cc (instNext cc σ i) j ≠ none := by
  intro hnone
  have hall := chk_all hnone
  have h4 := hall (.j4, "read-borrowed-usable", j.reads.all fun r => cc.st r != .borrowed || usable cc (instNext cc σ i) r)
    (by simp [instChecks])
  have := List.all_eq_true.1 h4 w hjw
  simp only [hw, bne_self_eq_false, Bool.false_or] at this
  rw [take_view_unusable htk hw hr] at this
  cases this

end Own

#print axioms Own.take_ends_slot_views
#print axioms Own.read_after_take_fails
