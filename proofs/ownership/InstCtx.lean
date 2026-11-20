import InstGuards

/-!
# The hypotheses of one instruction step

`IC` collects what the proof of one instruction step has: the static facts, the invariant, the
passed check, the semantic effect (`Xform` on the heap, the result interface, the pending-take
and decided-test updates).  The lemmas here are the ones every field of the invariant uses.
-/

namespace Own

theorem owning_iff {s : St} : s.owning = true ↔ s = .owned := by
  cases s <;> simp [St.owning]

/-- The hypotheses of one instruction step. -/
structure IC (cc : CCtx) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (σ : AbsState) (ds ds' : DState) (i : Inst) (r : Option Addr) : Prop where
  hs : Static cc args h0 pend0
  hI : Inv cc args h0 σ ds
  hok : InstOk cc σ i
  hmem : i ∈ cc.f.allInsts
  hp : (i.cls == .parameter) = false
  hx : Xform ds.heap ds'.heap (consumedRoots ds i) r
  hret : i.cls = .construct → (∃ d, i.dst = some d ∧ cc.st d = .owned) →
    Retains ds.heap ds'.heap (consumedRoots ds i) r
  hr : ResIf cc (Ctx.entering cc.f cc.c args) ds ds' i r
  hpend : ds'.pend = pendAfter (Ctx.entering cc.f cc.c args) ds i r
  hfacts : ds'.facts = clearFacts ds.facts i.dst.toList
  hlent : ds'.lent = lentAfter ds i
  hheld : ds'.held = heldAfter (Ctx.entering cc.f cc.c args) ds i r
  habn : ds'.abandoned = ds.abandoned

namespace IC

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {ds ds' : DState} {i : Inst} {r : Option Addr}

theorem hcls (c : IC cc args h0 pend0 σ ds ds' i r) : i.cls ≠ .parameter := by
  intro h; have := c.hp; simp [h] at this

/-- A value of `L` is not the value the instruction defines. -/
theorem env_L (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId} (hv : v ∈ σ.L) :
    ds'.env v = ds.env v :=
  c.hr.ne v (fun _ hd => L_ne_dst c.hI c.hok c.hcls hv hd)

/-- The tree of a surviving value is not consumed. -/
theorem not_consumed (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId} (hv : v ∈ σ.L)
    (hvo : v ∉ cc.ownConsumed i) {t : Addr} (ht : ds.env v = .own t) :
    t ∉ consumedRoots ds i := fun h => hvo ((consumed_iff c.hI c.hok hv ht).1 h)

/-- The tree of a surviving value is unchanged. -/
theorem keep_L (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId} (hv : v ∈ σ.L)
    (hvo : v ∉ cc.ownConsumed i) {t : Addr} (ht : ds.env v = .own t) {x : Addr}
    (hx : ds.heap x = .live t) : ds'.heap x = .live t :=
  c.hx.keep x t hx (c.not_consumed hv hvo ht)

/-- A result root names an owning value defined by the instruction. -/
theorem rsome (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} (h : r = some t) :
    ∃ d, i.dst = some d ∧ (cc.st d).owning = true ∧ ds'.env d = .own t := by
  refine Classical.byContradiction fun hno => ?_
  have hall : ∀ d, i.dst = some d → cc.st d ≠ .owned := by
    intro d hd hown
    apply hno
    rcases (c.hr.own d hd hown).1 with ⟨_, hrn⟩ | ⟨t', he, hrt⟩
    · rw [h] at hrn; cases hrn
    · rw [h] at hrt
      cases hrt
      exact ⟨d, hd, owning_iff.2 hown, he⟩
  have := c.hr.rnone hall
  rw [h] at this; cases this

/-- The root of a result tree is not a surviving value's root. -/
theorem root_fresh (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} (h : r = some t)
    {v : ValId} (hv : v ∈ σ.L) (hvo : v ∉ cc.ownConsumed i) {t' : Addr}
    (ht : ds.env v = .own t') : t' ≠ t := by
  intro heq
  subst heq
  obtain ⟨_, hroot⟩ := c.hx.root _ h
  rcases c.hI.Lval v hv with h1 | ⟨t2, h2, h3⟩
  · rw [h1] at ht; cases ht
  · rw [ht] at h2; cases h2
    rcases hroot with h4 | ⟨t3, h4, h5⟩
    · rw [h3] at h4; cases h4
    · rw [h3] at h4; cases h4
      exact c.not_consumed hv hvo ht h5

/-- A value that is not the definition of the instruction keeps its value. -/
theorem env_other (c : IC cc args h0 pend0 σ ds ds' i r) {v : ValId}
    (hv : ¬ ∃ d, i.dst = some d ∧ v = d) : ds'.env v = ds.env v :=
  c.hr.ne v (fun d hd hvd => hv ⟨d, hd, hvd⟩)

/-! ### The pending flags after the instruction -/

/-- A pending flag that nothing touches stays set. -/
theorem pend_keep (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} {k : String}
    (hnc : t ∉ consumedRoots ds i) (hr : r ≠ some t) (h : ds.pend t k = true) :
    ds'.pend t k = true := by
  rw [c.hpend]
  unfold pendAfter
  have h1 : (r == some t) = false := by simpa using hr
  simp [h1, hnc, h]

/-- A take opens its slot. -/
theorem pend_open (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} {k : String}
    (hnc : t ∉ consumedRoots ds i) (hr : r ≠ some t)
    (htr : isTransfer (Ctx.entering cc.f cc.c args) i = true) (htt : transferTarget ds i = some t)
    (hsl : i.slot = some k) : ds'.pend t k = true := by
  rw [c.hpend]
  unfold pendAfter
  have h1 : (r == some t) = false := by simpa using hr
  simp [h1, hnc, htr, htt, hsl]

/-- The closing update passes an open slot on to its result. -/
theorem pend_pass (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} {k : String} {ct : Addr}
    (hcl : i.isClosing = true) (hr : r = some t) (hct : closeTarget ds i = some ct)
    (hp : ds.pend ct k = true) (hk : k ∉ closedKeys i) : ds'.pend t k = true := by
  rw [c.hpend]
  unfold pendAfter closePend
  simp [hcl, hr, hct, hp, hk]

/-- Where a pending flag comes from. -/
theorem pend_cases (c : IC cc args h0 pend0 σ ds ds' i r) {t : Addr} {k : String}
    (h : ds'.pend t k = true) :
    (i.isClosing = true ∧ r = some t ∧ ∃ ct, closeTarget ds i = some ct ∧ ds.pend ct k = true ∧
      k ∉ closedKeys i) ∨
    (t ∉ consumedRoots ds i ∧ r ≠ some t ∧
      isTransfer (Ctx.entering cc.f cc.c args) i = true ∧ transferTarget ds i = some t ∧
      i.slot = some k) ∨
    (t ∉ consumedRoots ds i ∧ r ≠ some t ∧ ds.pend t k = true) := by
  rw [c.hpend] at h
  unfold pendAfter at h
  by_cases hA : (i.isClosing && r == some t && closePend ds i k) = true
  · simp only [hA, ↓reduceIte] at h
    left
    simp only [Bool.and_eq_true, beq_iff_eq] at hA
    obtain ⟨⟨hcl, hr⟩, hm⟩ := hA
    refine ⟨hcl, hr, ?_⟩
    unfold closePend at hm
    cases hct : closeTarget ds i with
    | none => rw [hct] at hm; simp at hm
    | some ct =>
      rw [hct] at hm
      simp only [Bool.and_eq_true, Bool.not_eq_true'] at hm
      exact ⟨ct, rfl, hm.1, by simpa using hm.2⟩
  · simp only [hA, Bool.false_eq_true, ↓reduceIte] at h
    by_cases hB : ((consumedRoots ds i).contains t || r == some t) = true
    · simp only [hB, ↓reduceIte] at h; cases h
    · simp only [hB, Bool.false_eq_true, ↓reduceIte] at h
      simp only [Bool.or_eq_true, not_or, beq_iff_eq] at hB
      by_cases hC : (isTransfer (Ctx.entering cc.f cc.c args) i && transferTarget ds i == some t &&
          i.slot == some k) = true
      · right; left
        simp only [Bool.and_eq_true, beq_iff_eq] at hC
        refine ⟨?_, ?_, hC.1.1, ?_, hC.2⟩
        · intro hm; apply hB.1; simpa using hm
        · intro hr; apply hB.2; exact hr
        · simpa using hC.1.2
      · simp only [hC, Bool.false_eq_true, ↓reduceIte] at h
        right; right
        refine ⟨?_, ?_, h⟩
        · intro hm; apply hB.1; simpa using hm
        · intro hr; apply hB.2; exact hr

end IC

end Own
