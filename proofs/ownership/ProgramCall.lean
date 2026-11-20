import ProgramDefs

/-!
# A call site and its callee

From the caller's invariant and a call site that agrees with the callee's signature:
* the callee's before-the-call condition holds (`pre_of_call`);
* the callee's after-return condition gives the effect the caller's step needs
  (`effect_of_post`).
-/

namespace Own

/-! ## Lending -/

theorem lend_cells (h : Heap) (v : Val) (hv : ∀ t, v = .own t → h t = .live t) (x : Addr) :
    (lend v).cells h x ↔ v.cells h x := by
  cases v with
  | imm => simp [lend, Val.cells]
  | stk => simp [lend, Val.cells]
  | bor fp => simp [lend]
  | own t =>
    have ht := hv t rfl
    simp only [lend, Val.cells, List.mem_singleton, exists_eq_left]
    constructor
    · rintro ⟨l, hl, hx⟩
      rw [ht] at hl; cases hl; exact hx
    · intro hx; exact ⟨t, ht, hx⟩

theorem lend_alive (h : Heap) (v : Val) : (lend v).alive h ↔ v.alive h := by
  cases v with
  | imm => simp [lend, Val.alive]
  | stk => simp [lend, Val.alive]
  | bor fp => simp [lend]
  | own t => simp [lend, Val.alive]

theorem lend_ne_own (v : Val) (t : Addr) : lend v ≠ .own t := by
  cases v <;> simp [lend]

/-! ## The argument list -/

theorem mem_args_index {α : Type} (A : List α) (a : α) (h : a ∈ A) :
    ∃ I : Nat, A[I]? = some a := by
  obtain ⟨I, hI, e⟩ := List.getElem_of_mem h
  exact ⟨I, by simp [List.getElem?_eq_getElem hI, e]⟩

theorem owned_pos_inj (g : ValId → Option Addr) :
    ∀ (A : List (ValId × Bool)), (((A.filter (·.2)).map (·.1)).filterMap g).Nodup →
      ∀ (i j : Nat) (n m : ValId) (t : Addr), A[i]? = some (n, true) → A[j]? = some (m, true) →
        g n = some t → g m = some t → i = j := by
  intro A
  induction A with
  | nil => intro _ i j n m t h; simp at h
  | cons a As ih =>
    obtain ⟨a1, a2⟩ := a
    intro hnd i j n m t hi hj gn gm
    have tail : ∀ (j' : Nat) (m : ValId), As[j']? = some (m, true) →
        m ∈ (As.filter (·.2)).map (·.1) := by
      intro j' m h
      exact List.mem_map.2 ⟨(m, true), List.mem_filter.2 ⟨List.mem_of_getElem? h, by simp⟩, rfl⟩
    cases a2 with
    | false =>
      have hnd' : (((As.filter (·.2)).map (·.1)).filterMap g).Nodup := by
        simpa [List.filter_cons] using hnd
      cases i with
      | zero => simp at hi
      | succ i' =>
        cases j with
        | zero => simp at hj
        | succ j' =>
          simp only [List.getElem?_cons_succ] at hi hj
          exact congrArg (· + 1) (ih hnd' i' j' n m t hi hj gn gm)
    | true =>
      simp only [List.filter_cons, List.map_cons, List.filterMap_cons, ↓reduceIte] at hnd
      cases hg : g a1 with
      | none =>
        rw [hg] at hnd
        simp only at hnd
        cases i with
        | zero => simp at hi; subst hi; rw [hg] at gn; cases gn
        | succ i' =>
          cases j with
          | zero => simp at hj; subst hj; rw [hg] at gm; cases gm
          | succ j' =>
            simp only [List.getElem?_cons_succ] at hi hj
            exact congrArg (· + 1) (ih hnd i' j' n m t hi hj gn gm)
      | some t0 =>
        rw [hg] at hnd
        simp only [List.nodup_cons] at hnd
        obtain ⟨hnot, hnd'⟩ := hnd
        cases i with
        | zero =>
          simp at hi
          subst hi; rw [hg] at gn
          have ht0 : t0 = t := Option.some.inj gn
          cases j with
          | zero => rfl
          | succ j' =>
            simp only [List.getElem?_cons_succ] at hj
            exfalso
            apply hnot
            rw [List.mem_filterMap]
            exact ⟨m, tail j' m hj, by rw [ht0]; exact gm⟩
        | succ i' =>
          cases j with
          | zero =>
            simp at hj
            subst hj; rw [hg] at gm
            have ht0 : t0 = t := Option.some.inj gm
            simp only [List.getElem?_cons_succ] at hi
            exfalso
            apply hnot
            rw [List.mem_filterMap]
            exact ⟨n, tail i' n hi, by rw [ht0]; exact gn⟩
          | succ j' =>
            simp only [List.getElem?_cons_succ] at hi hj
            exact congrArg (· + 1) (ih hnd' i' j' n m t hi hj gn gm)

end Own
