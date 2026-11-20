import ProgramDefs

/-!
# The call-site agreement is derived, not assumed (C9.2, design entry 57)

`CallWf` (the call site agrees with the callee) used to be a hypothesis of the whole-program corollary.  Now the
checker has established the call-site half for every call line of a function that passes `check` (`InstOk.centry` to
`InstOk.cfrom`: the line names an entry of the function's callee table, its arguments fit the entry's parameters, a scalar
parameter receives a scalar, its value follows the entry's result, a borrowed value lists the arguments of the borrow
contract as parents), and the program-level link has established the entry half (`entryTag`: the entry says what the
callee's header says).  `callWf_of_site` puts them together.
-/

namespace Own

/-! ## The walk over the parameters -/

theorem walkArgs_length : ∀ (ps : List ParamTok) (rs cs : List ValId),
    cs.length = (ps.filter (·.takes)).length → rs.length = (ps.filter (fun t => !t.takes)).length →
      (walkArgs ps rs cs).length = ps.length := by
  intro ps
  induction ps with
  | nil => intro rs cs _ _; simp [walkArgs]
  | cons t ts ih =>
    intro rs cs hc hr
    cases hq : t.takes with
    | true =>
      cases cs with
      | nil => simp [hq] at hc
      | cons c cs' =>
        simp only [List.filter_cons, hq, ↓reduceIte, List.length_cons] at hc hr
        simp only [walkArgs, hq, ↓reduceIte, List.length_cons]
        have := ih rs cs' (by simpa using hc) (by simpa using hr)
        omega
    | false =>
      cases rs with
      | nil => simp [hq] at hr
      | cons r rs' =>
        simp only [List.filter_cons, hq, Bool.false_eq_true, ↓reduceIte, Bool.not_false, List.length_cons] at hc hr
        simp only [walkArgs, hq, Bool.false_eq_true, ↓reduceIte, List.length_cons]
        have := ih rs' cs (by simpa using hc) (by simpa using hr)
        omega

theorem walkArgs_cons : ∀ (ps : List ParamTok) (rs cs : List ValId),
    cs.length = (ps.filter (·.takes)).length → rs.length = (ps.filter (fun t => !t.takes)).length →
      ((walkArgs ps rs cs).filter (·.2)).map (·.1) = cs := by
  intro ps
  induction ps with
  | nil => intro rs cs hc _; simp [walkArgs] at hc ⊢; exact hc.symm ▸ rfl
  | cons t ts ih =>
    intro rs cs hc hr
    cases hq : t.takes with
    | true =>
      cases cs with
      | nil => simp [hq] at hc
      | cons c cs' =>
        simp only [List.filter_cons, hq, ↓reduceIte, List.length_cons] at hc hr
        simp only [walkArgs, hq, ↓reduceIte, List.filter_cons, List.map_cons]
        simp [ih rs cs' (by simpa using hc) (by simpa using hr)]
    | false =>
      cases rs with
      | nil => simp [hq] at hr
      | cons r rs' =>
        simp only [List.filter_cons, hq, Bool.false_eq_true, ↓reduceIte, Bool.not_false, List.length_cons] at hc hr
        simp only [walkArgs, hq, Bool.false_eq_true, ↓reduceIte, List.filter_cons]
        simpa using ih rs' cs (by simpa using hc) (by simpa using hr)

theorem walkArgs_reads : ∀ (ps : List ParamTok) (rs cs : List ValId),
    cs.length = (ps.filter (·.takes)).length → rs.length = (ps.filter (fun t => !t.takes)).length →
      ((walkArgs ps rs cs).filter (fun a => !a.2)).map (·.1) = rs := by
  intro ps
  induction ps with
  | nil => intro rs cs _ hr; simp [walkArgs] at hr ⊢; exact hr
  | cons t ts ih =>
    intro rs cs hc hr
    cases hq : t.takes with
    | true =>
      cases cs with
      | nil => simp [hq] at hc
      | cons c cs' =>
        simp only [List.filter_cons, hq, ↓reduceIte, List.length_cons] at hc hr
        simp only [walkArgs, hq, ↓reduceIte, List.filter_cons]
        simpa using ih rs cs' (by simpa using hc) (by simpa using hr)
    | false =>
      cases rs with
      | nil => simp [hq] at hr
      | cons r rs' =>
        simp only [List.filter_cons, hq, Bool.false_eq_true, ↓reduceIte, Bool.not_false, List.length_cons] at hc hr
        simp only [walkArgs, hq, Bool.false_eq_true, ↓reduceIte, List.filter_cons, List.map_cons]
        simp [ih rs' cs (by simpa using hc) (by simpa using hr)]

/-- The argument at a position is the one of the parameter at that position: it is consumed iff the parameter takes it. -/
theorem walkArgs_getElem? : ∀ (ps : List ParamTok) (rs cs : List ValId) (I : Nat) (n : ValId) (b : Bool),
    (walkArgs ps rs cs)[I]? = some (n, b) → ∃ t, ps[I]? = some t ∧ t.takes = b := by
  intro ps
  induction ps with
  | nil => intro rs cs I n b h; simp [walkArgs] at h
  | cons t ts ih =>
    intro rs cs I n b h
    cases I with
    | zero =>
      cases hq : t.takes with
      | true =>
        cases cs with
        | nil => simp [walkArgs, hq] at h
        | cons c cs' =>
          simp [walkArgs, hq] at h
          exact ⟨t, rfl, by simp [hq, h.2]⟩
      | false =>
        cases rs with
        | nil => simp [walkArgs, hq] at h
        | cons r rs' =>
          simp [walkArgs, hq] at h
          exact ⟨t, rfl, by simp [hq, h.2]⟩
    | succ I =>
      cases hq : t.takes with
      | true =>
        cases cs with
        | nil => simp [walkArgs, hq] at h
        | cons c cs' =>
          simp only [walkArgs, hq, ↓reduceIte, List.getElem?_cons_succ] at h
          obtain ⟨t', ht', hb⟩ := ih rs cs' I n b h
          exact ⟨t', by simpa using ht', hb⟩
      | false =>
        cases rs with
        | nil => simp [walkArgs, hq] at h
        | cons r rs' =>
          simp only [walkArgs, hq, Bool.false_eq_true, ↓reduceIte, List.getElem?_cons_succ] at h
          obtain ⟨t', ht', hb⟩ := ih rs' cs I n b h
          exact ⟨t', by simpa using ht', hb⟩


/-! ## What the link says of an entry -/

theorem entryTag_none {e : CalleeEntry} {h : Header} (ht : entryTag e h = none) :
    e.params.length = h.params.length ∧
    (∀ (I : Nat) (t : ParamTok), e.params[I]? = some t →
      h.params[I]? = some t.state ∧ h.states[I]? = some t.state) ∧
    e.result.state = h.result ∧ e.from_ = h.from_ := by
  unfold entryTag at ht
  by_cases h1 : (e.params.length != h.params.length || h.states.length != h.params.length) = true
  · simp [h1] at ht
  · by_cases h2 : (!((e.params.zip (h.params.zip h.states)).all fun (t, k, s) => t.state == k && s == k)) = true
    · simp [h1, h2] at ht
    · by_cases h3 : (e.result.state != h.result) = true
      · simp [h1, h2, h3] at ht
      · by_cases h4 : (e.from_ != h.from_) = true
        · simp [h1, h2, h3, h4] at ht
        · simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or, Decidable.not_not] at h1
          obtain ⟨hl, hs⟩ := h1
          simp only [Bool.not_eq_true', Bool.not_eq_false, List.all_eq_true] at h2
          simp only [bne_iff_ne, ne_eq, Decidable.not_not] at h3 h4
          refine ⟨hl, ?_, h3, h4⟩
          intro I t hI
          have hI' : I < e.params.length := (List.getElem?_eq_some_iff.1 hI).1
          obtain ⟨k, hp⟩ : ∃ k, h.params[I]? = some k := ⟨_, List.getElem?_eq_getElem (by omega)⟩
          obtain ⟨q, hst⟩ : ∃ q, h.states[I]? = some q := ⟨_, List.getElem?_eq_getElem (by omega)⟩
          have hz : (e.params.zip (h.params.zip h.states))[I]? = some (t, k, q) := by
            simp [List.getElem?_zip_eq_some, hI, hp, hst]
          have := h2 (t, k, q) (List.mem_of_getElem? hz)
          simp only [Bool.and_eq_true, beq_iff_eq] at this
          obtain ⟨h1', h2'⟩ := this
          rw [hp, hst]
          exact ⟨by rw [← h1'], by rw [h2', ← h1']⟩


/-! ## `CallWf` from the checks -/

theorem entryOf_some {f : Function} {i : Inst} {e : CalleeEntry} (h : f.entryOf i = some e) :
    ∃ n, i.entry = some n := by
  unfold Function.entryOf at h
  cases hn : i.entry with
  | none => rw [hn] at h; simp at h
  | some n => exact ⟨n, rfl⟩

theorem entryOf_mem {f : Function} {i : Inst} {e : CalleeEntry} (h : f.entryOf i = some e) : e ∈ f.callees := by
  unfold Function.entryOf at h
  cases hn : i.entry with
  | none => rw [hn] at h; simp at h
  | some n =>
    rw [hn] at h
    exact List.mem_of_getElem? (by simpa using h)

theorem callWf_of_site {cc : CCtx} {σ : AbsState} {i : Inst} {e : CalleeEntry} {g : Function × Certificate}
    (hok : InstOk cc σ i) (he : cc.f.entryOf i = some e) (hk : e.kind = .program)
    (ht : entryTag e (Header.of g) = none) : CallWf cc.c g i (i.argsOf e) := by
  obtain ⟨hlen, hpar, hres, hfrom⟩ := entryTag_none ht
  have hlen' : e.params.length = g.1.params.length := by rw [hlen]; rfl
  have hpar' : ∀ (I : Nat) (t : ParamTok), e.params[I]? = some t → g.1.params[I]? = some t.state :=
    fun I t h => (hpar I t h).1
  have hres' : e.result.state = g.1.result := hres
  have hfrom' : e.from_ = g.1.from_ := hfrom
  -- the line is a call
  have hcls : i.cls = .call := by
    have h1 := hok.centry
    unfold callEntryOk at h1
    by_cases hc : (i.cls == .call) = true
    · simpa using hc
    · simp only [hc, Bool.false_eq_true, ↓reduceIte, Option.isNone_iff_eq_none] at h1
      obtain ⟨n, hn⟩ := entryOf_some he
      rw [h1] at hn; cases hn
  have hnind : (e.kind == .indirect) = false := by simp [hk]
  have hed : cc.entryOf i = some e := he
  -- the arity
  have har := hok.carity
  unfold callArityOk at har
  simp only [hcls, bne_self_eq_false, Bool.false_or, hed, hnind, Bool.and_eq_true, beq_iff_eq,
    Bool.false_eq_true, ↓reduceIte, Nat.add_zero] at har
  obtain ⟨hcons, hrds⟩ := har
  have hA : ∀ (I : Nat) (n : ValId) (b : Bool), (i.argsOf e)[I]? = some (n, b) →
      ∃ t : ParamTok, e.params[I]? = some t ∧ t.takes = b := by
    intro I n b h
    unfold Inst.argsOf at h
    simp only [hnind, Bool.false_eq_true, ↓reduceIte] at h
    exact walkArgs_getElem? _ _ _ I n b h
  have hlenA : (i.argsOf e).length = e.params.length := by
    unfold Inst.argsOf
    simp only [hnind, Bool.false_eq_true, ↓reduceIte]
    exact walkArgs_length _ _ _ hcons hrds
  -- the scalar parameters
  have hsc : ∀ (I : Nat) (n : ValId) (b : Bool) (t : ParamTok), (i.argsOf e)[I]? = some (n, b) →
      e.params[I]? = some t → t.scalarVal = true → Unmanaged cc.c n := by
    intro I n b t hAI hpI hsv
    have h1 := hok.cscalar
    unfold callScalarOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    simp only [h2, Bool.not_true, Bool.false_or] at h1
    have hz : ((i.argsOf e).zip e.params)[I]? = some ((n, b), t) := by
      simp [List.getElem?_zip_eq_some, hAI, hpI]
    have := List.all_eq_true.1 h1 _ (List.mem_of_getElem? hz)
    simp only [hsv, Bool.not_true, Bool.false_or, Bool.or_eq_true, beq_iff_eq] at this
    unfold Unmanaged
    rcases this with (h | h) | h
    · exact Or.inl h
    · exact Or.inr (Or.inl h)
    · exact Or.inr (Or.inr h)
  refine ⟨hcls, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · -- len
    rw [hlenA, hlen']
  · -- mode
    intro I n b hAI
    obtain ⟨t, hpI, hb⟩ := hA I n b hAI
    have hgp := hpar' I t hpI
    constructor
    · intro hown
      rw [hgp] at hown
      have hs : t.state = .owned := Option.some.inj hown
      cases t <;> simp [ParamTok.state] at hs <;> simpa [ParamTok.takes] using hb.symm
    · intro hbt
      subst hbt
      cases t with
      | take => left; simpa [ParamTok.state] using hgp
      | takeScalar =>
        right
        exact ⟨by simpa [ParamTok.state] using hgp, hsc I n true _ hAI hpI rfl⟩
      | read => simp [ParamTok.takes] at hb
      | readScalar => simp [ParamTok.takes] at hb
  · -- cons
    unfold Inst.argsOf
    simp only [hnind, Bool.false_eq_true, ↓reduceIte]
    exact walkArgs_cons _ _ _ hcons hrds
  · -- rds
    unfold Inst.argsOf
    simp only [hnind, Bool.false_eq_true, ↓reduceIte]
    exact walkArgs_reads _ _ _ hcons hrds
  · -- scalar
    intro I n b hAI hsca
    obtain ⟨t, hpI, hb⟩ := hA I n b hAI
    have hgp := hpar' I t hpI
    rw [hgp] at hsca
    have hs : t.state = .scalar := Option.some.inj hsca
    have hsv : t.scalarVal = true := by cases t <;> simp [ParamTok.state, ParamTok.scalarVal] at hs ⊢
    exact hsc I n b t hAI hpI hsv
  · -- argScalar
    intro I n b v hAI hv hsv
    obtain ⟨t, hpI, hb⟩ := hA I n b hAI
    have hI' : I < e.params.length := (List.getElem?_eq_some_iff.1 hpI).1
    have hst := (hpar I t hpI).2
    have hvs : (g.1.paramVals.map g.2.state)[I]? = some (g.2.state v) := by simp [hv]
    have hst' : (Header.of g).states[I]? = some t.state := hst
    simp only [Header.of] at hst'
    rw [hvs] at hst'
    have hs : g.2.state v = t.state := Option.some.inj hst'
    rw [hsv] at hs
    have hsv' : t.scalarVal = true := by cases t <;> simp [ParamTok.state, ParamTok.scalarVal] at hs ⊢
    exact hsc I n b t hAI hpI hsv'
  · -- voidRes
    intro hd
    have h1 := hok.cresult
    unfold callResultOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    simp only [h2, Bool.not_true, Bool.false_or, hd, beq_iff_eq] at h1
    rw [← hres', h1]
    simp [ResTok.state]
  · -- resOwned
    intro d hd hown
    have h1 := hok.cresult
    unfold callResultOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    have hst : cc.st d = .owned := owning_iff.1 hown
    simp only [h2, Bool.not_true, Bool.false_or, hd, hst, beq_iff_eq] at h1
    rw [← hres', h1]
    simp [ResTok.state]
  · -- resBor
    intro d hd hb
    have hb' : cc.st d = .borrowed := hb
    have h1 := hok.cresult
    unfold callResultOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    simp only [h2, Bool.not_true, Bool.false_or, hd, hb', beq_iff_eq] at h1
    refine ⟨by rw [← hres', h1]; simp [ResTok.state], ?_⟩
    have h3 := hok.cfrom
    unfold callFromOk at h3
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed, h2, Bool.not_true, hd, hb', bne_self_eq_false] at h3
    intro I hI
    rw [← hfrom'] at hI
    have h4 := List.all_eq_true.1 h3 I hI
    cases hAI : (i.argsOf e)[I]? with
    | none => simp [hAI] at h4
    | some a =>
      cases hpI : e.params[I]? with
      | none => simp [hAI, hpI] at h4
      | some t =>
        simp only [hAI, hpI, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_true, beq_iff_eq,
          List.contains_iff_mem] at h4
        obtain ⟨hnt, hcase⟩ := h4
        obtain ⟨t', hpI', hb''⟩ := hA I a.1 a.2 hAI
        rw [hpI] at hpI'
        have ht' : t' = t := (Option.some.inj hpI').symm
        subst ht'
        have hbf : a.2 = false := by rw [← hb'']; exact hnt
        refine ⟨a.1, by rw [← hbf], ?_⟩
        rcases hcase with ((h | h) | h) | h
        · exact Or.inl (Or.inl h)
        · exact Or.inl (Or.inr (Or.inl h))
        · exact Or.inl (Or.inr (Or.inr h))
        · exact Or.inr h
  · -- resImm
    intro d hd hs
    have h1 := hok.cresult
    unfold callResultOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    simp only [h2, Bool.not_true, Bool.false_or, hd] at h1
    have hr : e.result = .scalar := by
      rcases hs with hs | hs | hs
      · have hs' : cc.st d = .scalar := hs
        simpa [hs'] using h1
      · have hs' : cc.st d = .immortal := hs
        simpa [hs'] using h1
      · have hs' : cc.st d = .none := hs
        simpa [hs'] using h1
    rw [← hres', hr]
    simp [ResTok.state]
  · -- resEmptied
    intro d hd hemp
    have h1 := hok.cresult
    unfold callResultOk at h1
    simp only [hcls, bne_self_eq_false, Bool.false_or, hed] at h1
    have h2 : e.judged = true := by simp [CalleeEntry.judged, hk]
    have hemp' : cc.st d = .emptied := hemp
    simp only [h2, Bool.not_true, Bool.false_or, hd, hemp', beq_iff_eq] at h1
    rw [← hres', h1]
    simp [ResTok.state]
  · -- noStack
    intro d hd hstk
    have h1 := hok.cok
    unfold classOk at h1
    simp only [hcls, Bool.and_eq_true] at h1
    have hsd : cc.sd i = .stack := by simp [CCtx.sd, hd, hstk]
    have := h1.2
    simp only [hsd] at this
    simp at this


/-! ## From the link to the entries of a program -/

theorem linkOk_entry {fs : List LinkFn} (h : linkOk fs = true) {f : LinkFn} (hf : f ∈ fs) {e : CalleeEntry}
    (he : e ∈ f.callees) (hk : e.kind = .program) :
    ∃ g callee, indexOfName fs e.name = some g ∧ fs[g]? = some callee ∧ entryTag e callee.hd = none := by
  unfold linkOk linkRejects at h
  rw [List.isEmpty_iff, List.flatMap_eq_nil_iff] at h
  have h1 := h f hf
  rw [List.filterMap_eq_nil_iff] at h1
  have h2 := h1 e he
  simp only [hk, beq_self_eq_true, ↓reduceIte] at h2
  cases hi : indexOfName fs e.name with
  | none => rw [hi] at h2; simp at h2
  | some g =>
    rw [hi] at h2
    dsimp only at h2
    cases hg : fs[g]? with
    | none => rw [hg] at h2; simp at h2
    | some callee =>
      rw [hg] at h2
      dsimp only at h2
      refine ⟨g, callee, rfl, hg, ?_⟩
      cases ht : entryTag e callee.hd with
      | none => rfl
      | some t => rw [ht] at h2; simp at h2

theorem indexOfName_map (prog : Program) (name : String) :
    indexOfName (prog.map LinkFn.of) name = Program.indexOf prog name := by
  simp [indexOfName, Program.indexOf, List.findIdx?_map, Function.comp_def, LinkFn.of, Header.of]

/-- Every `program` entry of a function of a well formed program names a function of the program whose header the
entry describes. -/
theorem ProgWf.entry_link {prog : Program} (hw : ProgWf prog) {fc : Function × Certificate} (hfc : fc ∈ prog)
    {e : CalleeEntry} (he : e ∈ fc.1.callees) (hk : e.kind = .program) :
    ∃ g fg, prog.indexOf e.name = some g ∧ prog[g]? = some fg ∧ entryTag e (Header.of fg) = none := by
  have hf : LinkFn.of fc ∈ prog.map LinkFn.of := List.mem_map.2 ⟨fc, hfc, rfl⟩
  obtain ⟨g, callee, hi, hg, ht⟩ := linkOk_entry hw.link hf (e := e) (by simpa [LinkFn.of] using he) hk
  rw [indexOfName_map] at hi
  have hg' : (prog.map LinkFn.of)[g]? = some callee := hg
  rw [List.getElem?_map] at hg'
  cases hp : prog[g]? with
  | none => rw [hp] at hg'; simp at hg'
  | some fg =>
    rw [hp] at hg'
    simp only [Option.map_some, Option.some.injEq] at hg'
    refine ⟨g, fg, hi, hp, ?_⟩
    rw [← hg'] at ht
    exact ht

end Own
