import ProgramCall

/-!
# The caller's step from the callee's contract
-/

namespace Own

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool} {σ : AbsState}
  {ds : DState} {i : Inst} {g : Function × Certificate} {A : List (ValId × Bool)}

/-- A value that holds no tree is an immediate. -/
theorem imm_of_unmanaged (hI : Inv cc args h0 σ ds) {n : ValId} (h : Unmanaged cc.c n) : ds.env n = .imm :=
  hI.imm n (by rcases h with h | h | h <;> simp [CCtx.st, h])

/-- The trees a call consumes are the owned arguments' trees. -/
theorem owned_iff_consumed (hInv : Inv cc args h0 σ ds) (hw : CallWf cc.c g i A) (t : Addr) :
    t ∈ consumedRoots ds i ↔ OwnedArg g.1 (argOf A ds.env) t := by
  constructor
  · intro ht
    unfold consumedRoots at ht
    rw [List.mem_filterMap] at ht
    obtain ⟨k, hk, hkt⟩ := ht
    have hown : ds.env k = .own t := by
      cases h : ds.env k <;> simp [ownedRoot, h] at hkt
      subst hkt; rfl
    rw [← hw.cons] at hk
    obtain ⟨⟨n, b⟩, hmem, hkn⟩ := List.mem_map.1 hk
    obtain ⟨hmemA, hb⟩ := List.mem_filter.1 hmem
    obtain ⟨I, hI⟩ := mem_args_index _ _ hmemA
    simp only [decide_eq_true_eq] at hb
    subst hb
    simp only at hkn
    subst hkn
    have hmode := (hw.mode I n true hI).2 rfl
    rcases hmode with hm | ⟨_, hu⟩
    · refine ⟨I, hm, ?_⟩
      simp [argOf, hI, hown]
    · exfalso
      have := imm_of_unmanaged hInv hu
      rw [hown] at this; cases this
  · rintro ⟨I, hI, hargs⟩
    have hlen : I < A.length := by
      rw [hw.len]; exact (List.getElem?_eq_some_iff.1 hI).1
    obtain ⟨⟨n, b⟩, hA⟩ : ∃ a, A[I]? = some a := ⟨_, List.getElem?_eq_getElem hlen⟩
    have hb : b = true := (hw.mode I n b hA).1 hI
    subst hb
    have hargs' : ds.env n = .own t := by simpa [argOf, hA] using hargs
    unfold consumedRoots
    rw [List.mem_filterMap]
    refine ⟨n, ?_, by simp [ownedRoot, hargs']⟩
    rw [← hw.cons]
    exact List.mem_map.2 ⟨(n, true), List.mem_filter.2 ⟨List.mem_of_getElem? hA, by simp⟩, rfl⟩

/-- Every cell's tree root is live and labelled by itself, in every state of the run. -/
theorem heap_wf (hs : Static cc args h0 pend0) (hI : Inv cc args h0 σ ds) :
    ∀ x t, ds.heap x = .live t → ds.heap t = .live t := by
  intro x t hx
  rcases hI.acct x t hx with ⟨v, hv, hvt⟩ | ⟨hx0, hn⟩ | hab
  · rcases hI.Lval v hv with h | ⟨t', h1, h2⟩
    · rw [h] at hvt; cases hvt
    · rw [h1] at hvt; cases hvt; exact h2
  · exact hI.frame t t (hs.pre.wf x t hx0) hn
  · exact hI.abLive t hab

/-- A value whose state is a scalar or an immortal is an immediate. -/
theorem imm_of_scalar (hI : Inv cc args h0 σ ds) {n : ValId}
    (h : cc.st n = .scalar ∨ cc.st n = .immortal) : ds.env n = .imm :=
  hI.imm n (by rcases h with h | h <;> simp [h])

/-- The owned root a read value holds is a live root. -/
theorem read_root (hI : Inv cc args h0 σ ds) (hok : InstOk cc σ i) {r : ValId}
    (hr : r ∈ i.reads) {t : Addr} (ht : ds.env r = .own t) : ds.heap t = .live t := by
  have hu : usable cc σ r = true := by
    by_cases hb : cc.st r = .borrowed
    · exact hok.r4 r hr hb
    · exact hok.r3 r hr hb
  cases hst : cc.st r with
  | scalar => rw [hI.imm r (by simp [hst])] at ht; cases ht
  | immortal => rw [hI.imm r (by simp [hst])] at ht; cases ht
  | stack => rcases hI.stk r hst with h | h <;> rw [h] at ht <;> cases ht
  | emptied => rw [hI.imm r (by simp [hst])] at ht; cases ht
  | none => simp [usable, hst] at hu
  | owned =>
    have hL := usable_owning (by simp [hst, St.owning]) hu
    rcases hI.Lval r hL with h | ⟨t', h1, h2⟩
    · rw [h] at ht; cases ht
    · rw [h1] at ht; cases ht; exact h2
  | borrowed =>
    obtain ⟨hD, _⟩ := usable_borrowed hst hu
    rcases hI.Dval r hD with h | ⟨fp, h⟩ <;> rw [h] at ht <;> cases ht

/-- The callee's before-the-call condition holds at a checked call site. -/
theorem pre_of_call (hs : Static cc args h0 pend0) (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A) :
    Pre g.1 (argOf A ds.env) ds.heap ds.pend := by
  have hargAt : ∀ (I : Nat) (k : St), g.1.params[I]? = some k →
      ∃ n b, A[I]? = some (n, b) := by
    intro I k hk
    have hlt : I < g.1.params.length := (List.getElem?_eq_some_iff.1 hk).1
    have hlt' : I < A.length := by rw [hw.len]; exact hlt
    obtain ⟨⟨n, b⟩, hA⟩ : ∃ a, A[I]? = some a := ⟨_, List.getElem?_eq_getElem hlt'⟩
    exact ⟨n, b, hA⟩
  have hcons_mem : ∀ n, (n, true) ∈ A → n ∈ i.consumes := by
    intro n hn
    rw [← hw.cons]
    exact List.mem_map.2 ⟨(n, true), List.mem_filter.2 ⟨hn, by simp⟩, rfl⟩
  have hreads_mem : ∀ n, (n, false) ∈ A → n ∈ i.reads := by
    intro n hn
    rw [← hw.rds]
    exact List.mem_map.2 ⟨(n, false), List.mem_filter.2 ⟨hn, by simp⟩, rfl⟩
  have hnotclosing : i.isClosing = false := by simp [Inst.isClosing, hw.cls]
  have hnd : (((A.filter (·.2)).map (·.1)).filterMap
      (fun c => ownedRoot (ds.env c))).Nodup := by
    rw [hw.cons]; exact consumeOnce_ok hInv hok
  have ownedArg : ∀ (I : Nat), g.1.params[I]? = some .owned →
      ∃ n, A[I]? = some (n, true) ∧ n ∈ i.consumes ∧
        argOf A ds.env I = ds.env n := by
    intro I hk
    obtain ⟨n, b, hA⟩ := hargAt I _ hk
    have hb : b = true := (hw.mode I n b hA).1 hk
    subst hb
    exact ⟨n, hA, hcons_mem n (List.mem_of_getElem? hA), by simp [argOf, hA]⟩
  have readArg : ∀ (I : Nat) (k : St), g.1.params[I]? = some k → k ≠ .owned → k ≠ .scalar →
      ∃ n, A[I]? = some (n, false) ∧ n ∈ i.reads ∧
        argOf A ds.env I = lend (ds.env n) := by
    intro I k hk hne hns
    obtain ⟨n, b, hA⟩ := hargAt I _ hk
    have hb : b = false := by
      cases b with
      | false => rfl
      | true =>
        have := (hw.mode I n true hA).2 rfl
        rcases this with h | ⟨h, _⟩ <;> rw [hk] at h
        · exact (hne (Option.some.inj h)).elim
        · exact (hns (Option.some.inj h)).elim
    subst hb
    exact ⟨n, hA, hreads_mem n (List.mem_of_getElem? hA), by simp [argOf, hA]⟩
  have scalarArg : ∀ (I : Nat), g.1.params[I]? = some .scalar → argOf A ds.env I = .imm := by
    intro I hk
    obtain ⟨n, b, hA⟩ := hargAt I _ hk
    have himm : ds.env n = .imm := imm_of_unmanaged hInv (hw.scalar I n b hA hk)
    cases b <;> simp [argOf, hA, himm, lend]
  have hcall : ¬ (i.cls = .construct ∧ (i.res (Ctx.entering cc.f cc.c args) = .owned ∨
      i.res (Ctx.entering cc.f cc.c args) = .emptied)) := by
    rintro ⟨h, _⟩; rw [hw.cls] at h; cases h
  refine ⟨heap_wf hs hInv, ?_, ?_, ?_, ?_, ?_⟩
  · intro I hk
    rw [scalarArg I hk]
  · intro I hk
    obtain ⟨n, hA, hnc, hv⟩ := ownedArg I hk
    rw [hv]
    rcases hok.c2 n hnc with hsc | ⟨hown, hnL⟩
    · left
      rcases hInv.noOwn4 hsc with h | h
      · exact h
      · exfalso
        have := (noEscape_ok hInv hok).1 n hnc h
        rw [hw.cls] at this
        cases this.1
    · rcases hInv.Lval n hnL with h | ⟨t, h1, h2⟩
      · left; exact h
      · right
        refine ⟨t, h1, h2, ?_⟩
        intro k
        cases hp : ds.pend t k with
        | false => rfl
        | true =>
          have := noStale_ok hInv hok n hnc t h1 ⟨k, hp⟩
          rw [hnotclosing] at this
          exact absurd this.1 (by simp)
  · intro I J t hI hJ hIt hJt
    obtain ⟨n, hAn, _, hvn⟩ := ownedArg I hI
    obtain ⟨m, hAm, _, hvm⟩ := ownedArg J hJ
    rw [hvn] at hIt
    rw [hvm] at hJt
    exact owned_pos_inj (fun c => ownedRoot (ds.env c)) A hnd I J n m t hAn hAm
      (by simp [ownedRoot, hIt]) (by simp [ownedRoot, hJt])
  · intro I hk
    obtain ⟨n, hA, hnr, hv⟩ := readArg I .borrowed hk (by simp) (by simp)
    rw [hv]
    refine ⟨?_, (lend_alive _ _).2 (readsAlive_ok hs hInv hok n hnr)⟩
    cases ds.env n with
    | imm => left; rfl
    | stk => left; rfl
    | own t => right; exact ⟨[t], rfl⟩
    | bor fp => right; exact ⟨fp, rfl⟩
  · intro I J t hI hIt hJ x hx
    obtain ⟨n, hAn, hnc, hvn⟩ := ownedArg I hI
    obtain ⟨m, hAm, hmr, hvm⟩ := readArg J .borrowed hJ (by simp) (by simp)
    rw [hvn] at hIt
    rw [hvm] at hx
    have htcs : t ∈ consumedRoots ds i := by
      unfold consumedRoots
      rw [List.mem_filterMap]
      exact ⟨n, hnc, by simp [ownedRoot, hIt]⟩
    exact separate_ok hs hInv hok hcall m hmr x
      ((lend_cells _ _ (fun t' h' => read_root hInv hok hmr h') x).1 hx) t htcs

/-- The arguments of a checked call site meet the callee's `ScalarArgs` (A9). -/
theorem scalarArgs_of_call (hInv : Inv cc args h0 σ ds) (hw : CallWf cc.c g i A) :
    ScalarArgs (mkCC g.1 g.2) (argOf A ds.env) := by
  intro n v hv hst
  have hst' : g.2.state v = .scalar := hst
  unfold argOf
  cases hA : A[n]? with
  | none => rfl
  | some a =>
    obtain ⟨m, b⟩ := a
    have hsm := hw.argScalar n m b v hA hv hst'
    have himm : ds.env m = .imm := imm_of_unmanaged hInv hsm
    cases b <;> simp [himm, lend]

theorem shape_imm_of {ds0 ds : DState} {v : Val} {args' : Nat → Val}
    (h1 : g.1.result ≠ .owned) (h2 : g.1.result ≠ .borrowed) (h : ResultShape g.1 args' ds0 ds v) :
    v = .imm := by
  unfold ResultShape at h
  cases hres : g.1.result <;> rw [hres] at h
  · exact h
  · exact h
  · exact absurd hres h1
  · exact h
  · exact absurd hres h2
  · exact h
  · exact h

/-- The caller's step after a call whose result is not an `emptied` record, from the callee's after-return
condition. -/
theorem effect_of_post_plain (hs : Static cc args h0 pend0) (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A) {d : ValId} (hd : i.dst = some d)
    (he : cc.c.state d ≠ .emptied) {dsr : DState} {v : Val}
    (hpost : Post g.1 (argOf A ds.env)
      { heap := ds.heap, pend := ds.pend, env := g.1.initEnv (argOf A ds.env),
        facts := fun _ => none } dsr v) :
    Effect (Ctx.entering cc.f cc.c args) ds i
      { ds with
        heap := dsr.heap
        pend := pendAfter (Ctx.entering cc.f cc.c args) ds i (resRoot v)
        env := upd ds.env d v
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter (Ctx.entering cc.f cc.c args) ds i (resRoot v) } := by
  have hshape := hpost.shape
  have hnotclosing : i.isClosing = false := by simp [Inst.isClosing, hw.cls]
  have hlnone : i.lent = none := by
    cases hl : i.lent with
    | none => rfl
    | some gv =>
      have := (lend_shape hok.lend hl).1
      rw [hw.cls] at this; cases this
  right
  refine ⟨by simp [hw.cls], resRoot v, ?_, ?_, ?_, rfl, rfl, ?_, rfl, rfl⟩
  · refine ⟨?_, ?_, ?_, ?_, ?_⟩
    · intro x t0 hx ht0
      exact hpost.frame x t0 hx (fun hO => ht0 ((owned_iff_consumed hInv hw t0).2 hO))
    · intro x hx; exact hpost.deadStays x hx
    · intro x t0 hx ht0
      rcases hpost.consumed x t0 hx ((owned_iff_consumed hInv hw t0).1 ht0) with h | ⟨r, hv, hr⟩
      · left; exact h
      · right; exact ⟨r, by rw [hv]; rfl, hr⟩
    · intro x hx
      rcases hpost.created x hx with h | h | ⟨r, hv, hr⟩
      · left; exact h
      · right; left; exact h
      · right; right; exact ⟨r, by rw [hv]; rfl, hr⟩
    · intro r hr
      have hv : v = .own r := by
        cases v <;> simp [resRoot] at hr
        subst hr; rfl
      subst hv
      have hlive : dsr.heap r = .live r := by
        unfold ResultShape at hshape
        cases hres : g.1.result <;> rw [hres] at hshape <;> simp at hshape
        exact hshape.1
      refine ⟨hlive, ?_⟩
      have hf := hpost.fresh r r rfl hlive
      cases hc : ds.heap r with
      | unused => left; rfl
      | dead => exact absurd hc hf.1
      | live t =>
        right
        refine ⟨t, rfl, (owned_iff_consumed hInv hw t).2 ?_⟩
        refine Classical.byContradiction fun hn => hf.2 ⟨t, hc, hn⟩
  · intro hc; rw [hw.cls] at hc; cases hc
  · unfold ResultOk
    rw [hd]
    refine ⟨v, rfl, ?_⟩
    simp only [entering_cert]
    cases hst : cc.c.state d with
    | owned =>
      have hres := hw.resOwned d hd (by simp [CCtx.st, hst, St.owning])
      unfold ResultShape at hshape
      rw [hres] at hshape
      refine ⟨?_, fun hc => absurd hc (by simp [hnotclosing])⟩
      rcases hshape with h | ⟨r, hv, _⟩
      · left; subst h; exact ⟨rfl, rfl⟩
      · right; subst hv; exact ⟨r, rfl, rfl⟩
    | borrowed =>
      obtain ⟨hres, hfrom⟩ := hw.resBor d hd hst
      unfold ResultShape at hshape
      rw [hres] at hshape
      rcases hshape with h | ⟨fp, hv, hal, hcov⟩
      · subst h; exact ⟨rfl, Or.inl rfl⟩
      · subst hv
        refine ⟨rfl, Or.inr ⟨fp, rfl, ?_⟩⟩
        intro x hx
        obtain ⟨I, hI, hxI⟩ := hcov x hx
        obtain ⟨n, hA, hnp⟩ := hfrom I hI
        have hnr : n ∈ i.reads := by
          rw [← hw.rds]
          exact List.mem_map.2 ⟨(n, false), List.mem_filter.2 ⟨List.mem_of_getElem? hA, by simp⟩, rfl⟩
        have hv : argOf A ds.env I = lend (ds.env n) := by simp [argOf, hA]
        rw [hv] at hxI
        -- an argument that holds no tree has no cells, so the parent is only needed for the others
        rcases hnp with hu | hnp
        · exfalso
          rw [imm_of_unmanaged hInv hu] at hxI
          simp [lend, Val.cells] at hxI
        refine ⟨⟨.val n, hnp, ?_, ?_⟩, hal x hx⟩
        · intro n' _
          simp [forwardTakeWith, hw.cls]
        · exact (lend_cells _ _ (fun t' h' => read_root hInv hok hnr h') x).1 hxI
    | scalar =>
      have := hw.resImm d hd (Or.inl hst)
      have hv := shape_imm_of this.1 this.2 hshape
      subst hv; exact ⟨rfl, rfl⟩
    | immortal =>
      have := hw.resImm d hd (Or.inr (Or.inl hst))
      have hv := shape_imm_of this.1 this.2 hshape
      subst hv; exact ⟨rfl, rfl⟩
    | stack => exact absurd hst (hw.noStack d hd)
    | emptied => exact absurd hst he
    | none =>
      have := hw.resImm d hd (Or.inr (Or.inr hst))
      have hv := shape_imm_of this.1 this.2 hshape
      subst hv; exact ⟨rfl, rfl⟩
  · show ds.lent = lentAfter ds i
    funext g x
    apply propext
    simp [lentAfter, hlnone]

/-- The caller's step after a call whose result is an `emptied` record: the callee's result tree is
dissolved (its parts are the fresh trees of the takes that follow), and the destination is an immediate. -/
theorem effect_of_post_emptied (hs : Static cc args h0 pend0) (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A) {d : ValId} (hd : i.dst = some d)
    (he : cc.c.state d = .emptied) {dsr : DState} {v : Val}
    (hpost : Post g.1 (argOf A ds.env)
      { heap := ds.heap, pend := ds.pend, env := g.1.initEnv (argOf A ds.env),
        facts := fun _ => none } dsr v) :
    Effect (Ctx.entering cc.f cc.c args) ds i
      { ds with
        heap := callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v
        pend := pendAfter (Ctx.entering cc.f cc.c args) ds i (resRoot (callVal (Ctx.entering cc.f cc.c args) i v))
        env := upd ds.env d (callVal (Ctx.entering cc.f cc.c args) i v)
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter (Ctx.entering cc.f cc.c args) ds i
          (resRoot (callVal (Ctx.entering cc.f cc.c args) i v)) } := by
  have hres : i.res (Ctx.entering cc.f cc.c args) = .emptied := by
    simp [Inst.res, hd, entering_cert, he]
  have hval : callVal (Ctx.entering cc.f cc.c args) i v = .imm := by simp [callVal, hres]
  have hnotclosing : i.isClosing = false := by simp [Inst.isClosing, hw.cls]
  have hlnone : i.lent = none := by
    cases hl : i.lent with
    | none => rfl
    | some gv =>
      have := (lend_shape hok.lend hl).1
      rw [hw.cls] at this; cases this
  right
  rw [hval]
  refine ⟨by simp [hw.cls], none, ?_, ?_, ?_, rfl, rfl, ?_, rfl, rfl⟩
  · -- the heap: a cell of an owned argument was destroyed or is in the result tree, which `dissolve` destroys;
    -- every other cell keeps its state, since the result tree holds no cell of the caller's other trees (`Post.fresh`)
    have key : ∀ x, (∀ r, v = .own r → dsr.heap x ≠ .live r) →
        callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v x = dsr.heap x := by
      intro x hx
      cases v with
      | own r => simp [callHeap, hres, dissolve, hx r rfl]
      | imm => rfl
      | stk => rfl
      | bor fp => rfl
    have dead_of : ∀ r, v = .own r → ∀ x, dsr.heap x = .live r →
        callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v x = .dead := by
      intro r hr x hx
      subst hr
      simp [callHeap, hres, dissolve, hx]
    have other : ∀ x c, dsr.heap x = c → (∀ r, v = .own r → c ≠ .live r) →
        callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v x = c := by
      intro x c hc hne
      rw [key x (fun r hr => by rw [hc]; exact hne r hr), hc]
    refine ⟨?_, ?_, ?_, ?_, ?_⟩
    · intro x t0 hx ht0
      have hf := hpost.frame x t0 hx (fun hO => ht0 ((owned_iff_consumed hInv hw t0).2 hO))
      refine other x _ hf ?_
      intro r hr hlive
      have hfr := hpost.fresh r x hr (by rw [hf, ← hlive])
      exact hfr.2 ⟨t0, hx, fun hO => ht0 ((owned_iff_consumed hInv hw t0).2 hO)⟩
    · intro x hx
      exact other x _ (hpost.deadStays x hx) (fun r _ => by simp)
    · intro x t0 hx ht0
      rcases hpost.consumed x t0 hx ((owned_iff_consumed hInv hw t0).1 ht0) with h | ⟨r, hv, hr⟩
      · left; exact other x _ h (fun r _ => by simp)
      · left; exact dead_of r hv x hr
    · intro x hx
      rcases hpost.created x hx with h | h | ⟨r, hv, hr⟩
      · left; exact other x _ h (fun r _ => by simp)
      · right; left; exact other x _ h (fun r _ => by simp)
      · right; left; exact dead_of r hv x hr
    · intro r hr; cases hr
  · intro hc; rw [hw.cls] at hc; cases hc
  · unfold ResultOk
    rw [hd]
    refine ⟨.imm, rfl, ?_⟩
    simp [entering_cert, he]
  · show ds.lent = lentAfter ds i
    funext g x
    apply propext
    simp [lentAfter, hlnone]

/-- The caller's step after a call, from the callee's after-return condition (any result state). -/
theorem effect_of_post (hs : Static cc args h0 pend0) (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A) {d : ValId} (hd : i.dst = some d)
    {dsr : DState} {v : Val}
    (hpost : Post g.1 (argOf A ds.env)
      { heap := ds.heap, pend := ds.pend, env := g.1.initEnv (argOf A ds.env),
        facts := fun _ => none } dsr v) :
    Effect (Ctx.entering cc.f cc.c args) ds i
      { ds with
        heap := callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v
        pend := pendAfter (Ctx.entering cc.f cc.c args) ds i (resRoot (callVal (Ctx.entering cc.f cc.c args) i v))
        env := upd ds.env d (callVal (Ctx.entering cc.f cc.c args) i v)
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter (Ctx.entering cc.f cc.c args) ds i
          (resRoot (callVal (Ctx.entering cc.f cc.c args) i v)) } := by
  by_cases he : cc.c.state d = .emptied
  · exact effect_of_post_emptied hs hInv hok hw hd he hpost
  · have hres : i.res (Ctx.entering cc.f cc.c args) ≠ .emptied := by
      simp [Inst.res, hd, entering_cert, he]
    have h1 : callVal (Ctx.entering cc.f cc.c args) i v = v := by simp [callVal, hres]
    have h2 : callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v = dsr.heap := by
      cases v <;> simp [callHeap, hres]
    rw [h1, h2]
    exact effect_of_post_plain hs hInv hok hw hd he hpost

/-- The caller's step after a call without a value (a unit function, `inst - call`): the callee returns an
immediate, and the caller binds nothing. -/
theorem effect_of_post_void (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A) (hd : i.dst = none)
    {dsr : DState} {v : Val}
    (hpost : Post g.1 (argOf A ds.env)
      { heap := ds.heap, pend := ds.pend, env := g.1.initEnv (argOf A ds.env),
        facts := fun _ => none } dsr v) :
    Effect (Ctx.entering cc.f cc.c args) ds i
      { ds with
        heap := dsr.heap
        pend := pendAfter (Ctx.entering cc.f cc.c args) ds i none
        env := ds.env
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter (Ctx.entering cc.f cc.c args) ds i none } := by
  have hv : v = .imm := shape_imm_of (hw.voidRes hd).1 (hw.voidRes hd).2 hpost.shape
  have hlnone : i.lent = none := by
    cases hl : i.lent with
    | none => rfl
    | some gv =>
      have := (lend_shape hok.lend hl).1
      rw [hw.cls] at this; cases this
  right
  refine ⟨by simp [hw.cls], none, ?_, ?_, ?_, rfl, rfl, ?_, rfl, rfl⟩
  · refine ⟨?_, ?_, ?_, ?_, ?_⟩
    · intro x t0 hx ht0
      exact hpost.frame x t0 hx (fun hO => ht0 ((owned_iff_consumed hInv hw t0).2 hO))
    · intro x hx; exact hpost.deadStays x hx
    · intro x t0 hx ht0
      rcases hpost.consumed x t0 hx ((owned_iff_consumed hInv hw t0).1 ht0) with h | ⟨r, hv', _⟩
      · left; exact h
      · rw [hv] at hv'; cases hv'
    · intro x hx
      rcases hpost.created x hx with h | h | ⟨r, hv', _⟩
      · left; exact h
      · right; left; exact h
      · rw [hv] at hv'; cases hv'
    · intro r hr; cases hr
  · intro hc; rw [hw.cls] at hc; cases hc
  · unfold ResultOk
    rw [hd]
    exact ⟨rfl, rfl⟩
  · show ds.lent = lentAfter ds i
    funext g x
    apply propext
    simp [lentAfter, hlnone]

/-- The caller's step after a call, from the callee's after-return condition (any result state), in the shape
`callNext` gives the next configuration. -/
theorem effect_of_post_next (hs : Static cc args h0 pend0) (hInv : Inv cc args h0 σ ds)
    (hok : InstOk cc σ i) (hw : CallWf cc.c g i A)
    {dsr : DState} {v : Val}
    (hpost : Post g.1 (argOf A ds.env)
      { heap := ds.heap, pend := ds.pend, env := g.1.initEnv (argOf A ds.env),
        facts := fun _ => none } dsr v) :
    Effect (Ctx.entering cc.f cc.c args) ds i
      { ds with
        heap := callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v
        pend := pendAfter (Ctx.entering cc.f cc.c args) ds i (resRoot (callVal (Ctx.entering cc.f cc.c args) i v))
        env := match i.dst with
          | some d => upd ds.env d (callVal (Ctx.entering cc.f cc.c args) i v)
          | none => ds.env
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter (Ctx.entering cc.f cc.c args) ds i
          (resRoot (callVal (Ctx.entering cc.f cc.c args) i v)) } := by
  cases hd : i.dst with
  | some d =>
    have h := effect_of_post hs hInv hok hw hd hpost
    simp only [hd] at h ⊢
    exact h
  | none =>
    have hv : v = .imm := shape_imm_of (hw.voidRes hd).1 (hw.voidRes hd).2 hpost.shape
    have hres : i.res (Ctx.entering cc.f cc.c args) ≠ .emptied := by
      simp [Inst.res, hd]
    have h1 : callVal (Ctx.entering cc.f cc.c args) i v = .imm := by simp [callVal, hres, hv]
    have h2 : callHeap (Ctx.entering cc.f cc.c args) i dsr.heap v = dsr.heap := by
      simp [callHeap, hv]
    have h := effect_of_post_void hInv hok hw hd hpost
    simp only [hd, h1, h2, resRoot] at h ⊢
    exact h

end Own
