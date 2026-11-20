import InstCtx

/-!
# Pending takes, guarded takes and decided tests after an instruction

`Pin`, `Gin`, `Pout` and `Fin` of the invariant hold at `instNext cc σ i`.
-/

namespace Own

section Next

variable {cc : CCtx} {σ : AbsState} {i : Inst}

theorem instNext_P_eq (hp : (i.cls == .parameter) = false) : (instNext cc σ i).P = nextP cc σ i := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte]
  cases hd : i.dst with
  | none => rfl
  | some d => cases hs : cc.st d <;> simp only [hs]

theorem instNext_G_eq (hp : (i.cls == .parameter) = false) : (instNext cc σ i).G = nextG cc σ i := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte]
  cases hd : i.dst with
  | none => rfl
  | some d => cases hs : cc.st d <;> simp only [hs]

theorem instNext_F_eq (hp : (i.cls == .parameter) = false) : (instNext cc σ i).F = nextF σ i := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte]
  cases hd : i.dst with
  | none => rfl
  | some d => cases hs : cc.st d <;> simp only [hs]

theorem takenSlot_spec {a : ValId} {k : String} (h : takenSlot cc i = some (a, k)) :
    i.reads.head? = some a ∧ i.slot = some k ∧ cc.st a = .owned ∧ isTakeI cc i = true := by
  unfold takenSlot at h
  by_cases ht : isTakeI cc i = true
  · simp only [ht, ↓reduceIte] at h
    unfold takeSlot at h
    cases hrd : i.reads.head? with
    | none => rw [hrd] at h; simp at h
    | some c =>
      cases hsl : i.slot with
      | none => rw [hrd, hsl] at h; simp at h
      | some kk =>
        rw [hrd, hsl] at h
        simp only [] at h
        by_cases hc : cc.st c == .owned
        · simp only [hc, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨rfl, rfl, by simpa using hc, ht⟩
        · simp [hc] at h
  · simp [ht] at h

theorem mem_nextP (p : ValId × String) :
    p ∈ nextP cc σ i ↔
      takenSlot cc i = some p ∨
      (∃ d c k, i.dst = some d ∧ i.consumes.head? = some c ∧ i.isClosing = true ∧
        cc.sd i = .owned ∧ (c, k) ∈ σ.P ∧ k ∉ closedKeys i ∧ p = (d, k)) ∨
      (p ∈ σ.P ∧ p.1 ∉ cc.ownConsumed i) := by
  unfold nextP
  simp only [List.mem_append]
  constructor
  · rintro ((h | h) | h)
    · left
      cases htk : takenSlot cc i with
      | none => rw [htk] at h; simp at h
      | some q => rw [htk] at h; simp at h; rw [h]
    · right; left
      cases hd : i.dst with
      | none => rw [hd] at h; simp at h
      | some d =>
        cases hc : i.consumes.head? with
        | none => rw [hd, hc] at h; simp at h
        | some c =>
          rw [hd, hc] at h
          by_cases hcl : (i.isClosing && cc.sd i == .owned) = true
          · simp only [hcl, ↓reduceIte, List.mem_map, List.mem_filter] at h
            obtain ⟨q, ⟨hq, hq2⟩, rfl⟩ := h
            simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hq2 hcl
            exact ⟨d, c, q.2, rfl, rfl, hcl.1, hcl.2, by
              have : q.1 = c := by simpa using hq2.1
              rw [← this]; exact hq, by simpa using hq2.2, rfl⟩
          · simp [hcl] at h
    · right; right
      simp only [List.mem_filter] at h
      exact ⟨h.1, by simpa using h.2⟩
  · rintro (h | ⟨d, c, k, hd, hc, hcl, hsd, hP, hk, rfl⟩ | h)
    · left; left
      cases htk : takenSlot cc i with
      | none => rw [htk] at h; cases h
      | some q => rw [htk] at h; cases h; simp
    · left; right
      rw [hd, hc]
      have : (i.isClosing && cc.sd i == .owned) = true := by simp [hcl, hsd]
      simp only [this, ↓reduceIte, List.mem_map, List.mem_filter]
      exact ⟨(c, k), ⟨hP, by simpa using hk⟩, rfl⟩
    · right
      simp only [List.mem_filter]
      exact ⟨h.1, by simpa using h.2⟩

theorem mem_nextG (g : ValId × String × Key × Bool) :
    g ∈ nextG cc σ i ↔
      (∃ d c g0, i.dst = some d ∧ i.consumes.head? = some c ∧ i.isClosing = true ∧
        cc.sd i = .owned ∧ g0 ∈ σ.G ∧ g0.1 = c ∧ g0.2.1 ∉ closedKeys i ∧
        g = (d, g0.2.1, g0.2.2)) ∨
      (g ∈ σ.G ∧ g.1 ∉ cc.ownConsumed i) := by
  unfold nextG
  simp only [List.mem_append]
  constructor
  · rintro (h | h)
    · left
      cases hd : i.dst with
      | none => rw [hd] at h; simp at h
      | some d =>
        cases hc : i.consumes.head? with
        | none => rw [hd, hc] at h; simp at h
        | some c =>
          rw [hd, hc] at h
          by_cases hcl : (i.isClosing && cc.sd i == .owned) = true
          · simp only [hcl, ↓reduceIte, List.mem_map, List.mem_filter] at h
            obtain ⟨q, ⟨hq, hq2⟩, rfl⟩ := h
            simp only [Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hq2 hcl
            exact ⟨d, c, q, rfl, rfl, hcl.1, hcl.2, hq, hq2.1, by simpa using hq2.2, rfl⟩
          · simp [hcl] at h
    · right
      simp only [List.mem_filter] at h
      exact ⟨h.1, by simpa using h.2⟩
  · rintro (⟨d, c, g0, hd, hc, hcl, hsd, hg, h1, h2, rfl⟩ | h)
    · left
      rw [hd, hc]
      have : (i.isClosing && cc.sd i == .owned) = true := by simp [hcl, hsd]
      simp only [this, ↓reduceIte, List.mem_map, List.mem_filter]
      exact ⟨g0, ⟨hg, by simpa [h1] using h2⟩, rfl⟩
    · right
      simp only [List.mem_filter]
      exact ⟨h.1, by simpa using h.2⟩

theorem mem_nextF (f : Key × Option Bool) :
    f ∈ nextF σ i ↔ f ∈ σ.F ∧ ∀ d, i.dst = some d → f.1.mentions d = false := by
  unfold nextF
  cases hd : i.dst with
  | none => simp
  | some d =>
    simp only [List.mem_filter]
    constructor
    · rintro ⟨h1, h2⟩
      exact ⟨h1, fun d' hd' => by
        have := Option.some.inj hd'; subst this; simpa using h2⟩
    · rintro ⟨h1, h2⟩
      exact ⟨h1, by simpa using h2 d rfl⟩

end Next


namespace IC

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {ds ds' : DState} {i : Inst} {r : Option Addr}

/-- What a take of an owned container's slot gives. -/
theorem take_facts (c : IC cc args h0 pend0 σ ds ds' i r) {a : ValId} {k : String}
    (h : takenSlot cc i = some (a, k)) :
    a ∈ σ.L ∧ a ∉ cc.ownConsumed i ∧ ¬ (σ.slotOpen a k = true) ∧
      isTransfer (Ctx.entering cc.f cc.c args) i = true ∧ i.slot = some k ∧
      i.reads.head? = some a := by
  obtain ⟨hrd, hsl, hao, htk⟩ := takenSlot_spec h
  have hok := c.hok.j8take
  unfold takeOk at hok
  simp only [htk, Bool.not_true, Bool.false_or] at hok
  unfold takeSlot at hok
  rw [hrd, hsl] at hok
  simp only [hao, Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hok
  rcases hok with hem | ⟨⟨_, haL⟩, hnot⟩
  · simp at hem
  · have haL' : a ∈ σ.L := List.mem_of_elem_eq_true haL
    have hao' : a ∉ cc.ownConsumed i := fun hc => c.hok.j6b a hc (List.mem_of_mem_head? hrd)
    have hbr : isTransfer (Ctx.entering cc.f cc.c args) i = true := by
      simp only [isTransfer, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq]
      simp only [isTakeI, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at htk
      refine ⟨⟨htk.1, ?_⟩, by simp [hsl]⟩
      exact htk.2
    exact ⟨haL', hao', by simpa using hnot, hbr, hsl, hrd⟩

theorem Pin' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ p ∈ (instNext cc σ i).P, p.1 ∈ (instNext cc σ i).L ∧
      (ds'.env p.1 = .imm ∨ ∃ t, ds'.env p.1 = .own t ∧ ds'.pend t p.2 = true) := by
  intro p hp
  rw [instNext_P_eq c.hp] at hp
  rcases (mem_nextP p).1 hp with htk | ⟨d, cc0, k, hd, hhd, hcl, hsd, hP, hk, rfl⟩ | ⟨hpP, hpo⟩
  · -- the slot a take opens
    obtain ⟨a, k⟩ := p
    obtain ⟨haL, hao, _, htr, hsl, hrd⟩ := c.take_facts htk
    refine ⟨(instNext_L c.hp a).2 (Or.inl ⟨haL, hao⟩), ?_⟩
    simp only []
    rw [c.env_L haL]
    rcases c.hI.Lval a haL with h | ⟨t, h1, h2⟩
    · left; exact h
    · right
      refine ⟨t, h1, c.pend_open (c.not_consumed haL hao h1) ?_ htr ?_ hsl⟩
      · intro hrt; exact c.root_fresh hrt haL hao h1 rfl
      · simp [transferTarget, hrd, ownedRoot, h1]
  · -- a slot passed on by a closing update
    have hdown : cc.st d = .owned := by
      have : cc.sd i = cc.st d := by simp [CCtx.sd, CCtx.st, hd]
      rw [← this]; exact hsd
    have hdL : d ∈ (instNext cc σ i).L :=
      (instNext_L c.hp d).2 (Or.inr ⟨d, hd, owning_iff.2 hdown, rfl⟩)
    refine ⟨hdL, ?_⟩
    simp only []
    obtain ⟨hown, himm⟩ := c.hr.own d hd hdown
    rcases hown with ⟨h, _⟩ | ⟨t, he, hrt⟩
    · left; exact h
    · right
      refine ⟨t, he, ?_⟩
      -- the closing target
      have hcmem : cc0 ∈ i.consumes := List.mem_of_mem_head? hhd
      obtain ⟨hPL, hPval⟩ := c.hI.Pin (cc0, k) hP
      have hct : ∃ ct, closeTarget ds i = some ct := by
        cases hh : closeTarget ds i with
        | none =>
          exfalso
          have := (himm hcl hh).2
          rw [hrt] at this; cases this
        | some ct => exact ⟨ct, rfl⟩
      obtain ⟨ct, hct⟩ := hct
      have hcenv : ds.env cc0 = .own ct := by
        unfold closeTarget at hct
        rw [hhd] at hct
        simp only [Option.bind_some] at hct
        cases h : ds.env cc0 <;> simp [ownedRoot, h] at hct
        subst hct; rfl
      have hpendct : ds.pend ct k = true := by
        rcases hPval with h | ⟨t0, h1, h2⟩
        · rw [h] at hcenv; cases hcenv
        · rw [hcenv] at h1; cases h1; exact h2
      exact c.pend_pass hcl hrt hct hpendct hk
  · -- an old slot, kept
    obtain ⟨hvL, hval⟩ := c.hI.Pin p hpP
    have hvo : p.1 ∉ cc.ownConsumed i := hpo
    refine ⟨(instNext_L c.hp p.1).2 (Or.inl ⟨hvL, hvo⟩), ?_⟩
    rw [c.env_L hvL]
    rcases hval with h | ⟨t, h1, h2⟩
    · left; exact h
    · right
      exact ⟨t, h1, c.pend_keep (c.not_consumed hvL hvo h1)
        (fun hrt => c.root_fresh hrt hvL hvo h1 rfl) h2⟩

/-- A test that does not depend on the defined value stays decided. -/
theorem facts_same (c : IC cc args h0 pend0 σ ds ds' i r) {key : Key}
    (h : ∀ d, i.dst = some d → key.mentions d = false) : ds'.facts key = ds.facts key := by
  rw [c.hfacts]
  unfold clearFacts
  cases hd : i.dst with
  | none => simp
  | some d =>
    have := h d hd
    simp [this]

/-- The guards of the state do not depend on the defined value. -/
theorem guard_not_mentions (c : IC cc args h0 pend0 σ ds ds' i r) {g : ValId × String × Key × Bool}
    (hg : g ∈ σ.G) : ∀ d, i.dst = some d → g.2.2.1.mentions d = false := by
  intro d hd
  rcases c.hok.guard d hd with h | h
  · exact absurd h c.hcls
  · exact h g hg

/-- The closing target of a closing update that defines a tree. -/
theorem closeTarget_of_tree (c : IC cc args h0 pend0 σ ds ds' i r) {d : ValId} {t : Addr}
    (hd : i.dst = some d) (hdown : cc.st d = .owned) (hcl : i.isClosing = true)
    (hrt : r = some t) : ∃ ct, closeTarget ds i = some ct := by
  obtain ⟨_, himm⟩ := c.hr.own d hd hdown
  cases hh : closeTarget ds i with
  | none =>
    exfalso
    have := (himm hcl hh).2
    rw [hrt] at this; cases this
  | some ct => exact ⟨ct, rfl⟩

theorem closeTarget_env {c0 : ValId} {ct : Addr} (hhd : i.consumes.head? = some c0)
    (hct : closeTarget ds i = some ct) : ds.env c0 = .own ct := by
  unfold closeTarget at hct
  rw [hhd] at hct
  simp only [Option.bind_some] at hct
  cases h : ds.env c0 <;> simp [ownedRoot, h] at hct
  subst hct; rfl


/-- A transferring read that reaches a tree takes the slot of a value of `L`. -/
theorem take_of_transfer (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} {k : String}
    (htr : isTransfer (Ctx.entering cc.f cc.c args) i = true) (htt : transferTarget ds i = some t)
    (hsl : i.slot = some k) : ∃ a, takenSlot cc i = some (a, k) ∧ ds.env a = .own t := by
  simp only [isTransfer, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at htr
  obtain ⟨⟨hcls, hres⟩, _⟩ := htr
  have hres' : cc.sd i = .owned ∨ cc.sd i = .emptied := hres
  have htk : isTakeI cc i = true := by
    simp only [isTakeI, Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true]
    exact ⟨hcls, hres'⟩
  unfold transferTarget at htt
  cases hrd : i.reads.head? with
  | none => rw [hrd] at htt; simp at htt
  | some a =>
    rw [hrd] at htt
    simp only [] at htt
    have hae : ds.env a = .own t := by
      cases h : ds.env a <;> simp [ownedRoot, h] at htt
      subst htt; rfl
    have hok := c.hok.j8take
    unfold takeOk at hok
    simp only [htk, Bool.not_true, Bool.false_or] at hok
    unfold takeSlot at hok
    rw [hrd, hsl] at hok
    simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at hok
    have hao : cc.st a = .owned := by
      rcases hok with hem | ⟨⟨hao, _⟩, _⟩
      · rw [c.hI.imm a (by simp [hem])] at hae; cases hae
      · exact hao
    refine ⟨a, ?_, hae⟩
    unfold takenSlot
    simp only [htk, ↓reduceIte, takeSlot, hrd, hsl, hao, beq_self_eq_true]

theorem Gin' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ g ∈ (instNext cc σ i).G, g.1 ∈ (instNext cc σ i).L ∧ ds'.facts g.2.2.1 ≠ none ∧
      (ds'.env g.1 = .imm ∨ ∃ t, ds'.env g.1 = .own t ∧
        (ds'.pend t g.2.1 = true ↔ ds'.facts g.2.2.1 = some g.2.2.2)) := by
  intro g hg
  rw [instNext_G_eq c.hp] at hg
  rcases (mem_nextG g).1 hg with ⟨d, c0, g0, hd, hhd, hcl, hsd, hg0, h1, h2, rfl⟩ | ⟨hgG, hgo⟩
  · -- a guarded take passed on to the result of a closing update
    have hdown : cc.st d = .owned := by
      have : cc.sd i = cc.st d := by simp [CCtx.sd, CCtx.st, hd]
      rw [← this]; exact hsd
    have hdL : d ∈ (instNext cc σ i).L :=
      (instNext_L c.hp d).2 (Or.inr ⟨d, hd, owning_iff.2 hdown, rfl⟩)
    obtain ⟨hgL, hdec, hgenv⟩ := c.hI.Gin g0 hg0
    have hfs := c.facts_same (key := g0.2.2.1) (c.guard_not_mentions hg0)
    refine ⟨hdL, by simp only []; rw [hfs]; exact hdec, ?_⟩
    simp only []
    rw [hfs]
    obtain ⟨hown, _⟩ := c.hr.own d hd hdown
    rcases hown with ⟨h, _⟩ | ⟨t, he, hrt⟩
    · left; exact h
    · right
      refine ⟨t, he, ?_⟩
      obtain ⟨ct, hct⟩ := c.closeTarget_of_tree hd hdown hcl hrt
      have hcenv := closeTarget_env hhd hct
      rw [h1] at hgenv
      have hiff : ds.pend ct g0.2.1 = true ↔ ds.facts g0.2.2.1 = some g0.2.2.2 := by
        rcases hgenv with h | ⟨t0, ht0, hiff⟩
        · rw [h] at hcenv; cases hcenv
        · rw [hcenv] at ht0; cases ht0; exact hiff
      constructor
      · intro hp
        rcases c.pend_cases hp with ⟨_, _, ct', hct', hp', _⟩ | ⟨_, hrn, _⟩ | ⟨_, hrn, _⟩
        · rw [hct] at hct'; cases hct'; exact hiff.1 hp'
        · exact absurd hrt hrn
        · exact absurd hrt hrn
      · intro hf
        exact c.pend_pass hcl hrt hct (hiff.2 hf) h2
  · -- an old guarded take, kept
    obtain ⟨hgL, hdec, hgenv⟩ := c.hI.Gin g hgG
    have hvo : g.1 ∉ cc.ownConsumed i := hgo
    have hfs := c.facts_same (key := g.2.2.1) (c.guard_not_mentions hgG)
    refine ⟨(instNext_L c.hp g.1).2 (Or.inl ⟨hgL, hvo⟩), by rw [hfs]; exact hdec, ?_⟩
    rw [c.env_L hgL, hfs]
    rcases hgenv with h | ⟨t, h1, hiff⟩
    · left; exact h
    · right
      refine ⟨t, h1, ?_⟩
      have hnc := c.not_consumed hgL hvo h1
      have hrn : r ≠ some t := fun hrt => c.root_fresh hrt hgL hvo h1 rfl
      constructor
      · intro hp
        rcases c.pend_cases hp with ⟨_, hrt, _⟩ | ⟨_, _, htr, htt, hsl⟩ | ⟨_, _, hp'⟩
        · exact absurd hrt hrn
        · -- a take of the very slot that is guarded
          exfalso
          obtain ⟨a, htk0, hae⟩ := c.take_of_transfer htr htt hsl
          have hag : a = g.1 := c.hI.Linj a (c.take_facts htk0).1 g.1 hgL t hae h1
          subst hag
          obtain ⟨_, _, hnot, _⟩ := c.take_facts htk0
          apply hnot
          unfold AbsState.slotOpen
          simp only [Bool.or_eq_true, List.any_eq_true]
          right
          exact ⟨g, hgG, by simp⟩
        · exact hiff.1 hp'
      · intro hf
        exact c.pend_keep hnc hrn (hiff.2 hf)

theorem Pout' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, ∀ t, ds'.env v = .own t → ∀ k, ds'.pend t k = true →
      (instNext cc σ i).predicts ds'.facts v k = true := by
  intro v hv t hvt k hpt
  unfold AbsState.predicts
  rw [instNext_P_eq c.hp, instNext_G_eq c.hp]
  rcases (instNext_L c.hp v).1 hv with ⟨hvL, hvo⟩ | ⟨d, hd, hown, hvd⟩
  · rw [c.env_L hvL] at hvt
    rcases c.pend_cases hpt with ⟨_, hrt, _⟩ | ⟨_, _, htr, htt, hsl⟩ | ⟨_, _, hp'⟩
    · exact absurd rfl (c.root_fresh hrt hvL hvo hvt)
    · -- v is the container of the take
      obtain ⟨a, htk, hae⟩ := c.take_of_transfer htr htt hsl
      have hav : a = v := c.hI.Linj a (c.take_facts htk).1 v hvL t hae hvt
      subst hav
      simp only [Bool.or_eq_true]
      left
      exact List.elem_eq_true_of_mem ((mem_nextP (a, k)).2 (Or.inl htk))
    · have hpred := c.hI.Pout v hvL t hvt k hp'
      unfold AbsState.predicts at hpred
      simp only [Bool.or_eq_true] at hpred ⊢
      rcases hpred with hP | hG
      · left
        exact List.elem_eq_true_of_mem ((mem_nextP (v, k)).2 (Or.inr (Or.inr ⟨List.mem_of_elem_eq_true hP, hvo⟩)))
      · right
        obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 hG
        simp only [Bool.and_eq_true, beq_iff_eq] at hgc
        have hfs := c.facts_same (key := g.2.2.1) (c.guard_not_mentions hg)
        refine List.any_eq_true.2 ⟨g, (mem_nextG g).2 (Or.inr ⟨hg, by rw [hgc.1.1]; exact hvo⟩), ?_⟩
        simp only [Bool.and_eq_true, beq_iff_eq]
        refine ⟨hgc.1, ?_⟩
        rw [hfs]; exact hgc.2
  · -- the value the instruction defines
    rw [hvd] at hvt ⊢
    have hdown : cc.st d = .owned := owning_iff.1 hown
    obtain ⟨hown', _⟩ := c.hr.own d hd hdown
    rcases hown' with ⟨h, _⟩ | ⟨t', he, hrt⟩
    · rw [h] at hvt; cases hvt
    · rw [he] at hvt; cases hvt
      rcases c.pend_cases hpt with ⟨hcl, _, ct, hct, hp', hk⟩ | ⟨_, hrn, _⟩ | ⟨_, hrn, _⟩
      · -- passed on by the closing update
        have hhd : ∃ c0, i.consumes.head? = some c0 := by
          unfold closeTarget at hct
          cases h : i.consumes.head? with
          | none => rw [h] at hct; simp at hct
          | some c0 => exact ⟨c0, rfl⟩
        obtain ⟨c0, hhd⟩ := hhd
        have hcenv := closeTarget_env hhd hct
        have hc0 : c0 ∈ σ.L := by
          have hmem : c0 ∈ i.consumes := List.mem_of_mem_head? hhd
          rcases c.hok.c2 c0 hmem with hsc | ⟨_, hL⟩
          · rcases c.hI.noOwn4 hsc with h | h <;> rw [h] at hcenv <;> cases hcenv
          · exact hL
        have hpred := c.hI.Pout c0 hc0 ct hcenv k hp'
        unfold AbsState.predicts at hpred
        simp only [Bool.or_eq_true] at hpred ⊢
        have hsd : cc.sd i = .owned := by
          have : cc.sd i = cc.st d := by simp [CCtx.sd, CCtx.st, hd]
          rw [this]; exact hdown
        rcases hpred with hP | hG
        · left
          exact List.elem_eq_true_of_mem ((mem_nextP (d, k)).2
            (Or.inr (Or.inl ⟨d, c0, k, hd, hhd, hcl, hsd, List.mem_of_elem_eq_true hP, hk, rfl⟩)))
        · right
          obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 hG
          simp only [Bool.and_eq_true, beq_iff_eq] at hgc
          have hfs := c.facts_same (key := g.2.2.1) (c.guard_not_mentions hg)
          refine List.any_eq_true.2 ⟨(d, g.2.1, g.2.2), (mem_nextG _).2
            (Or.inl ⟨d, c0, g, hd, hhd, hcl, hsd, hg, hgc.1.1, by rw [hgc.1.2]; exact hk, rfl⟩), ?_⟩
          simp only [Bool.and_eq_true, beq_iff_eq]
          refine ⟨⟨trivial, hgc.1.2⟩, ?_⟩
          rw [hfs]; exact hgc.2
      · exact absurd hrt hrn
      · exact absurd hrt hrn

theorem Fin' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ f ∈ (instNext cc σ i).F, ds'.facts f.1 ≠ none ∧ ∀ p, f.2 = some p → ds'.facts f.1 = some p := by
  intro f hf
  rw [instNext_F_eq c.hp] at hf
  obtain ⟨hfF, hment⟩ := (mem_nextF f).1 hf
  obtain ⟨h1, h2⟩ := c.hI.Fin f hfF
  have hfs := c.facts_same (key := f.1) hment
  exact ⟨by rw [hfs]; exact h1, fun p hp => by rw [hfs]; exact h2 p hp⟩

end IC

end Own
