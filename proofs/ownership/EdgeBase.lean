import InstPres

/-!
# Phi edges: what a passed edge check says, and the list lemmas the edge step needs
-/

namespace Own

variable {cc : CCtx}

/-! ## Membership in the edge lists -/

theorem mem_livePhis {phis : List Phi} {φ : Phi} :
    φ ∈ livePhis cc phis ↔ φ ∈ phis ∧ Phi.live cc.c φ = true := by
  unfold livePhis
  simp [List.mem_filter]

theorem mem_edgeOps {b : BlockId} {phis : List Phi} {φ : Phi} {o : ValId} :
    (φ, o) ∈ edgeOps cc b phis ↔
      φ ∈ phis ∧ Phi.live cc.c φ = true ∧ φ.edges.lookup b = some o := by
  unfold edgeOps
  rw [List.mem_filterMap]
  constructor
  · rintro ⟨φ', hφ', h⟩
    cases hl : φ'.edges.lookup b <;> simp [hl] at h
    obtain ⟨rfl, rfl⟩ := h
    have := mem_livePhis.1 hφ'
    exact ⟨this.1, this.2, hl⟩
  · rintro ⟨hφ, hv, hl⟩
    exact ⟨φ, mem_livePhis.2 ⟨hφ, hv⟩, by simp [hl]⟩

/-- The operand of a phi that the edge consumes, if it does. -/
def consOf (cc : CCtx) (b : BlockId) (φ : Phi) : Option ValId :=
  if Phi.live cc.c φ then
    match φ.edges.lookup b with
    | some o => if (cc.st φ.dst).owning && (cc.st o).owning then some o else none
    | none => none
  else none

theorem mem_edgeMoves {b : BlockId} {phis : List Phi} {o h : ValId} :
    (o, h) ∈ edgeMoves cc b phis ↔
      ∃ φ ∈ phis, Phi.live cc.c φ = true ∧ φ.edges.lookup b = some o ∧ φ.dst = h ∧
        (cc.st φ.dst).owning = true ∧ (cc.st o).owning = true := by
  unfold edgeMoves
  rw [List.mem_map]
  constructor
  · rintro ⟨p, hp, hpe⟩
    rw [List.mem_filter] at hp
    obtain ⟨hp1, hp2⟩ := hp
    obtain ⟨φ, o'⟩ := p
    obtain ⟨hφ, hv, hl⟩ := mem_edgeOps.1 hp1
    simp only [Prod.mk.injEq] at hpe
    obtain ⟨rfl, rfl⟩ := hpe
    simp only [Bool.and_eq_true] at hp2
    exact ⟨φ, hφ, hv, hl, rfl, hp2.1, hp2.2⟩
  · rintro ⟨φ, hφ, hv, hl, rfl, h1, h2⟩
    refine ⟨(φ, o), ?_, rfl⟩
    rw [List.mem_filter]
    exact ⟨mem_edgeOps.2 ⟨hφ, hv, hl⟩, by simp [h1, h2]⟩

theorem mem_edgeConsumed {b : BlockId} {phis : List Phi} {o : ValId} :
    o ∈ edgeConsumed cc b phis ↔
      ∃ φ ∈ phis, Phi.live cc.c φ = true ∧ φ.edges.lookup b = some o ∧
        (cc.st φ.dst).owning = true ∧ (cc.st o).owning = true := by
  unfold edgeConsumed
  rw [List.mem_map]
  constructor
  · rintro ⟨⟨o', h⟩, hp, rfl⟩
    obtain ⟨φ, hφ, hv, hl, _, h1, h2⟩ := mem_edgeMoves.1 hp
    exact ⟨φ, hφ, hv, hl, h1, h2⟩
  · rintro ⟨φ, hφ, hv, hl, h1, h2⟩
    exact ⟨(o, φ.dst), mem_edgeMoves.2 ⟨φ, hφ, hv, hl, rfl, h1, h2⟩, rfl⟩

theorem mem_edgeDsts {phis : List Phi} {d : ValId} :
    d ∈ edgeDsts cc phis ↔
      ∃ φ ∈ phis, Phi.live cc.c φ = true ∧ φ.dst = d ∧ (cc.st d).owning = true := by
  unfold edgeDsts
  simp only [List.mem_map, List.mem_filter, mem_livePhis]
  constructor
  · rintro ⟨φ, ⟨⟨hφ, hv⟩, h⟩, rfl⟩
    exact ⟨φ, hφ, hv, rfl, h⟩
  · rintro ⟨φ, hφ, hv, rfl, h⟩
    exact ⟨φ, ⟨⟨hφ, hv⟩, h⟩, rfl⟩

