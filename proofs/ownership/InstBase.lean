import Entry

/-!
# Helper lemmas for the instruction step

Caller cells, consumed roots, the membership view of `instNext`, and the interface the
semantics gives for the value an instruction defines.
-/

namespace Own

section Caller

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}

/-- A cell of a borrowed parameter's trees is a frame cell (design `Pre.apart`). -/
theorem callerCell_frame (hs : Static cc args h0 pend0) {i : Nat} {x : Addr}
    (hi : cc.f.params[i]? = some .borrowed) (hc : (args i).cells h0 x) :
    ∃ l, h0 x = .live l ∧ ¬ OwnedArg cc.f args l := by
  rcases (hs.pre.borrowed i hi).1 with h | ⟨fp, h⟩
  · rw [h] at hc; simp [Val.cells] at hc
  · rw [h] at hc
    obtain ⟨y, hy, l, hyl, hxl⟩ := hc
    refine ⟨l, hxl, ?_⟩
    rintro ⟨j, hj, hjt⟩
    have := hs.pre.apart j i l hj hjt hi x (by rw [h]; exact ⟨y, hy, l, hyl, hxl⟩)
    exact this hxl

/-- Caller cells stay live and unchanged. -/
theorem callerCell_live {σ : AbsState} {ds : DState} (hs : Static cc args h0 pend0)
    (hI : Inv cc args h0 σ ds) {i : Nat} {x : Addr}
    (hi : cc.f.params[i]? = some .borrowed) (hc : (args i).cells h0 x) :
    ∃ l, h0 x = .live l ∧ ds.heap x = .live l ∧ ¬ OwnedArg cc.f args l := by
  obtain ⟨l, hl, hn⟩ := callerCell_frame hs hi hc
  exact ⟨l, hl, hI.frame x l hl hn, hn⟩

