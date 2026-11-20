import SoundFacts

/-!
# The after-return condition at a `ret`
-/

namespace Own

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}

theorem entry_heap : (entryDState cc.f args h0 pend0).heap = h0 := rfl

theorem shape_imm (ds0 ds : DState) : ResultShape cc.f args ds0 ds .imm := by
  unfold ResultShape
  split <;> simp

/-- The invariant at a `ret` whose live set holds nothing but the returned value gives
`Post`, provided nothing is abandoned (C9.1: a `ret` is never reached from a trap region). -/
theorem post_core (hs : Static cc args h0 pend0) {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) (hab : ∀ t, ¬ ds.abandoned t) (val : Val)
    (hL : ∀ v ∈ σ.L, val = ds.env v)
    (hown : ∀ r, val = .own r → ∃ v ∈ σ.L, ds.env v = .own r)
    (hshape : ResultShape cc.f args (entryDState cc.f args h0 pend0) ds val) :
    Post cc.f args (entryDState cc.f args h0 pend0) ds val := by
  refine ⟨?_, ?_, ?_, ?_, ?_, hshape⟩
  · intro x t h hn; exact hI.frame x t h hn
  · intro x h; exact hI.dead x h
  · intro x t0 h0x hO
    replace h0x : h0 x = .live t0 := h0x
    cases hcell : ds.heap x with
    | unused =>
      have := hI.unused x hcell
      rw [this] at h0x; cases h0x
    | dead => left; rfl
    | live t =>
      right
      rcases hI.acct x t hcell with ⟨v, hv, hvt⟩ | ⟨hx0, hn⟩ | hab'
      · exact ⟨t, by rw [hL v hv, hvt], rfl⟩
      · rw [h0x] at hx0; cases hx0; exact absurd hO hn
      · exact absurd hab' (hab t)
  · intro x h0x
    replace h0x : h0 x = .unused := h0x
    cases hcell : ds.heap x with
    | unused => left; rfl
    | dead => right; left; rfl
    | live t =>
      right; right
      rcases hI.acct x t hcell with ⟨v, hv, hvt⟩ | ⟨hx0, _⟩ | hab'
      · exact ⟨t, by rw [hL v hv, hvt], rfl⟩
      · rw [h0x] at hx0; cases hx0
      · exact absurd hab' (hab t)
  · intro r x hval hxr
    constructor
    · intro hd
      have := hI.dead x hd
      rw [this] at hxr; cases hxr
    · rintro ⟨t, ht, hn⟩
      have hfr := hI.frame x t ht hn
      rw [hxr] at hfr; cases hfr
      obtain ⟨v, hv, hvt⟩ := hown r hval
      exact hn (hI.Lfree v hv r hvt x ht)

/-- A returned value that is the only member of `L`, with nothing pending, has the owned
shape. -/
theorem shape_owned {σ : AbsState} {ds : DState} (hI : Inv cc args h0 σ ds) {v : ValId}
    (hv : v ∈ σ.L) (hP : σ.P = []) (hG : σ.G = []) (hres : cc.f.result = .owned) :
    ResultShape cc.f args (entryDState cc.f args h0 pend0) ds (ds.env v) := by
  unfold ResultShape
  rw [hres]
  rcases hI.Lval v hv with h | ⟨t, h1, h2⟩
  · left; exact h
  · right
    refine ⟨t, h1, h2, ?_⟩
    intro k
    cases hp : ds.pend t k with
    | false => rfl
    | true =>
      have := hI.Pout v hv t h1 k hp
      unfold AbsState.predicts at this
      rw [hP, hG] at this
      simp at this

theorem ret_none_facts (hs : Static cc args h0 pend0) {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) (hab : ∀ t, ¬ ds.abandoned t) (hchk : ∀ p ∈ termChecks cc σ (.ret none), p.2.2 = true) :
    Post cc.f args (entryDState cc.f args h0 pend0) ds .imm := by
  have hL : σ.L = [] := by
    have := hchk (.j2, "ret-live", σ.L.isEmpty) (by simp [termChecks])
    simpa using this
  apply post_core hs hI hab .imm
  · intro v hv; rw [hL] at hv; cases hv
  · intro r h; cases h
  · exact shape_imm _ _