theorem mem_edgeBdsts {phis : List Phi} {d : ValId} :
    d ∈ edgeBdsts cc phis ↔
      ∃ φ ∈ phis, Phi.live cc.c φ = true ∧ φ.dst = d ∧ cc.st d = .borrowed := by
  unfold edgeBdsts
  simp only [List.mem_map, List.mem_filter, mem_livePhis, beq_iff_eq]
  constructor
  · rintro ⟨φ, ⟨⟨hφ, hv⟩, h⟩, rfl⟩
    exact ⟨φ, hφ, hv, rfl, h⟩
  · rintro ⟨φ, hφ, hv, rfl, h⟩
    exact ⟨φ, ⟨⟨hφ, hv⟩, h⟩, rfl⟩

theorem edgeConsumed_eq (b : BlockId) (phis : List Phi) :
    edgeConsumed cc b phis = phis.filterMap (consOf cc b) := by
  induction phis with
  | nil => simp [edgeConsumed, edgeMoves, edgeOps, livePhis]
  | cons φ φs ih =>
    unfold edgeConsumed edgeMoves edgeOps livePhis at ih ⊢
    by_cases hv : Phi.live cc.c φ = true
    · cases hl : φ.edges.lookup b with
      | none =>
        have hc : consOf cc b φ = none := by simp [consOf, hv, hl]
        simp [List.filter_cons, hv, List.filterMap_cons, hl, hc, ih]
      | some o =>
        by_cases h1 : (cc.st φ.dst).owning = true <;> by_cases h2 : (cc.st o).owning = true
        · have hc : consOf cc b φ = some o := by simp [consOf, hv, hl, h1, h2]
          simp [List.filter_cons, hv, List.filterMap_cons, hl, hc, h1, h2, ih]
        all_goals
          have hc : consOf cc b φ = none := by simp [consOf, hv, hl, h1, h2]
          simp [List.filter_cons, hv, List.filterMap_cons, hl, hc, h1, h2, ih]
    · have hc : consOf cc b φ = none := by simp [consOf, hv]
      simp [List.filter_cons, hv, List.filterMap_cons, hc, ih]

