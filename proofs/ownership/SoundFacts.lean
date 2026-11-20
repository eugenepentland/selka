import SoundBlock

/-!
# Deciding a test on a branch edge keeps the invariant
-/

namespace Own

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap}

theorem inv_resolveG {σ : AbsState} {ds : DState} (hI : Inv cc args h0 σ ds) :
    Inv cc args h0 (resolveG σ) ds := by
  have hP : ∀ p ∈ (resolveG σ).P, p ∈ σ.P ∨ ∃ g ∈ σ.G, (g.1, g.2.1) = p ∧
      ds.facts g.2.2.1 = some g.2.2.2 := by
    intro p hp
    unfold resolveG at hp
    simp only [List.mem_append, List.mem_filterMap] at hp
    rcases hp with ⟨g, hg, hgp⟩ | hp
    · right
      refine ⟨g, hg, ?_, ?_⟩
      · cases hf : σ.fact g.2.2.1 with
        | none => rw [hf] at hgp; simp at hgp
        | some po =>
          rw [hf] at hgp
          cases po with
          | none => simp at hgp
          | some q =>
            by_cases hq : q == g.2.2.2
            · simpa [hq] using hgp
            · simp [hq] at hgp
      · cases hf : σ.fact g.2.2.1 with
        | none => rw [hf] at hgp; simp at hgp
        | some po =>
          rw [hf] at hgp
          cases po with
          | none => simp at hgp
          | some q =>
            by_cases hq : q == g.2.2.2
            · obtain ⟨e, he, he1, he2⟩ := fact_spec hf
              obtain ⟨_, hpol⟩ := hI.Fin e he
              have : ds.facts g.2.2.1 = some q := by rw [← he1]; exact hpol q he2
              rw [this]
              have : q = g.2.2.2 := by simpa using hq
              rw [this]
            · simp [hq] at hgp
    · left; exact hp
  have hGmem : ∀ g ∈ (resolveG σ).G, g ∈ σ.G := by
    intro g hg
    unfold resolveG at hg
    exact (List.mem_filter.1 hg).1
  exact
    { imm := hI.imm, stk := hI.stk, nostk := hI.nostk, Lown := hI.Lown, Lbd := hI.Lbd, Lval := hI.Lval, Linj := hI.Linj,
      Dst := hI.Dst, Dbd := hI.Dbd, Dval := hI.Dval, Dcov := hI.Dcov
      lentSeen := hI.lentSeen
      lentCov := hI.lentCov
      heldSeen := hI.heldSeen
      heldCov := hI.heldCov
      Pin := fun p hp => by
        rcases hP p hp with h | ⟨g, hg, hgp, hf⟩
        · exact hI.Pin p h
        · obtain ⟨hgL, _, hval⟩ := hI.Gin g hg
          subst hgp
          refine ⟨hgL, ?_⟩
          rcases hval with h | ⟨t, h1, hiff⟩
          · left; exact h
          · right; exact ⟨t, h1, hiff.2 hf⟩
      Gin := fun g hg => hI.Gin g (hGmem g hg)
      Pout := fun v hv t h1 k h2 => by
        have hpred := hI.Pout v hv t h1 k h2
        unfold AbsState.predicts at hpred ⊢
        simp only [Bool.or_eq_true] at hpred ⊢
        rcases hpred with hp | hg
        · left
          have : (v, k) ∈ (resolveG σ).P := by
            unfold resolveG
            exact List.mem_append_right _ (List.mem_of_elem_eq_true hp)
          exact List.elem_eq_true_of_mem this
        · obtain ⟨g, hgm, hgc⟩ := List.any_eq_true.1 hg
          simp only [Bool.and_eq_true, beq_iff_eq] at hgc
          by_cases hres : g ∈ (resolveG σ).G
          · right
            exact List.any_eq_true.2 ⟨g, hres, by simp only [Bool.and_eq_true, beq_iff_eq]; exact hgc⟩
          · left
            -- the guard was resolved: the test came out as the guard says
            have hnotres : ∀ po, σ.fact g.2.2.1 = some po → ∃ q, po = some q := by
              intro po hpo
              cases po with
              | some q => exact ⟨q, rfl⟩
              | none =>
                exfalso
                apply hres
                unfold resolveG
                exact List.mem_filter.2 ⟨hgm, by simp [hpo]⟩
            cases hf : σ.fact g.2.2.1 with
            | none =>
              exfalso
              apply hres
              unfold resolveG
              exact List.mem_filter.2 ⟨hgm, by simp [hf]⟩
            | some po =>
              obtain ⟨q, rfl⟩ := hnotres po hf
              obtain ⟨e, he, he1, he2⟩ := fact_spec hf
              obtain ⟨_, hpol⟩ := hI.Fin e he
              have hqq : ds.facts g.2.2.1 = some q := by rw [← he1]; exact hpol q he2
              have hqg : q = g.2.2.2 := by
                rw [hgc.2] at hqq; exact (Option.some.inj hqq).symm
              have : (v, k) ∈ (resolveG σ).P := by
                unfold resolveG
                refine List.mem_append_left _ (List.mem_filterMap.2 ⟨g, hgm, ?_⟩)
                rw [hf]
                simp only [hqg, beq_self_eq_true, ↓reduceIte]
                rw [← hgc.1.1, ← hgc.1.2]
              exact List.elem_eq_true_of_mem this
      Fin := hI.Fin
      frame := hI.frame
      dead := hI.dead
      unused := hI.unused
      acct := hI.acct
      abLive := hI.abLive
      Ldisj := hI.Ldisj
      abFree := hI.abFree
      Lfree := hI.Lfree }