/-- A checked `ret v`: the value can be read, and the after-return condition holds. -/
theorem ret_some_facts (hs : Static cc args h0 pend0) {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) (hab : ∀ t, ¬ ds.abandoned t) {v : ValId}
    (hchk : ∀ p ∈ termChecks cc σ (.ret (some v)), p.2.2 = true) :
    (ds.env v).alive ds.heap ∧
      Post cc.f args (entryDState cc.f args h0 pend0) ds (ds.env v) := by
  unfold termChecks at hchk
  cases hres : cc.f.result with
  | owned =>
    rw [hres] at hchk
    simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq] at hchk
    obtain ⟨h3, _, _, h1, h2⟩ := hchk
    have hP : σ.P = [] := by simp at h3; exact h3.1
    have hG : σ.G = [] := by simp at h3; exact h3.2
    simp only [Bool.or_eq_true, beq_iff_eq] at h1
    rcases h1 with hst | hst
    · -- an owned value: the only one live
      rw [hst] at h2
      simp only [beq_self_eq_true, if_true, beq_iff_eq] at h2
      have hvL : v ∈ σ.L := by rw [h2]; simp
      refine ⟨alive_of_L hI hvL, ?_⟩
      apply post_core hs hI hab _ _ _ (shape_owned hI hvL hP hG hres)
      · intro w hw; rw [h2] at hw; simp at hw; rw [hw]
      · intro r hr; exact ⟨v, hvL, hr⟩
    · -- an immortal: nothing is live
      have hL : σ.L = [] := by
        rw [hst] at h2; simpa using h2
      have himm := hI.imm v (Or.inr (Or.inl hst))
      refine ⟨by rw [himm]; trivial, ?_⟩
      apply post_core hs hI hab _ _ _ (by rw [himm]; exact shape_imm _ _)
      · intro w hw; rw [hL] at hw; cases hw
      · intro r hr; rw [himm] at hr; cases hr
  | borrowed =>
    rw [hres] at hchk
    simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq] at hchk
    obtain ⟨_, _, _, h1, h2, h3, h4⟩ := hchk
    have hL : σ.L = [] := by simpa using h4
    simp only [Bool.or_eq_true, beq_iff_eq] at h1
    rcases h1 with (hst | hst) | hst
    · -- a borrowed value
      have hu : usable cc σ v = true := by simpa [hst] using h2
      obtain ⟨hD, hroots⟩ := usable_borrowed hst hu
      refine ⟨usable_alive hs hI hu, ?_⟩
      have hshape : ResultShape cc.f args (entryDState cc.f args h0 pend0) ds (ds.env v) := by
        unfold ResultShape
        rw [hres]
        rcases hI.Dval v hD with h | ⟨fp, hfp⟩
        · left; exact h
        · right
          refine ⟨fp, hfp, usable_alive hs hI hu, ?_⟩
          intro x hx
          obtain ⟨ρ, hρ, hnf, hcov⟩ := hI.Dcov v hD (fun ρ hρ => Or.inr (hroots ρ hρ)) fp hfp x hx
          have hall := List.all_eq_true.1 (by simpa [hst] using h3) ρ hρ
          cases ρ with
          | val n => simp at hall
          | slot n k => simp at hall
          | fwd n => simp at hall
          | caller i =>
            obtain ⟨_, hc⟩ := hcov
            exact ⟨i, by simpa using hall, hc⟩
      apply post_core hs hI hab _ _ _ hshape
      · intro w hw; rw [hL] at hw; cases hw
      · intro r hr
        rcases hI.Dval v hD with h | ⟨fp, hfp⟩
        · rw [h] at hr; cases hr
        · rw [hfp] at hr; cases hr
    · -- an immortal
      have himm := hI.imm v (Or.inr (Or.inl hst))
      refine ⟨by rw [himm]; trivial, ?_⟩
      apply post_core hs hI hab _ _ _ (by rw [himm]; exact shape_imm _ _)
      · intro w hw; rw [hL] at hw; cases hw
      · intro r hr; rw [himm] at hr; cases hr
    · -- a scalar
      have himm := hI.imm v (Or.inl hst)
      refine ⟨by rw [himm]; trivial, ?_⟩
      apply post_core hs hI hab _ _ _ (by rw [himm]; exact shape_imm _ _)
      · intro w hw; rw [hL] at hw; cases hw
      · intro r hr; rw [himm] at hr; cases hr
  | scalar | immortal | stack | none | emptied =>
    all_goals
      rw [hres] at hchk
      simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq] at hchk
      obtain ⟨_, _, h1, h2⟩ := hchk
      have hL : σ.L = [] := by simpa using h2
      simp only [Bool.or_eq_true, beq_iff_eq] at h1
      have himm := hI.imm v (by rcases h1 with h | h <;> simp [h])
      refine ⟨by rw [himm]; trivial, ?_⟩
      apply post_core hs hI hab _ _ _ (by rw [himm]; unfold ResultShape; rw [hres])
      · intro w hw; rw [hL] at hw; cases hw
      · intro r hr; rw [himm] at hr; cases hr

end Own
