import InstBase

/-!
# A checked instruction cannot fault
-/

namespace Own

theorem filterMap_filter_eq {α β : Type} (l : List α) (g : α → Option β) (p : α → Bool)
    (h : ∀ k ∈ l, p k = false → g k = none) :
    l.filterMap g = (l.filter p).filterMap g := by
  induction l with
  | nil => rfl
  | cons k ks ih =>
    have ih' := ih (fun k' hk' => h k' (List.mem_cons_of_mem _ hk'))
    by_cases hp : p k = true
    · cases hg : g k <;> simp [List.filter_cons, hp, List.filterMap_cons, hg, ih']
    · have hp' : p k = false := by simpa using hp
      have := h k (List.mem_cons_self) hp'
      simp [List.filter_cons, hp', this, ih']

theorem nodup_roots {σ : AbsState} {ds : DState} {cc : CCtx} {args : Nat → Val} {h0 : Heap}
    (hI : Inv cc args h0 σ ds) (l : List ValId) (hl : l.Nodup) (hL : ∀ k ∈ l, k ∈ σ.L) :
    (l.filterMap fun k => ownedRoot (ds.env k)).Nodup := by
  induction l with
  | nil => simp
  | cons k ks ih =>
    rw [List.nodup_cons] at hl
    have ih' := ih hl.2 (fun k' hk' => hL k' (List.mem_cons_of_mem _ hk'))
    cases hk : ownedRoot (ds.env k) with
    | none => simpa [List.filterMap_cons, hk] using ih'
    | some t =>
      have hkt : ds.env k = .own t := by
        cases h : ds.env k <;> simp [ownedRoot, h] at hk
        subst hk; rfl
      simp only [List.filterMap_cons, hk, List.nodup_cons]
      refine ⟨?_, ih'⟩
      intro hmem
      rw [List.mem_filterMap] at hmem
      obtain ⟨k', hk', hk't⟩ := hmem
      have hk't' : ds.env k' = .own t := by
        cases h : ds.env k' <;> simp [ownedRoot, h] at hk't
        subst hk't; rfl
      have := hI.Linj k (hL k (List.mem_cons_self)) k'
        (hL k' (List.mem_cons_of_mem _ hk')) t hkt hk't'
      subst this
      exact hl.1 hk'

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {ds : DState} {i : Inst}

/-- The values an instruction consumes that hold no tree hold an immediate or a stack
allocation. -/
theorem consumed_nonowning_imm (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) {k : ValId}
    (hk : k ∈ i.consumes) (hn : (cc.st k).owning = false) :
    ds.env k = .imm ∨ ds.env k = .stk := by
  rcases hok.c2 k hk with hsc | ⟨hown, _⟩
  · exact hI.noOwn4 hsc
  · rw [hown] at hn; cases hn

theorem consumedRoots_eq_oc (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) :
    consumedRoots ds i = (cc.ownConsumed i).filterMap fun k => ownedRoot (ds.env k) := by
  unfold consumedRoots CCtx.ownConsumed
  apply filterMap_filter_eq
  intro k hk hn
  rcases consumed_nonowning_imm hI hok hk hn with h | h <;> rw [h] <;> rfl

theorem consumeOnce_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) : ConsumeOnce ds i := by
  unfold ConsumeOnce
  rw [consumedRoots_eq_oc hI hok]
  apply nodup_roots hI _ hok.j6a
  intro k hk
  obtain ⟨hc, hown⟩ := mem_ownConsumed.1 hk
  rcases hok.c2 k hc with hsc | ⟨_, hkL⟩
  · exfalso
    rcases hsc with h | h | h | h <;> simp [h, St.owning] at hown
  · exact hkL

theorem consumeLive_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) : ConsumeLive ds i := by
  intro t ht
  obtain ⟨k, _, hkL, hkt⟩ := consumedRoots_mem hI hok ht
  rcases hI.Lval k hkL with h | ⟨t', h1, h2⟩
  · rw [h] at hkt; cases hkt
  · rw [hkt] at h1; cases h1; exact h2