/-- The cells of a borrowed parameter read in the current heap are those read in the entry
heap. -/
theorem callerCells_iff {σ : AbsState} {ds : DState} (hs : Static cc args h0 pend0)
    (hI : Inv cc args h0 σ ds) {i : Nat} {x : Addr}
    (hi : cc.f.params[i]? = some .borrowed) :
    (args i).cells ds.heap x ↔ (args i).cells h0 x := by
  rcases (hs.pre.borrowed i hi).1 with h | ⟨fp, h⟩
  · rw [h]; simp [Val.cells]
  · rw [h]
    constructor
    · rintro ⟨y, hy, l, hyl, hxl⟩
      have hal := (hs.pre.borrowed i hi).2
      rw [h] at hal
      obtain ⟨l0, hl0⟩ := hal y hy
      have hn : ¬ OwnedArg cc.f args l0 := by
        rintro ⟨j, hj, hjt⟩
        have := hs.pre.apart j i l0 hj hjt hi y (by rw [h]; exact ⟨y, hy, l0, hl0, hl0⟩)
        exact this hl0
      have hyl' := hI.frame y l0 hl0 hn
      rw [hyl'] at hyl
      cases hyl
      rcases hI.acct x l hxl with ⟨v, hv, hvt⟩ | ⟨hx0, _⟩ | hab
      · exact absurd (hI.Lfree v hv l hvt y hl0) hn
      · exact ⟨y, hy, l, hl0, hx0⟩
      · exact absurd (hI.abFree l hab y hl0) hn
    · rintro ⟨y, hy, l, hyl, hxl⟩
      have hn : ¬ OwnedArg cc.f args l := by
        rintro ⟨j, hj, hjt⟩
        have := hs.pre.apart j i l hj hjt hi x (by rw [h]; exact ⟨y, hy, l, hyl, hxl⟩)
        exact this hxl
      exact ⟨y, hy, l, hI.frame y l hyl hn, hI.frame x l hxl hn⟩

/-- An owned value of `L` can be read: it is an immediate or the root of a live tree. -/
theorem alive_of_L {σ : AbsState} {ds : DState} (hI : Inv cc args h0 σ ds) {v : ValId}
    (hv : v ∈ σ.L) : (ds.env v).alive ds.heap := by
  rcases hI.Lval v hv with h | ⟨t, ht, hl⟩
  · rw [h]; trivial
  · rw [ht]; simp [Val.alive, hl]

/-- A value that passed the usability test can be read. -/
theorem usable_alive {σ : AbsState} {ds : DState} (hs : Static cc args h0 pend0)
    (hI : Inv cc args h0 σ ds) {v : ValId} (hu : usable cc σ v = true) :
    (ds.env v).alive ds.heap := by
  cases hst : cc.st v with
  | scalar => rw [hI.imm v (by simp [hst])]; trivial
  | immortal => rw [hI.imm v (by simp [hst])]; trivial
  | none => simp [usable, hst] at hu
  | owned =>
    have hv : v ∈ σ.L := usable_owning (by simp [hst, St.owning]) hu
    rcases hI.Lval v hv with h | ⟨t, ht, hl⟩
    · rw [h]; trivial
    · rw [ht]; simp [Val.alive, hl]
  | stack => rcases hI.stk v hst with h | h <;> rw [h] <;> trivial
  | emptied => rw [hI.imm v (by simp [hst])]; trivial
  | borrowed =>
    obtain ⟨hD, hroots⟩ := usable_borrowed hst hu
    rcases hI.Dval v hD with h | ⟨fp, hfp⟩
    · rw [h]; trivial
    · rw [hfp]
      intro x hx
      obtain ⟨ρ, _, _, hcov⟩ := hI.Dcov v hD (fun ρ hρ => Or.inr (hroots ρ hρ)) fp hfp x hx
      cases ρ with
      | val n => obtain ⟨t, _, hxt⟩ := hcov; exact ⟨t, hxt⟩
      | slot n k => obtain ⟨t, _, hxt⟩ := hcov; exact ⟨t, hxt⟩
      | fwd n => exact hcov.elim
      | caller i =>
        obtain ⟨hi, hc⟩ := hcov
        obtain ⟨l, _, hl, _⟩ := callerCell_live hs hI hi hc
        exact ⟨l, hl⟩

end Caller

section Lend

/-- What `lendOk` says of a lend (design §10.2). -/
theorem lend_shape {cc : CCtx} {i : Inst} (h : lendOk cc i = true) {gv : ValId}
    (hl : i.lent = some gv) :
    i.cls = .construct ∧ i.consumes = [] ∧ cc.sd i = .owned ∧ cc.pd i = [] ∧
      (∃ a, i.reads = [a, gv] ∧ a ≠ gv) ∧ cc.st gv = .owned := by
  unfold lendOk at h
  rw [hl] at h
  simp only [Bool.and_eq_true, beq_iff_eq, List.isEmpty_iff, bne_iff_ne, ne_eq] at h
  obtain ⟨⟨⟨⟨⟨⟨⟨hc, hcons⟩, hsd⟩, hpd⟩, hlen⟩, hr1⟩, hr0⟩, hst⟩ := h
  have hlen' : i.reads.length = 2 := hlen
  match hr : i.reads, hlen' with
  | [x, y], _ =>
    rw [hr] at hr1 hr0
    simp only [List.getElem?_cons_succ, List.getElem?_cons_zero, Option.some.injEq] at hr1 hr0
    subst hr1
    exact ⟨hc, hcons, hsd, hpd, ⟨x, rfl, hr0⟩, hst⟩

end Lend

section Consumed

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {σ : AbsState} {ds : DState} {i : Inst}

/-- The roots an instruction consumes belong to consumed values of `L`. -/
theorem consumedRoots_mem (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) {t : Addr}
    (ht : t ∈ consumedRoots ds i) :
    ∃ k ∈ cc.ownConsumed i, k ∈ σ.L ∧ ds.env k = .own t := by
  unfold consumedRoots at ht
  rw [List.mem_filterMap] at ht
  obtain ⟨k, hk, hkt⟩ := ht
  have hown : ds.env k = .own t := by
    cases h : ds.env k <;> simp [ownedRoot, h] at hkt
    subst hkt; rfl
  rcases hok.c2 k hk with hsc | ⟨hown', hkL⟩
  · rcases hI.noOwn (v := k) (by rcases hsc with h | h | h | h <;> simp [h]) with h | h <;>
      rw [h] at hown <;> cases hown
  · exact ⟨k, mem_ownConsumed.2 ⟨hk, hown'⟩, hkL, hown⟩

/-- A value of `L` is consumed exactly when its root is a consumed root. -/
theorem consumed_iff (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) {k : ValId}
    (hk : k ∈ σ.L) {t : Addr} (hkt : ds.env k = .own t) :
    t ∈ consumedRoots ds i ↔ k ∈ cc.ownConsumed i := by
  constructor
  · intro ht
    obtain ⟨k', hk', hk'L, hk't⟩ := consumedRoots_mem hI hok ht
    have := hI.Linj k' hk'L k hk t hk't hkt
    subst this; exact hk'
  · intro hkc
    obtain ⟨hc, _⟩ := mem_ownConsumed.1 hkc
    unfold consumedRoots
    rw [List.mem_filterMap]
    exact ⟨k, hc, by simp [ownedRoot, hkt]⟩

/-- A value of `L` is never the value an instruction defines. -/
theorem L_ne_dst (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) (hcls : i.cls ≠ .parameter)
    {v : ValId} (hv : v ∈ σ.L) {d : ValId} (hd : i.dst = some d) : v ≠ d := by
  rintro rfl
  have hown := hI.Lown v hv
  exact hok.dstNew v hd hcls hown hv

end Consumed

/-! ## `instNext` as membership -/

section Next

variable {cc : CCtx} {σ : AbsState} {i : Inst}

theorem instNext_param (hp : i.cls = .parameter) : instNext cc σ i = σ := by
  simp [instNext, hp]

theorem instNext_L (hp : (i.cls == .parameter) = false) (v : ValId) :
    v ∈ (instNext cc σ i).L ↔
      (v ∈ σ.L ∧ v ∉ cc.ownConsumed i) ∨
        ∃ d, i.dst = some d ∧ (cc.st d).owning = true ∧ v = d := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte]
  cases hd : i.dst with
  | none => simp [mem_without]
  | some d =>
    cases hs : cc.st d <;> simp [mem_without, hs, St.owning] <;> grind

