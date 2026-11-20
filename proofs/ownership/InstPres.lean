import InstSlots

/-!
# A checked instruction preserves the invariant

`inst_inv` is the heart of the soundness proof: from the invariant at `σ`, a passed instruction
check and the semantic effect of the instruction (`Xform` on the heap, the result interface,
the pending-take and decided-test updates), the invariant holds at `instNext cc σ i`.  The
fields are proved one by one; the pending takes, guarded takes and decided tests are in
`InstSlots.lean`.
-/

namespace Own

section Roots

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}

/-- A borrowed result's parents are operands the instruction reads (or a later take). -/
theorem parent_usable {σ : AbsState} {i : Inst} (hok : InstOk cc σ i) {d : ValId}
    (hd : i.dst = some d) (hb : cc.st d = .borrowed) {p : Root} (hp : p ∈ cc.c.parents d) :
    ∃ n, p = .val n ∧ (usable cc σ n = true ∨ forwardTake cc i n = true) := by
  have hpar := hok.par
  have hpu := hok.pu
  unfold parentsOk CCtx.sd CCtx.pd at hpar
  unfold parentsUsable CCtx.pd at hpu
  rw [hd] at hpar hpu
  have hb' : cc.c.state d = .borrowed := hb
  simp only [hb', beq_self_eq_true, if_true] at hpar
  have h1 := List.all_eq_true.1 hpar p hp
  have h2 := List.all_eq_true.1 hpu p hp
  cases p with
  | val n =>
    refine ⟨n, rfl, ?_⟩
    simpa using h2
  | caller j => simp at h1
  | slot n k => simp at h1
  | fwd n => simp at h1

variable {σ : AbsState} {ds : DState}

/-- Two cells with one label, one of them in a borrowed parameter's trees, are both there. -/
theorem callerCell_share (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds) {j : Nat}
    (hj : cc.f.params[j]? = some .borrowed) {y x : Addr} {l : Addr}
    (hy : (args j).cells h0 y) (hyl : ds.heap y = .live l) (hxl : ds.heap x = .live l) :
    (args j).cells h0 x := by
  obtain ⟨l0, hl0, hl0', hn⟩ := callerCell_live hs hI hj hy
  rw [hl0'] at hyl; cases hyl
  rcases hI.acct x l hxl with ⟨v, hv, hvt⟩ | ⟨hx0, _⟩ | hab
  · exact absurd (hI.Lfree v hv l hvt y hl0) hn
  · rcases (hs.pre.borrowed j hj).1 with h | ⟨fp, h⟩
    · rw [h] at hy; simp [Val.cells] at hy
    · rw [h] at hy ⊢
      obtain ⟨z, hz, l', hzl, hyl'⟩ := hy
      rw [hl0] at hyl'; cases hyl'
      exact ⟨z, hz, l, hzl, hx0⟩
  · exact absurd (hI.abFree l hab y hl0) hn

end Roots

/-- An owned result's parents are operands the instruction reads. -/
theorem parent_read {cc : CCtx} {σ : AbsState} {i : Inst} (hok : InstOk cc σ i) {d : ValId}
    (hd : i.dst = some d) (hs : cc.st d = .owned) {n : ValId} (hn : Root.val n ∈ cc.c.parents d) :
    n ∈ i.reads := by
  have hpar := hok.par
  unfold parentsOk CCtx.sd CCtx.pd at hpar
  rw [hd] at hpar
  have hs' : cc.c.state d = .owned := hs
  simp only [hs', beq_self_eq_true, if_true, reduceCtorEq, ↓reduceIte, Bool.false_eq_true] at hpar
  have := List.all_eq_true.1 hpar (.val n) hn
  simpa using this

namespace IC

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {ds ds' : DState} {i : Inst} {r : Option Addr}

theorem imm' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v, (cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .emptied ∨
      cc.st v = .none) → ds'.env v = .imm := by
  intro v hv
  by_cases hd : ∃ d, i.dst = some d ∧ v = d
  · obtain ⟨d, hd, rfl⟩ := hd
    exact c.hr.imm v hd hv
  · rw [c.env_other hd]
    exact c.hI.imm v hv

theorem stk' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v, cc.st v = .stack → ds'.env v = .imm ∨ ds'.env v = .stk := by
  intro v hv
  by_cases hd : ∃ d, i.dst = some d ∧ v = d
  · obtain ⟨d, hd, rfl⟩ := hd
    exact Or.inr (c.hr.stk v hd hv)
  · rw [c.env_other hd]
    exact c.hI.stk v hv

theorem nostk' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v, cc.st v ≠ .stack → ds'.env v ≠ .stk := by
  intro v hv
  by_cases hd : ∃ d, i.dst = some d ∧ v = d
  · obtain ⟨d, hd, rfl⟩ := hd
    cases hst : cc.st v with
    | scalar => rw [c.hr.imm v hd (by simp [hst])]; intro h; cases h
    | immortal => rw [c.hr.imm v hd (by simp [hst])]; intro h; cases h
    | emptied => rw [c.hr.imm v hd (by simp [hst])]; intro h; cases h
    | none => rw [c.hr.imm v hd (by simp [hst])]; intro h; cases h
    | stack => exact absurd hst hv
    | owned =>
      rcases (c.hr.own v hd hst).1 with ⟨h, _⟩ | ⟨t, h, _⟩ <;> rw [h] <;> intro h' <;> cases h'
    | borrowed =>
      rcases (c.hr.bor v hd hst).2 with h | ⟨fp, h, _⟩ <;> rw [h] <;> intro h' <;> cases h'
  · rw [c.env_other hd]
    exact c.hI.nostk v hv

theorem Lown' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, (cc.st v).owning = true := by
  intro v hv
  rcases (instNext_L c.hp v).1 hv with ⟨hv, _⟩ | ⟨d, _, hown, rfl⟩
  · exact c.hI.Lown v hv
  · exact hown

theorem Lbd' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, v < cc.f.nvals := by
  intro v hv
  rcases (instNext_L c.hp v).1 hv with ⟨hv, _⟩ | ⟨d, hd, _, rfl⟩
  · exact c.hI.Lbd v hv
  · exact inst_dst_lt cc.f i v c.hmem hd

theorem Lval' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, ds'.env v = .imm ∨ ∃ t, ds'.env v = .own t ∧ ds'.heap t = .live t := by
  intro v hv
  rcases (instNext_L c.hp v).1 hv with ⟨hvL, hvo⟩ | ⟨d, hd, hown, hvd⟩
  · rw [c.env_L hvL]
    rcases c.hI.Lval v hvL with h | ⟨t, h1, h2⟩
    · left; exact h
    · right; exact ⟨t, h1, c.keep_L hvL hvo h1 h2⟩
  · rw [hvd]
    rcases (c.hr.own d hd (owning_iff.1 hown)).1 with ⟨h, _⟩ | ⟨t, h1, h2⟩
    · left; exact h
    · right; exact ⟨t, h1, (c.hx.root t h2).1⟩

theorem Linj' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, ∀ w ∈ (instNext cc σ i).L, ∀ t, ds'.env v = .own t →
      ds'.env w = .own t → v = w := by
  intro v hv w hw t hvt hwt
  rcases (instNext_L c.hp v).1 hv with ⟨hvL, hvo⟩ | ⟨d, hd, hown, hvd⟩ <;>
    rcases (instNext_L c.hp w).1 hw with ⟨hwL, hwo⟩ | ⟨d', hd', hown', hwd'⟩
  · rw [c.env_L hvL] at hvt
    rw [c.env_L hwL] at hwt
    exact c.hI.Linj v hvL w hwL t hvt hwt
  · -- v old, w new
    rw [c.env_L hvL] at hvt
    rw [hwd'] at hwt
    rcases (c.hr.own d' hd' (owning_iff.1 hown')).1 with ⟨h, _⟩ | ⟨t', h1, h2⟩
    · rw [h] at hwt; cases hwt
    · rw [h1] at hwt; cases hwt
      exact absurd rfl (c.root_fresh h2 hvL hvo hvt)
  · rw [c.env_L hwL] at hwt
    rw [hvd] at hvt
    rcases (c.hr.own d hd (owning_iff.1 hown)).1 with ⟨h, _⟩ | ⟨t', h1, h2⟩
    · rw [h] at hvt; cases hvt
    · rw [h1] at hvt; cases hvt
      exact absurd rfl (c.root_fresh h2 hwL hwo hwt)
  · have := Option.some.inj (hd.symm.trans hd')
    rw [hvd, hwd', this]

theorem Dst' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ w ∈ (instNext cc σ i).D, cc.st w = .borrowed := by
  intro w hw
  rcases (instNext_D c.hp w).1 hw with ⟨hw, _⟩ | ⟨d, _, hb, rfl⟩
  · exact c.hI.Dst w hw
  · exact hb

theorem Dbd' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ w ∈ (instNext cc σ i).D, w < cc.f.nvals := by
  intro w hw
  rcases (instNext_D c.hp w).1 hw with ⟨hw, _⟩ | ⟨d, hd, _, rfl⟩
  · exact c.hI.Dbd w hw
  · exact inst_dst_lt cc.f i w c.hmem hd

/-- A borrowed value of `D` that is not redefined keeps its value. -/
theorem env_D (c : IC cc args h0 pend0 σ ds ds' i r) {w : ValId} (hw : w ∈ σ.D)
    (hnew : ¬ ∃ d, i.dst = some d ∧ cc.st d = .borrowed ∧ w = d) : ds'.env w = ds.env w :=
  c.hr.ne w (fun d hd hwd => hnew ⟨d, hd, by rw [← hwd]; exact c.hI.Dst w hw, hwd⟩)

theorem Dval' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ w ∈ (instNext cc σ i).D, ds'.env w = .imm ∨ ∃ fp, ds'.env w = .bor fp := by
  intro w hw
  by_cases hnew : ∃ d, i.dst = some d ∧ cc.st d = .borrowed ∧ w = d
  · obtain ⟨d, hd, hb, rfl⟩ := hnew
    obtain ⟨_, hv⟩ := c.hr.bor w hd hb
    rcases hv with h | ⟨fp, h, _⟩
    · left; exact h
    · right; exact ⟨fp, h⟩
  · rcases (instNext_D c.hp w).1 hw with ⟨hwD, _⟩ | hn
    · rw [c.env_D hwD hnew]; exact c.hI.Dval w hwD
    · exact absurd hn hnew

theorem frame' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ x t, h0 x = .live t → ¬ OwnedArg cc.f args t → ds'.heap x = .live t := by
  intro x t h0x hn
  have hx0 := c.hI.frame x t h0x hn
  apply c.hx.keep x t hx0
  intro htcs
  obtain ⟨k, _, hkL, hkt⟩ := consumedRoots_mem c.hI c.hok htcs
  exact hn (c.hI.Lfree k hkL t hkt x h0x)

theorem dead' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ x, h0 x = .dead → ds'.heap x = .dead :=
  fun x h => c.hx.stay x (c.hI.dead x h)

theorem unused' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ x, ds'.heap x = .unused → h0 x = .unused := by
  intro x hx
  apply c.hI.unused x
  cases hcell : ds.heap x with
  | unused => rfl
  | dead => rw [c.hx.stay x hcell] at hx; cases hx
  | live t0 =>
    by_cases ht : t0 ∈ consumedRoots ds i
    · rcases c.hx.gone x t0 hcell ht with h | ⟨r', _, h⟩ <;> rw [h] at hx <;> cases hx
    · rw [c.hx.keep x t0 hcell ht] at hx; cases hx

theorem acct' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ x t, ds'.heap x = .live t →
      (∃ v ∈ (instNext cc σ i).L, ds'.env v = .own t) ∨
        (h0 x = .live t ∧ ¬ OwnedArg cc.f args t) ∨ ds'.abandoned t := by
  intro x t hxt
  have viaR : ∀ r', r = some r' → ds'.heap x = .live r' →
      ∃ v ∈ (instNext cc σ i).L, ds'.env v = .own t := by
    intro r' hr' h
    rw [h] at hxt
    cases hxt
    obtain ⟨d, hd, hown, he⟩ := c.rsome hr'
    exact ⟨d, (instNext_L c.hp d).2 (Or.inr ⟨d, hd, hown, rfl⟩), he⟩
  cases hcell : ds.heap x with
  | unused =>
    left
    rcases c.hx.fresh x hcell with h | h | ⟨r', hr', h⟩
    · rw [h] at hxt; cases hxt
    · rw [h] at hxt; cases hxt
    · exact viaR r' hr' h
  | dead => rw [c.hx.stay x hcell] at hxt; cases hxt
  | live t0 =>
    by_cases ht : t0 ∈ consumedRoots ds i
    · left
      rcases c.hx.gone x t0 hcell ht with h | ⟨r', hr', h⟩
      · rw [h] at hxt; cases hxt
      · exact viaR r' hr' h
    · have hk := c.hx.keep x t0 hcell ht
      have htt : t = t0 := by have := hxt.symm.trans hk; simpa using this
      rw [htt]
      rcases c.hI.acct x t0 hcell with ⟨v, hv, hvt⟩ | h | hab
      · left
        have hvo : v ∉ cc.ownConsumed i := fun h' => ht ((consumed_iff c.hI c.hok hv hvt).2 h')
        exact ⟨v, (instNext_L c.hp v).2 (Or.inl ⟨hv, hvo⟩), by rw [c.env_L hv]; exact hvt⟩
      · right; left; exact h
      · right; right; rw [c.habn]; exact hab

/-- The consumed roots are not abandoned: they are owned by values of `L`. -/
theorem consumed_not_abandoned (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr}
    (ht : t ∈ consumedRoots ds i) : ¬ ds.abandoned t := by
  obtain ⟨k, _, hkL, hkt⟩ := consumedRoots_mem c.hI c.hok ht
  exact c.hI.Ldisj k hkL t hkt

theorem abLive' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ t, ds'.abandoned t → ds'.heap t = .live t := by
  intro t ht
  rw [c.habn] at ht
  have hl := c.hI.abLive t ht
  exact c.hx.keep t t hl (fun hc => consumed_not_abandoned c hc ht)

theorem Ldisj' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, ∀ t, ds'.env v = .own t → ¬ ds'.abandoned t := by
  intro v hv t hvt hab
  rw [c.habn] at hab
  rcases (instNext_L c.hp v).1 hv with ⟨hvL, hvo⟩ | ⟨d, hd, hown, hvd⟩
  · rw [c.env_L hvL] at hvt
    exact c.hI.Ldisj v hvL t hvt hab
  · rw [hvd] at hvt
    rcases (c.hr.own d hd (owning_iff.1 hown)).1 with ⟨h, _⟩ | ⟨t', h1, h2⟩
    · rw [h] at hvt; cases hvt
    · have htt : t' = t := Val.own.inj (h1.symm.trans hvt)
      subst htt
      obtain ⟨_, hroot⟩ := c.hx.root _ h2
      rcases hroot with h4 | ⟨t3, h4, h5⟩
      · have := c.hI.abLive t' hab
        rw [h4] at this; cases this
      · have h6 : t' = t3 := by
          have := c.hI.abLive t' hab
          rw [h4] at this; cases this; rfl
        subst h6
        exact consumed_not_abandoned c h5 hab

theorem abFree' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ t, ds'.abandoned t → ∀ x, h0 x = .live t → OwnedArg cc.f args t := by
  intro t ht x hx
  rw [c.habn] at ht
  exact c.hI.abFree t ht x hx

theorem Lfree' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ v ∈ (instNext cc σ i).L, ∀ t, ds'.env v = .own t → ∀ x, h0 x = .live t →
      OwnedArg cc.f args t := by
  intro v hv t hvt x h0x
  rcases (instNext_L c.hp v).1 hv with ⟨hvL, hvo⟩ | ⟨d, hd, hown, hvd⟩
  · rw [c.env_L hvL] at hvt
    exact c.hI.Lfree v hvL t hvt x h0x
  · rw [hvd] at hvt
    rcases (c.hr.own d hd (owning_iff.1 hown)).1 with ⟨h, _⟩ | ⟨t', h1, h2⟩
    · rw [h] at hvt; cases hvt
    · have htt : t' = t := Val.own.inj (h1.symm.trans hvt)
      subst htt
      obtain ⟨_, hroot⟩ := c.hx.root _ h2
      have hwf := c.hs.pre.wf x _ h0x
      rcases hroot with h4 | ⟨t3, h4, h5⟩
      · rw [c.hI.unused _ h4] at hwf; cases hwf
      · obtain ⟨k, _, hkL, hkt⟩ := consumedRoots_mem c.hI c.hok h5
        by_cases hn : OwnedArg cc.f args t'
        · exact hn
        · exfalso
          have hfr := c.hI.frame t' t' hwf hn
          rw [h4] at hfr; cases hfr
          exact hn (c.hI.Lfree k hkL _ hkt t' hwf)

/-- The members of `ownConsumed` are live. -/
theorem oc_live (c : IC cc args h0 pend0 σ ds ds' i r) {k : ValId} (hk : k ∈ cc.ownConsumed i) :
    k ∈ σ.L := by
  obtain ⟨hc, hown⟩ := mem_ownConsumed.1 hk
  rcases c.hok.c2 k hc with hsc | ⟨_, hL⟩
  · exfalso
    rcases hsc with h | h | h | h <;> simp [h, St.owning] at hown
  · exact hL

/-- A root that survives keeps its cells. -/
theorem transport (c : IC cc args h0 pend0 σ ds ds' i r) {ρ : Root}
    (hρ : rootLive (instNext cc σ i) ρ = true)
    (hne : ∀ d, i.dst = some d → cc.st d = .owned → ρ.ownedBy d = false) {x : Addr}
    (h : Covers cc args h0 ds ρ x) : Covers cc args h0 ds' ρ x := by
  cases ρ with
  | caller j => exact h
  | fwd n => exact h
  | val n =>
    have hn : n ∈ (instNext cc σ i).L := (rootLive_val _ n).1 hρ
    rcases (instNext_L c.hp n).1 hn with ⟨hnL, hno⟩ | ⟨d, hd, hown, hnd⟩
    · obtain ⟨t, h1, h2⟩ := h
      exact ⟨t, by rw [c.env_L hnL]; exact h1, c.keep_L hnL hno h1 h2⟩
    · have := hne d hd (owning_iff.1 hown)
      simp [Root.ownedBy, hnd] at this
  | slot n k =>
    have hn : n ∈ (instNext cc σ i).L := (rootLive_slot _ n k).1 hρ
    rcases (instNext_L c.hp n).1 hn with ⟨hnL, hno⟩ | ⟨d, hd, hown, hnd⟩
    · obtain ⟨t, h1, h2⟩ := h
      exact ⟨t, by rw [c.env_L hnL]; exact h1, c.keep_L hnL hno h1 h2⟩
    · have := hne d hd (owning_iff.1 hown)
      simp [Root.ownedBy, hnd] at this

/-- A root (other than a placeholder) alive after the instruction was alive before it. -/
theorem live_old (c : IC cc args h0 pend0 σ ds ds' i r) {ρ : Root}
    (hρ : rootLive (instNext cc σ i) ρ = true) (hf : ρ.isFwd = false)
    (hne : ∀ d, i.dst = some d → cc.st d = .owned → ρ.ownedBy d = false) :
    rootLive σ ρ = true := by
  cases ρ with
  | caller j => rfl
  | fwd n => simp [Root.isFwd] at hf
  | val n =>
    have hn : n ∈ (instNext cc σ i).L := (rootLive_val _ n).1 hρ
    rcases (instNext_L c.hp n).1 hn with ⟨hnL, _⟩ | ⟨d, hd, hown, hnd⟩
    · exact (rootLive_val σ n).2 hnL
    · have := hne d hd (owning_iff.1 hown)
      simp [Root.ownedBy, hnd] at this
  | slot n k =>
    have hn : n ∈ (instNext cc σ i).L := (rootLive_slot _ n k).1 hρ
    rcases (instNext_L c.hp n).1 hn with ⟨hnL, _⟩ | ⟨d, hd, hown, hnd⟩
    · exact (rootLive_slot σ n k).2 hnL
    · have := hne d hd (owning_iff.1 hown)
      simp [Root.ownedBy, hnd] at this

theorem forwardTake_eq (c : IC cc args h0 pend0 σ ds ds' i r) (n : ValId) :
    forwardTake cc i n =
      forwardTakeWith (Ctx.entering cc.f cc.c args).fn.defOf? (Ctx.entering cc.f cc.c args).cert i n := by
  unfold forwardTake
  have : (fun x => cc.defOf[x]?) = cc.f.defOf? := funext c.hs.defEq
  simp [this]

/-- The roots a borrowed parent contributes to the result. -/
theorem resultRoots_mem_borrowed {n : ValId} (hpm : Root.val n ∈ cc.pd i)
    (hnf : forwardTakeWith (fun x => cc.defOf[x]?) cc.c i n = false) (hst : cc.st n = .borrowed) :
    ∀ ρ ∈ Rget σ n, ρ ∈ resultRoots cc σ i := by
  intro ρ hρ
  unfold resultRoots
  refine mem_normRoots.2 (List.mem_flatMap.2 ⟨.val n, hpm, ?_⟩)
  have : (cc.st n == .owned) = false := by simp [hst]
  simp [hnf, this, rootsOf, hst, hρ]

/-- The root an owned parent contributes to the result. -/
theorem resultRoots_mem_owned {n : ValId} (hpm : Root.val n ∈ cc.pd i)
    (hnf : forwardTakeWith (fun x => cc.defOf[x]?) cc.c i n = false) (hst : cc.st n = .owned) :
    ∃ ρ ∈ resultRoots cc σ i, ρ = .val n ∨ ∃ k, ρ = .slot n k := by
  unfold resultRoots
  by_cases hcond : (i.cls == .project && cc.st n == .owned && i.reads.head? == some n) = true
  · cases hsl : i.slot with
    | none =>
      refine ⟨.val n, mem_normRoots.2 (List.mem_flatMap.2 ⟨.val n, hpm, ?_⟩), Or.inl rfl⟩
      simp [hnf, hcond, hsl]
    | some k =>
      refine ⟨.slot n k, mem_normRoots.2 (List.mem_flatMap.2 ⟨.val n, hpm, ?_⟩), Or.inr ⟨k, rfl⟩⟩
      simp [hnf, hcond, hsl]
  · have hcond2 : ¬ (i.cls = .project ∧ i.reads.head? = some n) := by
      rintro ⟨h1, h2⟩
      apply hcond
      simp [h1, hst, h2]
    refine ⟨.val n, mem_normRoots.2 (List.mem_flatMap.2 ⟨.val n, hpm, ?_⟩), Or.inl rfl⟩
    simp [hnf, hcond2, rootsOf, hst]

theorem Dcov' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ w ∈ (instNext cc σ i).D,
      (∀ ρ ∈ Rget (instNext cc σ i) w, ρ.isFwd = true ∨ rootLive (instNext cc σ i) ρ = true) →
      ∀ fp, ds'.env w = .bor fp → ∀ x ∈ fp,
        ∃ ρ ∈ Rget (instNext cc σ i) w, ρ.isFwd = false ∧ Covers cc args h0 ds' ρ x := by
  intro w hw hlive fp hfp x hx
  by_cases hnew : ∃ d, i.dst = some d ∧ cc.st d = .borrowed ∧ w = d
  · -- the borrowed value this instruction defines
    obtain ⟨d, hd, hb, rfl⟩ := hnew
    obtain ⟨_, hv⟩ := c.hr.bor w hd hb
    rcases hv with h | ⟨fp', h1, h2⟩
    · rw [h] at hfp; cases hfp
    · have hfpeq : fp' = fp := Val.bor.inj (h1.symm.trans hfp)
      subst hfpeq
      obtain ⟨⟨p, hp, hnf, hcell⟩, _⟩ := h2 x hx
      obtain ⟨n, rfl, hnu⟩ := parent_usable c.hok hd hb hp
      have hnofwd : forwardTakeWith (fun x => cc.defOf[x]?) cc.c i n = false := by
        have := hnf n rfl
        rw [← c.forwardTake_eq] at this
        exact this
      have hnu' : usable cc σ n = true := by
        rcases hnu with h | h
        · exact h
        · unfold forwardTake at h
          rw [hnofwd] at h; cases h
      have hR := Rget_next_new (σ := σ) c.hp hd hb
      have hpm : Root.val n ∈ cc.pd i := by simpa [CCtx.pd, hd] using hp
      have hne0 : ∀ ρ : Root, ∀ d', i.dst = some d' → cc.st d' = .owned → ρ.ownedBy d' = false := by
        intro ρ d' hd' hown
        have := Option.some.inj (hd.symm.trans hd')
        subst this
        rw [hb] at hown; cases hown
      simp only [rootCells] at hcell
      cases hst : cc.st n with
      | scalar => rw [c.hI.imm n (by simp [hst])] at hcell; simp [Val.cells] at hcell
      | immortal => rw [c.hI.imm n (by simp [hst])] at hcell; simp [Val.cells] at hcell
      | stack =>
        rcases c.hI.stk n hst with h | h <;> rw [h] at hcell <;> simp [Val.cells] at hcell
      | emptied =>
        rw [c.hI.imm n (by simp [hst])] at hcell; simp [Val.cells] at hcell
      | none => simp [usable, hst] at hnu'
      | owned =>
        have hnL : n ∈ σ.L := usable_owning (by simp [hst, St.owning]) hnu'
        rcases c.hI.Lval n hnL with h' | ⟨t, h1', _⟩
        · rw [h'] at hcell; simp [Val.cells] at hcell
        · rw [h1'] at hcell
          simp only [Val.cells] at hcell
          obtain ⟨ρ, hρR, hρ⟩ := resultRoots_mem_owned (σ := σ) hpm hnofwd hst
          rw [hR]
          have hnf' : ρ.isFwd = false := by rcases hρ with rfl | ⟨k, rfl⟩ <;> rfl
          refine ⟨ρ, hρR, hnf', ?_⟩
          have hlv : rootLive (instNext cc σ i) ρ = true := by
            rcases hlive ρ (by rw [hR]; exact hρR) with h | h
            · rw [hnf'] at h; cases h
            · exact h
          rcases hρ with rfl | ⟨k, rfl⟩
          · exact c.transport hlv (hne0 _) ⟨t, h1', hcell⟩
          · exact c.transport hlv (hne0 _) ⟨t, h1', hcell⟩
      | borrowed =>
        obtain ⟨hnD, hnroots⟩ := usable_borrowed hst hnu'
        rcases c.hI.Dval n hnD with h' | ⟨fpn, hfpn⟩
        · rw [h'] at hcell; simp [Val.cells] at hcell
        · rw [hfpn] at hcell
          obtain ⟨y, hy, l, hyl, hxl⟩ := hcell
          obtain ⟨ρ, hρ, hnf', hcov⟩ := c.hI.Dcov n hnD (fun ρ hρ => Or.inr (hnroots ρ hρ)) fpn hfpn y hy
          have hmem : ρ ∈ Rget (instNext cc σ i) w := by
            rw [hR]; exact resultRoots_mem_borrowed hpm hnofwd hst ρ hρ
          refine ⟨ρ, hmem, hnf', ?_⟩
          have hlv : rootLive (instNext cc σ i) ρ = true := by
            rcases hlive ρ hmem with h | h
            · rw [hnf'] at h; cases h
            · exact h
          cases ρ with
          | val m =>
            obtain ⟨t, h1', h2'⟩ := hcov
            have hlt : l = t := by have := hyl.symm.trans h2'; simpa using this
            rw [hlt] at hxl
            exact c.transport hlv (hne0 _) ⟨t, h1', hxl⟩
          | slot m k =>
            obtain ⟨t, h1', h2'⟩ := hcov
            have hlt : l = t := by have := hyl.symm.trans h2'; simpa using this
            rw [hlt] at hxl
            exact c.transport hlv (hne0 _) ⟨t, h1', hxl⟩
          | fwd m => exact hcov.elim
          | caller j =>
            obtain ⟨hj, hc⟩ := hcov
            exact ⟨hj, callerCell_share c.hs c.hI hj hc hyl hxl⟩
  · rcases (instNext_D c.hp w).1 hw with ⟨hwD, htk, hown⟩ | hn
    · have hwb := c.hI.Dst w hwD
      have henv := c.env_D hwD hnew
      rw [henv] at hfp
      -- every old root has a successor in the new state
      have hsucc := Rget_next_old (σ := σ) c.hp hwb hnew
      -- the premise of the old invariant
      have hpre : ∀ ρ ∈ Rget σ w, ρ.isFwd = true ∨ rootLive σ ρ = true := by
        intro ρ0 hρ0
        obtain ⟨ρ', hρ', hrn⟩ := hsucc ρ0 hρ0
        by_cases hf : ρ0.isFwd = true
        · exact Or.inl hf
        · right
          have hf' : ρ0.isFwd = false := by simpa using hf
          rcases hrn with hrn | ⟨hC, d, hd, hdo, o, ho, hren⟩
          · have hrn' : ρ0 = ρ' := hrn.symm
            subst hrn'
            rcases hlive _ hρ' with h | h
            · rw [hf'] at h; cases h
            · exact c.live_old h hf' (fun d hd hdo => hown d hd hdo _ hρ0)
          · have hoL := c.oc_live ho
            rcases hren with ⟨h1, _⟩ | ⟨k, h1, _⟩
            · rw [h1]; exact (rootLive_val σ o).2 hoL
            · rw [h1]; exact (rootLive_slot σ o k).2 hoL
      obtain ⟨ρ0, hρ0, hnf0, hcov⟩ := c.hI.Dcov w hwD hpre fp hfp x hx
      obtain ⟨ρ', hρ', hrn⟩ := hsucc ρ0 hρ0
      rcases hrn with hrn | ⟨hC, d, hd, hdo, o, ho, hren⟩
      · have hrn' : ρ0 = ρ' := hrn.symm
        subst hrn'
        refine ⟨ρ0, hρ', hnf0, ?_⟩
        have hlv : rootLive (instNext cc σ i) ρ0 = true := by
          rcases hlive _ hρ' with h | h
          · rw [hnf0] at h; cases h
          · exact h
        exact c.transport hlv (fun d hd hdo => hown d hd hdo _ hρ0) hcov
      · -- the owner was taken into the aggregate the constructor built
        have hoL := c.oc_live ho
        have hret := c.hret hC ⟨d, hd, hdo⟩
        have hnew : ∃ r', ds'.env d = .own r' ∧ ds'.heap x = .live r' := by
          obtain ⟨t0, ht0, hx0⟩ : ∃ t0, ds.env o = .own t0 ∧ ds.heap x = .live t0 := by
            rcases hren with ⟨h1, _⟩ | ⟨k, h1, _⟩ <;> (rw [h1] at hcov; exact hcov)
          have hcons : t0 ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hoL ht0).2 ho
          obtain ⟨r', hr', hxr⟩ := hret x t0 hx0 hcons
          rcases (c.hr.own d hd hdo).1 with ⟨_, hrn'⟩ | ⟨t', he, hrt⟩
          · rw [hrn'] at hr'; cases hr'
          · rw [hr'] at hrt; cases hrt
            exact ⟨r', he, hxr⟩
        obtain ⟨r', he, hxr⟩ := hnew
        rcases hren with ⟨h1, h2⟩ | ⟨k, h1, h2⟩
        · refine ⟨ρ', hρ', by rw [h2]; rfl, ?_⟩
          rw [h2]; exact ⟨r', he, hxr⟩
        · refine ⟨ρ', hρ', by rw [h2]; rfl, ?_⟩
          rw [h2]; exact ⟨r', he, hxr⟩
    · exact absurd hn hnew

/-! ### Lent cells (design §10.6) -/

/-- An allocated cell stays allocated. -/
theorem not_unused (c : IC cc args h0 pend0 σ ds ds' i r) {y : Addr} (h : ds.heap y ≠ .unused) :
    ds'.heap y ≠ .unused := by
  intro hu
  cases hy : ds.heap y with
  | unused => exact h hy
  | dead => have := c.hx.stay y hy; rw [hu] at this; cases this
  | live t =>
    by_cases ht : t ∈ consumedRoots ds i
    · rcases c.hx.gone y t hy ht with h' | ⟨r', _, h'⟩ <;> rw [hu] at h' <;> cases h'
    · have := c.hx.keep y t hy ht; rw [hu] at this; cases this

/-- A cell that is live after the instruction and was allocated before it was live before it. -/
theorem live_back (c : IC cc args h0 pend0 σ ds ds' i r) {y : Addr} (h : ds.heap y ≠ .unused)
    {l : Addr} (h' : ds'.heap y = .live l) : ∃ l0, ds.heap y = .live l0 := by
  cases hy : ds.heap y with
  | unused => exact absurd hy h
  | dead => have := c.hx.stay y hy; rw [h'] at this; cases this
  | live t => exact ⟨t, rfl⟩

/-- What the shape of a lend gives the step. -/
theorem lend_facts (c : IC cc args h0 pend0 σ ds ds' i r) {gv : ValId} (hl : i.lent = some gv) :
    i.cls = .construct ∧ cc.ownConsumed i = [] ∧ consumedRoots ds i = [] ∧ gv ∈ σ.L ∧
      (∃ d, i.dst = some d ∧ cc.st d = .owned) ∧ ∃ a, i.reads = [a, gv] ∧ a ≠ gv := by
  obtain ⟨hcl, hcons, hsd, hpd, ⟨a, hreads, hne⟩, hgst⟩ := lend_shape c.hok.lend hl
  refine ⟨hcl, ?_, ?_, ?_, ?_, a, hreads, hne⟩
  · simp [CCtx.ownConsumed, hcons]
  · simp [consumedRoots, hcons]
  · exact usable_owning (by simp [hgst, St.owning]) (c.hok.r3 gv (by simp [hreads]) (by simp [hgst]))
  · cases hd : i.dst with
    | none => simp [CCtx.sd, hd] at hsd
    | some d => exact ⟨d, rfl, by simpa [CCtx.sd, hd, CCtx.st] using hsd⟩

/-- A live root never names the value the instruction defines. -/
theorem live_ne_dst (c : IC cc args h0 pend0 σ ds ds' i r) {ρ : Root} (hl : rootLive σ ρ = true) :
    ∀ d, i.dst = some d → cc.st d = .owned → ρ.ownedBy d = false := by
  intro d hd _
  cases ρ with
  | val n =>
    have := L_ne_dst c.hI c.hok c.hcls ((rootLive_val σ n).1 hl) hd
    simpa [Root.ownedBy] using this
  | slot n k =>
    have := L_ne_dst c.hI c.hok c.hcls ((rootLive_slot σ n k).1 hl) hd
    simpa [Root.ownedBy] using this
  | caller _ => rfl
  | fwd _ => rfl

/-- A root of a surviving holder keeps its cells (or, renamed because a constructor took its owner, the
constructor's result does). -/
theorem root_next (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId} (hvL : v ∈ σ.L)
    (hvo : v ∉ cc.ownConsumed i) {ρ : Root} (hρ : ρ ∈ Rget σ v) (hfwd : ρ.isFwd = false)
    (hlive : rootLive σ ρ = true) {x : Addr} (hcov : Covers cc args h0 ds ρ x) :
    rootLive (instNext cc σ i) (nextRoot cc i ρ) = true ∧
      Covers cc args h0 ds' (nextRoot cc i ρ) x := by
  cases ρ with
  | fwd m => simp [Root.isFwd] at hfwd
  | caller j =>
    rw [nextRoot_caller]
    exact ⟨rootLive_caller _ j, hcov⟩
  | val n =>
    have hnL : n ∈ σ.L := (rootLive_val σ n).1 hlive
    obtain ⟨tn, hn, hxn⟩ := hcov
    by_cases hno : n ∈ cc.ownConsumed i
    · have htc : tn ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hnL hn).2 hno
      obtain ⟨hcl, hsd, _⟩ := root_consumed c.hs c.hI c.hok hvL hvo hρ hfwd hlive ⟨tn, hn, hxn⟩ hxn htc
      obtain ⟨d, hd, hds⟩ : ∃ d, i.dst = some d ∧ cc.st d = .owned := by
        cases hd : i.dst with
        | none => simp [CCtx.sd, hd] at hsd
        | some d => exact ⟨d, rfl, by simpa [CCtx.sd, hd, CCtx.st] using hsd⟩
      rw [nextRoot_val_moved hd hcl hds hno]
      refine ⟨(rootLive_val _ d).2 ((instNext_L c.hp d).2 (Or.inr ⟨d, hd, by simp [hds, St.owning], rfl⟩)), ?_⟩
      obtain ⟨r', hr', hxr⟩ := c.hret hcl ⟨d, hd, hds⟩ x tn hxn htc
      obtain ⟨d', hd', _, he⟩ := c.rsome hr'
      have : d' = d := Option.some.inj (hd'.symm.trans hd)
      subst this
      exact ⟨r', he, hxr⟩
    · rw [nextRoot_val_self hno]
      have hlv : rootLive (instNext cc σ i) (.val n) = true :=
        (rootLive_val _ n).2 ((instNext_L c.hp n).2 (Or.inl ⟨hnL, hno⟩))
      exact ⟨hlv, c.transport hlv (c.live_ne_dst hlive) ⟨tn, hn, hxn⟩⟩
  | slot n k =>
    have hnL : n ∈ σ.L := (rootLive_slot σ n k).1 hlive
    obtain ⟨tn, hn, hxn⟩ := hcov
    by_cases hno : n ∈ cc.ownConsumed i
    · have htc : tn ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hnL hn).2 hno
      obtain ⟨hcl, hsd, _⟩ := root_consumed c.hs c.hI c.hok hvL hvo hρ hfwd hlive ⟨tn, hn, hxn⟩ hxn htc
      obtain ⟨d, hd, hds⟩ : ∃ d, i.dst = some d ∧ cc.st d = .owned := by
        cases hd : i.dst with
        | none => simp [CCtx.sd, hd] at hsd
        | some d => exact ⟨d, rfl, by simpa [CCtx.sd, hd, CCtx.st] using hsd⟩
      rw [nextRoot_slot_moved k hd hcl hds hno]
      refine ⟨(rootLive_slot _ d "*").2 ((instNext_L c.hp d).2 (Or.inr ⟨d, hd, by simp [hds, St.owning], rfl⟩)), ?_⟩
      obtain ⟨r', hr', hxr⟩ := c.hret hcl ⟨d, hd, hds⟩ x tn hxn htc
      obtain ⟨d', hd', _, he⟩ := c.rsome hr'
      have : d' = d := Option.some.inj (hd'.symm.trans hd)
      subst this
      exact ⟨r', he, hxr⟩
    · rw [nextRoot_slot_self k hno]
      have hlv : rootLive (instNext cc σ i) (.slot n k) = true :=
        (rootLive_slot _ n k).2 ((instNext_L c.hp n).2 (Or.inl ⟨hnL, hno⟩))
      exact ⟨hlv, c.transport hlv (c.live_ne_dst hlive) ⟨tn, hn, hxn⟩⟩

/-- A root a new owned value `d` is given (a listed parent's root, or a root of an owner a constructor
took over): the cell it covers is in the tree of `d` (a constructor that took the root's owner keeps
it there), or `d` records the root, still alive, and it still covers the cell. -/
theorem root_new (c : IC cc args h0 pend0 σ ds ds' i r) {d : ValId} (hd : i.dst = some d)
    (hds : cc.st d = .owned) (hl : i.lent = none) {ρ : Root} (hin : ρ ∈ loansOf cc σ i)
    (hfwd : ρ.isFwd = false) (hlive : rootLive σ ρ = true)
    (hdisj : ∀ m ∈ cc.ownConsumed i, ρ.ownedBy m = true → i.cls = .construct) {x : Addr}
    (hcov : Covers cc args h0 ds ρ x) :
    (∃ r', ds'.env d = .own r' ∧ ds'.heap x = .live r') ∨
    ∃ ρ' ∈ Rget (instNext cc σ i) d, ρ'.isFwd = false ∧
      rootLive (instNext cc σ i) ρ' = true ∧ Covers cc args h0 ds' ρ' x := by
  have hp := c.hp
  have hsel := fun ρ0 => Rget_next_owned_self (cc := cc) (i := i) hp hd hds hl σ ρ0
  have hmemN : ∀ ρ0 ∈ loansOf cc σ i,
      (match nextRoot cc i ρ0 with
        | .val n => n != d
        | .slot n _ => n != d
        | .caller _ => true
        | .fwd _ => true) = true →
      nextRoot cc i ρ0 ∈ Rget (instNext cc σ i) d := by
    intro ρ0 h0 hself
    rw [hsel]
    by_cases hC : (i.cls == .construct) = true
    · left
      refine ⟨hC, mem_normRoots.2 (List.mem_map.2 ⟨ρ0, h0, ?_⟩), hself⟩
      simp [nextRoot, hd, hC, hds]
    · right
      have hC' : (i.cls == .construct) = false := by simpa using hC
      refine ⟨hC', ?_⟩
      have : nextRoot cc i ρ0 = ρ0 := by simp [nextRoot, hd, hds, hC']
      rw [this]; exact h0
  have hne : ∀ n, rootLive σ (.val n) = true → (n != d) = true := by
    intro n hn
    have := c.live_ne_dst hn d hd hds
    simpa [Root.ownedBy] using this
  have hnes : ∀ n k, rootLive σ (.slot n k) = true → (n != d) = true := by
    intro n k hn
    have := c.live_ne_dst hn d hd hds
    simpa [Root.ownedBy] using this
  have hd' : (instNext cc σ i).L.contains d = true := by
    exact List.contains_iff_mem.2 ((instNext_L hp d).2 (Or.inr ⟨d, hd, by simp [hds, St.owning], rfl⟩))
  cases ρ with
  | fwd m => simp [Root.isFwd] at hfwd
  | caller j =>
    right
    have h1 : nextRoot cc i (.caller j) = .caller j := nextRoot_caller cc i j
    refine ⟨.caller j, ?_, rfl, rootLive_caller _ j, hcov⟩
    have := hmemN (.caller j) hin (by rw [h1])
    rwa [h1] at this
  | val n =>
    have hnL : n ∈ σ.L := (rootLive_val σ n).1 hlive
    obtain ⟨tn, hn, hxn⟩ := hcov
    by_cases hno : n ∈ cc.ownConsumed i
    · left
      have hC : i.cls = .construct := hdisj n hno (by simp [Root.ownedBy])
      have htc : tn ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hnL hn).2 hno
      obtain ⟨r', hr', hxr⟩ := c.hret hC ⟨d, hd, hds⟩ x tn hxn htc
      obtain ⟨d', hd'', _, he⟩ := c.rsome hr'
      have : d' = d := Option.some.inj (hd''.symm.trans hd)
      subst this
      exact ⟨r', he, hxr⟩
    · right
      have h1 := nextRoot_val_self (cc := cc) (i := i) hno
      have hlv : rootLive (instNext cc σ i) (.val n) = true :=
        (rootLive_val _ n).2 ((instNext_L hp n).2 (Or.inl ⟨hnL, hno⟩))
      refine ⟨.val n, ?_, rfl, hlv, c.transport hlv (c.live_ne_dst hlive) ⟨tn, hn, hxn⟩⟩
      have := hmemN (.val n) hin (by rw [h1]; exact hne n hlive)
      rwa [h1] at this
  | slot n k =>
    have hnL : n ∈ σ.L := (rootLive_slot σ n k).1 hlive
    obtain ⟨tn, hn, hxn⟩ := hcov
    by_cases hno : n ∈ cc.ownConsumed i
    · left
      have hC : i.cls = .construct := hdisj n hno (by simp [Root.ownedBy])
      have htc : tn ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hnL hn).2 hno
      obtain ⟨r', hr', hxr⟩ := c.hret hC ⟨d, hd, hds⟩ x tn hxn htc
      obtain ⟨d', hd'', _, he⟩ := c.rsome hr'
      have : d' = d := Option.some.inj (hd''.symm.trans hd)
      subst this
      exact ⟨r', he, hxr⟩
    · right
      have h1 := nextRoot_slot_self (cc := cc) (i := i) k hno
      have hlv : rootLive (instNext cc σ i) (.slot n k) = true :=
        (rootLive_slot _ n k).2 ((instNext_L hp n).2 (Or.inl ⟨hnL, hno⟩))
      refine ⟨.slot n k, ?_, rfl, hlv, c.transport hlv (c.live_ne_dst hlive) ⟨tn, hn, hxn⟩⟩
      have := hmemN (.slot n k) hin (by rw [h1]; exact hnes n k hlive)
      rwa [h1] at this

theorem lentSeen' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ g x, ds'.lent g x → ds'.heap g ≠ .unused := by
  intro g x h
  rw [c.hlent] at h
  rcases h with h | ⟨gv, a, hl, ha, hg, hx⟩
  · exact c.not_unused (c.hI.lentSeen g x h)
  · obtain ⟨_, _, hcr, hgvL, _⟩ := c.lend_facts hl
    have hgv : ds.env gv = .own g := by
      cases h : ds.env gv <;> simp [ownedRoot, h] at hg
      subst hg; rfl
    rcases c.hI.Lval gv hgvL with h1 | ⟨t, h1, h2⟩
    · rw [h1] at hgv; cases hgv
    · rw [hgv] at h1; cases h1
      have := c.hx.keep g g h2 (by rw [hcr]; simp)
      rw [this]; intro h'; cases h'

theorem lentCov' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ g x, ds'.lent g x → (∃ l, ds'.heap g = .live l) →
      ∃ v ∈ (instNext cc σ i).L, ∃ t, ds'.env v = .own t ∧ ds'.heap g = .live t ∧
        Root.val v ∈ Rget (instNext cc σ i) v ∧
        ∃ ρ ∈ Rget (instNext cc σ i) v, ρ.isFwd = false ∧ rootLive (instNext cc σ i) ρ = true ∧
          Covers cc args h0 ds' ρ x := by
  intro g x hl hgl'
  obtain ⟨l', hgl'⟩ := hgl'
  rw [c.hlent] at hl
  rcases hl with hold | ⟨gv, a0, hlg, ha0, hgo, hcells⟩
  · -- a cell lent by an earlier instruction
    obtain ⟨l, hgl⟩ := c.live_back (c.hI.lentSeen g x hold) hgl'
    obtain ⟨v, hvL, tv, hvt, hgv, hmark, ρ, hρ, hfwd, hlive, hcov⟩ := c.hI.lentCov g x hold ⟨l, hgl⟩
    have hltv : l = tv := by rw [hgl] at hgv; exact Cell.live.inj hgv
    subst hltv
    by_cases hvo : v ∈ cc.ownConsumed i
    · -- the group is consumed: that is its join, which returns nothing, so it is gone
      exfalso
      have hgj := List.all_eq_true.1 c.hok.gj v hvo
      have hmk : (Rget σ v).contains (.val v) = true := List.contains_iff_mem.2 hmark
      simp only [hmk, Bool.not_true, Bool.false_or, Bool.and_eq_true, beq_iff_eq] at hgj
      have hrnone : r = none := c.hr.rnone (fun d hd hown => by
        have := hgj.2
        simp [CCtx.sd, hd] at this
        simp [CCtx.st] at hown
        rw [this] at hown; cases hown)
      have hcons : l ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hvL hvt).2 hvo
      rcases c.hx.gone g l hgl hcons with hdead | ⟨r', hr', _⟩
      · rw [hgl'] at hdead; cases hdead
      · rw [hrnone] at hr'; cases hr'
    · -- the holder survives
      have hvd : ∀ d, i.dst = some d → v ≠ d := fun d hd => L_ne_dst c.hI c.hok c.hcls hvL hd
      have hvL' : v ∈ (instNext cc σ i).L := (instNext_L c.hp v).2 (Or.inl ⟨hvL, hvo⟩)
      refine ⟨v, hvL', l, by rw [c.env_L hvL]; exact hvt, c.keep_L hvL hvo hvt hgv, ?_, ?_⟩
      · have := Rget_next_keep (cc := cc) (σ := σ) (i := i) c.hp hvd _ hmark
        rwa [nextRoot_val_self hvo] at this
      · refine ⟨nextRoot cc i ρ, Rget_next_keep c.hp hvd ρ hρ, ?_, ?_⟩
        · rw [nextRoot_isFwd]; exact hfwd
        · exact c.root_next hvL hvo hρ hfwd hlive hcov
  · -- the lend this instruction performs
    obtain ⟨hcl, hoc, hcr, hgvL, ⟨d, hd, hds⟩, a, hreads, hne⟩ := c.lend_facts hlg
    have ha0a : a = a0 := by rw [hreads] at ha0; simpa using ha0
    subst ha0a
    have hgv : ds.env gv = .own g := by
      cases h : ds.env gv <;> simp [ownedRoot, h] at hgo
      subst hgo; rfl
    have hgl0 : ds.heap g = .live g := by
      rcases c.hI.Lval gv hgvL with h1 | ⟨t, h1, h2⟩
      · rw [h1] at hgv; cases hgv
      · rw [hgv] at h1; cases h1; exact h2
    have hgvd : gv ≠ d := L_ne_dst c.hI c.hok c.hcls hgvL hd
    have hgvo : gv ∉ cc.ownConsumed i := by rw [hoc]; simp
    have hgvL' : gv ∈ (instNext cc σ i).L := (instNext_L c.hp gv).2 (Or.inl ⟨hgvL, hgvo⟩)
    obtain ⟨hmark, hroots⟩ := Rget_next_lend c.hp hd hds hlg hcl hoc hgvd
    refine ⟨gv, hgvL', g, by rw [c.env_L hgvL]; exact hgv, c.keep_L hgvL hgvo hgv hgl0, hmark, ?_⟩
    -- the roots of the lender cover the lent cell
    have hlr : lentRoots cc σ i = rootsOf cc σ a := by simp [lentRoots, hlg, hreads]
    have haR : a ∈ i.reads := by simp [hreads]
    have hnoc : ∀ m, m ∈ σ.L → m ∈ (instNext cc σ i).L := fun m hm =>
      (instNext_L c.hp m).2 (Or.inl ⟨hm, by rw [hoc]; simp⟩)
    have hmono : ∀ ρ, rootLive σ ρ = true → rootLive (instNext cc σ i) ρ = true := by
      intro ρ h
      cases ρ with
      | caller j => rfl
      | val n => exact (rootLive_val _ n).2 (hnoc n ((rootLive_val σ n).1 h))
      | slot n k => exact (rootLive_slot _ n k).2 (hnoc n ((rootLive_slot σ n k).1 h))
      | fwd n => exact (rootLive_fwd _ n).2 (hnoc n ((rootLive_fwd σ n).1 h))
    cases hst : cc.st a with
    | scalar => rw [c.hI.imm a (by simp [hst])] at hcells; simp [Val.cells] at hcells
    | immortal => rw [c.hI.imm a (by simp [hst])] at hcells; simp [Val.cells] at hcells
    | emptied => rw [c.hI.imm a (by simp [hst])] at hcells; simp [Val.cells] at hcells
    | stack => rcases c.hI.stk a hst with h | h <;> rw [h] at hcells <;> simp [Val.cells] at hcells
    | none =>
      have hu := c.hok.r3 a haR (by simp [hst])
      simp [usable, hst] at hu
    | owned =>
      have haL : a ∈ σ.L := usable_owning (by simp [hst, St.owning]) (c.hok.r3 a haR (by simp [hst]))
      rcases c.hI.Lval a haL with h1 | ⟨ta, h1, _⟩
      · rw [h1] at hcells; simp [Val.cells] at hcells
      · rw [h1] at hcells
        simp only [Val.cells] at hcells
        have hrt : rootsOf cc σ a = [.val a] := by simp [rootsOf, hst]
        have hao : a ∉ cc.ownConsumed i := by rw [hoc]; simp
        refine ⟨.val a, hroots _ (by rw [hlr, hrt]; simp), rfl, (rootLive_val _ a).2 (hnoc a haL), ?_⟩
        exact ⟨ta, by rw [c.env_L haL]; exact h1, c.keep_L haL hao h1 hcells⟩
    | borrowed =>
      obtain ⟨hD, hrl⟩ := usable_borrowed hst (c.hok.r4 a haR hst)
      rcases c.hI.Dval a hD with h' | ⟨fp, hfp⟩
      · rw [h'] at hcells; simp [Val.cells] at hcells
      · rw [hfp] at hcells
        obtain ⟨y, hy, l0, hyl, hxl⟩ := hcells
        obtain ⟨ρ0, hρ0, hf0, hcov0⟩ := c.hI.Dcov a hD (fun ρ hρ => Or.inr (hrl ρ hρ)) fp hfp y hy
        have hmem : ρ0 ∈ Rget (instNext cc σ i) gv :=
          hroots ρ0 (by rw [hlr]; simp [rootsOf, hst, hρ0])
        have hlv := hmono ρ0 (hrl ρ0 hρ0)
        refine ⟨ρ0, hmem, hf0, hlv, ?_⟩
        cases ρ0 with
        | fwd m => simp [Root.isFwd] at hf0
        | caller j =>
          obtain ⟨hj, hc⟩ := hcov0
          exact ⟨hj, callerCell_share c.hs c.hI hj hc hyl hxl⟩
        | val m =>
          obtain ⟨tm, hm1, hm2⟩ := hcov0
          have hlt : l0 = tm := by have := hyl.symm.trans hm2; simpa using this
          rw [hlt] at hxl
          exact c.transport hlv (c.live_ne_dst (hrl _ hρ0)) ⟨tm, hm1, hxl⟩
        | slot m k =>
          obtain ⟨tm, hm1, hm2⟩ := hcov0
          have hlt : l0 = tm := by have := hyl.symm.trans hm2; simpa using this
          rw [hlt] at hxl
          exact c.transport hlv (c.live_ne_dst (hrl _ hρ0)) ⟨tm, hm1, hxl⟩

/-- A lend consumes nothing. -/
theorem lent_none_of_oc (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId}
    (hv : v ∈ cc.ownConsumed i) : i.lent = none := by
  cases hl : i.lent with
  | none => rfl
  | some gv =>
    have := (c.lend_facts hl).2.1
    rw [this] at hv; cases hv

/-- A lend lists no parents. -/
theorem lent_none_of_pd (c : IC cc args h0 pend0 σ ds ds' i r) {n : ValId}
    (hn : Root.val n ∈ cc.pd i) : i.lent = none := by
  cases hl : i.lent with
  | none => rfl
  | some gv =>
    have hpd : cc.pd i = [] := (lend_shape c.hok.lend hl).2.2.2.1
    rw [hpd] at hn; cases hn

theorem heldSeen' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ g x, ds'.held g x → ds'.heap g ≠ .unused := by
  intro g x h
  rw [c.hheld] at h
  rcases h with ⟨h, _⟩ | ⟨d, t, hd, hs, hrt, hg, n, hn, hx⟩
  · exact c.not_unused (c.hI.heldSeen g x h)
  · subst hg
    rw [(c.hx.root _ hrt).1]; intro h'; cases h'

theorem heldCov' (c : IC cc args h0 pend0 σ ds ds' i r) :
    ∀ g x, ds'.held g x → (∃ l, ds'.heap g = .live l) →
      ∃ v ∈ (instNext cc σ i).L, ∃ t, ds'.env v = .own t ∧ ds'.heap g = .live t ∧
        (ds'.heap x = .live t ∨
          ∃ ρ ∈ Rget (instNext cc σ i) v, ρ.isFwd = false ∧
            rootLive (instNext cc σ i) ρ = true ∧ Covers cc args h0 ds' ρ x) := by
  intro g x hh hgl'
  obtain ⟨l', hgl'⟩ := hgl'
  rw [c.hheld] at hh
  rcases hh with ⟨hold, hnf⟩ | ⟨d, t, hd, hds, hrt, hgt, n, hn, hx⟩
  · -- a loan held by an earlier instruction
    obtain ⟨l, hgl⟩ := c.live_back (c.hI.heldSeen g x hold) hgl'
    obtain ⟨v, hvL, tv, hvt, hgv, hcv⟩ := c.hI.heldCov g x hold ⟨l, hgl⟩
    have hltv : l = tv := by rw [hgl] at hgv; exact Cell.live.inj hgv
    subst hltv
    by_cases hvo : v ∈ cc.ownConsumed i
    · -- the holder is consumed
      have hcons : l ∈ consumedRoots ds i := (consumed_iff c.hI c.hok hvL hvt).2 hvo
      by_cases hC : i.cls = .construct
      · by_cases hown : ∃ d, i.dst = some d ∧ cc.st d = .owned
        · obtain ⟨d, hd, hds⟩ := hown
          obtain ⟨r', hr', hxg⟩ := c.hret hC ⟨d, hd, hds⟩ g l hgl hcons
          obtain ⟨d', hd'', _, he⟩ := c.rsome hr'
          have : d' = d := Option.some.inj (hd''.symm.trans hd)
          subst this
          have hl0 : i.lent = none := c.lent_none_of_oc hvo
          refine ⟨d', (instNext_L c.hp d').2 (Or.inr ⟨d', hd, by simp [hds, St.owning], rfl⟩), r', he,
            hxg, ?_⟩
          rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
          · left
            obtain ⟨r'', hr'', hxr⟩ := c.hret hC ⟨d', hd, hds⟩ x l hsame hcons
            rw [hr'] at hr''
            have := Option.some.inj hr''
            rw [← this] at hxr
            exact hxr
          · have hin : ρ ∈ loansOf cc σ i := by
              unfold loansOf
              refine mem_normRoots.2 (List.mem_append.2 (Or.inr ?_))
              have hCb : (!i.dropsLoans) = true := by simp [Inst.dropsLoans, hC]
              simp only [hCb, ↓reduceIte]
              exact List.mem_flatMap.2 ⟨v, hvo, hρ⟩
            rcases c.root_new hd hds hl0 hin hfwd hlive (fun _ _ _ => hC) hcov with
              ⟨r'', he', hxr⟩ | ⟨ρ', hρ', hf', hl', hc'⟩
            · left
              rw [he] at he'
              have := Own.Val.own.inj he'
              rw [← this] at hxr
              exact hxr
            · exact Or.inr ⟨ρ', hρ', hf', hl', hc'⟩
        · -- a constructor with no owned result destroys what it consumes
          exfalso
          have hrn : r = none := c.hr.rnone (fun d hd hdo => hown ⟨d, hd, hdo⟩)
          rcases c.hx.gone g l hgl hcons with hdead | ⟨r', hr', _⟩
          · rw [hgl'] at hdead; cases hdead
          · rw [hrn] at hr'; cases hr'
      · by_cases hcar : carries cc i = true
        · -- an owned result carries the holder's loans on
          have hsd : cc.sd i = .owned ∧ i.dropsLoans = false := by
            simpa [carries] using hcar
          obtain ⟨d, hd, hds⟩ : ∃ d, i.dst = some d ∧ cc.st d = .owned := by
            cases hd : i.dst with
            | none => simp [CCtx.sd, hd] at hsd
            | some d => exact ⟨d, rfl, by simpa [CCtx.sd, hd, CCtx.st] using hsd.1⟩
          rcases c.hx.gone g l hgl hcons with hdead | ⟨r', hr', hxg⟩
          · rw [hgl'] at hdead; cases hdead
          · obtain ⟨d', hd'', _, he⟩ := c.rsome hr'
            have hdd : d' = d := Option.some.inj (hd''.symm.trans hd)
            subst hdd
            have hl0 : i.lent = none := c.lent_none_of_oc hvo
            refine ⟨d', (instNext_L c.hp d').2 (Or.inr ⟨d', hd, by simp [hds, St.owning], rfl⟩), r',
              he, hxg, ?_⟩
            rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
            · exfalso
              exact hnf (Or.inr ⟨hC, l, hcons, hgl, hsame⟩)
            · have hin : ρ ∈ loansOf cc σ i := by
                unfold loansOf
                refine mem_normRoots.2 (List.mem_append.2 (Or.inr ?_))
                have hnt : (!i.dropsLoans) = true := by simp [hsd.2]
                simp only [hnt, ↓reduceIte]
                exact List.mem_flatMap.2 ⟨v, hvo, hρ⟩
              have hends : ρ.endsAt (dyingOwners cc i) (takenSlot cc i) = false := by
                rcases c.hok.loans v hvL with h | h
                · rw [hcar] at h; cases h.2
                · exact h ρ hρ
              have hdisj : ∀ m ∈ cc.ownConsumed i, ρ.ownedBy m = true → i.cls = .construct := by
                intro m hm hown
                exfalso
                have hdy : dyingOwners cc i = cc.ownConsumed i := by
                  unfold dyingOwners
                  have : (i.cls == .construct && cc.sd i == .owned) = false := by
                    simp [hC]
                  simp [this]
                rw [hdy] at hends
                rw [endsAt_of_owned _ hm hown] at hends
                cases hends
              rcases c.root_new hd hds hl0 hin hfwd hlive hdisj hcov with
                ⟨r'', he', hxr⟩ | ⟨ρ', hρ', hf', hl', hc'⟩
              · left
                rw [he] at he'
                have := Own.Val.own.inj he'
                rw [← this] at hxr
                exact hxr
              · exact Or.inr ⟨ρ', hρ', hf', hl', hc'⟩
        · -- the loans end with the holder
          exfalso
          by_cases htake : i.dropsLoans = true
          · exact hnf (Or.inl ⟨htake, l, hcons, hgl⟩)
          · have hnown : ∀ d, i.dst = some d → cc.st d ≠ .owned := by
              intro d hd hdo
              apply hcar
              have hdo' : cc.c.state d = .owned := hdo
              simp [carries, CCtx.sd, hd, hdo', htake]
            have hrn : r = none := c.hr.rnone hnown
            rcases c.hx.gone g l hgl hcons with hdead | ⟨r', hr', _⟩
            · rw [hgl'] at hdead; cases hdead
            · rw [hrn] at hr'; cases hr'
    · -- the holder survives
      have hvd : ∀ d, i.dst = some d → v ≠ d := fun d hd => L_ne_dst c.hI c.hok c.hcls hvL hd
      have hvL' : v ∈ (instNext cc σ i).L := (instNext_L c.hp v).2 (Or.inl ⟨hvL, hvo⟩)
      refine ⟨v, hvL', l, by rw [c.env_L hvL]; exact hvt, c.keep_L hvL hvo hvt hgv, ?_⟩
      rcases hcv with hsame | ⟨ρ, hρ, hfwd, hlive, hcov⟩
      · exact Or.inl (c.keep_L hvL hvo hvt hsame)
      · right
        refine ⟨nextRoot cc i ρ, Rget_next_keep c.hp hvd ρ hρ, ?_,
          c.root_next hvL hvo hρ hfwd hlive hcov⟩
        rw [nextRoot_isFwd]; exact hfwd
  · -- a loan the result of this instruction holds on the values it lists
    subst hgt
    replace hds : cc.st d = .owned := hds
    have hnpd : Root.val n ∈ cc.pd i := by simpa [CCtx.pd, hd] using hn
    have hl0 : i.lent = none := c.lent_none_of_pd hnpd
    obtain ⟨dd, hdd, _, he0⟩ := c.rsome hrt
    have hdd' : dd = d := Option.some.inj (hdd.symm.trans hd)
    have he : ds'.env d = .own g := hdd' ▸ he0
    have hnR : n ∈ i.reads := parent_read c.hok hd hds (by simpa [CCtx.pd, hd] using hnpd)
    refine ⟨d, (instNext_L c.hp d).2 (Or.inr ⟨d, hd, by simp [hds, St.owning], rfl⟩), g, he,
      (c.hx.root g hrt).1, ?_⟩
    have hhit : ∀ ρ : Root, ρ ∈ rootsOf cc σ n → ρ ∈ loansOf cc σ i := by
      intro ρ hρ
      unfold loansOf
      refine mem_normRoots.2 (List.mem_append.2 (Or.inl ?_))
      unfold parentRoots
      refine mem_normRoots.2 (List.mem_flatMap.2 ⟨.val n, hnpd, ?_⟩)
      simpa using hρ
    have finish : ∀ ρ ∈ rootsOf cc σ n, ρ.isFwd = false → rootLive σ ρ = true →
        Covers cc args h0 ds ρ x →
        (ds'.heap x = .live g ∨
          ∃ ρ' ∈ Rget (instNext cc σ i) d, ρ'.isFwd = false ∧
            rootLive (instNext cc σ i) ρ' = true ∧ Covers cc args h0 ds' ρ' x) := by
      intro ρ hρ hfwd hlive hcov
      have hdisj : ∀ m ∈ cc.ownConsumed i, ρ.ownedBy m = true → i.cls = .construct := by
        intro m hm hown
        have hmR : m ∉ i.reads := c.hok.j6b m hm
        have hnm : n ≠ m := fun h => hmR (h ▸ hnR)
        rcases c.hok.j6c m hm n (List.mem_append_left _ hnR) hnm with h | h
        · rw [h ρ hρ] at hown; cases hown
        · unfold loanOfOwnedConstruct at h
          simp only [Bool.and_eq_true, beq_iff_eq] at h
          exact h.1
      rcases c.root_new hd hds hl0 (hhit ρ hρ) hfwd hlive hdisj hcov with
        ⟨r'', he', hxr⟩ | ⟨ρ', h1, h2, h3, h4⟩
      · left
        rw [he] at he'
        have := Val.own.inj he'
        rw [← this] at hxr
        exact hxr
      · exact Or.inr ⟨ρ', h1, h2, h3, h4⟩
    cases hst : cc.st n with
    | scalar => rw [c.hI.imm n (by simp [hst])] at hx; simp [Val.cells] at hx
    | immortal => rw [c.hI.imm n (by simp [hst])] at hx; simp [Val.cells] at hx
    | emptied => rw [c.hI.imm n (by simp [hst])] at hx; simp [Val.cells] at hx
    | stack => rcases c.hI.stk n hst with h | h <;> rw [h] at hx <;> simp [Val.cells] at hx
    | none =>
      have hu := c.hok.r3 n hnR (by simp [hst])
      simp [usable, hst] at hu
    | owned =>
      have hnL : n ∈ σ.L := usable_owning (by simp [hst, St.owning]) (c.hok.r3 n hnR (by simp [hst]))
      rcases c.hI.Lval n hnL with h1 | ⟨tn, h1, _⟩
      · rw [h1] at hx; simp [Val.cells] at hx
      · rw [h1] at hx
        simp only [Val.cells] at hx
        have hrt' : rootsOf cc σ n = [.val n] := by simp [rootsOf, hst]
        exact finish (.val n) (by rw [hrt']; simp) rfl ((rootLive_val σ n).2 hnL) ⟨tn, h1, hx⟩
    | borrowed =>
      obtain ⟨hD, hrl⟩ := usable_borrowed hst (c.hok.r4 n hnR hst)
      rcases c.hI.Dval n hD with h' | ⟨fp, hfp⟩
      · rw [h'] at hx; simp [Val.cells] at hx
      · rw [hfp] at hx
        obtain ⟨y, hy, l0, hyl, hxl⟩ := hx
        obtain ⟨ρ0, hρ0, hf0, hcov0⟩ := c.hI.Dcov n hD (fun ρ hρ => Or.inr (hrl ρ hρ)) fp hfp y hy
        have hρr : ρ0 ∈ rootsOf cc σ n := by simp [rootsOf, hst, hρ0]
        have hcovx : Covers cc args h0 ds ρ0 x := by
          cases ρ0 with
          | fwd m => simp [Root.isFwd] at hf0
          | caller j =>
            obtain ⟨hj, hc⟩ := hcov0
            exact ⟨hj, callerCell_share c.hs c.hI hj hc hyl hxl⟩
          | val m =>
            obtain ⟨tm, hm1, hm2⟩ := hcov0
            have hlt : l0 = tm := by have := hyl.symm.trans hm2; simpa using this
            rw [hlt] at hxl
            exact ⟨tm, hm1, hxl⟩
          | slot m k =>
            obtain ⟨tm, hm1, hm2⟩ := hcov0
            have hlt : l0 = tm := by have := hyl.symm.trans hm2; simpa using this
            rw [hlt] at hxl
            exact ⟨tm, hm1, hxl⟩
        exact finish ρ0 hρr hf0 (hrl ρ0 hρ0) hcovx

end IC


/-- **A checked instruction preserves the invariant.** -/
theorem inst_inv {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    {σ : AbsState} {ds ds' : DState} {i : Inst} {r : Option Addr}
    (c : IC cc args h0 pend0 σ ds ds' i r) : Inv cc args h0 (instNext cc σ i) ds' :=
  { imm := c.imm', stk := c.stk', nostk := c.nostk', Lown := c.Lown', Lbd := c.Lbd', Lval := c.Lval', Linj := c.Linj',
    Dst := c.Dst', Dbd := c.Dbd', Dval := c.Dval', Dcov := c.Dcov', Pin := c.Pin',
    Gin := c.Gin', Pout := c.Pout', Fin := c.Fin', frame := c.frame', dead := c.dead',
    unused := c.unused', acct := c.acct', abLive := c.abLive', Ldisj := c.Ldisj', abFree := c.abFree',
    Lfree := c.Lfree', lentSeen := c.lentSeen',
    lentCov := c.lentCov', heldSeen := c.heldSeen', heldCov := c.heldCov' }

/-- The instruction step, from the semantics: `Effect` gives the hypotheses of `IC`. -/
theorem inst_step {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    {σ : AbsState} {ds ds' : DState} {i : Inst}
    (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i)
    (hmem : i ∈ cc.f.allInsts) (hE : Effect (Ctx.entering cc.f cc.c args) ds i ds') :
    Inv cc args h0 (instNext cc σ i) ds' := by
  rcases hE with ⟨hcls, rfl⟩ | ⟨hcls, r, hx, hret, hres, hp, hf, hlt, hhd, hab⟩
  · rw [instNext_param hcls]; exact hI
  · have hp' : (i.cls == .parameter) = false := by simp [hcls]
    refine inst_inv ⟨hs, hI, hok, hmem, hp', hx, ?_, resIf_of_resultOk hres, hp, hf, hlt, hhd, hab⟩
    intro hc ⟨d, hd, hdo⟩
    exact hret hc (by simp only [Inst.res, entering_cert, hd]; exact hdo)

end Own