theorem notBorrowed_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) : NotBorrowed ds i := by
  intro c hc fp hfp
  rcases hok.c2 c hc with hsc | ⟨_, hcL⟩
  · rcases hI.noOwn4 hsc with h | h <;> rw [h] at hfp <;> cases hfp
  · rcases hI.Lval c hcL with h | ⟨t, h, _⟩ <;> rw [h] at hfp <;> cases hfp

theorem readsAlive_ok (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) : ReadsAlive ds i := by
  intro r hr
  by_cases hb : cc.st r = .borrowed
  · exact usable_alive hs hI (hok.r4 r hr hb)
  · exact usable_alive hs hI (hok.r3 r hr hb)

theorem separate_ok (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i)
    (hnc : ¬ (i.cls = .construct ∧ (i.res (Ctx.entering cc.f cc.c args) = .owned ∨
      i.res (Ctx.entering cc.f cc.c args) = .emptied))) :
    Separate ds i := by
  intro r hr x hx t ht hxt
  obtain ⟨k, hk, hkL, hkt⟩ := consumedRoots_mem hI hok ht
  have hkr : k ∉ i.reads := hok.j6b k hk
  have hkc : k ∈ i.consumes := (mem_ownConsumed.1 hk).1
  have hkown : (cc.st k).owning = true := (mem_ownConsumed.1 hk).2
  have hrk : r ≠ k := fun h => hkr (h ▸ hr)
  have himm : ∀ v, (cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .stack ∨
      cc.st v = .emptied ∨ cc.st v = .none) → (ds.env v).cells ds.heap x → False := by
    intro v hv hx'
    rcases hI.noOwn hv with h | h <;> rw [h] at hx' <;> simp [Val.cells] at hx'
  cases hst : cc.st r with
  | scalar => exact himm r (Or.inl hst) hx
  | immortal => exact himm r (Or.inr (Or.inl hst)) hx
  | stack => exact himm r (Or.inr (Or.inr (Or.inl hst))) hx
  | emptied => exact himm r (Or.inr (Or.inr (Or.inr (Or.inl hst)))) hx
  | none =>
    have := hok.r3 r hr (by simp [hst]); simp [usable, hst] at this
  | owned =>
    have hrL : r ∈ σ.L := usable_owning (by simp [hst, St.owning]) (hok.r3 r hr (by simp [hst]))
    rcases hI.Lval r hrL with h | ⟨t', h1, _⟩
    · rw [h] at hx; simp [Val.cells] at hx
    · rw [h1] at hx; simp only [Val.cells] at hx
      have htt : t' = t := by have := hx.symm.trans hxt; simpa using this
      rw [htt] at h1
      exact hrk (hI.Linj r hrL k hkL t h1 hkt)
  | borrowed =>
    obtain ⟨hD, hroots⟩ := usable_borrowed hst (hok.r4 r hr hst)
    rcases hI.Dval r hD with h | ⟨fp, hfp⟩
    · rw [h] at hx; simp [Val.cells] at hx
    · rw [hfp] at hx
      obtain ⟨y, hy, l, hyl, hxl⟩ := hx
      rw [hxl] at hxt; cases hxt
      obtain ⟨ρ, hρ, hnf, hcov⟩ := hI.Dcov r hD (fun ρ hρ => Or.inr (hroots ρ hρ)) fp hfp y hy
      have hj6 := hok.j6c k hk r (List.mem_append_left _ hr) hrk
      have hroots_r : rootsOf cc σ r = Rget σ r := by simp [rootsOf, hst]
      have hnl : loanOfOwnedConstruct cc i r = false := by
        cases hh : loanOfOwnedConstruct cc i r with
        | false => rfl
        | true =>
          exfalso
          apply hnc
          have hres : i.res (Ctx.entering cc.f cc.c args) = cc.sd i := rfl
          simp only [loanOfOwnedConstruct, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at hh
          refine ⟨hh.1, ?_⟩
          rw [hres]
          rcases hh.2 with h | h
          · exact Or.inr h
          · exact Or.inl h.1
      rcases hj6 with hj | hj
      · rw [hroots_r] at hj
        have hρ' := hj ρ hρ
        cases ρ with
        | val n =>
          obtain ⟨tn, hn1, hn2⟩ := hcov
          rw [hyl] at hn2; cases hn2
          have hnL : n ∈ σ.L := (rootLive_val σ n).1 (hroots _ hρ)
          have := hI.Linj n hnL k hkL _ hn1 hkt
          subst this
          simp [Root.ownedBy] at hρ'
        | slot n kk =>
          obtain ⟨tn, hn1, hn2⟩ := hcov
          rw [hyl] at hn2; cases hn2
          have hnL : n ∈ σ.L := (rootLive_slot σ n kk).1 (hroots _ hρ)
          have := hI.Linj n hnL k hkL _ hn1 hkt
          subst this
          simp [Root.ownedBy] at hρ'
        | fwd n => exact hcov.elim
        | caller j =>
          obtain ⟨hj', hc⟩ := hcov
          obtain ⟨l0, hl0, hl0', hn⟩ := callerCell_live hs hI hj' hc
          rw [hl0'] at hyl; cases hyl
          exact hn (hI.Lfree k hkL _ hkt y hl0)
      · simp [hnl] at hj

theorem noStale_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) : NoStale ds i := by
  intro c hc t hct hpend
  rcases hok.c2 c hc with hsc | ⟨hown, hcL⟩
  · rcases hI.noOwn4 hsc with h | h <;> rw [h] at hct <;> cases hct
  · obtain ⟨k, hk⟩ := hpend
    have hpred := hI.Pout c hcL t hct k hk
    have hany : σ.pendingAny c = true := by
      unfold AbsState.predicts at hpred
      simp only [Bool.or_eq_true] at hpred
      unfold AbsState.pendingAny
      rcases hpred with h | h
      · have := List.mem_of_elem_eq_true h
        simp only [Bool.or_eq_true, List.any_eq_true]
        left; exact ⟨(c, k), this, by simp⟩
      · obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
        simp only [Bool.and_eq_true, beq_iff_eq] at hgc
        simp only [Bool.or_eq_true, List.any_eq_true]
        right; exact ⟨g, hg, by simp [hgc.1.1]⟩
    exact hok.j8a c (mem_ownConsumed.2 ⟨hc, hown⟩) hany

/-- `closeAgrees` looks only at the slots the update closes. -/
theorem closeAgrees_congr (p q : String → Bool) (i : Inst)
    (h : ∀ k ∈ queriedKeys i, p k = q k) : closeAgrees p i = closeAgrees q i := by
  unfold closeAgrees
  by_cases hc : i.isClosing = true
  · simp only [hc, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
    have hop : i.op ∈ closingOps := by
      simp only [Inst.isClosing, Bool.and_eq_true] at hc
      simpa using hc.2
    simp only [closingOps, List.mem_cons, List.not_mem_nil, or_false] at hop
    have hslot : ∀ k, i.slot = some k → i.op ≠ "list_pop" → i.op ≠ "dict_remove" →
        p k = q k := by
      intro k hk hne1 hne2
      apply h
      have hst : storeOps.contains i.op = true := by
        rcases hop with hop | hop | hop | hop | hop | hop | hop <;> simp_all [storeOps]
      
      have hst' : i.op ∈ storeOps := by simpa using hst
      simp [queriedKeys, hne2, hne1, hst', hk]
    rcases hop with hop | hop | hop | hop | hop | hop | hop <;> rw [hop]
    · cases hsl : i.slot with
      | none => rfl
      | some k => exact hslot k hsl (by simp [hop]) (by simp [hop])
    · cases hsl : i.slot with
      | none => rfl
      | some k => exact hslot k hsl (by simp [hop]) (by simp [hop])
    · cases hsl : i.slot with
      | none => rfl
      | some k =>
        have := hslot k hsl (by simp [hop]) (by simp [hop])
        simp [this]
    · cases hsl : i.slot with
      | none => rfl
      | some k =>
        have := hslot k hsl (by simp [hop]) (by simp [hop])
        simp [this]
    · cases hsl : i.slot with
      | none => rfl
      | some k =>
        have := hslot k hsl (by simp [hop]) (by simp [hop])
        simp [this]
    · cases hsl : i.slot with
      | none => rfl
      | some k =>
        by_cases kt : k = "tail"
        · simp [kt]
        · have := h k (by simp [queriedKeys, hop, hsl, kt])
          simp [this]
    · cases hhd : i.reads.head? with
      | none => rfl
      | some e =>
        have h1 := h s!"k%{e}" (by simp [queriedKeys, hop, hhd])
        have h2 := h s!"v%{e}" (by simp [queriedKeys, hop, hhd])
        show (((i.taken.isNone ||
            ((!takenPart i "key" || p s!"k%{e}") && (!takenPart i "value" || p s!"v%{e}"))) &&
            (!releasesPart i "key" || !p s!"k%{e}")) && (!releasesPart i "value" || !p s!"v%{e}")) =
          (((i.taken.isNone ||
            ((!takenPart i "key" || q s!"k%{e}") && (!takenPart i "value" || q s!"v%{e}"))) &&
            (!releasesPart i "key" || !q s!"k%{e}")) && (!releasesPart i "value" || !q s!"v%{e}"))
        rw [h1, h2]
  · have : i.isClosing = false := by simpa using hc
    simp [this]

theorem closeOk_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) : CloseOk ds i := by
  unfold CloseOk
  cases hct : closeTarget ds i with
  | none => trivial
  | some t =>
    show closeAgrees (ds.pend t) i = true
    by_cases hcl : i.isClosing = true
    · have hok' := hok.j8close
      unfold closeOk at hok'
      simp only [hcl, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at hok'
      unfold closeTarget at hct
      cases hhd : i.consumes.head? with
      | none => rw [hhd] at hct; simp at hct
      | some c =>
        rw [hhd] at hct
        simp only [Option.bind_some] at hct
        rw [hhd] at hok'
        simp only [Bool.and_eq_true] at hok'
        obtain ⟨hnoG, hag⟩ := hok'
        have hcmem : c ∈ i.consumes := List.mem_of_mem_head? hhd
        have hct' : ds.env c = .own t := by
          cases h : ds.env c <;> simp [ownedRoot, h] at hct
          subst hct; rfl
        have hcL : c ∈ σ.L := by
          rcases hok.c2 c hcmem with hsc | ⟨_, hcL⟩
          · rcases hI.noOwn4 hsc with h | h <;> rw [h] at hct' <;> cases hct'
          · exact hcL
        rw [closeAgrees_congr (ds.pend t) (fun k => σ.P.contains (c, k)) i]
        · exact hag
        · intro k hk
          have hnog : ¬ ∃ g ∈ σ.G, g.1 = c ∧ g.2.1 = k := by
            rintro ⟨g, hg, h1, h2⟩
            have := List.all_eq_true.1 hnoG k hk
            simp only [Bool.not_eq_true', List.any_eq_false] at this
            have := this g hg
            simp [h1, h2] at this
          cases hq : σ.P.contains (c, k) with
          | true =>
            exact (hI.Pin (c, k) (List.mem_of_elem_eq_true hq)).2.elim
              (fun h => by rw [h] at hct'; cases hct')
              (fun ⟨t', h1, h2⟩ => by
                rw [hct'] at h1; cases h1; exact h2)
          | false =>
            cases hp : ds.pend t k with
            | false => rfl
            | true =>
              exfalso
              have hpred := hI.Pout c hcL t hct' k hp
              unfold AbsState.predicts at hpred
              simp only [Bool.or_eq_true] at hpred
              rcases hpred with h | h
              · rw [hq] at h; cases h
              · obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
                simp only [Bool.and_eq_true, beq_iff_eq] at hgc
                exact hnog ⟨g, hg, hgc.1.1, hgc.1.2⟩
    · have : i.isClosing = false := by simpa using hcl
      simp [closeAgrees, this]

theorem transferOk_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) :
    TransferOk (Ctx.entering cc.f cc.c args) ds i := by
  intro ht
  simp only [isTransfer, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at ht
  obtain ⟨⟨hcls, hres⟩, hslot⟩ := ht
  have hres' : cc.sd i = .owned ∨ cc.sd i = .emptied := hres
  have htk : isTakeI cc i = true := by
    simp only [isTakeI, Bool.and_eq_true, beq_iff_eq, Bool.or_eq_true]
    exact ⟨hcls, hres'⟩
  have hok' := hok.j8take
  unfold takeOk at hok'
  simp only [htk, Bool.not_true, Bool.false_or] at hok'
  unfold takeSlot at hok'
  cases hrd : i.reads.head? with
  | none => rw [hrd] at hok'; simp at hok'
  | some a =>
    cases hsl : i.slot with
    | none => rw [hsl] at hslot; simp at hslot
    | some k =>
      rw [hrd, hsl] at hok'
      simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, Bool.not_eq_true'] at hok'
      simp only [hrd]
      rcases hok' with hem | ⟨⟨hao, haL⟩, hnot⟩
      · rw [hI.imm a (by simp [hem])]; trivial
      · have haL' : a ∈ σ.L := List.mem_of_elem_eq_true haL
        rcases hI.Lval a haL' with h | ⟨t, h1, h2⟩
        · rw [h]; trivial
        · rw [h1]
          refine ⟨h2, ?_⟩
          intro k' hk'
          have hkk := Option.some.inj hk'
          subst hkk
          cases hp : ds.pend t k with
          | false => rfl
          | true =>
            exfalso
            have hpred := hI.Pout a haL' t h1 k hp
            unfold AbsState.predicts at hpred
            simp only [Bool.or_eq_true] at hpred
            unfold AbsState.slotOpen at hnot
            simp only [Bool.or_eq_false_iff] at hnot
            rcases hpred with h | h
            · rw [hnot.1] at h; cases h
            · obtain ⟨g, hg, hgc⟩ := List.any_eq_true.1 h
              have := List.any_eq_false.1 hnot.2 g hg
              simp only [Bool.and_eq_true, beq_iff_eq] at hgc this
              exact this ⟨hgc.1.1, hgc.1.2⟩

/-- A checked instruction lets no stack allocation escape (J7). -/
theorem noEscape_ok (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) :
    NoEscape (Ctx.entering cc.f cc.c args) ds i := by
  have hj7 := hok.j7
  unfold stackOk at hj7
  simp only [Bool.and_eq_true, List.all_eq_true, Bool.or_eq_true, Bool.not_eq_true',
    List.any_eq_false] at hj7
  obtain ⟨hA, hB⟩ := hj7
  have hstk : ∀ k, ds.env k = .stk → cc.st k = .stack := fun k hk =>
    Classical.byContradiction fun hne => hI.nostk k hne hk
  refine ⟨?_, ?_⟩
  · intro k hk hek
    have hsk := hstk k hek
    have := hA k hk
    simp only [bne_iff_ne, ne_eq, Bool.and_eq_true, beq_iff_eq] at this
    rcases this with h | ⟨⟨hc, hh⟩, hr⟩
    · exact absurd hsk h
    · exact ⟨hc, hh, hr⟩
  · intro c hc hec k hk t hkt
    have hsc := hstk c hec
    have hcm : c ∈ i.consumes := List.mem_of_mem_head? hc
    rcases hB with hB | hB
    · exact absurd (by simp [hsc]) (hB c hcm)
    · have hkm : k ∈ i.consumes := List.mem_of_mem_tail hk
      have hks := hB k hk
      simp only [Bool.or_eq_false_iff, beq_eq_false_iff_ne, ne_eq] at hks
      rcases hok.c2 k hkm with hsc' | ⟨hown, _⟩
      · rcases hI.noOwn4 hsc' with h | h <;> rw [h] at hkt <;> cases hkt
      · have hso : cc.st k = .owned := by
          cases h : cc.st k <;> simp [h, St.owning] at hown ⊢
        exact absurd hso hks.1.1

/-- A checked instruction reads no owned value whose listed loans are gone (J4). -/
theorem loansLive_ok (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) : LoansLive (Ctx.entering cc.f cc.c args) ds i := by
  intro r hr hst n hn
  have hst' : cc.st r = .owned := hst
  have hu : usable cc σ r = true := hok.r3 r hr (by rw [hst']; simp)
  unfold usable at hu
  rw [hst'] at hu
  simp only [Bool.and_eq_true, List.all_eq_true] at hu
  have hl := hu.2 (.val n) hn
  simp only [loanAlive] at hl
  cases hsn : cc.st n with
  | owned =>
    simp only [hsn] at hl
    exact alive_of_L hI (List.contains_iff_mem.1 hl)
  | borrowed =>
    simp only [hsn] at hl
    exact usable_alive hs hI (by unfold usable; rw [hsn]; exact hl)
  | scalar => rw [hI.imm n (by simp [hsn])]; trivial
  | immortal => rw [hI.imm n (by simp [hsn])]; trivial
  | emptied => rw [hI.imm n (by simp [hsn])]; trivial
  | none => rw [hI.imm n (by simp [hsn])]; trivial
  | stack => rcases hI.stk n hsn with h | h <;> rw [h] <;> trivial

/-- A root whose owner an instruction destroys ends there. -/
theorem endsAt_of_owned {ρ : Root} {m : ValId} {dying : List ValId} (taken : Option (ValId × String))
    (hm : m ∈ dying) (ho : ρ.ownedBy m = true) : ρ.endsAt dying taken = true := by
  cases ρ with
  | val n =>
    have : n = m := by simpa [Root.ownedBy] using ho
    subst this
    simp [Root.endsAt, hm]
  | slot n k =>
    have : n = m := by simpa [Root.ownedBy] using ho
    subst this
    simp [Root.endsAt, hm]
  | caller _ => simp [Root.ownedBy] at ho
  | fwd _ => simp [Root.ownedBy] at ho

/-- A cell covered by a loan of a surviving holder lies in a tree the instruction consumes only if
the instruction is a constructor that keeps the owners it takes (`loansOk`, design §5 J4): the
consumed owner is the one the root names. -/
theorem root_consumed (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) {v : ValId} (hvL : v ∈ σ.L)
    (hvo : v ∉ cc.ownConsumed i) {ρ : Root}
    (hρ : ρ ∈ Rget σ v) (hfwd : ρ.isFwd = false) (hlive : rootLive σ ρ = true) {x t : Addr}
    (hcov : Covers cc args h0 ds ρ x) (hxt : ds.heap x = .live t) (htc : t ∈ consumedRoots ds i) :
    i.cls = .construct ∧ cc.sd i = .owned ∧
      ∃ n ∈ cc.ownConsumed i, ds.env n = .own t ∧ (ρ = .val n ∨ ∃ k, ρ = .slot n k) := by
  have hvc : (cc.ownConsumed i).contains v = false := by simpa using hvo
  have hend : ρ.endsAt (dyingOwners cc i) (takenSlot cc i) = false := by
    rcases hok.loans v hvL with h | h
    · rw [hvc] at h; cases h.1
    · exact h ρ hρ
  obtain ⟨n, hn, hnL, hnt⟩ := consumedRoots_mem hI hok htc
  -- the root names the consumed owner
  have hown : ρ = .val n ∨ ∃ k, ρ = .slot n k := by
    cases ρ with
    | val m =>
      obtain ⟨tm, hm, hxm⟩ := hcov
      have hmL : m ∈ σ.L := (rootLive_val σ m).1 hlive
      have htm : t = tm := Cell.live.inj (hxt.symm.trans hxm)
      rw [← htm] at hm
      have : m = n := hI.Linj m hmL n hnL t hm hnt
      subst this
      exact Or.inl rfl
    | slot m k =>
      obtain ⟨tm, hm, hxm⟩ := hcov
      have hmL : m ∈ σ.L := (rootLive_slot σ m k).1 hlive
      have htm : t = tm := Cell.live.inj (hxt.symm.trans hxm)
      rw [← htm] at hm
      have : m = n := hI.Linj m hmL n hnL t hm hnt
      subst this
      exact Or.inr ⟨k, rfl⟩
    | fwd m => simp [Root.isFwd] at hfwd
    | caller j =>
      obtain ⟨hj, hc⟩ := hcov
      obtain ⟨l', hl0, hl', hno⟩ := callerCell_live hs hI hj hc
      rw [hxt] at hl'
      have hl'' : t = l' := Cell.live.inj hl'
      rw [hl''] at hnt
      exact absurd (hI.Lfree n hnL l' hnt x hl0) hno
  -- if the owner were dying the root would end here
  have hdy : n ∉ dyingOwners cc i := by
    intro hdn
    rcases hown with rfl | ⟨k, rfl⟩
    · simp [Root.endsAt] at hend
      exact hend hdn
    · simp [Root.endsAt] at hend
      exact hend.1 hdn
  unfold dyingOwners at hdy
  by_cases hc : (i.cls == .construct && cc.sd i == .owned) = true
  · simp only [Bool.and_eq_true, beq_iff_eq] at hc
    exact ⟨hc.1, hc.2, n, hn, hnt, hown⟩
  · exfalso
    simp only [hc, Bool.false_eq_true, ↓reduceIte] at hdy
    exact hdy hn

/-- **No lent or held cell is destroyed** (design §10.6, rule K1, and J4): from the invariants of the
lent and held cells, the loans of the holder (`loansOk`) and the lookup of the consumed trees. -/
theorem lentSafe_ok (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) : LentSafe (Ctx.entering cc.f cc.c args) ds i := by
  intro g x t hlh hgl hxt htc
  obtain ⟨l, hgl, hlnc⟩ := hgl
  rcases hlh with hl | hh
  · obtain ⟨v, hvL, tv, hvt, hgv, _, ρ, hρ, hfwd, hlive, hcov⟩ := hI.lentCov g x hl ⟨l, hgl⟩
    have hltv : l = tv := by rw [hgl] at hgv; exact Cell.live.inj hgv
    subst hltv
    have hvo : v ∉ cc.ownConsumed i := fun h => hlnc ((consumed_iff hI hok hvL hvt).2 h)
    obtain ⟨hc, hsd, _⟩ := root_consumed hs hI hok hvL hvo hρ hfwd hlive hcov hxt htc
    exact ⟨hc, hsd⟩
  · obtain ⟨v, hvL, tv, hvt, hgv, hcv⟩ := hI.heldCov g x hh ⟨l, hgl⟩
    have hltv : l = tv := by rw [hgl] at hgv; exact Cell.live.inj hgv
    subst hltv
    have hvo : v ∉ cc.ownConsumed i := fun h => hlnc ((consumed_iff hI hok hvL hvt).2 h)
    rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
    · exfalso
      have : t = l := Cell.live.inj (hxt.symm.trans hsame)
      rw [this] at htc
      exact hlnc htc
    · obtain ⟨hc, hsd, _⟩ := root_consumed hs hI hok hvL hvo hρ hfwd hlive hcov hxt htc
      exact ⟨hc, hsd⟩

/-- A checked instruction does not fault. -/
theorem inst_no_fault (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) : ∀ f, ¬ Violates (Ctx.entering cc.f cc.c args) ds i f := by
  intro f
  cases f
  · exact fun h => h (readsAlive_ok hs hI hok)
  · exact fun h => h (consumeLive_ok hI hok)
  · exact fun h => h (consumeOnce_ok hI hok)
  · exact fun h => h (notBorrowed_ok hI hok)
  · rintro ⟨hnc, h⟩
    exact h (separate_ok hs hI hok hnc)
  · rintro (h | h | h)
    · exact h (noStale_ok hI hok)
    · exact h (transferOk_ok hI hok)
    · exact h (closeOk_ok hI hok)
  · exact fun h => h (noEscape_ok hI hok)
  · exact fun h => h (loansLive_ok hs hI hok)
  · exact fun h => h (lentSafe_ok hs hI hok)
  · exact fun h => h

end Own
