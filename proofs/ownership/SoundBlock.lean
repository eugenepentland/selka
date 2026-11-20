import EdgeStep
import Abandon

/-!
# From a passed check to facts about blocks and edges
-/

namespace Own

/-! ## Instructions of a block -/

/-- The instructions of a block, run from `σ`, pass their checks and end in `σ'`. -/
inductive RunGood (cc : CCtx) : AbsState → List Inst → AbsState → Prop
  | nil (σ : AbsState) : RunGood cc σ [] σ
  | cons (σ : AbsState) (i : Inst) (is : List Inst) (σ' : AbsState) :
      instFail cc σ i = none → RunGood cc (instNext cc σ i) is σ' → RunGood cc σ (i :: is) σ'

theorem runGood_of_runInsts {cc : CCtx} {b : BlockId} :
    ∀ (k : Nat) (σ : AbsState) (is : List Inst) (σ' : AbsState),
      runInsts cc b k σ is = .ok σ' → RunGood cc σ is σ' := by
  intro k σ is
  induction is generalizing k σ with
  | nil =>
    intro σ' h
    simp only [runInsts, Except.ok.injEq] at h
    subst h; exact .nil _
  | cons i is ih =>
    intro σ' h
    simp only [runInsts] at h
    cases hf : instFail cc σ i with
    | some j => rw [hf] at h; simp at h
    | none =>
      rw [hf] at h
      exact .cons σ i is σ' hf (ih (k + 1) _ σ' h)

theorem RunGood.nil_inv {cc : CCtx} {σ σ' : AbsState} (h : RunGood cc σ [] σ') : σ' = σ := by
  cases h; rfl

theorem RunGood.cons_inv {cc : CCtx} {σ σ' : AbsState} {i : Inst} {is : List Inst}
    (h : RunGood cc σ (i :: is) σ') :
    instFail cc σ i = none ∧ RunGood cc (instNext cc σ i) is σ' := by
  cases h with
  | cons _ _ _ _ h1 h2 => exact ⟨h1, h2⟩

/-! ## The terminator and the edges -/

/-- The terminator's checks pass and every live edge fits the target's entry state. -/
structure TermGood (cc : CCtx) (inn : BlockId → Option AbsState) (b : BlockId) (blk : Block)
    (σo : AbsState) : Prop where
  chk : ∀ p ∈ termChecks cc σo blk.term, p.2.2 = true
  edges : ∃ es, liveEdges cc b σo blk.term = .ok es ∧
    ∀ e ∈ es, compatErr inn e.1 e.2 = none

theorem verifyBlock_good {cc : CCtx} {inn : BlockId → Option AbsState} {b : BlockId}
    {σ : AbsState} {blk : Block} (h : verifyBlock cc inn b = none) (hin : inn b = some σ)
    (hblk : cc.f.block? b = some blk) :
    ∃ σo, RunGood cc σ blk.insts σo ∧ TermGood cc inn b blk σo := by
  unfold verifyBlock at h
  rw [hin, hblk] at h
  dsimp only at h
  cases hr : runInsts cc b 0 σ blk.insts with
  | error fl => rw [hr] at h; simp at h
  | ok σo =>
    rw [hr] at h
    simp only at h
    refine ⟨σo, runGood_of_runInsts 0 σ _ σo hr, ?_, ?_⟩
    · cases hf : firstFail (termChecks cc σo blk.term) with
      | some p => rw [hf] at h; simp at h
      | none => exact chk_all hf
    · cases hf : firstFail (termChecks cc σo blk.term) with
      | some p => rw [hf] at h; simp at h
      | none =>
        rw [hf] at h
        simp only at h
        cases hl : liveEdges cc b σo blk.term with
        | error j => rw [hl] at h; simp at h
        | ok es =>
          rw [hl] at h
          simp only at h
          refine ⟨es, rfl, ?_⟩
          intro e he
          have := List.findSome?_eq_none_iff.1 h e he
          cases hc : compatErr inn e.1 e.2 with
          | none => rfl
          | some j => rw [hc] at this; simp at this

/-- Facts about `liveEdgesOf`. -/
theorem liveEdgesOf_edge {cc : CCtx} {b : BlockId} :
    ∀ (ts : List (BlockId × AbsState)) (es : List (BlockId × AbsState)),
      liveEdgesOf cc b ts = .ok es → ∀ t ∈ ts, ∃ r, edgeTo cc b t.2 t.1 = .ok r ∧
        ∀ σe, r = some σe → (t.1, σe) ∈ es := by
  intro ts
  induction ts with
  | nil => intro es _ t ht; simp at ht
  | cons t0 ts ih =>
    intro es h t ht
    obtain ⟨t0b, t0s⟩ := t0
    simp only [liveEdgesOf] at h
    cases he : edgeTo cc b t0s t0b with
    | error j => rw [he] at h; simp at h
    | ok r0 =>
      rw [he] at h
      cases r0 with
      | none =>
        simp only at h
        rcases List.mem_cons.1 ht with rfl | ht'
        · exact ⟨none, he, by simp⟩
        · exact ih es h t ht'
      | some σe0 =>
        simp only at h
        cases hl : liveEdgesOf cc b ts with
        | error j => rw [hl] at h; simp at h
        | ok es' =>
          rw [hl] at h
          simp only [Except.ok.injEq] at h
          subst h
          rcases List.mem_cons.1 ht with rfl | ht'
          · exact ⟨some σe0, he, fun σe hσ => by cases hσ; simp⟩
          · obtain ⟨r, hr, hmem⟩ := ih es' hl t ht'
            exact ⟨r, hr, fun σe hσ => List.mem_cons_of_mem _ (hmem σe hσ)⟩

/-- A checked edge into an existing block is live and gives its edge state: the abandon list of the target for this
edge is applied first, and its checks and the phi checks pass. -/
theorem edgeTo_live {cc : CCtx} {b b' : BlockId} {σ : AbsState} {blk' : Block}
    {r : Option AbsState} (hblk' : cc.f.block? b' = some blk')
    (h : edgeTo cc b σ b' = .ok r) :
    r = some (edgeNext cc (σ.abandon (blk'.abandonFrom b)) b blk'.phis) ∧
      AbandonOk σ (blk'.abandonFrom b) ∧ (blk'.abandonFrom b ≠ [] → region cc b' = true) ∧
      EdgeOk cc (σ.abandon (blk'.abandonFrom b)) b blk'.phis := by
  unfold edgeTo at h
  rw [hblk'] at h
  simp only at h
  cases hf0 : firstFail (abandonChecks cc σ b' (blk'.abandonFrom b)) with
  | some p => rw [hf0] at h; simp at h
  | none =>
    rw [hf0] at h
    simp only at h
    cases hf : firstFail (edgeChecks cc (σ.abandon (blk'.abandonFrom b)) b blk'.phis) with
    | some p => rw [hf] at h; simp at h
    | none =>
      rw [hf] at h
      simp only [Except.ok.injEq] at h
      subst h
      have hall := chk_all hf0
      refine ⟨rfl, abandonOk_of_checks hall, ?_, edgeOk_of_checks hf⟩
      intro hne
      have := hall (.j2, "abandon-region", (blk'.abandonFrom b).isEmpty || region cc b') (by simp [abandonChecks])
      simp only [Bool.or_eq_true, List.isEmpty_iff] at this
      rcases this with h1 | h1
      · exact absurd h1 hne
      · exact h1

/-! ## Conversion of states -/

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap}

theorem fact_spec {σ : AbsState} {key : Key} {pe : Option Bool} (h : σ.fact key = some pe) :
    ∃ e ∈ σ.F, e.1 = key ∧ e.2 = pe := by
  unfold AbsState.fact at h
  cases hf : σ.F.find? (·.1 == key) with
  | none => rw [hf] at h; simp at h
  | some e =>
    rw [hf] at h
    simp only [Option.map_some, Option.some.injEq] at h
    exact ⟨e, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf, h⟩

/-- The invariant at an edge state gives the invariant at the entry state it fits. -/
theorem Inv.conv {σe σs : AbsState} {ds : DState}
    (hI : Inv cc args h0 σe ds) (hL : same σs.L σe.L = true) (hS : slotsFit σs σe = true)
    (hF : factsFit σs σe = true) (hD : sub σs.D σe.D = true)
    (hR : (σs.D ++ σs.L).all (fun w => sub (Rget σe w) (Rget σs w)) = true) :
    Inv cc args h0 σs ds := by
  have hL' := (same_iff _ _).1 hL
  have hD' := (sub_iff _ _).1 hD
  have hlive : ∀ ρ, rootLive σs ρ = true → rootLive σe ρ = true := by
    intro ρ h
    cases ρ with
    | caller _ => rfl
    | val n => exact (rootLive_val σe n).2 ((hL' n).1 ((rootLive_val σs n).1 h))
    | slot n k => exact (rootLive_slot σe n k).2 ((hL' n).1 ((rootLive_slot σs n k).1 h))
    | fwd n => exact (rootLive_fwd σe n).2 ((hL' n).1 ((rootLive_fwd σs n).1 h))
  have hRsub : ∀ w, (w ∈ σs.D ∨ w ∈ σs.L) → ∀ ρ ∈ Rget σe w, ρ ∈ Rget σs w := by
    intro w hw ρ hρ
    have := List.all_eq_true.1 hR w (List.mem_append.2 (by simpa using hw))
    exact (sub_iff _ _).1 this ρ hρ
  have hlive' : ∀ ρ, rootLive σe ρ = true → rootLive σs ρ = true := by
    intro ρ h
    cases ρ with
    | caller _ => rfl
    | val n => exact (rootLive_val σs n).2 ((hL' n).2 ((rootLive_val σe n).1 h))
    | slot n k => exact (rootLive_slot σs n k).2 ((hL' n).2 ((rootLive_slot σe n k).1 h))
    | fwd n => exact (rootLive_fwd σs n).2 ((hL' n).2 ((rootLive_fwd σe n).1 h))
  simp only [slotsFit, Bool.and_eq_true, List.all_eq_true] at hS
  obtain ⟨⟨⟨⟨hS1, hS2⟩, hS2b⟩, hS3⟩, hS4⟩ := hS
  simp only [factsFit, List.all_eq_true] at hF
  exact
    { imm := hI.imm, stk := hI.stk, nostk := hI.nostk
      Lown := fun v hv => hI.Lown v ((hL' v).1 hv)
      Lbd := fun v hv => hI.Lbd v ((hL' v).1 hv)
      Lval := fun v hv => hI.Lval v ((hL' v).1 hv)
      Linj := fun v hv w hw => hI.Linj v ((hL' v).1 hv) w ((hL' w).1 hw)
      Dst := fun w hw => hI.Dst w (hD' w hw)
      Dbd := fun w hw => hI.Dbd w (hD' w hw)
      Dval := fun w hw => hI.Dval w (hD' w hw)
      Dcov := fun w hw hl fp hfp x hx => by
        obtain ⟨ρ, hρ, hf, hc⟩ := hI.Dcov w (hD' w hw)
          (fun ρ hρ => (hl ρ (hRsub w (Or.inl hw) ρ hρ)).imp id (hlive ρ)) fp hfp x hx
        exact ⟨ρ, hRsub w (Or.inl hw) ρ hρ, hf, hc⟩
      Pin := fun p hp => by
        have hpe : p ∈ σe.P := List.mem_of_elem_eq_true (hS1 p hp)
        obtain ⟨h1, h2⟩ := hI.Pin p hpe
        exact ⟨(hL' p.1).2 h1, h2⟩
      Gin := fun g hg => by
        have hgL : g.1 ∈ σs.L := List.mem_of_elem_eq_true (hS2b g hg)
        have hgLe : g.1 ∈ σe.L := (hL' g.1).1 hgL
        have hfit := hS2 g hg
        unfold guardFits at hfit
        cases hfact : σe.fact g.2.2.1 with
        | none => rw [hfact] at hfit; cases hfit
        | some po =>
          rw [hfact] at hfit
          cases po with
          | none =>
            simp only [] at hfit
            exact ⟨hgL, (hI.Gin g (List.mem_of_elem_eq_true hfit)).2⟩
          | some p =>
            simp only [] at hfit
            obtain ⟨e, he, he1, he2⟩ := fact_spec hfact
            obtain ⟨hdec, hpol⟩ := hI.Fin e he
            have hfp : ds.facts g.2.2.1 = some p := by rw [← he1]; exact hpol p he2
            refine ⟨hgL, by rw [hfp]; simp, ?_⟩
            rcases hI.Lval g.1 hgLe with h | ⟨t, h1, _⟩
            · left; exact h
            · right
              refine ⟨t, h1, ?_⟩
              by_cases hpp : p = g.2.2.2
              · subst hpp
                simp only [beq_self_eq_true, ↓reduceIte] at hfit
                rcases (hI.Pin (g.1, g.2.1) (List.mem_of_elem_eq_true hfit)).2 with h | ⟨t', h', hp⟩
                · rw [h] at h1; cases h1
                · rw [h1] at h'; cases h'
                  rw [hfp]; simp [hp]
              · have hne : (p == g.2.2.2) = false := by simpa using hpp
                simp only [hne, Bool.false_eq_true, ↓reduceIte] at hfit
                have hnot : σe.slotOpen g.1 g.2.1 = false := by simpa using hfit
                rw [hfp]
                constructor
                · intro hp
                  exfalso
                  have hpred := hI.Pout g.1 hgLe t h1 g.2.1 hp
                  unfold AbsState.predicts at hpred
                  unfold AbsState.slotOpen at hnot
                  simp only [Bool.or_eq_false_iff, List.any_eq_false] at hnot
                  simp only [Bool.or_eq_true] at hpred
                  rcases hpred with h | h
                  · rw [hnot.1] at h; cases h
                  · obtain ⟨g', hg', hgc⟩ := List.any_eq_true.1 h
                    simp only [Bool.and_eq_true, beq_iff_eq] at hgc
                    exact hnot.2 g' hg' (by simp [hgc.1.1, hgc.1.2])
                · intro h; cases h; exact absurd rfl hpp
      Pout := fun v hv t h1 k h2 => by
        have hpred := hI.Pout v ((hL' v).1 hv) t h1 k h2
        unfold AbsState.predicts at hpred ⊢
        simp only [Bool.or_eq_true] at hpred ⊢
        rcases hpred with hP | hG
        · have := hS3 (v, k) (List.mem_of_elem_eq_true hP)
          simp only [Bool.or_eq_true] at this
          rcases this with h | h
          · left; exact h
          · right
            obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
            simp only [Bool.and_eq_true, beq_iff_eq] at hgc
            obtain ⟨e, he, he1, he2⟩ := fact_spec (σ := σe) (key := g.2.2.1)
              (pe := some g.2.2.2) (by simpa using hgc.2)
            obtain ⟨_, hpol⟩ := hI.Fin e he
            have hfp : ds.facts g.2.2.1 = some g.2.2.2 := by rw [← he1]; exact hpol _ he2
            refine List.any_eq_true.2 ⟨g, hg, ?_⟩
            simp only [Bool.and_eq_true, beq_iff_eq]
            exact ⟨hgc.1, hfp⟩
        · right
          obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 hG
          exact List.any_eq_true.2 ⟨g, List.mem_of_elem_eq_true (hS4 g hg), hgc⟩
      Fin := fun f hf => by
        have hfit := hF f hf
        cases hfact : σe.fact f.1 with
        | none => rw [hfact] at hfit; cases hfit
        | some pe =>
          rw [hfact] at hfit
          obtain ⟨e, he, he1, he2⟩ := fact_spec hfact
          obtain ⟨hdec, hpol⟩ := hI.Fin e he
          rw [he1] at hdec
          refine ⟨hdec, fun p hp => ?_⟩
          have hfp : f.2 = some p := hp
          simp only [Bool.or_eq_true, hfp] at hfit
          rcases hfit with h | h
          · simp at h
          · have : pe = some p := by simpa using h
            rw [← he1]; exact hpol p (by rw [he2]; exact this)
      frame := hI.frame
      dead := hI.dead
      unused := hI.unused
      acct := fun x t h => by
        rcases hI.acct x t h with ⟨v, hv, hvt⟩ | h
        · exact Or.inl ⟨v, (hL' v).2 hv, hvt⟩
        · exact Or.inr h
      abLive := hI.abLive
      Ldisj := fun v hv => hI.Ldisj v ((hL' v).1 hv)
      abFree := hI.abFree
      Lfree := fun v hv => hI.Lfree v ((hL' v).1 hv)
      lentSeen := hI.lentSeen
      lentCov := fun g x hl hg => by
        obtain ⟨v, hvL, t, hvt, hgv, hmark, ρ, hρ, hf, hlv, hc⟩ := hI.lentCov g x hl hg
        have hvs : v ∈ σs.L := (hL' v).2 hvL
        exact ⟨v, hvs, t, hvt, hgv, hRsub v (Or.inr hvs) _ hmark, ρ, hRsub v (Or.inr hvs) ρ hρ,
          hf, hlive' ρ hlv, hc⟩
      heldSeen := hI.heldSeen
      heldCov := fun g x hl hg => by
        obtain ⟨v, hvL, t, hvt, hgv, hcv⟩ := hI.heldCov g x hl hg
        have hvs : v ∈ σs.L := (hL' v).2 hvL
        refine ⟨v, hvs, t, hvt, hgv, ?_⟩
        rcases hcv with hsame | ⟨ρ, hρ, hf, hlv, hc⟩
        · exact Or.inl hsame
        · exact Or.inr ⟨ρ, hRsub v (Or.inr hvs) ρ hρ, hf, hlive' ρ hlv, hc⟩ }

end Own