/-- Distinct phis consume distinct operands. -/
theorem consumed_inj (b : BlockId) :
    ∀ (phis : List Phi), (phis.filterMap (consOf cc b)).Nodup →
      ∀ φ1 ∈ phis, ∀ φ2 ∈ phis, ∀ o, consOf cc b φ1 = some o → consOf cc b φ2 = some o →
        φ1 = φ2 := by
  intro phis
  induction phis with
  | nil => intro _ φ1 h; simp at h
  | cons φ φs ih =>
    intro hnd φ1 h1 φ2 h2 o e1 e2
    rw [List.filterMap_cons] at hnd
    cases hφ : consOf cc b φ with
    | none =>
      rw [hφ] at hnd
      simp only at hnd
      have h1' : φ1 ∈ φs := by
        rcases List.mem_cons.1 h1 with rfl | h; · rw [hφ] at e1; cases e1
        · exact h
      have h2' : φ2 ∈ φs := by
        rcases List.mem_cons.1 h2 with rfl | h; · rw [hφ] at e2; cases e2
        · exact h
      exact ih hnd φ1 h1' φ2 h2' o e1 e2
    | some o0 =>
      rw [hφ] at hnd
      simp only [List.nodup_cons] at hnd
      obtain ⟨hnot, hnd'⟩ := hnd
      have notin : ∀ ψ ∈ φs, consOf cc b ψ ≠ some o0 := by
        intro ψ hψ hc
        exact hnot (List.mem_filterMap.2 ⟨ψ, hψ, hc⟩)
      rcases List.mem_cons.1 h1 with rfl | h1' <;> rcases List.mem_cons.1 h2 with rfl | h2'
      · rfl
      · rw [hφ] at e1; cases e1; exact absurd e2 (notin _ h2')
      · rw [hφ] at e2; cases e2; exact absurd e1 (notin _ h1')
      · exact ih hnd' φ1 h1' φ2 h2' o e1 e2

/-! ## `applyPhis` -/

theorem find_phi (c : Certificate) (phis : List Phi)
    (hnd : ((phis.filter (Phi.live c)).map (·.dst)).Nodup) {φ : Phi} (hφ : φ ∈ phis)
    (hv : Phi.live c φ = true) :
    phis.find? (fun x => x.dst == φ.dst && Phi.live c x) = some φ := by
  induction phis with
  | nil => simp at hφ
  | cons x xs ih =>
    rw [List.find?_cons]
    by_cases hxv : Phi.live c x = true
    · simp only [List.filter_cons, hxv, ↓reduceIte, List.map_cons, List.nodup_cons] at hnd
      by_cases hx : x.dst = φ.dst
      · have : x = φ := by
          rcases List.mem_cons.1 hφ with rfl | h
          · rfl
          · exact absurd (List.mem_map.2 ⟨φ, List.mem_filter.2 ⟨h, hv⟩, hx.symm⟩) hnd.1
        subst this
        simp [hv]
      · have hφxs : φ ∈ xs := by
          rcases List.mem_cons.1 hφ with rfl | h
          · exact absurd rfl hx
          · exact h
        have hb : (x.dst == φ.dst && Phi.live c x) = false := by simp [hx]
        rw [hb]
        exact ih hnd.2 hφxs
    · simp only [List.filter_cons, hxv, Bool.false_eq_true, ↓reduceIte] at hnd
      have hb : (x.dst == φ.dst && Phi.live c x) = false := by simp [hxv]
      have hφxs : φ ∈ xs := by
        rcases List.mem_cons.1 hφ with rfl | h
        · exact absurd hv hxv
        · exact h
      rw [hb]
      exact ih hnd hφxs

theorem applyPhis_dst (c : Certificate) {phis : List Phi}
    (hnd : ((phis.filter (Phi.live c)).map (·.dst)).Nodup) {φ : Phi}
    (hφ : φ ∈ phis) (hv : Phi.live c φ = true) {b : BlockId} {o : ValId}
    (ho : φ.edges.lookup b = some o) (env : ValId → Val) :
    applyPhis c phis b env φ.dst =
      (if c.state φ.dst == .borrowed then (env o).toBorrowed else env o) := by
  unfold applyPhis
  rw [find_phi c phis hnd hφ hv]
  simp [ho]

theorem applyPhis_other (c : Certificate) {phis : List Phi} {n : ValId}
    (hn : ∀ φ ∈ phis, Phi.live c φ = true → φ.dst ≠ n) (b : BlockId)
    (env : ValId → Val) : applyPhis c phis b env n = env n := by
  unfold applyPhis
  have : phis.find? (fun φ => φ.dst == n && Phi.live c φ) = none := by
    rw [List.find?_eq_none]
    intro φ hφ h
    simp only [Bool.and_eq_true, beq_iff_eq] at h
    exact hn φ hφ h.2 h.1
  rw [this]

/-! ## What a passed edge check says -/

/-- The checks of an edge, as propositions. -/
structure EdgeOk (cc : CCtx) (σ : AbsState) (b : BlockId) (phis : List Phi) : Prop where
  nd : ((phis.filter (Phi.live cc.c)).map (·.dst)).Nodup
  shape : ∀ φ ∈ phis, Phi.live cc.c φ = true → ∀ o, φ.edges.lookup b = some o →
    phiShape cc φ o = true
  live : ∀ φ ∈ phis, Phi.live cc.c φ = true → ∀ o, φ.edges.lookup b = some o →
    (cc.st o).owning = true → (cc.st φ.dst).owning = true → o ∈ σ.L
  bor : ∀ φ ∈ phis, Phi.live cc.c φ = true → ∀ o, φ.edges.lookup b = some o →
    cc.st φ.dst = .borrowed → usable cc σ o = true
  nodupC : (edgeConsumed cc b phis).Nodup
  notP : ∀ o ∈ edgeConsumed cc b phis, σ.pendingAny o = false
  guard : ∀ g ∈ σ.G, ∀ φ ∈ phis, Phi.live cc.c φ = true → g.2.2.1.mentions φ.dst = false
  fresh : ∀ d ∈ edgeDsts cc phis, d ∉ without σ.L (edgeConsumed cc b phis)

theorem edgeOk_of_checks {σ : AbsState} {b : BlockId} {phis : List Phi}
    (h : firstFail (edgeChecks cc σ b phis) = none) : EdgeOk cc σ b phis := by
  have hall := chk_all h
  simp only [edgeChecks, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq] at hall
  obtain ⟨_hlen, hnd, hshape, _hpar, hlive, hbor, hnc, hnp, hg, hfresh⟩ := hall
  refine ⟨?_, ?_, ?_, ?_, (nodupB_iff _).1 hnc, ?_, ?_, ?_⟩
  · have := (nodupB_iff _).1 hnd
    simpa [livePhis] using this
  · intro φ hφ hv o ho
    exact List.all_eq_true.1 hshape (φ, o) (mem_edgeOps.2 ⟨hφ, hv, ho⟩)
  · intro φ hφ hv o ho h1 h2
    have := List.all_eq_true.1 hlive (φ, o) (mem_edgeOps.2 ⟨hφ, hv, ho⟩)
    simpa [h1, h2] using this
  · intro φ hφ hv o ho h1
    have := List.all_eq_true.1 hbor (φ, o) (mem_edgeOps.2 ⟨hφ, hv, ho⟩)
    simpa [h1] using this
  · intro o ho
    have := List.all_eq_true.1 hnp o ho
    simpa using this
  · intro g hg' φ hφ hv
    have h1 := List.all_eq_true.1 hg g hg'
    have h2 := List.all_eq_true.1 h1 φ (mem_livePhis.2 ⟨hφ, hv⟩)
    simpa using h2
  · intro d hd
    have := List.all_eq_true.1 hfresh d hd
    simpa using this

end Own
