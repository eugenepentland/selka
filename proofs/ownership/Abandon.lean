import Invariant

/-!
# An edge that abandons owners preserves the invariant (C9.1, design entry 55)

The edge into a trap-region block may name owners the path leaks (`abandon bP %V,…`).  The checker removes them from
`L` (`AbsState.abandon`); the semantics leaves memory alone and records the roots of their trees in the ghost set
`DState.abandoned`, forgetting the loans held by or on an abandoned tree (`abandonNext`).  This file proves the
invariant survives that step: `acct` gains the disjunct "abandoned", and the checks of the edge (`abandonChecks`:
the values are owners live on the edge, and none is a lent-to group) are what the loan invariants need.
-/

namespace Own

section

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap}

/-- What the checks `abandon-live` and `abandon-group` of an edge say. -/
structure AbandonOk (σ : AbsState) (A : List ValId) : Prop where
  live : ∀ a ∈ A, a ∈ σ.L
  group : ∀ a ∈ A, Root.val a ∉ Rget σ a

theorem abandonOk_of_checks {σ : AbsState} {b' : BlockId} {A : List ValId}
    (h : ∀ p ∈ abandonChecks cc σ b' A, p.2.2 = true) : AbandonOk σ A := by
  have h1 := h (.j2, "abandon-live", A.all fun a => cc.st a == .owned && σ.L.contains a) (by simp [abandonChecks])
  have h2 := h (.j2, "abandon-group", A.all fun a => !(Rget σ a).contains (.val a)) (by simp [abandonChecks])
  simp only [List.all_eq_true, Bool.and_eq_true, beq_iff_eq, List.contains_iff_mem, Bool.not_eq_true',
    decide_eq_true_eq] at h1 h2
  exact ⟨fun a ha => (h1 a ha).2, fun a ha hm => by
    have := h2 a ha
    simp [List.contains_iff_mem, hm] at this⟩

theorem mem_abandon_L (σ : AbsState) (A : List ValId) (v : ValId) :
    v ∈ (σ.abandon A).L ↔ v ∈ σ.L ∧ v ∉ A := by
  simp [AbsState.abandon, mem_without]

theorem abandon_R (σ : AbsState) (A : List ValId) (w : ValId) : Rget (σ.abandon A) w = Rget σ w := rfl

theorem rootLive_abandon {σ : AbsState} {A : List ValId} {ρ : Root}
    (h : rootLive (σ.abandon A) ρ = true) : rootLive σ ρ = true := by
  cases ρ with
  | val n => exact (rootLive_val σ n).2 ((mem_abandon_L σ A n).1 ((rootLive_val _ n).1 h)).1
  | slot n k => exact (rootLive_slot σ n k).2 ((mem_abandon_L σ A n).1 ((rootLive_slot _ n k).1 h)).1
  | fwd n => exact (rootLive_fwd σ n).2 ((mem_abandon_L σ A n).1 ((rootLive_fwd _ n).1 h)).1
  | caller _ => rfl

theorem mem_abandonedRoots (ds : DState) (A : List ValId) (t : Addr) :
    t ∈ abandonedRoots ds A ↔ ∃ a ∈ A, ds.env a = .own t := by
  unfold abandonedRoots
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨a, ha, h⟩
    refine ⟨a, ha, ?_⟩
    cases hv : ds.env a with
    | own t' => rw [hv] at h; simp [ownedRoot] at h; rw [h]
    | imm => rw [hv] at h; simp [ownedRoot] at h
    | stk => rw [hv] at h; simp [ownedRoot] at h
    | bor fp => rw [hv] at h; simp [ownedRoot] at h
  · rintro ⟨a, ha, h⟩
    exact ⟨a, ha, by rw [h]; rfl⟩

variable {σ : AbsState} {ds : DState}

/-- **An edge that abandons owners preserves the invariant.** -/
theorem abandon_inv (hI : Inv cc args h0 σ ds) {A : List ValId} (hA : AbandonOk σ A) :
    Inv cc args h0 (σ.abandon A) (abandonNext ds A) := by
  -- the owner of an abandoned tree is a listed value
  have hroot : ∀ t, t ∈ abandonedRoots ds A → ∃ a ∈ A, ds.env a = .own t ∧ ds.heap t = .live t := by
    intro t ht
    obtain ⟨a, ha, he⟩ := (mem_abandonedRoots ds A t).1 ht
    rcases hI.Lval a (hA.live a ha) with h | ⟨t', h1, h2⟩
    · rw [h] at he; cases he
    · rw [h1] at he; cases he
      exact ⟨a, ha, h1, h2⟩
  -- a root of a surviving value is alive in the abandoned state when it was alive before and covers a cell of a
  -- tree that was not abandoned
  have hcov : ∀ {ρ : Root} {x : Addr}, ρ.isFwd = false → rootLive σ ρ = true →
      Covers cc args h0 ds ρ x → (∀ t ∈ abandonedRoots ds A, ds.heap x ≠ .live t) →
      rootLive (σ.abandon A) ρ = true := by
    intro ρ x hf hl hc hx
    cases ρ with
    | caller _ => rfl
    | fwd _ => simp [Root.isFwd] at hf
    | val n =>
      refine (rootLive_val _ n).2 ((mem_abandon_L σ A n).2 ⟨(rootLive_val σ n).1 hl, fun hn => ?_⟩)
      obtain ⟨t, hnt, hxt⟩ := hc
      exact hx t ((mem_abandonedRoots ds A t).2 ⟨n, hn, hnt⟩) hxt
    | slot n k =>
      refine (rootLive_slot _ n k).2 ((mem_abandon_L σ A n).2 ⟨(rootLive_slot σ n k).1 hl, fun hn => ?_⟩)
      obtain ⟨t, hnt, hxt⟩ := hc
      exact hx t ((mem_abandonedRoots ds A t).2 ⟨n, hn, hnt⟩) hxt
  refine
    { imm := hI.imm, stk := hI.stk, nostk := hI.nostk
      Lown := fun v hv => hI.Lown v ((mem_abandon_L σ A v).1 hv).1
      Lbd := fun v hv => hI.Lbd v ((mem_abandon_L σ A v).1 hv).1
      Lval := fun v hv => hI.Lval v ((mem_abandon_L σ A v).1 hv).1
      Linj := fun v hv w hw => hI.Linj v ((mem_abandon_L σ A v).1 hv).1 w ((mem_abandon_L σ A w).1 hw).1
      Dst := hI.Dst, Dbd := hI.Dbd, Dval := hI.Dval
      Dcov := fun w hw hl fp hfp x hx => by
        exact hI.Dcov w hw (fun ρ hρ => (hl ρ hρ).imp id (rootLive_abandon)) fp hfp x hx
      Pin := fun p hp => by
        simp only [AbsState.abandon, List.mem_filter, Bool.not_eq_true', List.contains_eq_mem,
          decide_eq_false_iff_not] at hp
        obtain ⟨h1, h2⟩ := hI.Pin p hp.1
        exact ⟨(mem_abandon_L σ A p.1).2 ⟨h1, hp.2⟩, h2⟩
      Gin := fun g hg => by
        simp only [AbsState.abandon, List.mem_filter, Bool.not_eq_true', List.contains_eq_mem,
          decide_eq_false_iff_not] at hg
        obtain ⟨h1, h2, h3⟩ := hI.Gin g hg.1
        exact ⟨(mem_abandon_L σ A g.1).2 ⟨h1, hg.2⟩, h2, h3⟩
      Pout := fun v hv t h1 k h2 => by
        obtain ⟨hvL, hvA⟩ := (mem_abandon_L σ A v).1 hv
        have hp := hI.Pout v hvL t h1 k h2
        have hAv : A.contains v = false := by
          cases h : A.contains v with
          | false => rfl
          | true => exact absurd (List.contains_iff_mem.1 h) hvA
        unfold AbsState.predicts at hp ⊢
        rw [Bool.or_eq_true] at hp ⊢
        rcases hp with hp | hp
        · left
          rw [List.contains_iff_mem] at hp ⊢
          simp only [AbsState.abandon, List.mem_filter]
          exact ⟨hp, by simpa using hvA⟩
        · right
          obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 hp
          rw [List.any_eq_true]
          refine ⟨g, ?_, hgc⟩
          have hgv : g.1 = v := by
            simp only [Bool.and_eq_true, beq_iff_eq] at hgc
            exact hgc.1.1
          simp only [AbsState.abandon, List.mem_filter]
          exact ⟨hg, by rw [hgv]; simpa using hvA⟩
      Fin := hI.Fin
      frame := hI.frame, dead := hI.dead, unused := hI.unused
      acct := fun x t hx => by
        rcases hI.acct x t hx with ⟨v, hv, hvt⟩ | h | hab
        · by_cases hvA : v ∈ A
          · right; right
            exact Or.inr ((mem_abandonedRoots ds A t).2 ⟨v, hvA, hvt⟩)
          · exact Or.inl ⟨v, (mem_abandon_L σ A v).2 ⟨hv, hvA⟩, hvt⟩
        · exact Or.inr (Or.inl h)
        · exact Or.inr (Or.inr (Or.inl hab))
      abLive := fun t ht => by
        rcases ht with ht | ht
        · exact hI.abLive t ht
        · exact (hroot t ht).choose_spec.2.2
      Ldisj := fun v hv t hvt hab => by
        obtain ⟨hvL, hvA⟩ := (mem_abandon_L σ A v).1 hv
        rcases hab with hab | hab
        · exact hI.Ldisj v hvL t hvt hab
        · obtain ⟨a, haA, hae, _⟩ := hroot t hab
          have := hI.Linj v hvL a (hA.live a haA) t hvt hae
          exact hvA (this ▸ haA)
      abFree := fun t ht x hx => by
        rcases ht with ht | ht
        · exact hI.abFree t ht x hx
        · obtain ⟨a, haA, hae, _⟩ := hroot t ht
          exact hI.Lfree a (hA.live a haA) t hae x hx
      Lfree := fun v hv => hI.Lfree v ((mem_abandon_L σ A v).1 hv).1
      lentSeen := fun g x h => hI.lentSeen g x h.1
      lentCov := fun g x hl hg => by
        obtain ⟨v, hvL, t, hvt, hgv, hmark, ρ, hρ, hf, hlv, hc⟩ := hI.lentCov g x hl.1 hg
        have hvA : v ∉ A := fun hv => hA.group v hv hmark
        have hxn : ∀ t' ∈ abandonedRoots ds A, ds.heap x ≠ .live t' := fun t' ht' hx' => hl.2 ⟨t', ht', hx'⟩
        exact ⟨v, (mem_abandon_L σ A v).2 ⟨hvL, hvA⟩, t, hvt, hgv, hmark, ρ, hρ, hf,
          hcov hf hlv hc hxn, hc⟩
      heldSeen := fun g x h => hI.heldSeen g x h.1
      heldCov := fun g x hh hg => by
        obtain ⟨v, hvL, t, hvt, hgv, hcv⟩ := hI.heldCov g x hh.1 hg
        have hvA : v ∉ A := fun hv => hh.2 ⟨t, (mem_abandonedRoots ds A t).2 ⟨v, hv, hvt⟩, Or.inl hgv⟩
        refine ⟨v, (mem_abandon_L σ A v).2 ⟨hvL, hvA⟩, t, hvt, hgv, ?_⟩
        rcases hcv with hsame | ⟨ρ, hρ, hf, hlv, hc⟩
        · exact Or.inl hsame
        · have hxn : ∀ t' ∈ abandonedRoots ds A, ds.heap x ≠ .live t' := fun t' ht' hx' =>
            hh.2 ⟨t', ht', Or.inr hx'⟩
          exact Or.inr ⟨ρ, hρ, hf, hcov hf hlv hc hxn, hc⟩ }

end

end Own