theorem mem_instD0 (w : ValId) :
    w ∈ instD0 cc σ i ↔
      w ∈ σ.D ∧ ∀ tk, takenSlot cc i = some tk → ∀ r ∈ Rget σ w, r.endsAt [] (some tk) = false := by
  unfold instD0
  cases htk : takenSlot cc i with
  | none => simp
  | some tk => simp [List.mem_filter, List.all_eq_true]

theorem instNext_D (hp : (i.cls == .parameter) = false) (w : ValId) :
    w ∈ (instNext cc σ i).D ↔
      (w ∈ σ.D ∧
        (∀ tk, takenSlot cc i = some tk → ∀ r ∈ Rget σ w, r.endsAt [] (some tk) = false) ∧
        ∀ d, i.dst = some d → cc.st d = .owned → ∀ r ∈ Rget σ w, r.ownedBy d = false) ∨
      ∃ d, i.dst = some d ∧ cc.st d = .borrowed ∧ w = d := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte]
  cases hd : i.dst with
  | none =>
    simp only []
    rw [mem_instD0]
    simp
  | some d =>
    cases hs : cc.st d <;> simp [hs, List.mem_filter, mem_instD0] <;> grind

end Next

/-! ## The value an instruction defines -/

/-- What `ResultOk` says, per defined value. -/
structure ResIf (cc : CCtx) (ctx : Ctx) (ds ds' : DState) (i : Inst) (r : Option Addr) : Prop where
  ne : ∀ v, (∀ d, i.dst = some d → v ≠ d) → ds'.env v = ds.env v
  imm : ∀ d, i.dst = some d →
    (cc.st d = .scalar ∨ cc.st d = .immortal ∨ cc.st d = .emptied ∨
      cc.st d = .none) → ds'.env d = .imm
  stk : ∀ d, i.dst = some d → cc.st d = .stack → ds'.env d = .stk
  own : ∀ d, i.dst = some d → cc.st d = .owned →
    ((ds'.env d = .imm ∧ r = none) ∨ ∃ t, ds'.env d = .own t ∧ r = some t) ∧
    (i.isClosing = true → closeTarget ds i = none → ds'.env d = .imm ∧ r = none)
  bor : ∀ d, i.dst = some d → cc.st d = .borrowed → r = none ∧
    (ds'.env d = .imm ∨ ∃ fp, ds'.env d = .bor fp ∧ ∀ x ∈ fp,
      (∃ p ∈ cc.c.parents d, (∀ n, p = .val n → forwardTakeWith ctx.fn.defOf? ctx.cert i n = false) ∧
        rootCells ctx ds p x) ∧ ∃ l, ds'.heap x = .live l)
  rnone : (∀ d, i.dst = some d → cc.st d ≠ .owned) → r = none

@[simp] theorem entering_cert (f : Function) (c : Certificate) (a : Nat → Val) :
    (Ctx.entering f c a).cert = c := rfl

@[simp] theorem entering_fn (f : Function) (c : Certificate) (a : Nat → Val) :
    (Ctx.entering f c a).fn = f := rfl

@[simp] theorem entering_callerVals (f : Function) (c : Certificate) (a : Nat → Val) :
    (Ctx.entering f c a).callerVals = a := rfl

theorem resIf_of_resultOk {cc : CCtx} {args : Nat → Val} {ds ds' : DState} {i : Inst}
    {r : Option Addr} (h : ResultOk (Ctx.entering cc.f cc.c args) ds i ds' r) :
    ResIf cc (Ctx.entering cc.f cc.c args) ds ds' i r := by
  unfold ResultOk at h
  cases hd : i.dst with
  | none =>
    rw [hd] at h
    obtain ⟨he, hr⟩ := h
    exact ⟨fun v _ => by rw [he], fun d hd' _ => (by rw [hd] at hd'; cases hd'),
      fun d hd' _ => (by rw [hd] at hd'; cases hd'),
      fun d hd' _ => (by rw [hd] at hd'; cases hd'),
      fun d hd' _ => (by rw [hd] at hd'; cases hd'), fun _ => hr⟩
  | some d =>
    rw [hd] at h
    obtain ⟨v, he, hm⟩ := h
    simp only [entering_cert] at hm
    have hdv : ds'.env d = v := by rw [he]; simp [upd]
    have same : ∀ d', i.dst = some d' → d' = d := by
      intro d' hd'; rw [hd] at hd'; exact (Option.some.inj hd').symm
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro w hw
      rw [he]; unfold upd
      have : w ≠ d := hw d (by simp [hd])
      simp [this]
    · intro d' hd' hst'
      have := same d' hd'
      subst this
      rw [hdv]
      have hst'' : cc.c.state d' = .scalar ∨ cc.c.state d' = .immortal ∨
          cc.c.state d' = .emptied ∨ cc.c.state d' = .none := hst'
      rcases hst'' with h' | h' | h' | h' <;> rw [h'] at hm <;> exact hm.1
    · intro d' hd' hst'
      have := same d' hd'
      subst this
      rw [hdv]
      have hs' : cc.c.state d' = .stack := hst'
      rw [hs'] at hm
      exact hm.1
    · intro d' hd' hown
      have := same d' hd'
      subst this
      rw [hdv]
      have hs' : cc.c.state d' = .owned := hown
      rw [hs'] at hm
      obtain ⟨h1, h2⟩ := hm
      refine ⟨?_, fun hc ht => by exact h2 hc ht⟩
      rcases h1 with ⟨h1, h2⟩ | ⟨t, h1, h2⟩
      · left; exact ⟨h1, h2⟩
      · right; exact ⟨t, h2, h1⟩
    · intro d' hd' hbor
      have := same d' hd'
      subst this
      rw [hdv]
      have hs' : cc.c.state d' = .borrowed := hbor
      rw [hs'] at hm
      obtain ⟨hr, hv⟩ := hm
      refine ⟨hr, ?_⟩
      rcases hv with h | ⟨fp, h1, h2⟩
      · left; exact h
      · right; exact ⟨fp, h1, h2⟩
    · intro hall
      have hd' := hall d hd
      have hs' : cc.c.state d = .scalar ∨ cc.c.state d = .immortal ∨ cc.c.state d = .stack ∨
          cc.c.state d = .emptied ∨ cc.c.state d = .none ∨ cc.c.state d = .borrowed := by
        have : cc.c.state d = cc.st d := rfl
        cases h' : cc.st d <;> simp_all
      rcases hs' with h' | h' | h' | h' | h' | h' <;> rw [h'] at hm
      · exact hm.2
      · exact hm.2
      · exact hm.2
      · exact hm.2
      · exact hm.2
      · exact hm.1


/-! ## Roots in the new state -/

section Roots

theorem lookup_filter_ne {β : Type} (l : List (ValId × β)) (d a : ValId) (h : a ≠ d) :
    (l.filter fun p => p.1 != d).lookup a = l.lookup a := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    by_cases hp : p.1 = d
    · have : (p.1 != d) = false := by simp [hp]
      have hne : (a == p.1) = false := by
        have : a ≠ p.1 := by rw [hp]; exact h
        simpa using this
      simp [List.filter_cons, this, List.lookup, hne, ih]
    · have : (p.1 != d) = true := by simpa using hp
      simp [List.filter_cons, this, List.lookup, ih]

theorem lookup_map_roots (f : List Root → List Root) (l : List (ValId × List Root)) (a : ValId) :
    (l.map fun p => (p.1, f p.2)).lookup a = (l.lookup a).map f := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.map_cons, List.lookup]
    by_cases h : a == p.1
    · simp [h]
    · simp [h, ih]

theorem lookup_cons_ne {β : Type} (l : List (ValId × β)) (k a : ValId) (v : β) (h : a ≠ k) :
    ((k, v) :: l).lookup a = l.lookup a := by
  have : (a == k) = false := by simpa using h
  simp [List.lookup, this]

theorem lookup_cons_self {β : Type} (l : List (ValId × β)) (k : ValId) (v : β) :
    ((k, v) :: l).lookup k = some v := by
  simp [List.lookup]

theorem lookup_moves (oc : List ValId) (d n : ValId) :
    (oc.map fun o => (o, d)).lookup n = if oc.contains n then some d else none := by
  induction oc with
  | nil => simp
  | cons o os ih =>
    simp only [List.map_cons, List.lookup]
    by_cases h : n == o
    · have : n = o := by simpa using h
      subst this; simp
    · have hno : n ≠ o := by simpa using h
      simp [h, ih, hno]

/-- How a root of the old state is named in the new one: unchanged, or (a constructor took the
owner) renamed to the aggregate it built. -/
def Rn (cc : CCtx) (i : Inst) (ρ ρ' : Root) : Prop :=
  ρ' = ρ ∨ (i.cls = .construct ∧ ∃ d, i.dst = some d ∧ cc.st d = .owned ∧ ∃ o ∈ cc.ownConsumed i,
    (ρ = .val o ∧ ρ' = .val d) ∨ ∃ k, ρ = .slot o k ∧ ρ' = .slot d "*")

variable {cc : CCtx} {σ : AbsState} {i : Inst}

theorem lookup_map_keep {β : Type} (l : List (ValId × β)) (f : ValId × β → ValId × β) (w : ValId)
    (hk : ∀ p, (f p).1 = p.1) (hid : ∀ p, p.1 = w → f p = p) :
    (l.map f).lookup w = l.lookup w := by
  induction l with
  | nil => rfl
  | cons p ps ih =>
    simp only [List.map_cons, List.lookup, hk]
    by_cases h : w == p.1
    · have hpw : p.1 = w := (by simpa using h : w = p.1).symm
      have := hid p hpw
      simp [h, this]
    · simp [h, ih]

theorem lookup_dropSelf (R : List (ValId × List Root)) (h w : ValId) (hw : w ≠ h) :
    (dropSelf R h).lookup w = R.lookup w := by
  unfold dropSelf
  apply lookup_map_keep
  · intro p; split <;> rfl
  · intro p hp
    have : (p.1 == h) = false := by
      have : p.1 ≠ h := by rw [hp]; exact hw
      simpa using this
    simp [this]

theorem getD_renameAll (R : List (ValId × List Root)) (moves : List (ValId × ValId)) (wild : Bool)
    (w : ValId) :
    ((renameAll R moves wild).lookup w).getD [] =
      normRoots (((R.lookup w).getD []).map (renameRoot1 moves wild)) := by
  unfold renameAll
  rw [lookup_map_roots (fun rs => normRoots (rs.map (renameRoot1 moves wild))) R w]
  cases R.lookup w <;> simp [normRoots]

variable {cc : CCtx} {σ : AbsState} {i : Inst}

theorem Rn_rename (hc : i.cls = .construct) {d : ValId} (hd : i.dst = some d)
    (hs : cc.st d = .owned) (ρ : Root) :
    Rn cc i ρ (renameRoot1 ((cc.ownConsumed i).map (·, d)) true ρ) := by
  cases ρ with
  | val n =>
    simp only [renameRoot1, lookup_moves]
    by_cases hn : (cc.ownConsumed i).contains n = true
    · simp only [hn, ↓reduceIte]
      exact Or.inr ⟨hc, d, hd, hs, n, List.mem_of_elem_eq_true hn, Or.inl ⟨rfl, rfl⟩⟩
    · have : (cc.ownConsumed i).contains n = false := by simpa using hn
      simp only [this]
      exact Or.inl (by simp)
  | slot n k =>
    simp only [renameRoot1, lookup_moves]
    by_cases hn : (cc.ownConsumed i).contains n = true
    · simp only [hn, ↓reduceIte]
      exact Or.inr ⟨hc, d, hd, hs, n, List.mem_of_elem_eq_true hn, Or.inr ⟨k, rfl, by simp⟩⟩
    · have : (cc.ownConsumed i).contains n = false := by simpa using hn
      simp only [this]
      exact Or.inl (by simp)
  | caller j => exact Or.inl rfl
  | fwd n => exact Or.inl rfl

/-- The roots recorded for `w` before a constructor renames them: a lend adds the roots of its
lender, and the mark of the group, to those of the group it is lent to. -/
def lendR (cc : CCtx) (σ : AbsState) (i : Inst) (w : ValId) : List Root :=
  match i.lent with
  | some b => if w = b then normRoots (Rget σ b ++ (.val b :: lentRoots cc σ i)) else Rget σ w
  | none => Rget σ w

theorem Rget_sub_lendR (cc : CCtx) (σ : AbsState) (i : Inst) (w : ValId) :
    ∀ ρ ∈ Rget σ w, ρ ∈ lendR cc σ i w := by
  intro ρ hρ
  unfold lendR
  cases hl : i.lent with
  | none => exact hρ
  | some b =>
    by_cases hwb : w = b
    · subst hwb
      simp only [if_true]
      exact mem_normRoots.2 (List.mem_append.2 (Or.inl hρ))
    · simp only [hwb, if_false]
      exact hρ

/-- The roots of a value other than the one the instruction defines, after an instruction that
defines an owned value. -/
theorem Rget_next_ne (hp : (i.cls == .parameter) = false) {d : ValId} (hd : i.dst = some d)
    (hs : cc.st d = .owned) {w : ValId} (hwd : w ≠ d) :
    Rget (instNext cc σ i) w =
      if i.cls == .construct then
        normRoots ((lendR cc σ i w).map (renameRoot1 ((cc.ownConsumed i).map (·, d)) true))
      else lendR cc σ i w := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
  unfold Rget
  by_cases hc : (i.cls == .construct) = true
  · simp only [hc, ↓reduceIte]
    rw [lookup_dropSelf _ _ _ hwd, getD_renameAll]
    congr 2
    unfold lendR
    cases hl : i.lent with
    | none =>
      simp only []
      rw [lookup_cons_ne _ _ _ _ hwd, lookup_filter_ne _ _ _ hwd]
      rfl
    | some b =>
      simp only []
      by_cases hwb : w = b
      · subst hwb
        simp [Rget]
      · rw [lookup_cons_ne _ _ _ _ hwb, lookup_filter_ne _ _ _ hwb,
          lookup_cons_ne _ _ _ _ hwd, lookup_filter_ne _ _ _ hwd]
        simp [hwb, Rget]
  · have hc' : (i.cls == .construct) = false := by simpa using hc
    simp only [hc', Bool.false_eq_true, ↓reduceIte]
    unfold lendR
    cases hl : i.lent with
    | none =>
      simp only []
      rw [lookup_cons_ne _ _ _ _ hwd, lookup_filter_ne _ _ _ hwd]
      rfl
    | some b =>
      simp only []
      by_cases hwb : w = b
      · subst hwb
        simp [Rget]
      · rw [lookup_cons_ne _ _ _ _ hwb, lookup_filter_ne _ _ _ hwb,
          lookup_cons_ne _ _ _ _ hwd, lookup_filter_ne _ _ _ hwd]
        simp [hwb, Rget]

theorem Rget_next_old (hp : (i.cls == .parameter) = false) {w : ValId}
    (hw : cc.st w = .borrowed)
    (hnb : ¬ ∃ d, i.dst = some d ∧ cc.st d = .borrowed ∧ w = d) :
    ∀ ρ ∈ Rget σ w, ∃ ρ' ∈ Rget (instNext cc σ i) w, Rn cc i ρ ρ' := by
  intro ρ hρ
  cases hd : i.dst with
  | none =>
    unfold instNext
    simp only [hp, Bool.false_eq_true, ↓reduceIte, hd]
    exact ⟨ρ, hρ, Or.inl rfl⟩
  | some d =>
    cases hs : cc.st d with
    | owned =>
      have hwd : w ≠ d := by rintro rfl; rw [hs] at hw; cases hw
      rw [Rget_next_ne hp hd hs hwd]
      have hmem := Rget_sub_lendR cc σ i w ρ hρ
      by_cases hc : (i.cls == .construct) = true
      · simp only [hc, ↓reduceIte]
        refine ⟨renameRoot1 ((cc.ownConsumed i).map (·, d)) true ρ, mem_normRoots.2 ?_, ?_⟩
        · exact List.mem_map.2 ⟨ρ, hmem, rfl⟩
        · exact Rn_rename (by simpa using hc) hd hs ρ
      · have hc' : (i.cls == .construct) = false := by simpa using hc
        simp only [hc', Bool.false_eq_true, ↓reduceIte]
        exact ⟨ρ, hmem, Or.inl rfl⟩
    | borrowed =>
      have hwd : w ≠ d := fun h => hnb ⟨d, hd, hs, h⟩
      unfold instNext
      simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      refine ⟨ρ, ?_, Or.inl rfl⟩
      unfold Rget
      rw [lookup_cons_ne _ _ _ _ hwd, lookup_filter_ne _ _ _ hwd]
      exact hρ
    | scalar => unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]; exact ⟨ρ, hρ, Or.inl rfl⟩
    | immortal => unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]; exact ⟨ρ, hρ, Or.inl rfl⟩
    | stack => unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]; exact ⟨ρ, hρ, Or.inl rfl⟩
    | emptied => unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]; exact ⟨ρ, hρ, Or.inl rfl⟩
    | none => unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]; exact ⟨ρ, hρ, Or.inl rfl⟩

theorem renameRoot1_nil (wild : Bool) (ρ : Root) : renameRoot1 [] wild ρ = ρ := by
  cases ρ <;> simp [renameRoot1, List.lookup]

theorem renameRoot1_isFwd (moves : List (ValId × ValId)) (wild : Bool) (ρ : Root) :
    (renameRoot1 moves wild ρ).isFwd = ρ.isFwd := by
  cases ρ with
  | val n => cases hm : moves.lookup n <;> simp [renameRoot1, hm, Root.isFwd]
  | slot n k => cases hm : moves.lookup n <;> simp [renameRoot1, hm, Root.isFwd]
  | caller j => simp [renameRoot1, Root.isFwd]
  | fwd n => simp [renameRoot1, Root.isFwd]

/-- Where a root of the old state goes: a constructor that builds an owned aggregate renames the
owners it took into it (their storage does not move). -/
def nextRoot (cc : CCtx) (i : Inst) (ρ : Root) : Root :=
  match i.dst with
  | some d => if i.cls == .construct && cc.st d == .owned then
      renameRoot1 ((cc.ownConsumed i).map (·, d)) true ρ else ρ
  | none => ρ

theorem nextRoot_caller (cc : CCtx) (i : Inst) (j : Nat) : nextRoot cc i (.caller j) = .caller j := by
  unfold nextRoot
  cases i.dst with
  | none => rfl
  | some d => simp only []; split <;> simp [renameRoot1]

theorem nextRoot_val_self {cc : CCtx} {i : Inst} {v : ValId} (hvo : v ∉ cc.ownConsumed i) :
    nextRoot cc i (.val v) = .val v := by
  have hc : (cc.ownConsumed i).contains v = false := by simpa using hvo
  unfold nextRoot
  cases i.dst with
  | none => rfl
  | some d => simp only []; split <;> simp [renameRoot1, lookup_moves, hc, hvo]

theorem nextRoot_slot_self {cc : CCtx} {i : Inst} {v : ValId} (k : String)
    (hvo : v ∉ cc.ownConsumed i) : nextRoot cc i (.slot v k) = .slot v k := by
  have hc : (cc.ownConsumed i).contains v = false := by simpa using hvo
  unfold nextRoot
  cases i.dst with
  | none => rfl
  | some d => simp only []; split <;> simp [renameRoot1, lookup_moves, hc, hvo]

theorem nextRoot_val_moved {cc : CCtx} {i : Inst} {n d : ValId} (hd : i.dst = some d)
    (hc : i.cls = .construct) (hs : cc.st d = .owned) (hn : n ∈ cc.ownConsumed i) :
    nextRoot cc i (.val n) = .val d := by
  have hn' : (cc.ownConsumed i).contains n = true := List.contains_iff_mem.2 hn
  simp [nextRoot, hd, hc, hs, renameRoot1, lookup_moves, hn', hn]

theorem nextRoot_slot_moved {cc : CCtx} {i : Inst} {n d : ValId} (k : String) (hd : i.dst = some d)
    (hc : i.cls = .construct) (hs : cc.st d = .owned) (hn : n ∈ cc.ownConsumed i) :
    nextRoot cc i (.slot n k) = .slot d "*" := by
  have hn' : (cc.ownConsumed i).contains n = true := List.contains_iff_mem.2 hn
  simp [nextRoot, hd, hc, hs, renameRoot1, lookup_moves, hn', hn]

theorem nextRoot_isFwd (cc : CCtx) (i : Inst) (ρ : Root) : (nextRoot cc i ρ).isFwd = ρ.isFwd := by
  unfold nextRoot
  cases i.dst with
  | none => rfl
  | some d => simp only []; split <;> simp [renameRoot1_isFwd]

/-- A root recorded for a value the instruction does not define survives, renamed if a constructor
took its owner. -/
theorem Rget_next_keep (hp : (i.cls == .parameter) = false) {w : ValId}
    (hwd : ∀ d, i.dst = some d → w ≠ d) :
    ∀ ρ ∈ Rget σ w, nextRoot cc i ρ ∈ Rget (instNext cc σ i) w := by
  intro ρ hρ
  cases hd : i.dst with
  | none =>
    unfold instNext
    simp only [hp, Bool.false_eq_true, ↓reduceIte, hd]
    have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd]
    rw [this]; exact hρ
  | some d =>
    have hwd' : w ≠ d := hwd d hd
    cases hs : cc.st d with
    | owned =>
      rw [Rget_next_ne hp hd hs hwd']
      have hmem := Rget_sub_lendR cc σ i w ρ hρ
      by_cases hc : (i.cls == .construct) = true
      · simp only [hc, ↓reduceIte]
        have : nextRoot cc i ρ = renameRoot1 ((cc.ownConsumed i).map (·, d)) true ρ := by
          simp [nextRoot, hd, hs, hc]
        rw [this]
        exact mem_normRoots.2 (List.mem_map.2 ⟨ρ, hmem, rfl⟩)
      · have hc' : (i.cls == .construct) = false := by simpa using hc
        simp only [hc', Bool.false_eq_true, ↓reduceIte]
        have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs, hc']
        rw [this]
        exact hmem
    | borrowed =>
      unfold instNext
      simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]
      unfold Rget
      rw [lookup_cons_ne _ _ _ _ hwd', lookup_filter_ne _ _ _ hwd']
      exact hρ
    | scalar =>
      unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]; exact hρ
    | immortal =>
      unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]; exact hρ
    | stack =>
      unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]; exact hρ
    | emptied =>
      unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]; exact hρ
    | none =>
      unfold instNext; simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
      have : nextRoot cc i ρ = ρ := by simp [nextRoot, hd, hs]
      rw [this]; exact hρ

/-- A lend records its group as lent-to and hands it the roots of its lender. -/
theorem Rget_next_lend (hp : (i.cls == .parameter) = false) {d : ValId} (hd : i.dst = some d)
    (hs : cc.st d = .owned) {b : ValId} (hl : i.lent = some b) (hc : i.cls = .construct)
    (hoc : cc.ownConsumed i = []) (hbd : b ≠ d) :
    Root.val b ∈ Rget (instNext cc σ i) b ∧ ∀ ρ ∈ lentRoots cc σ i, ρ ∈ Rget (instNext cc σ i) b := by
  rw [Rget_next_ne hp hd hs hbd]
  have hcb : (i.cls == .construct) = true := by simp [hc]
  have hmap : ∀ l : List Root, l.map (renameRoot1 [] true) = l := by
    intro l
    induction l with
    | nil => rfl
    | cons x xs ih => simp [renameRoot1_nil, ih]
  simp only [hcb, ↓reduceIte, hoc, List.map_nil, hmap]
  unfold lendR
  simp only [hl, ite_true]
  constructor
  · exact mem_normRoots.2 (mem_normRoots.2 (List.mem_append.2 (Or.inr List.mem_cons_self)))
  · intro ρ hρ
    exact mem_normRoots.2 (mem_normRoots.2 (List.mem_append.2 (Or.inr (List.mem_cons_of_mem _ hρ))))

theorem lookup_dropSelf_self (R : List (ValId × List Root)) (h : ValId) (r : Root) :
    r ∈ ((dropSelf R h).lookup h).getD [] ↔
      r ∈ (R.lookup h).getD [] ∧
        (match r with
          | .val n => n != h
          | .slot n _ => n != h
          | .caller _ => true
          | .fwd _ => true) = true := by
  induction R with
  | nil => simp [dropSelf]
  | cons p ps ih =>
    unfold dropSelf at ih ⊢
    simp only [List.map_cons, List.lookup]
    by_cases hp : h == p.1
    · have hp' : (p.1 == h) = true := by simpa [BEq.comm] using hp
      simp [hp, hp', List.mem_filter]
      intro _; rfl
    · have hp' : (p.1 == h) = false := by
        cases hh : p.1 == h
        · rfl
        · exfalso; apply hp; simpa [BEq.comm] using hh
      simp only [hp, hp', Bool.false_eq_true, ↓reduceIte]
      exact ih

/-- The loans a newly defined owned value holds. -/
def loansOf (cc : CCtx) (σ : AbsState) (i : Inst) : List Root :=
  normRoots (parentRoots cc σ (cc.pd i) ++
    (if !i.dropsLoans then (cc.ownConsumed i).flatMap (Rget σ ·) else []))

theorem Rget_next_owned_self (hp : (i.cls == .parameter) = false) {d : ValId}
    (hd : i.dst = some d) (hs : cc.st d = .owned) (hl : i.lent = none) (σ : AbsState) (r : Root) :
    r ∈ Rget (instNext cc σ i) d ↔
      (i.cls == .construct) = true ∧
        (r ∈ normRoots ((loansOf cc σ i).map (renameRoot1 ((cc.ownConsumed i).map (·, d)) true)) ∧
          (match r with
            | .val n => n != d
            | .slot n _ => n != d
            | .caller _ => true
            | .fwd _ => true) = true) ∨
      (i.cls == .construct) = false ∧ r ∈ loansOf cc σ i := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs, hl, lentRoots, List.append_nil]
  by_cases hc : (i.cls == .construct) = true
  · simp only [hc, ↓reduceIte]
    unfold Rget
    rw [lookup_dropSelf_self, getD_renameAll, lookup_cons_self]
    simp [loansOf, hc]
    intro _; exact Iff.rfl
  · have hc' : (i.cls == .construct) = false := by simpa using hc
    simp only [hc', Bool.false_eq_true, ↓reduceIte]
    unfold Rget
    rw [lookup_cons_self]
    simp [loansOf, hc']
    exact Iff.rfl

/-- The roots of a newly defined borrowed value. -/
theorem Rget_next_new (hp : (i.cls == .parameter) = false) {d : ValId} (hd : i.dst = some d)
    (hs : cc.st d = .borrowed) : Rget (instNext cc σ i) d = resultRoots cc σ i := by
  unfold instNext
  simp only [hp, Bool.false_eq_true, ↓reduceIte, hd, hs]
  unfold Rget
  rw [lookup_cons_self]
  rfl

end Roots

end Own
