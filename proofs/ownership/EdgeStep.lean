import EdgeBase

/-!
# A checked phi edge preserves the invariant
-/

namespace Own

/-- The machine state after entering a block along the edge from `b`: the live phis take their
values and the tests that depend on them are forgotten. -/
def DState.enter (c : Certificate) (ds : DState) (phis : List Phi) (b : BlockId) : DState :=
  { ds with env := applyPhis c phis b ds.env, facts := clearFacts ds.facts (phiDsts c phis) }

@[simp] theorem enter_heap (c : Certificate) (ds : DState) (phis : List Phi) (b : BlockId) :
    (ds.enter c phis b).heap = ds.heap := rfl

@[simp] theorem enter_pend (c : Certificate) (ds : DState) (phis : List Phi) (b : BlockId) :
    (ds.enter c phis b).pend = ds.pend := rfl

/-! ## Lookups in the root records of an edge -/

theorem lookup_append_none {β : Type} (l1 l2 : List (ValId × β)) (a : ValId)
    (h : l1.lookup a = none) : (l1 ++ l2).lookup a = l2.lookup a := by
  induction l1 with
  | nil => rfl
  | cons p ps ih =>
    by_cases e : (a == p.1) = true
    · simp only [List.lookup, e] at h; cases h
    · have e' : (a == p.1) = false := by simpa using e
      simp only [List.lookup, e'] at h
      simp only [List.cons_append, List.lookup, e']
      exact ih h

theorem lookup_append_some {β : Type} (l1 l2 : List (ValId × β)) (a : ValId) (v : β)
    (h : l1.lookup a = some v) : (l1 ++ l2).lookup a = some v := by
  induction l1 with
  | nil => simp [List.lookup] at h
  | cons p ps ih =>
    by_cases e : (a == p.1) = true
    · simp only [List.lookup, e] at h
      simp only [List.cons_append, List.lookup, e]
      exact h
    · have e' : (a == p.1) = false := by simpa using e
      simp only [List.lookup, e'] at h
      simp only [List.cons_append, List.lookup, e']
      exact ih h

theorem lookup_filter_pred {β : Type} (l : List (ValId × β)) (p : ValId × β → Bool) (a : ValId)
    (h : ∀ e ∈ l, e.1 = a → p e = true) : (l.filter p).lookup a = l.lookup a := by
  induction l with
  | nil => rfl
  | cons e es ih =>
    have ih' := ih (fun e' he' => h e' (List.mem_cons_of_mem _ he'))
    by_cases hp : p e = true
    · simp [List.filter_cons, hp, List.lookup, ih']
    · have hne : e.1 ≠ a := fun heq => hp (h e List.mem_cons_self heq)
      have : (a == e.1) = false := by
        have : a ≠ e.1 := fun h' => hne h'.symm
        simpa using this
      have hp' : p e = false := by simpa using hp
      simp [List.filter_cons, hp', List.lookup, this, ih']

theorem lookup_filterMap_none {β : Type} (l : List (ValId × β)) (g : ValId × β → Option (ValId × β))
    (a : ValId) (h : ∀ e ∈ l, ∀ e', g e = some e' → e'.1 ≠ a) : (l.filterMap g).lookup a = none := by
  induction l with
  | nil => rfl
  | cons e es ih =>
    have ih' := ih (fun e' he' => h e' (List.mem_cons_of_mem _ he'))
    cases hg : g e with
    | none => simp [List.filterMap_cons, hg, ih']
    | some e' =>
      have hne := h e List.mem_cons_self e' hg
      have : (a == e'.1) = false := by
        have : a ≠ e'.1 := fun h' => hne h'.symm
        simpa using this
      simp [List.filterMap_cons, hg, List.lookup, this, ih']

theorem lookup_eq_none_of_notin {β : Type} (l : List (ValId × β)) (a : ValId)
    (h : a ∉ l.map (·.1)) : l.lookup a = none := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.map_cons, List.mem_cons, not_or] at h
    have e : (a == p.1) = false := by simpa using h.1
    simp only [List.lookup, e]
    exact ih h.2

theorem lookup_eq_some_of_mem {β : Type} (l : List (ValId × β)) (hnd : (l.map (·.1)).Nodup)
    (a : ValId) (v : β) (h : (a, v) ∈ l) : l.lookup a = some v := by
  induction l with
  | nil => simp at h
  | cons p ps ih =>
    simp only [List.map_cons, List.nodup_cons] at hnd
    rcases List.mem_cons.1 h with rfl | h'
    · simp [List.lookup]
    · have hne : a ≠ p.1 := by
        intro heq
        exact hnd.1 (List.mem_map.2 ⟨(a, v), h', heq⟩)
      have e : (a == p.1) = false := by simpa using hne
      simp only [List.lookup, e]
      exact ih hnd.2 h'

theorem lookup_mem {β : Type} (l : List (ValId × β)) (a : ValId) (v : β)
    (h : l.lookup a = some v) : (a, v) ∈ l := by
  induction l with
  | nil => simp [List.lookup] at h
  | cons p ps ih =>
    by_cases e : (a == p.1) = true
    · simp only [List.lookup, e] at h
      have ha : a = p.1 := by simpa using e
      have : p = (a, v) := by cases p; simp_all
      rw [← this]; exact List.mem_cons_self
    · have e' : (a == p.1) = false := by simpa using e
      simp only [List.lookup, e'] at h
      exact List.mem_cons_of_mem _ (ih h)

theorem lookup_filter_none {β : Type} (l : List (ValId × β)) (p : ValId × β → Bool) (a : ValId)
    (h : ∀ e ∈ l, e.1 = a → p e = false) : (l.filter p).lookup a = none := by
  induction l with
  | nil => rfl
  | cons e es ih =>
    have ih' := ih (fun e' he' => h e' (List.mem_cons_of_mem _ he'))
    by_cases hp : p e = true
    · have hne : e.1 ≠ a := fun heq => by
        have := h e List.mem_cons_self heq
        rw [this] at hp; cases hp
      have : (a == e.1) = false := by
        have : a ≠ e.1 := fun h' => hne h'.symm
        simpa using this
      simp [List.filter_cons, hp, List.lookup, this, ih']
    · have hp' : p e = false := by simpa using hp
      simp [List.filter_cons, hp', ih']

theorem lookup_moveHolders (R : List (ValId × List Root)) (moves : List (ValId × ValId))
    {o h : ValId} (hm : moves.lookup o = some h) (hinj : ∀ e, moves.lookup e = some h → e = o) :
    (moveHolders R moves).lookup h = R.lookup o := by
  unfold moveHolders
  have hA : ∀ R' : List (ValId × List Root),
      (R'.filterMap fun p => (moves.lookup p.1).map fun h' => (h', p.2)).lookup h = R'.lookup o := by
    intro R'
    induction R' with
    | nil => rfl
    | cons p ps ih =>
      by_cases hp : p.1 = o
      · simp [List.filterMap_cons, hp, hm, List.lookup]
      · have hpo : (o == p.1) = false := by
          have : o ≠ p.1 := fun h' => hp h'.symm
          simpa using this
        cases hl : moves.lookup p.1 with
        | none => simp [List.filterMap_cons, hl, List.lookup, hpo, ih]
        | some h' =>
          have hne : (h == h') = false := by
            have : h ≠ h' := fun e => hp (hinj p.1 (by rw [hl, e]))
            simpa using this
          simp [List.filterMap_cons, hl, List.lookup, hpo, hne, ih]
  have hB : (R.filter fun p => (moves.lookup p.1).isNone && !moves.any (·.2 == p.1)).lookup h = none := by
    apply lookup_filter_none
    intro e _ he
    have : moves.any (·.2 == e.1) = true := by
      apply List.any_eq_true.2
      refine ⟨(o, h), ?_, by simp [he]⟩
      exact lookup_mem _ _ _ hm
    simp [this]
  cases hAh : (R.filterMap fun p => (moves.lookup p.1).map fun h' => (h', p.2)).lookup h with
  | none =>
    rw [lookup_append_none _ _ _ hAh, hB]
    rw [hA R] at hAh
    exact hAh.symm
  | some v =>
    rw [lookup_append_some _ _ _ _ hAh]
    rw [hA R] at hAh
    exact hAh.symm

theorem lookup_moveHolders_other (R : List (ValId × List Root)) (moves : List (ValId × ValId))
    {w : ValId} (hkey : moves.lookup w = none) (hdst : ∀ q ∈ moves, q.2 ≠ w) :
    (moveHolders R moves).lookup w = R.lookup w := by
  unfold moveHolders
  rw [lookup_append_none]
  · apply lookup_filter_pred
    intro e _ he
    have hne : ¬ moves.any (·.2 == w) = true := by
      intro hany
      obtain ⟨q, hq, hqw⟩ := List.any_eq_true.1 hany
      exact hdst q hq (by simpa using hqw)
    rw [he, hkey]; simp [hne]
  · apply lookup_filterMap_none
    intro e _ e' he'
    cases hl : moves.lookup e.1 with
    | none => rw [hl] at he'; simp at he'
    | some h =>
      rw [hl] at he'
      simp only [Option.map_some, Option.some.injEq] at he'
      subst he'
      intro hh
      exact hdst _ (lookup_mem _ _ _ hl) hh

theorem edgeOps_dst_nodup (cc : CCtx) (b : BlockId) (phis : List Phi)
    (hnd : ((phis.filter (Phi.live cc.c)).map (·.dst)).Nodup) :
    ((edgeOps cc b phis).map (·.1.dst)).Nodup := by
  unfold edgeOps livePhis
  generalize phis.filter (Phi.live cc.c) = l at hnd
  induction l with
  | nil => simp
  | cons φ φs ih =>
    simp only [List.map_cons, List.nodup_cons] at hnd
    cases hl : φ.edges.lookup b with
    | none => simpa [List.filterMap_cons, hl] using ih hnd.2
    | some o =>
      simp only [List.filterMap_cons, hl, Option.map_some, List.map_cons, List.nodup_cons]
      refine ⟨?_, ih hnd.2⟩
      intro hmem
      apply hnd.1
      obtain ⟨p, hp, hpd⟩ := List.mem_map.1 hmem
      obtain ⟨φ', hφ', hp'⟩ := List.mem_filterMap.1 hp
      cases hl' : φ'.edges.lookup b <;> simp [hl'] at hp'
      subst hp'
      exact List.mem_map.2 ⟨φ', hφ', hpd.symm ▸ rfl⟩

/-- The hypotheses of one edge step. -/
structure EC (cc : CCtx) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (σ : AbsState) (b : BlockId) (blk' : Block) (ds : DState) : Prop where
  hs : Static cc args h0 pend0
  hI : Inv cc args h0 σ ds
  hok : EdgeOk cc σ b blk'.phis
  hb : blk' ∈ cc.f.blocks
  hops : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → ∃ o, φ.edges.lookup b = some o

namespace EC

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {b : BlockId} {blk' : Block} {ds : DState}

theorem mem_L (c : EC cc args h0 pend0 σ b blk' ds) (v : ValId) :
    v ∈ (edgeNext cc σ b blk'.phis).L ↔
      v ∈ edgeDsts cc blk'.phis ∨ (v ∈ σ.L ∧ v ∉ edgeConsumed cc b blk'.phis) := by
  simp [edgeNext, mem_without]

theorem mem_D (c : EC cc args h0 pend0 σ b blk' ds) (w : ValId) :
    w ∈ (edgeNext cc σ b blk'.phis).D ↔
      w ∈ edgeBdsts cc blk'.phis ∨ (w ∈ σ.D ∧ w ∉ edgeBdsts cc blk'.phis ∧
        ∀ d ∈ edgeDsts cc blk'.phis, ∀ ρ ∈ Rget σ w, ρ.ownedBy d = false) := by
  simp only [edgeNext, List.mem_append, List.mem_filter, Bool.and_eq_true, Bool.not_eq_true',
    List.all_eq_true, List.any_eq_false]
  constructor
  · rintro (h | ⟨h1, h2, h3⟩)
    · exact Or.inl h
    · exact Or.inr ⟨h1, by simpa using h2, fun d hd ρ hρ => by simpa using h3 d hd ρ hρ⟩
  · rintro (h | ⟨h1, h2, h3⟩)
    · exact Or.inl h
    · exact Or.inr ⟨h1, by simpa using h2, fun d hd ρ hρ => by simpa using h3 d hd ρ hρ⟩

theorem not_dst (c : EC cc args h0 pend0 σ b blk' ds) {v : ValId} (hv : v ∈ σ.L)
    (hvo : v ∉ edgeConsumed cc b blk'.phis) :
    ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → φ.dst ≠ v := by
  intro φ hφ hl heq
  have hown := c.hI.Lown v hv
  exact c.hok.fresh v (mem_edgeDsts.2 ⟨φ, hφ, hl, heq, hown⟩) ((mem_without _ _ _).2 ⟨hv, hvo⟩)

theorem env_old (c : EC cc args h0 pend0 σ b blk' ds) {v : ValId} (hv : v ∈ σ.L)
    (hvo : v ∉ edgeConsumed cc b blk'.phis) :
    (ds.enter cc.c blk'.phis b).env v = ds.env v :=
  applyPhis_other cc.c (c.not_dst hv hvo) b ds.env

theorem env_phi (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o) :
    (ds.enter cc.c blk'.phis b).env φ.dst =
      (if cc.c.state φ.dst == .borrowed then (ds.env o).toBorrowed else ds.env o) :=
  applyPhis_dst cc.c c.hok.nd hφ hl ho ds.env

/-- A phi that is not borrowed copies its operand. -/
theorem env_phi_nb (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o)
    (hnb : cc.st φ.dst ≠ .borrowed) : (ds.enter cc.c blk'.phis b).env φ.dst = ds.env o := by
  rw [c.env_phi hφ hl ho]
  have : (cc.c.state φ.dst == .borrowed) = false := by
    have : cc.st φ.dst ≠ .borrowed := hnb
    simpa [CCtx.st] using this
  simp [this]

/-- The operand of an owning phi is a live owning value, or an immortal. -/
theorem src_cases (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o)
    (hown : (cc.st φ.dst).owning = true) :
    ((cc.st o).owning = true ∧ o ∈ σ.L) ∨ cc.st o = .immortal := by
  have hsh := c.hok.shape φ hφ hl o ho
  have hd := owning_iff.1 hown
  unfold phiShape at hsh
  rw [hd] at hsh
  simp only [Bool.or_eq_true, beq_iff_eq] at hsh
  rcases hsh with h | h
  · left
    have ho' : (cc.st o).owning = true := by rw [h]; rfl
    exact ⟨ho', c.hok.live φ hφ hl o ho ho' hown⟩
  · right; exact h

theorem toBorrowed_stk {v : Val} (h : v.toBorrowed = .stk) : v = .stk := by
  cases v <;> simp [Val.toBorrowed] at h ⊢

/-- A phi of a stack list takes a stack operand; a phi of any other kind does not. -/
theorem shape_stack (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o) :
    (cc.st φ.dst = .stack ↔ cc.st o = .stack) := by
  have hsh := c.hok.shape φ hφ hl o ho
  unfold phiShape at hsh
  cases hs : cc.st φ.dst <;> cases ho' : cc.st o <;> simp [hs, ho'] at hsh ⊢

theorem imm' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v, (cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .emptied ∨
      cc.st v = .none) → (ds.enter cc.c blk'.phis b).env v = .imm := by
  intro v hv
  by_cases hd : ∃ φ ∈ blk'.phis, Phi.live cc.c φ = true ∧ φ.dst = v
  · obtain ⟨φ, hφ, hl, rfl⟩ := hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by
      rcases hv with h | h | h | h <;> rw [h] <;> simp
    rw [c.env_phi_nb hφ hl ho hnb]
    have hsh := c.hok.shape φ hφ hl o ho
    unfold phiShape at hsh
    rcases hv with h | h | h | h <;> rw [h] at hsh <;> simp only [beq_iff_eq] at hsh
    · exact c.hI.imm o (by simp [hsh])
    · exact c.hI.imm o (by simp [hsh])
    · simp at hsh
    · -- a live phi is not `none`
      exfalso
      have h' : cc.c.state φ.dst = .none := h
      simp [Phi.live, h'] at hl
  · rw [show (ds.enter cc.c blk'.phis b).env v = ds.env v from
      applyPhis_other cc.c (fun φ hφ hl h => hd ⟨φ, hφ, hl, h⟩) b ds.env]
    exact c.hI.imm v hv

theorem stk' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v, cc.st v = .stack → (ds.enter cc.c blk'.phis b).env v = .imm ∨
      (ds.enter cc.c blk'.phis b).env v = .stk := by
  intro v hv
  by_cases hd : ∃ φ ∈ blk'.phis, Phi.live cc.c φ = true ∧ φ.dst = v
  · obtain ⟨φ, hφ, hl, rfl⟩ := hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [hv]; simp
    rw [c.env_phi_nb hφ hl ho hnb]
    exact c.hI.stk o ((c.shape_stack hφ hl ho).1 hv)
  · rw [show (ds.enter cc.c blk'.phis b).env v = ds.env v from
      applyPhis_other cc.c (fun φ hφ hl h => hd ⟨φ, hφ, hl, h⟩) b ds.env]
    exact c.hI.stk v hv

theorem nostk' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v, cc.st v ≠ .stack → (ds.enter cc.c blk'.phis b).env v ≠ .stk := by
  intro v hv
  by_cases hd : ∃ φ ∈ blk'.phis, Phi.live cc.c φ = true ∧ φ.dst = v
  · obtain ⟨φ, hφ, hl, rfl⟩ := hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hso : cc.st o ≠ .stack := fun h => hv ((c.shape_stack hφ hl ho).2 h)
    have hon := c.hI.nostk o hso
    rw [c.env_phi hφ hl ho]
    by_cases hb : (cc.c.state φ.dst == .borrowed) = true
    · simp only [hb, ↓reduceIte]
      exact fun h => hon (toBorrowed_stk h)
    · simp only [hb, Bool.false_eq_true, ↓reduceIte]
      exact hon
  · rw [show (ds.enter cc.c blk'.phis b).env v = ds.env v from
      applyPhis_other cc.c (fun φ hφ hl h => hd ⟨φ, hφ, hl, h⟩) b ds.env]
    exact c.hI.nostk v hv

theorem Lown' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, (cc.st v).owning = true := by
  intro v hv
  rcases (c.mem_L v).1 hv with h | ⟨h, _⟩
  · obtain ⟨φ, _, _, rfl, hown⟩ := mem_edgeDsts.1 h; exact hown
  · exact c.hI.Lown v h

theorem Lbd' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, v < cc.f.nvals := by
  intro v hv
  rcases (c.mem_L v).1 hv with h | ⟨h, _⟩
  · obtain ⟨φ, hφ, _, rfl, _⟩ := mem_edgeDsts.1 h
    exact phi_dst_lt cc.f blk' φ c.hb hφ
  · exact c.hI.Lbd v h

theorem Lval' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, (ds.enter cc.c blk'.phis b).env v = .imm ∨
      ∃ t, (ds.enter cc.c blk'.phis b).env v = .own t ∧
        (ds.enter cc.c blk'.phis b).heap t = .live t := by
  intro v hv
  rcases (c.mem_L v).1 hv with h | ⟨hvL, hvo⟩
  · obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 h
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 hown]; simp
    rw [c.env_phi_nb hφ hl ho hnb]
    rcases c.src_cases hφ hl ho hown with ⟨_, hoL⟩ | himm
    · exact c.hI.Lval o hoL
    · left; exact c.hI.imm o (Or.inr (Or.inl himm))
  · rw [c.env_old hvL hvo]
    exact c.hI.Lval v hvL

theorem Linj' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, ∀ w ∈ (edgeNext cc σ b blk'.phis).L, ∀ t,
      (ds.enter cc.c blk'.phis b).env v = .own t →
      (ds.enter cc.c blk'.phis b).env w = .own t → v = w := by
  intro v hv w hw t hvt hwt
  have hnbo : ∀ φ ∈ blk'.phis, (cc.st φ.dst).owning = true → cc.st φ.dst ≠ .borrowed := by
    intro φ _ hown; rw [owning_iff.1 hown]; simp
  rcases (c.mem_L v).1 hv with hd | ⟨hvL, hvo⟩ <;> rcases (c.mem_L w).1 hw with hd' | ⟨hwL, hwo⟩
  · -- both phi values
    obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd
    obtain ⟨ψ, hψ, hl', rfl, hown'⟩ := mem_edgeDsts.1 hd'
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    obtain ⟨o', ho'⟩ := c.hops ψ hψ hl'
    rw [c.env_phi_nb hφ hl ho (hnbo φ hφ hown)] at hvt
    rw [c.env_phi_nb hψ hl' ho' (hnbo ψ hψ hown')] at hwt
    rcases c.src_cases hφ hl ho hown with ⟨hoo, hoL⟩ | hi
    · rcases c.src_cases hψ hl' ho' hown' with ⟨hoo', hoL'⟩ | hi'
      · have heq := c.hI.Linj o hoL o' hoL' t hvt hwt
        subst heq
        have e1 : consOf cc b φ = some o := by simp [consOf, hl, ho, hown, hoo]
        have e2 : consOf cc b ψ = some o := by simp [consOf, hl', ho', hown', hoo']
        have hnd : (blk'.phis.filterMap (consOf cc b)).Nodup := by
          rw [← edgeConsumed_eq]; exact c.hok.nodupC
        rw [consumed_inj b _ hnd φ hφ ψ hψ o e1 e2]
      · rw [c.hI.imm o' (Or.inr (Or.inl hi'))] at hwt; cases hwt
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hvt; cases hvt
  · -- v a phi value, w old
    obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    rw [c.env_phi_nb hφ hl ho (hnbo φ hφ hown)] at hvt
    rw [c.env_old hwL hwo] at hwt
    rcases c.src_cases hφ hl ho hown with ⟨hoo, hoL⟩ | hi
    · have heq := c.hI.Linj o hoL w hwL t hvt hwt
      subst heq
      exact absurd (mem_edgeConsumed.2 ⟨φ, hφ, hl, ho, hown, hoo⟩) hwo
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hvt; cases hvt
  · obtain ⟨ψ, hψ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd'
    obtain ⟨o, ho⟩ := c.hops ψ hψ hl
    rw [c.env_phi_nb hψ hl ho (hnbo ψ hψ hown)] at hwt
    rw [c.env_old hvL hvo] at hvt
    rcases c.src_cases hψ hl ho hown with ⟨hoo, hoL⟩ | hi
    · have heq := c.hI.Linj v hvL o hoL t hvt hwt
      subst heq
      exact absurd (mem_edgeConsumed.2 ⟨ψ, hψ, hl, ho, hown, hoo⟩) hvo
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hwt; cases hwt
  · rw [c.env_old hvL hvo] at hvt
    rw [c.env_old hwL hwo] at hwt
    exact c.hI.Linj v hvL w hwL t hvt hwt

theorem Dst' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ w ∈ (edgeNext cc σ b blk'.phis).D, cc.st w = .borrowed := by
  intro w hw
  rcases (c.mem_D w).1 hw with h | ⟨h, _⟩
  · obtain ⟨φ, _, _, rfl, hb⟩ := mem_edgeBdsts.1 h; exact hb
  · exact c.hI.Dst w h

theorem Dbd' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ w ∈ (edgeNext cc σ b blk'.phis).D, w < cc.f.nvals := by
  intro w hw
  rcases (c.mem_D w).1 hw with h | ⟨h, _⟩
  · obtain ⟨φ, hφ, _, rfl, _⟩ := mem_edgeBdsts.1 h
    exact phi_dst_lt cc.f blk' φ c.hb hφ
  · exact c.hI.Dbd w h

/-- Every phi operand along a checked edge can be read. -/
theorem operand_alive (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o) :
    (ds.env o).alive ds.heap := by
  have hsh := c.hok.shape φ hφ hl o ho
  unfold phiShape at hsh
  cases hst : cc.st φ.dst
  all_goals rw [hst] at hsh
  · simp only [beq_iff_eq] at hsh; exact usable_alive c.hs c.hI (usable_imm (Or.inl hsh))
  · simp only [beq_iff_eq] at hsh; exact usable_alive c.hs c.hI (usable_imm (Or.inr hsh))
  · rcases c.src_cases hφ hl ho (by rw [hst]; rfl) with ⟨_, hoL⟩ | hi
    · exact alive_of_L c.hI hoL
    · exact usable_alive c.hs c.hI (usable_imm (Or.inr hi))
  · simp only [beq_iff_eq] at hsh
    exact usable_alive c.hs c.hI (by simp [usable, hsh])
  · exact usable_alive c.hs c.hI (c.hok.bor φ hφ hl o ho hst)
  · simp at hsh
  · simp at hsh

theorem Dval' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ w ∈ (edgeNext cc σ b blk'.phis).D,
      (ds.enter cc.c blk'.phis b).env w = .imm ∨
        ∃ fp, (ds.enter cc.c blk'.phis b).env w = .bor fp := by
  intro w hw
  rcases (c.mem_D w).1 hw with hnew | ⟨hD, hnb, _⟩
  · obtain ⟨φ, hφ, hl, rfl, hb⟩ := mem_edgeBdsts.1 hnew
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    rw [c.env_phi hφ hl ho]
    have hb' : (cc.c.state φ.dst == .borrowed) = true := by simpa [CCtx.st] using hb
    simp only [hb', ↓reduceIte]
    have hsh := c.hok.shape φ hφ hl o ho
    unfold phiShape at hsh
    rw [hb] at hsh
    simp only [Bool.or_eq_true, beq_iff_eq] at hsh
    rcases hsh with (h | h) | h
    · obtain ⟨hD, _⟩ := usable_borrowed h (c.hok.bor φ hφ hl o ho hb)
      rcases c.hI.Dval o hD with h' | ⟨fp, h'⟩
      · left; rw [h']; rfl
      · right; exact ⟨fp, by rw [h']; rfl⟩
    · left; rw [c.hI.imm o (Or.inr (Or.inl h))]; rfl
    · have hoL : o ∈ σ.L := usable_owning (by simp [h, St.owning]) (c.hok.bor φ hφ hl o ho hb)
      rcases c.hI.Lval o hoL with h' | ⟨t, h', _⟩
      · left; rw [h']; rfl
      · right; exact ⟨[t], by rw [h']; rfl⟩
  · have hnd : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → φ.dst ≠ w := by
      intro φ hφ hl heq
      apply hnb
      exact mem_edgeBdsts.2 ⟨φ, hφ, hl, heq, c.hI.Dst w hD⟩
    rw [show (ds.enter cc.c blk'.phis b).env w = ds.env w from applyPhis_other cc.c hnd b ds.env]
    exact c.hI.Dval w hD

theorem moves_owning (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ p ∈ edgeMoves cc b blk'.phis, (cc.st p.1).owning = true ∧ (cc.st p.2).owning = true := by
  rintro ⟨o, h⟩ hp
  obtain ⟨φ, _, _, _, rfl, h1, h2⟩ := mem_edgeMoves.1 hp
  exact ⟨h2, h1⟩

theorem moves_lookup_consumed (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi}
    (hφ : φ ∈ blk'.phis) (hl : Phi.live cc.c φ = true) {o : ValId}
    (ho : φ.edges.lookup b = some o) (hown : (cc.st φ.dst).owning = true)
    (hoo : (cc.st o).owning = true) :
    (edgeMoves cc b blk'.phis).lookup o = some φ.dst :=
  lookup_eq_some_of_mem _ (by
    have : (edgeMoves cc b blk'.phis).map (·.1) = edgeConsumed cc b blk'.phis := rfl
    rw [this]; exact c.hok.nodupC) o φ.dst (mem_edgeMoves.2 ⟨φ, hφ, hl, ho, rfl, hown, hoo⟩)

theorem moves_lookup_other (c : EC cc args h0 pend0 σ b blk' ds) {v : ValId}
    (hv : v ∉ edgeConsumed cc b blk'.phis) : (edgeMoves cc b blk'.phis).lookup v = none :=
  lookup_eq_none_of_notin _ v (by
    have : (edgeMoves cc b blk'.phis).map (·.1) = edgeConsumed cc b blk'.phis := rfl
    rw [this]; exact hv)

/-- A root of the old state, renamed by the edge's moves, keeps its cells. -/
theorem rename_covers (c : EC cc args h0 pend0 σ b blk' ds) {ρ0 : Root}
    (hf : ρ0.isFwd = false) (hl : rootLive σ ρ0 = true) {x : Addr}
    (h : Covers cc args h0 ds ρ0 x) :
    Covers cc args h0 (ds.enter cc.c blk'.phis b)
      (renameRoot1 (edgeMoves cc b blk'.phis) false ρ0) x := by
  cases ρ0 with
  | caller j => exact h
  | fwd n => simp [Root.isFwd] at hf
  | val n =>
    have hnL : n ∈ σ.L := (rootLive_val σ n).1 hl
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hn
      rw [renameRoot1, c.moves_lookup_consumed hφ hv ho h1 h2]
      obtain ⟨t, ht, hx⟩ := h
      refine ⟨t, ?_, hx⟩
      have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 h1]; simp
      rw [c.env_phi_nb hφ hv ho hnb]; exact ht
    · rw [renameRoot1, c.moves_lookup_other hn]
      obtain ⟨t, ht, hx⟩ := h
      exact ⟨t, by rw [c.env_old hnL hn]; exact ht, hx⟩
  | slot n k =>
    have hnL : n ∈ σ.L := (rootLive_slot σ n k).1 hl
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hn
      rw [renameRoot1, c.moves_lookup_consumed hφ hv ho h1 h2]
      obtain ⟨t, ht, hx⟩ := h
      refine ⟨t, ?_, hx⟩
      have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 h1]; simp
      rw [c.env_phi_nb hφ hv ho hnb]; exact ht
    · rw [renameRoot1, c.moves_lookup_other hn]
      obtain ⟨t, ht, hx⟩ := h
      exact ⟨t, by rw [c.env_old hnL hn]; exact ht, hx⟩

theorem edgeNext_R (cc : CCtx) (σ : AbsState) (b : BlockId) (phis : List Phi) :
    (edgeNext cc σ b phis).R =
      edgeFresh cc σ b phis ++
        renameAll (moveHolders σ.R (edgeMoves cc b phis)) (edgeMoves cc b phis) false := rfl

theorem Rget_edge_old (c : EC cc args h0 pend0 σ b blk' ds) {w : ValId} (hD : w ∈ σ.D)
    (hnb : w ∉ edgeBdsts cc blk'.phis) :
    Rget (edgeNext cc σ b blk'.phis) w =
      normRoots ((Rget σ w).map (renameRoot1 (edgeMoves cc b blk'.phis) false)) := by
  have hwb := c.hI.Dst w hD
  unfold Rget
  rw [edgeNext_R]
  have hfresh : (edgeFresh cc σ b blk'.phis).lookup w = none := by
    apply lookup_eq_none_of_notin
    intro hmem
    obtain ⟨p, hp, hpw⟩ := List.mem_map.1 hmem
    obtain ⟨p', hp', rfl⟩ := List.mem_map.1 hp
    rw [List.mem_filter] at hp'
    obtain ⟨hp1, hp2⟩ := hp'
    obtain ⟨φ, o⟩ := p'
    obtain ⟨hφ, hv, _⟩ := mem_edgeOps.1 hp1
    apply hnb
    exact mem_edgeBdsts.2 ⟨φ, hφ, hv, hpw, by rw [← hpw]; simpa using hp2⟩
  rw [lookup_append_none _ _ _ hfresh]
  rw [getD_renameAll]
  have hmv : (moveHolders σ.R (edgeMoves cc b blk'.phis)).lookup w = σ.R.lookup w := by
    unfold moveHolders
    have hnot : w ∉ edgeConsumed cc b blk'.phis := by
      intro hw
      have := c.moves_owning
      obtain ⟨φ, _, _, _, h1, h2⟩ := mem_edgeConsumed.1 hw
      rw [hwb] at h2; simp [St.owning] at h2
    have h1 : (edgeMoves cc b blk'.phis).lookup w = none := c.moves_lookup_other hnot
    rw [lookup_append_none]
    · apply lookup_filter_pred
      intro e _ he
      have hne : ¬ (edgeMoves cc b blk'.phis).any (·.2 == w) = true := by
        intro hany
        obtain ⟨q, hq, hqw⟩ := List.any_eq_true.1 hany
        have := (c.moves_owning q hq).2
        have hqw' : q.2 = w := by simpa using hqw
        rw [hqw', hwb] at this; simp [St.owning] at this
      rw [he, h1]
      simp [hne]
    · apply lookup_filterMap_none
      intro e _ e' he'
      cases hl : (edgeMoves cc b blk'.phis).lookup e.1 with
      | none => rw [hl] at he'; simp at he'
      | some h =>
        rw [hl] at he'
        simp only [Option.map_some, Option.some.injEq] at he'
        subst he'
        intro hh
        have hmem := lookup_mem _ _ _ hl
        have := (c.moves_owning _ hmem).2
        simp only [] at hh this
        rw [hh, hwb] at this; simp [St.owning] at this
  rw [hmv]

theorem Rget_edge_new (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o)
    (hb : cc.st φ.dst = .borrowed) :
    Rget (edgeNext cc σ b blk'.phis) φ.dst =
      normRoots ((rootsOf cc σ o).map (renameRoot1 (edgeMoves cc b blk'.phis) false)) := by
  unfold Rget
  rw [edgeNext_R]
  have hmem : (φ.dst, normRoots ((rootsOf cc σ o).map (renameRoot1 (edgeMoves cc b blk'.phis) false)))
      ∈ edgeFresh cc σ b blk'.phis := by
    unfold edgeFresh
    refine List.mem_map.2 ⟨(φ, o), ?_, rfl⟩
    rw [List.mem_filter]
    exact ⟨mem_edgeOps.2 ⟨hφ, hl, ho⟩, by simpa using hb⟩
  have hnd : ((edgeFresh cc σ b blk'.phis).map (·.1)).Nodup := by
    unfold edgeFresh
    rw [List.map_map]
    have hn := edgeOps_dst_nodup cc b blk'.phis c.hok.nd
    have : ((edgeOps cc b blk'.phis).filter fun p => cc.st p.1.dst == .borrowed).map (·.1.dst) =
        ((edgeOps cc b blk'.phis).filter fun p => cc.st p.1.dst == .borrowed).map
          ((fun p => p.1) ∘ fun p => (p.1.dst, normRoots
            ((rootsOf cc σ p.2).map (renameRoot1 (edgeMoves cc b blk'.phis) false)))) := rfl
    rw [← this]
    exact (hn.sublist ((List.filter_sublist).map _))
  rw [lookup_append_some _ _ _ _ (lookup_eq_some_of_mem _ hnd _ _ hmem)]
  rfl

theorem consumed_live (c : EC cc args h0 pend0 σ b blk' ds) {n : ValId}
    (hn : n ∈ edgeConsumed cc b blk'.phis) : n ∈ σ.L := by
  obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hn
  exact c.hok.live φ hφ hv n ho h2 h1

theorem rename_isFwd (moves : List (ValId × ValId)) (ρ : Root) :
    (renameRoot1 moves false ρ).isFwd = ρ.isFwd := by
  cases ρ with
  | val n => cases hm : moves.lookup n <;> simp [renameRoot1, hm, Root.isFwd]
  | slot n k => cases hm : moves.lookup n <;> simp [renameRoot1, hm, Root.isFwd]
  | caller j => simp [renameRoot1, Root.isFwd]
  | fwd n => simp [renameRoot1, Root.isFwd]

/-- A renamed root that is alive after the edge came from a root that was alive before it. -/
theorem live_of_renamed (c : EC cc args h0 pend0 σ b blk' ds) {ρ0 : Root}
    (hf : ρ0.isFwd = false)
    (hnd : ∀ d ∈ edgeDsts cc blk'.phis, ρ0.ownedBy d = false)
    (h : rootLive (edgeNext cc σ b blk'.phis) (renameRoot1 (edgeMoves cc b blk'.phis) false ρ0) = true) :
    rootLive σ ρ0 = true := by
  cases ρ0 with
  | caller j => rfl
  | fwd n => simp [Root.isFwd] at hf
  | val n =>
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · exact (rootLive_val σ n).2 (c.consumed_live hn)
    · rw [renameRoot1, c.moves_lookup_other hn] at h
      have hnL := (rootLive_val _ n).1 h
      rcases (c.mem_L n).1 hnL with hd | ⟨hL, _⟩
      · have := hnd n hd
        simp [Root.ownedBy] at this
      · exact (rootLive_val σ n).2 hL
  | slot n k =>
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · exact (rootLive_slot σ n k).2 (c.consumed_live hn)
    · rw [renameRoot1, c.moves_lookup_other hn] at h
      have hnL := (rootLive_slot _ n k).1 h
      rcases (c.mem_L n).1 hnL with hd | ⟨hL, _⟩
      · have := hnd n hd
        simp [Root.ownedBy] at this
      · exact (rootLive_slot σ n k).2 hL

/-- Two moves into one phi value start at one operand. -/
theorem moves_inj (c : EC cc args h0 pend0 σ b blk' ds) {e o h : ValId}
    (he : (edgeMoves cc b blk'.phis).lookup e = some h)
    (ho : (edgeMoves cc b blk'.phis).lookup o = some h) : e = o := by
  obtain ⟨φ, hφ, hl, hlk, hd, _, _⟩ := mem_edgeMoves.1 (lookup_mem _ _ _ he)
  obtain ⟨ψ, hψ, hl', hlk', hd', _, _⟩ := mem_edgeMoves.1 (lookup_mem _ _ _ ho)
  have h1 := find_phi cc.c blk'.phis c.hok.nd hφ hl
  have h2 := find_phi cc.c blk'.phis c.hok.nd hψ hl'
  have hdd : φ.dst = ψ.dst := hd.trans hd'.symm
  rw [← hdd] at h2
  have hφψ : φ = ψ := Option.some.inj (h1.symm.trans h2)
  subst hφψ
  rw [hlk] at hlk'
  exact Option.some.inj hlk'

/-- The loans of an owner an owned phi takes over are those of the phi value, renamed. -/
theorem Rget_edge_moved (c : EC cc args h0 pend0 σ b blk' ds) {φ : Phi} (hφ : φ ∈ blk'.phis)
    (hl : Phi.live cc.c φ = true) {o : ValId} (ho : φ.edges.lookup b = some o)
    (h1 : (cc.st φ.dst).owning = true) (h2 : (cc.st o).owning = true) :
    Rget (edgeNext cc σ b blk'.phis) φ.dst =
      normRoots ((Rget σ o).map (renameRoot1 (edgeMoves cc b blk'.phis) false)) := by
  have hm := c.moves_lookup_consumed hφ hl ho h1 h2
  unfold Rget
  rw [edgeNext_R]
  have hfresh : (edgeFresh cc σ b blk'.phis).lookup φ.dst = none := by
    apply lookup_eq_none_of_notin
    intro hmem
    obtain ⟨p, hp, hpw⟩ := List.mem_map.1 hmem
    obtain ⟨p', hp', rfl⟩ := List.mem_map.1 hp
    rw [List.mem_filter] at hp'
    obtain ⟨_, hp2⟩ := hp'
    have hb : cc.st φ.dst = .borrowed := by
      rw [← hpw]; simpa using hp2
    rw [hb] at h1; simp [St.owning] at h1
  rw [lookup_append_none _ _ _ hfresh, getD_renameAll,
    lookup_moveHolders σ.R _ hm (fun e he => c.moves_inj he hm)]

/-- The loans of an owner the edge keeps are renamed by the edge's moves. -/
theorem Rget_edge_keepL (c : EC cc args h0 pend0 σ b blk' ds) {w : ValId} (hwL : w ∈ σ.L)
    (hwo : w ∉ edgeConsumed cc b blk'.phis) :
    Rget (edgeNext cc σ b blk'.phis) w =
      normRoots ((Rget σ w).map (renameRoot1 (edgeMoves cc b blk'.phis) false)) := by
  have hwown := c.hI.Lown w hwL
  unfold Rget
  rw [edgeNext_R]
  have hfresh : (edgeFresh cc σ b blk'.phis).lookup w = none := by
    apply lookup_eq_none_of_notin
    intro hmem
    obtain ⟨p, hp, hpw⟩ := List.mem_map.1 hmem
    obtain ⟨p', hp', rfl⟩ := List.mem_map.1 hp
    rw [List.mem_filter] at hp'
    obtain ⟨_, hp2⟩ := hp'
    have hb : cc.st w = .borrowed := by
      rw [← hpw]; simpa using hp2
    rw [hb] at hwown; simp [St.owning] at hwown
  rw [lookup_append_none _ _ _ hfresh, getD_renameAll]
  have hdst : ∀ q ∈ edgeMoves cc b blk'.phis, q.2 ≠ w := by
    intro q hq hqw
    obtain ⟨φ, hφ, hv, _, hd, _, _⟩ := mem_edgeMoves.1 (show (q.1, q.2) ∈ _ from hq)
    exact c.not_dst hwL hwo φ hφ hv (hd.trans hqw)
  rw [lookup_moveHolders_other σ.R _ (c.moves_lookup_other hwo) hdst]

/-- A root that is alive before the edge and not a placeholder is alive, renamed, after it. -/
theorem live_rename (c : EC cc args h0 pend0 σ b blk' ds) {ρ : Root} (hf : ρ.isFwd = false)
    (hl : rootLive σ ρ = true) :
    rootLive (edgeNext cc σ b blk'.phis) (renameRoot1 (edgeMoves cc b blk'.phis) false ρ) = true := by
  cases ρ with
  | caller j => rfl
  | fwd n => simp [Root.isFwd] at hf
  | val n =>
    have hnL : n ∈ σ.L := (rootLive_val σ n).1 hl
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hn
      rw [renameRoot1, c.moves_lookup_consumed hφ hv ho h1 h2]
      exact (rootLive_val _ _).2 ((c.mem_L _).2 (Or.inl (mem_edgeDsts.2 ⟨φ, hφ, hv, rfl, h1⟩)))
    · rw [renameRoot1, c.moves_lookup_other hn]
      exact (rootLive_val _ _).2 ((c.mem_L _).2 (Or.inr ⟨hnL, hn⟩))
  | slot n k =>
    have hnL : n ∈ σ.L := (rootLive_slot σ n k).1 hl
    by_cases hn : n ∈ edgeConsumed cc b blk'.phis
    · obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hn
      rw [renameRoot1, c.moves_lookup_consumed hφ hv ho h1 h2]
      exact (rootLive_slot _ _ _).2 ((c.mem_L _).2 (Or.inl (mem_edgeDsts.2 ⟨φ, hφ, hv, rfl, h1⟩)))
    · rw [renameRoot1, c.moves_lookup_other hn]
      exact (rootLive_slot _ _ _).2 ((c.mem_L _).2 (Or.inr ⟨hnL, hn⟩))

theorem heldSeen' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ g x, (ds.enter cc.c blk'.phis b).held g x → (ds.enter cc.c blk'.phis b).heap g ≠ .unused :=
  fun g x h => c.hI.heldSeen g x h

theorem heldCov' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ g x, (ds.enter cc.c blk'.phis b).held g x →
      (∃ l, (ds.enter cc.c blk'.phis b).heap g = .live l) →
      ∃ v ∈ (edgeNext cc σ b blk'.phis).L, ∃ t, (ds.enter cc.c blk'.phis b).env v = .own t ∧
        (ds.enter cc.c blk'.phis b).heap g = .live t ∧
        ((ds.enter cc.c blk'.phis b).heap x = .live t ∨
          ∃ ρ ∈ Rget (edgeNext cc σ b blk'.phis) v, ρ.isFwd = false ∧
            rootLive (edgeNext cc σ b blk'.phis) ρ = true ∧
            Covers cc args h0 (ds.enter cc.c blk'.phis b) ρ x) := by
  intro g x hh hgl
  obtain ⟨v, hvL, tv, hvt, hgv, hcv⟩ := c.hI.heldCov g x hh hgl
  by_cases hvo : v ∈ edgeConsumed cc b blk'.phis
  · -- the holder moves into an owned phi value
    obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hvo
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 h1]; simp
    refine ⟨φ.dst, (c.mem_L _).2 (Or.inl (mem_edgeDsts.2 ⟨φ, hφ, hv, rfl, h1⟩)), tv,
      by rw [c.env_phi_nb hφ hv ho hnb]; exact hvt, hgv, ?_⟩
    rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
    · exact Or.inl hsame
    · right
      rw [c.Rget_edge_moved hφ hv ho h1 h2]
      refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ,
        mem_normRoots.2 (List.mem_map.2 ⟨ρ, hρ, rfl⟩), ?_, c.live_rename hfwd hlive,
        c.rename_covers hfwd hlive hcov⟩
      rw [rename_isFwd]; exact hfwd
  · -- the holder stays
    have hvL' := (c.mem_L v).2 (Or.inr ⟨hvL, hvo⟩)
    refine ⟨v, hvL', tv, by rw [c.env_old hvL hvo]; exact hvt, hgv, ?_⟩
    rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
    · exact Or.inl hsame
    · right
      rw [c.Rget_edge_keepL hvL hvo]
      refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ,
        mem_normRoots.2 (List.mem_map.2 ⟨ρ, hρ, rfl⟩), ?_, c.live_rename hfwd hlive,
        c.rename_covers hfwd hlive hcov⟩
      rw [rename_isFwd]; exact hfwd

theorem lentSeen' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ g x, (ds.enter cc.c blk'.phis b).lent g x → (ds.enter cc.c blk'.phis b).heap g ≠ .unused :=
  fun g x h => c.hI.lentSeen g x h

theorem lentCov' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ g x, (ds.enter cc.c blk'.phis b).lent g x →
      (∃ l, (ds.enter cc.c blk'.phis b).heap g = .live l) →
      ∃ v ∈ (edgeNext cc σ b blk'.phis).L, ∃ t, (ds.enter cc.c blk'.phis b).env v = .own t ∧
        (ds.enter cc.c blk'.phis b).heap g = .live t ∧
        Root.val v ∈ Rget (edgeNext cc σ b blk'.phis) v ∧
        ∃ ρ ∈ Rget (edgeNext cc σ b blk'.phis) v, ρ.isFwd = false ∧
          rootLive (edgeNext cc σ b blk'.phis) ρ = true ∧
          Covers cc args h0 (ds.enter cc.c blk'.phis b) ρ x := by
  intro g x hl hgl
  obtain ⟨v, hvL, tv, hvt, hgv, hmark, ρ, hρ, hfwd, hlive, hcov⟩ := c.hI.lentCov g x hl hgl
  by_cases hvo : v ∈ edgeConsumed cc b blk'.phis
  · -- the holder moves into an owned phi value
    obtain ⟨φ, hφ, hv, ho, h1, h2⟩ := mem_edgeConsumed.1 hvo
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 h1]; simp
    refine ⟨φ.dst, (c.mem_L _).2 (Or.inl (mem_edgeDsts.2 ⟨φ, hφ, hv, rfl, h1⟩)), tv,
      by rw [c.env_phi_nb hφ hv ho hnb]; exact hvt, hgv, ?_, ?_⟩
    · rw [c.Rget_edge_moved hφ hv ho h1 h2]
      have hm : renameRoot1 (edgeMoves cc b blk'.phis) false (.val v) = .val φ.dst := by
        rw [renameRoot1, c.moves_lookup_consumed hφ hv ho h1 h2]
      exact mem_normRoots.2 (List.mem_map.2 ⟨.val v, hmark, hm⟩)
    · rw [c.Rget_edge_moved hφ hv ho h1 h2]
      refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ,
        mem_normRoots.2 (List.mem_map.2 ⟨ρ, hρ, rfl⟩), ?_, c.live_rename hfwd hlive,
        c.rename_covers hfwd hlive hcov⟩
      rw [rename_isFwd]; exact hfwd
  · -- the holder stays
    have hvL' := (c.mem_L v).2 (Or.inr ⟨hvL, hvo⟩)
    refine ⟨v, hvL', tv, by rw [c.env_old hvL hvo]; exact hvt, hgv, ?_, ?_⟩
    · rw [c.Rget_edge_keepL hvL hvo]
      have hm : renameRoot1 (edgeMoves cc b blk'.phis) false (.val v) = .val v := by
        rw [renameRoot1, c.moves_lookup_other hvo]
      exact mem_normRoots.2 (List.mem_map.2 ⟨.val v, hmark, hm⟩)
    · rw [c.Rget_edge_keepL hvL hvo]
      refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ,
        mem_normRoots.2 (List.mem_map.2 ⟨ρ, hρ, rfl⟩), ?_, c.live_rename hfwd hlive,
        c.rename_covers hfwd hlive hcov⟩
      rw [rename_isFwd]; exact hfwd

theorem Dcov' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ w ∈ (edgeNext cc σ b blk'.phis).D,
      (∀ ρ ∈ Rget (edgeNext cc σ b blk'.phis) w,
        ρ.isFwd = true ∨ rootLive (edgeNext cc σ b blk'.phis) ρ = true) →
      ∀ fp, (ds.enter cc.c blk'.phis b).env w = .bor fp → ∀ x ∈ fp,
        ∃ ρ ∈ Rget (edgeNext cc σ b blk'.phis) w, ρ.isFwd = false ∧
          Covers cc args h0 (ds.enter cc.c blk'.phis b) ρ x := by
  intro w hw hlive fp hfp x hx
  rcases (c.mem_D w).1 hw with hnew | ⟨hD, hnb, hnd⟩
  · -- a borrowed phi value
    obtain ⟨φ, hφ, hl, rfl, hb⟩ := mem_edgeBdsts.1 hnew
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    rw [c.env_phi hφ hl ho] at hfp
    have hb' : (cc.c.state φ.dst == .borrowed) = true := by simpa [CCtx.st] using hb
    simp only [hb', ↓reduceIte] at hfp
    rw [Rget_edge_new c hφ hl ho hb]
    have hsh := c.hok.shape φ hφ hl o ho
    unfold phiShape at hsh
    rw [hb] at hsh
    simp only [Bool.or_eq_true, beq_iff_eq] at hsh
    rcases hsh with (h | h) | h
    · -- a borrowed operand
      obtain ⟨hDo, hroots⟩ := usable_borrowed h (c.hok.bor φ hφ hl o ho hb)
      have hrt : rootsOf cc σ o = Rget σ o := by simp [rootsOf, h]
      rcases c.hI.Dval o hDo with h' | ⟨fpo, h'⟩
      · rw [h'] at hfp; cases hfp
      · rw [h'] at hfp
        have hfpo : fpo = fp := by simpa [Val.toBorrowed] using hfp
        subst hfpo
        obtain ⟨ρ0, hρ0, hf0, hcov⟩ := c.hI.Dcov o hDo (fun ρ hρ => Or.inr (hroots ρ hρ)) fpo h' x hx
        refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ0, ?_, ?_, ?_⟩
        · rw [hrt]; exact mem_normRoots.2 (List.mem_map.2 ⟨ρ0, hρ0, rfl⟩)
        · rw [rename_isFwd]; exact hf0
        · exact c.rename_covers hf0 (hroots ρ0 hρ0) hcov
    · -- an immortal operand
      rw [c.hI.imm o (Or.inr (Or.inl h))] at hfp; cases hfp
    · -- an owned operand the phi selects
      have hoL : o ∈ σ.L := usable_owning (by simp [h, St.owning]) (c.hok.bor φ hφ hl o ho hb)
      rcases c.hI.Lval o hoL with h' | ⟨t, h', ht⟩
      · rw [h'] at hfp; cases hfp
      · rw [h'] at hfp
        have hfpt : [t] = fp := by simpa [Val.toBorrowed] using hfp
        subst hfpt
        simp only [List.mem_singleton] at hx
        subst hx
        have hrt : rootsOf cc σ o = [.val o] := by simp [rootsOf, h]
        refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false (.val o), ?_, ?_, ?_⟩
        · rw [hrt]; exact mem_normRoots.2 (List.mem_map.2 ⟨.val o, by simp, rfl⟩)
        · rw [rename_isFwd]; rfl
        · exact c.rename_covers (by rfl) ((rootLive_val σ o).2 hoL) ⟨x, h', ht⟩
  · -- an old borrowed value
    have hwb := c.hI.Dst w hD
    have hnd' : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → φ.dst ≠ w := by
      intro φ hφ hl heq
      apply hnb
      exact mem_edgeBdsts.2 ⟨φ, hφ, hl, heq, hwb⟩
    rw [show (ds.enter cc.c blk'.phis b).env w = ds.env w from
      applyPhis_other cc.c hnd' b ds.env] at hfp
    rw [Rget_edge_old c hD hnb] at hlive ⊢
    have hpre : ∀ ρ0 ∈ Rget σ w, ρ0.isFwd = true ∨ rootLive σ ρ0 = true := by
      intro ρ0 hρ0
      by_cases hf : ρ0.isFwd = true
      · exact Or.inl hf
      · right
        have hf' : ρ0.isFwd = false := by simpa using hf
        have hmem : renameRoot1 (edgeMoves cc b blk'.phis) false ρ0 ∈
            normRoots ((Rget σ w).map (renameRoot1 (edgeMoves cc b blk'.phis) false)) :=
          mem_normRoots.2 (List.mem_map.2 ⟨ρ0, hρ0, rfl⟩)
        rcases hlive _ hmem with h | h
        · rw [rename_isFwd, hf'] at h; cases h
        · -- the edge state of the premise is the one with the renamed record
          rw [← Rget_edge_old c hD hnb] at hmem
          exact c.live_of_renamed hf' (fun d hd => hnd d hd ρ0 hρ0) h
    obtain ⟨ρ0, hρ0, hf0, hcov⟩ := c.hI.Dcov w hD hpre fp hfp x hx
    refine ⟨renameRoot1 (edgeMoves cc b blk'.phis) false ρ0, ?_, ?_, ?_⟩
    · exact mem_normRoots.2 (List.mem_map.2 ⟨ρ0, hρ0, rfl⟩)
    · rw [rename_isFwd]; exact hf0
    · have hl0 : rootLive σ ρ0 = true := by
        rcases hpre ρ0 hρ0 with h | h
        · rw [hf0] at h; cases h
        · exact h
      exact c.rename_covers hf0 hl0 hcov

theorem facts_same (c : EC cc args h0 pend0 σ b blk' ds) {key : Key}
    (h : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → key.mentions φ.dst = false) :
    (ds.enter cc.c blk'.phis b).facts key = ds.facts key := by
  show clearFacts ds.facts (phiDsts cc.c blk'.phis) key = ds.facts key
  unfold clearFacts phiDsts
  have : ((blk'.phis.filter (Phi.live cc.c)).map (·.dst)).any (fun d => key.mentions d) = false := by
    simp only [List.any_eq_false, List.mem_map, List.mem_filter]
    rintro d ⟨φ, ⟨hφ, hl⟩, rfl⟩
    simpa using h φ hφ hl
  simp [this]

theorem Pin' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ p ∈ (edgeNext cc σ b blk'.phis).P, p.1 ∈ (edgeNext cc σ b blk'.phis).L ∧
      ((ds.enter cc.c blk'.phis b).env p.1 = .imm ∨
        ∃ t, (ds.enter cc.c blk'.phis b).env p.1 = .own t ∧
          (ds.enter cc.c blk'.phis b).pend t p.2 = true) := by
  intro p hp
  have hpP : p ∈ σ.P := hp
  obtain ⟨hvL, hval⟩ := c.hI.Pin p hpP
  have hvo : p.1 ∉ edgeConsumed cc b blk'.phis := by
    intro h
    have := c.hok.notP p.1 h
    unfold AbsState.pendingAny at this
    simp only [Bool.or_eq_false_iff, List.any_eq_false] at this
    exact this.1 p hpP (by simp)
  refine ⟨(c.mem_L p.1).2 (Or.inr ⟨hvL, hvo⟩), ?_⟩
  rw [c.env_old hvL hvo]
  exact hval

theorem Gin' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ g ∈ (edgeNext cc σ b blk'.phis).G, g.1 ∈ (edgeNext cc σ b blk'.phis).L ∧
      (ds.enter cc.c blk'.phis b).facts g.2.2.1 ≠ none ∧
      ((ds.enter cc.c blk'.phis b).env g.1 = .imm ∨
        ∃ t, (ds.enter cc.c blk'.phis b).env g.1 = .own t ∧
          ((ds.enter cc.c blk'.phis b).pend t g.2.1 = true ↔
            (ds.enter cc.c blk'.phis b).facts g.2.2.1 = some g.2.2.2)) := by
  intro g hg
  have hgG : g ∈ σ.G := hg
  obtain ⟨hvL, hdec, hval⟩ := c.hI.Gin g hgG
  have hvo : g.1 ∉ edgeConsumed cc b blk'.phis := by
    intro h
    have := c.hok.notP g.1 h
    unfold AbsState.pendingAny at this
    simp only [Bool.or_eq_false_iff, List.any_eq_false] at this
    exact this.2 g hgG (by simp)
  have hfs := c.facts_same (key := g.2.2.1) (fun φ hφ hl => c.hok.guard g hgG φ hφ hl)
  refine ⟨(c.mem_L g.1).2 (Or.inr ⟨hvL, hvo⟩), by rw [hfs]; exact hdec, ?_⟩
  rw [c.env_old hvL hvo, hfs]
  exact hval

theorem Pout' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, ∀ t, (ds.enter cc.c blk'.phis b).env v = .own t →
      ∀ k, (ds.enter cc.c blk'.phis b).pend t k = true →
        (edgeNext cc σ b blk'.phis).predicts (ds.enter cc.c blk'.phis b).facts v k = true := by
  intro v hv t hvt k hpt
  have hpt' : ds.pend t k = true := hpt
  rcases (c.mem_L v).1 hv with hd | ⟨hvL, hvo⟩
  · -- a phi value: its operand was consumed, and nothing was pending on it
    obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 hown]; simp
    rw [c.env_phi_nb hφ hl ho hnb] at hvt
    rcases c.src_cases hφ hl ho hown with ⟨hoo, hoL⟩ | hi
    · exfalso
      have hpred := c.hI.Pout o hoL t hvt k hpt'
      have hnp := c.hok.notP o (mem_edgeConsumed.2 ⟨φ, hφ, hl, ho, hown, hoo⟩)
      unfold AbsState.predicts at hpred
      unfold AbsState.pendingAny at hnp
      simp only [Bool.or_eq_false_iff, List.any_eq_false] at hnp
      simp only [Bool.or_eq_true] at hpred
      rcases hpred with h | h
      · exact hnp.1 (o, k) (List.mem_of_elem_eq_true h) (by simp)
      · obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
        simp only [Bool.and_eq_true, beq_iff_eq] at hgc
        exact hnp.2 g hg (by simp [hgc.1.1])
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hvt; cases hvt
  · rw [c.env_old hvL hvo] at hvt
    have hpred := c.hI.Pout v hvL t hvt k hpt'
    unfold AbsState.predicts at hpred ⊢
    simp only [Bool.or_eq_true] at hpred ⊢
    rcases hpred with h | h
    · left; exact h
    · right
      obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
      refine List.any_eq_true.2 ⟨g, hg, ?_⟩
      simp only [Bool.and_eq_true, beq_iff_eq] at hgc ⊢
      refine ⟨hgc.1, ?_⟩
      have hfs := c.facts_same (key := g.2.2.1) (fun φ hφ hl => c.hok.guard g hg φ hφ hl)
      show (ds.enter cc.c blk'.phis b).facts g.2.2.1 = some g.2.2.2
      rw [hfs]; exact hgc.2

theorem Fin' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ f ∈ (edgeNext cc σ b blk'.phis).F, (ds.enter cc.c blk'.phis b).facts f.1 ≠ none ∧
      ∀ p, f.2 = some p → (ds.enter cc.c blk'.phis b).facts f.1 = some p := by
  intro f hf
  have hf' : f ∈ σ.F.filter fun f => ((livePhis cc blk'.phis).map (·.dst)).all fun d => !f.1.mentions d := hf
  rw [List.mem_filter] at hf'
  obtain ⟨hfF, hall⟩ := hf'
  have hment : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → f.1.mentions φ.dst = false := by
    intro φ hφ hl
    have := List.all_eq_true.1 hall φ.dst (List.mem_map.2 ⟨φ, mem_livePhis.2 ⟨hφ, hl⟩, rfl⟩)
    simpa using this
  have hfs := c.facts_same (key := f.1) hment
  obtain ⟨h1, h2⟩ := c.hI.Fin f hfF
  exact ⟨by rw [hfs]; exact h1, fun p hp => by rw [hfs]; exact h2 p hp⟩

theorem acct' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ x t, (ds.enter cc.c blk'.phis b).heap x = .live t →
      (∃ v ∈ (edgeNext cc σ b blk'.phis).L, (ds.enter cc.c blk'.phis b).env v = .own t) ∨
        (h0 x = .live t ∧ ¬ OwnedArg cc.f args t) ∨ (ds.enter cc.c blk'.phis b).abandoned t := by
  intro x t hxt
  rcases c.hI.acct x t hxt with ⟨v, hv, hvt⟩ | h | hab
  · left
    by_cases hvc : v ∈ edgeConsumed cc b blk'.phis
    · obtain ⟨φ, hφ, hl, ho, hown, _⟩ := mem_edgeConsumed.1 hvc
      refine ⟨φ.dst, (c.mem_L _).2 (Or.inl (mem_edgeDsts.2 ⟨φ, hφ, hl, rfl, hown⟩)), ?_⟩
      have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 hown]; simp
      rw [c.env_phi_nb hφ hl ho hnb]; exact hvt
    · exact ⟨v, (c.mem_L v).2 (Or.inr ⟨hv, hvc⟩), by rw [c.env_old hv hvc]; exact hvt⟩
  · right; left; exact h
  · right; right; exact hab

theorem abLive' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ t, (ds.enter cc.c blk'.phis b).abandoned t → (ds.enter cc.c blk'.phis b).heap t = .live t :=
  fun t ht => c.hI.abLive t ht

theorem abFree' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ t, (ds.enter cc.c blk'.phis b).abandoned t → ∀ x, h0 x = .live t → OwnedArg cc.f args t :=
  fun t ht x hx => c.hI.abFree t ht x hx

theorem Ldisj' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, ∀ t, (ds.enter cc.c blk'.phis b).env v = .own t →
      ¬ (ds.enter cc.c blk'.phis b).abandoned t := by
  intro v hv t hvt hab
  rcases (c.mem_L v).1 hv with hd | ⟨hvL, hvo⟩
  · obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 hown]; simp
    rw [c.env_phi_nb hφ hl ho hnb] at hvt
    rcases c.src_cases hφ hl ho hown with ⟨_, hoL⟩ | hi
    · exact c.hI.Ldisj o hoL t hvt hab
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hvt; cases hvt
  · rw [c.env_old hvL hvo] at hvt
    exact c.hI.Ldisj v hvL t hvt hab

theorem Lfree' (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ v ∈ (edgeNext cc σ b blk'.phis).L, ∀ t, (ds.enter cc.c blk'.phis b).env v = .own t →
      ∀ x, h0 x = .live t → OwnedArg cc.f args t := by
  intro v hv t hvt x hx
  rcases (c.mem_L v).1 hv with hd | ⟨hvL, hvo⟩
  · obtain ⟨φ, hφ, hl, rfl, hown⟩ := mem_edgeDsts.1 hd
    obtain ⟨o, ho⟩ := c.hops φ hφ hl
    have hnb : cc.st φ.dst ≠ .borrowed := by rw [owning_iff.1 hown]; simp
    rw [c.env_phi_nb hφ hl ho hnb] at hvt
    rcases c.src_cases hφ hl ho hown with ⟨_, hoL⟩ | hi
    · exact c.hI.Lfree o hoL t hvt x hx
    · rw [c.hI.imm o (Or.inr (Or.inl hi))] at hvt; cases hvt
  · rw [c.env_old hvL hvo] at hvt
    exact c.hI.Lfree v hvL t hvt x hx

end EC

/-- **A checked phi edge preserves the invariant.** -/
theorem edge_inv {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    {σ : AbsState} {b : BlockId} {blk' : Block} {ds : DState}
    (c : EC cc args h0 pend0 σ b blk' ds) :
    Inv cc args h0 (edgeNext cc σ b blk'.phis) (ds.enter cc.c blk'.phis b) :=
  { imm := c.imm', stk := c.stk', nostk := c.nostk', Lown := c.Lown', Lbd := c.Lbd', Lval := c.Lval', Linj := c.Linj',
    Dst := c.Dst', Dbd := c.Dbd', Dval := c.Dval', Dcov := c.Dcov', Pin := c.Pin',
    Gin := c.Gin', Pout := c.Pout', Fin := c.Fin', frame := c.hI.frame, dead := c.hI.dead,
    unused := c.hI.unused, acct := c.acct', abLive := c.abLive', Ldisj := c.Ldisj', abFree := c.abFree',
    Lfree := c.Lfree', lentSeen := c.lentSeen',
    lentCov := c.lentCov', heldSeen := c.heldSeen', heldCov := c.heldCov' }

/-- The values flowing along a checked edge can be read. -/
theorem edge_alive {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    {σ : AbsState} {b : BlockId} {blk' : Block} {ds : DState}
    (c : EC cc args h0 pend0 σ b blk' ds) :
    ∀ o ∈ incoming cc.c blk'.phis b, (ds.env o).alive ds.heap := by
  intro o ho
  unfold incoming at ho
  rw [List.mem_filterMap] at ho
  obtain ⟨φ, hφ, hl⟩ := ho
  obtain ⟨hφ', hv⟩ := List.mem_filter.1 hφ
  exact c.operand_alive hφ' hv hl

end Own