theorem setFact_apply (facts : Key → Option Bool) (key k : Key) (b : Bool) :
    setFact facts key b k = if k = key then some b else facts k := rfl

theorem inv_setFact {σ : AbsState} {ds : DState} (hI : Inv cc args h0 σ ds) {key : Key} {pol : Bool}
    (hcons : ds.facts key = none ∨ ds.facts key = some pol) :
    Inv cc args h0 { σ with F := (key, some pol) :: σ.F.filter (·.1 != key) }
      { ds with facts := setFact ds.facts key pol } := by
  have hfg : ∀ g ∈ σ.G, setFact ds.facts key pol g.2.2.1 = ds.facts g.2.2.1 := by
    intro g hg
    rw [setFact_apply]
    by_cases hk : g.2.2.1 = key
    · simp only [hk, ↓reduceIte]
      obtain ⟨_, hdec, _⟩ := hI.Gin g hg
      rw [hk] at hdec
      rcases hcons with h | h
      · exact absurd h hdec
      · rw [h]
    · simp [hk]
  exact
    { imm := hI.imm, stk := hI.stk, nostk := hI.nostk, Lown := hI.Lown, Lbd := hI.Lbd, Lval := hI.Lval, Linj := hI.Linj,
      Dst := hI.Dst, Dbd := hI.Dbd, Dval := hI.Dval, Dcov := hI.Dcov, Pin := hI.Pin
      lentSeen := hI.lentSeen
      lentCov := hI.lentCov
      heldSeen := hI.heldSeen
      heldCov := hI.heldCov
      Gin := fun g hg => by
        obtain ⟨h1, h2, h3⟩ := hI.Gin g hg
        have := hfg g hg
        refine ⟨h1, ?_, ?_⟩
        · show setFact ds.facts key pol g.2.2.1 ≠ none
          rw [this]; exact h2
        · show _ ∨ ∃ t, _ ∧ (_ ↔ setFact ds.facts key pol g.2.2.1 = some g.2.2.2)
          rw [this]; exact h3
      Pout := fun v hv t h1 k h2 => by
        have hpred := hI.Pout v hv t h1 k h2
        unfold AbsState.predicts at hpred ⊢
        simp only [Bool.or_eq_true] at hpred ⊢
        rcases hpred with h | h
        · left; exact h
        · right
          obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
          refine List.any_eq_true.2 ⟨g, hg, ?_⟩
          simp only [Bool.and_eq_true, beq_iff_eq] at hgc ⊢
          show _ ∧ setFact ds.facts key pol g.2.2.1 = some g.2.2.2
          rw [hfg g hg]; exact hgc
      Fin := fun f hf => by
        simp only [List.mem_cons, List.mem_filter] at hf
        rcases hf with rfl | ⟨hf1, hf2⟩
        · refine ⟨?_, fun p hp => ?_⟩
          · show setFact ds.facts key pol key ≠ none
            simp [setFact_apply]
          · show setFact ds.facts key pol key = some p
            simp only [setFact_apply, ↓reduceIte]
            simpa using hp
        · obtain ⟨h1, h2⟩ := hI.Fin f hf1
          have hne : f.1 ≠ key := by simpa using hf2
          show setFact ds.facts key pol f.1 ≠ none ∧ ∀ p, f.2 = some p → setFact ds.facts key pol f.1 = some p
          rw [setFact_apply]
          simp only [hne, ↓reduceIte]
          exact ⟨h1, h2⟩
      frame := hI.frame
      dead := hI.dead
      unused := hI.unused
      acct := hI.acct
      abLive := hI.abLive
      Ldisj := hI.Ldisj
      abFree := hI.abFree
      Lfree := hI.Lfree }

theorem inv_withFact {σ σ1 : AbsState} {ds : DState} (hI : Inv cc args h0 σ ds) {c : ValId}
    {pol : Bool} (h : withFact cc σ c pol = some σ1)
    (hcons : ds.facts (cc.keyOf c) = none ∨ ds.facts (cc.keyOf c) = some pol) :
    Inv cc args h0 σ1 { ds with facts := setFact ds.facts (cc.keyOf c) pol } := by
  unfold withFact at h
  dsimp only at h
  cases hf : σ.F.find? (·.1 == cc.keyOf c) with
  | none =>
    rw [hf] at h
    simp only [Option.some.injEq] at h
    subst h
    exact inv_resolveG (inv_setFact hI hcons)
  | some e =>
    rw [hf] at h
    obtain ⟨k0, po⟩ := e
    cases po with
    | none =>
      simp only [Option.some.injEq] at h
      subst h
      exact inv_resolveG (inv_setFact hI hcons)
    | some p =>
      simp only at h
      by_cases hp : p == pol
      · simp only [hp, ↓reduceIte, Option.some.injEq] at h
        subst h
        -- the test was already decided this way: the facts do not change
        have hmem : (k0, some p) ∈ σ.F := List.mem_of_find?_eq_some hf
        have hk0 : k0 = cc.keyOf c := by simpa using List.find?_some hf
        obtain ⟨_, hpol⟩ := hI.Fin (k0, some p) hmem
        have hfp : ds.facts (cc.keyOf c) = some p := by rw [← hk0]; exact hpol p rfl
        have hpp : p = pol := by simpa using hp
        have : setFact ds.facts (cc.keyOf c) pol = ds.facts := by
          funext k
          rw [setFact_apply]
          by_cases hk : k = cc.keyOf c
          · simp only [hk, ↓reduceIte]; rw [hfp, hpp]
          · simp [hk]
        have hds : ({ ds with facts := setFact ds.facts (cc.keyOf c) pol } : DState) = ds := by
          rw [this]
        rw [hds]; exact hI
      · simp [hp] at h

end Own
