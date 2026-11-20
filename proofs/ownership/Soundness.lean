import StaticFacts
import Abandon

/-!
# Soundness of the checker (design §6)

**Theorem** (`check_sound`).  If `check f c = true` and the arguments meet the before-the-call
condition `Pre`, then every execution of `f` never faults, and every normal return meets the
after-return condition `Post`.

The proof maintains, along every execution, the invariant `Inv` of `Invariant.lean` between
the machine state and the checker's abstract state at the same program point:
* one instruction (`inst_step` in `InstPres.lean`),
* one edge: the owners the edge abandons leave `L` (`abandon_inv` in `Abandon.lean`), then the phis take their
  operands (`edge_inv` in `EdgeStep.lean`), after the branch decided its test (`inv_withFact` in `SoundFacts.lean`),
* a `ret` (`ret_none_facts`, `ret_some_facts` in `SoundRet.lean`).

Every block is an ordinary block.  A path that ends in a trap leaks the owners it does not drop, and says so with
`abandon` lines (C9.1, design entry 55): the owners leave `L` while their trees stay in the heap, so `acct` has the
disjunct "abandoned" (`DState.abandoned`).  Only an edge into a block of the trap region abandons, the region is closed
under successors and never returns, so a `ret` is reached with nothing abandoned (`Good`), and the after-return
condition, which says nothing is leaked, is proved there.
-/

namespace Own

variable {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}

theorem compatErr_none {inn : BlockId → Option AbsState} {s : BlockId} {σe : AbsState}
    (h : compatErr inn s σe = none) :
    ∃ σs, inn s = some σs ∧ same σs.L σe.L = true ∧
      slotsFit σs σe = true ∧ factsFit σs σe = true ∧ sub σs.D σe.D = true ∧
      ((σs.D ++ σs.L).all fun w => sub (Rget σe w) (Rget σs w)) = true := by
  unfold compatErr at h
  cases hs : inn s with
  | none => rw [hs] at h; simp at h
  | some σs =>
    rw [hs] at h
    refine ⟨σs, rfl, ?_⟩
    unfold joinCompat at h
    by_cases h1 : same σs.L σe.L = true
    · by_cases h2 : slotsFit σs σe = true
      · by_cases h3 : factsFit σs σe = true
        · by_cases h4 : sub σs.D σe.D = true
          · by_cases h5 : ((σs.D ++ σs.L).all fun w => sub (Rget σe w) (Rget σs w)) = true
            · exact ⟨h1, h2, h3, h4, h5⟩
            · simp [h1, h2, h3, h4, h5] at h
          · simp [h1, h2, h3, h4] at h
        · simp [h1, h2, h3] at h
      · simp [h1, h2] at h
    · simp [h1] at h

/-! ## The trap region -/

theorem regionIn_mono (cc : CCtx) : ∀ (k : Nat) (b : BlockId), regionIn cc k b = true →
    regionIn cc (k + 1) b = true := by
  intro k
  induction k with
  | zero => intro b h; simp [regionIn] at h
  | succ k ih =>
    intro b h
    unfold regionIn at h ⊢
    cases hb : cc.f.block? b with
    | none => rw [hb] at h; simp at h
    | some blk =>
      rw [hb] at h
      simp only at h ⊢
      cases ht : blk.term with
      | unreachable => simp
      | jump s =>
        rw [ht] at h
        simp only [Term.succs, List.isEmpty_cons, Bool.not_false, Bool.true_and, List.all_cons,
          List.all_nil, Bool.and_true] at h ⊢
        exact ih s h
      | branch c t f =>
        rw [ht] at h
        simp only [Term.succs, List.isEmpty_cons, Bool.not_false, Bool.true_and, List.all_cons,
          List.all_nil, Bool.and_true, Bool.and_eq_true] at h ⊢
        exact ⟨ih t h.1, ih f h.2⟩
      | ret v =>
        rw [ht] at h
        simp [Term.succs] at h

/-- A block of the trap region has only successors in the region. -/
theorem region_succ {b : BlockId} {blk : Block} (hb : cc.f.block? b = some blk)
    (h : region cc b = true) : ∀ s ∈ blk.term.succs, region cc s = true := by
  intro s hs
  unfold region at h ⊢
  unfold regionIn at h
  rw [hb] at h
  simp only at h
  cases ht : blk.term with
  | unreachable => rw [ht] at hs; simp [Term.succs] at hs
  | jump s' =>
    rw [ht] at h hs
    simp only [Term.succs, List.mem_singleton] at hs h
    subst hs
    simp only [List.isEmpty_cons, Bool.not_false, Bool.true_and, List.all_cons, List.all_nil,
      Bool.and_true] at h
    exact regionIn_mono cc _ _ h
  | branch c t f =>
    rw [ht] at h hs
    simp only [Term.succs, List.mem_cons, List.not_mem_nil, or_false] at hs
    simp only [Term.succs, List.isEmpty_cons, Bool.not_false, Bool.true_and, List.all_cons, List.all_nil,
      Bool.and_true, Bool.and_eq_true] at h
    rcases hs with rfl | rfl
    · exact regionIn_mono cc _ _ h.1
    · exact regionIn_mono cc _ _ h.2
  | ret v => rw [ht] at h; simp [Term.succs] at h

/-- A block that returns is not in the trap region: every path from the region ends in a trap. -/
theorem region_false_of_ret {b : BlockId} {blk : Block} (hb : cc.f.block? b = some blk) {v : Option ValId}
    (ht : blk.term = .ret v) : region cc b = false := by
  unfold region regionIn
  rw [hb]
  simp only
  rw [ht]
  simp [Term.succs]

theorem targets_succs {σ σ1 : AbsState} {t : Term} {b' : BlockId}
    (h : (b', σ1) ∈ t.targets cc σ) : b' ∈ t.succs := by
  cases t with
  | jump s => simp only [Term.targets, List.mem_singleton, Prod.mk.injEq] at h; simp [Term.succs, h.1]
  | ret v => simp [Term.targets] at h
  | unreachable => simp [Term.targets] at h
  | branch c t f =>
    unfold Term.targets at h
    by_cases htf : (t == f) = true
    · simp only [htf, ↓reduceIte, List.mem_cons, Prod.mk.injEq, List.not_mem_nil, or_false] at h
      simp only [Term.succs, List.mem_cons, List.not_mem_nil, or_false]
      rcases h with ⟨h, _⟩ | ⟨h, _⟩ <;> simp [h]
    · simp only [htf, Bool.false_eq_true, ↓reduceIte, List.mem_append] at h
      simp only [Term.succs, List.mem_cons, List.not_mem_nil, or_false]
      rcases h with h | h
      · cases hw : withFact cc σ c true with
        | none => rw [hw] at h; simp at h
        | some s => rw [hw] at h; simp at h; simp [h.1]
      · cases hw : withFact cc σ c false with
        | none => rw [hw] at h; simp at h
        | some s => rw [hw] at h; simp at h; simp [h.1]

/-- The reachability invariant over configurations: at every point of a block the checker's state matches the
machine state, the rest of the block and its terminator pass, and nothing is abandoned unless the block is in the
trap region. -/
def Good (cc : CCtx) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (inn : BlockId → Option AbsState) : Config → Prop
  | .run b k ds => ∀ blk, cc.f.block? b = some blk →
      (region cc b = false → ∀ t, ¬ ds.abandoned t) ∧
      ∃ σ σo, k ≤ blk.insts.length ∧ Inv cc args h0 σ ds ∧
        RunGood cc σ (blk.insts.drop k) σo ∧ TermGood cc inn b blk σo
  | .ret ds v => Post cc.f args (entryDState cc.f args h0 pend0) ds v
  | .trap => True
  | .fault _ => False

/-- The invariant a checked edge hands to the target block: the edge abandons the owners the target's line for
this edge names, and the phis take their operands; the result fits the entry state recorded for the target. -/
theorem edge_facts (hs : Static cc args h0 pend0) {inn : BlockId → Option AbsState}
    {b b' : BlockId} {blk blk' : Block} {ds1 : DState} {σ σ1 : AbsState}
    (hI1 : Inv cc args h0 σ1 ds1) (hterm : TermGood cc inn b blk σ)
    (hmem : (b', σ1) ∈ blk.term.targets cc σ) (hblk' : cc.f.block? b' = some blk')
    (hops : ∀ φ ∈ blk'.phis, Phi.live cc.c φ = true → ∃ o, φ.edges.lookup b = some o) :
    EC cc args h0 pend0 (σ1.abandon (blk'.abandonFrom b)) b blk' (abandonNext ds1 (blk'.abandonFrom b)) ∧
      (blk'.abandonFrom b ≠ [] → region cc b' = true) ∧
      ∃ σs, inn b' = some σs ∧
        Inv cc args h0 σs ((abandonNext ds1 (blk'.abandonFrom b)).enter cc.c blk'.phis b) := by
  obtain ⟨es, hes, hcompat⟩ := hterm.edges
  unfold liveEdges at hes
  obtain ⟨r, hr, hmem'⟩ := liveEdgesOf_edge _ es hes (b', σ1) hmem
  obtain ⟨hr1, hab, hreg, hok⟩ := edgeTo_live hblk' hr
  have hbm : blk' ∈ cc.f.blocks := Function.block?_mem hblk'
  have hIab := abandon_inv hI1 hab
  have ec : EC cc args h0 pend0 (σ1.abandon (blk'.abandonFrom b)) b blk' (abandonNext ds1 (blk'.abandonFrom b)) :=
    ⟨hs, hIab, hok, hbm, hops⟩
  refine ⟨ec, hreg, ?_⟩
  have hc := hcompat (b', edgeNext cc (σ1.abandon (blk'.abandonFrom b)) b blk'.phis) (hmem' _ hr1)
  obtain ⟨σs, hin, hL, hS, hF, hD, hR⟩ := compatErr_none hc
  exact ⟨σs, hin, (edge_inv ec).conv hL hS hF hD hR⟩

theorem key_eq (hs : Static cc args h0 pend0) (c : ValId) :
    (Ctx.entering cc.f cc.c args).key c = cc.keyOf c := by
  unfold Ctx.key CCtx.keyOf
  have : (fun x => cc.defOf[x]?) = cc.f.defOf? := funext hs.defEq
  rw [this]
  rfl

/-- The state a branch edge carries: the test the condition stands for is decided. -/
theorem branch_edge (hs : Static cc args h0 pend0) {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) {blk : Block} {c : ValId} {t f b' : BlockId}
    (hterm' : blk.term = .branch c t f) (hbt : b' = t ∨ b' = f)
    (hcons : t ≠ f → ds.facts ((Ctx.entering cc.f cc.c args).key c) = none ∨
      ds.facts ((Ctx.entering cc.f cc.c args).key c) = some (decide (b' = t))) :
    ∃ σ1, Inv cc args h0 σ1
        { ds with facts := if t = f then ds.facts else
            setFact ds.facts ((Ctx.entering cc.f cc.c args).key c) (decide (b' = t)) } ∧
      (b', σ1) ∈ blk.term.targets cc σ := by
  by_cases htf : t = f
  · subst htf
    refine ⟨σ, ?_, ?_⟩
    · simpa using hI
    · rw [hterm']
      simp only [Term.targets, ↓reduceIte]
      rcases hbt with rfl | rfl <;> simp
  · rw [key_eq hs] at hcons ⊢
    have hc' := hcons htf
    have hkey : cc.keyOf c = cc.keyOf c := rfl
    -- the polarity of the edge
    have hpol : ∃ pol, pol = decide (b' = t) := ⟨_, rfl⟩
    obtain ⟨pol, hpol⟩ := hpol
    have hsome : ∃ σ1, withFact cc σ c pol = some σ1 := by
      unfold withFact
      dsimp only
      cases hf : σ.F.find? (·.1 == cc.keyOf c) with
      | none => exact ⟨_, rfl⟩
      | some e =>
        obtain ⟨k0, po⟩ := e
        cases po with
        | none => exact ⟨_, rfl⟩
        | some p =>
          by_cases hpp : p == pol
          · exact ⟨σ, by simp [hpp]⟩
          · exfalso
            have hmem : (k0, some p) ∈ σ.F := List.mem_of_find?_eq_some hf
            have hk0 : k0 = cc.keyOf c := by simpa using List.find?_some hf
            obtain ⟨hdec, hfp⟩ := hI.Fin (k0, some p) hmem
            have hfp' : ds.facts (cc.keyOf c) = some p := by rw [← hk0]; exact hfp p rfl
            rw [hfp'] at hc'
            rcases hc' with h | h
            · cases h
            · have : p = decide (b' = t) := Option.some.inj h
              apply hpp
              rw [hpol, this]; simp
    obtain ⟨σ1, hσ1⟩ := hsome
    have hcons' : ds.facts (cc.keyOf c) = none ∨ ds.facts (cc.keyOf c) = some pol := by
      rw [hpol]; exact hc'
    refine ⟨σ1, ?_, ?_⟩
    · have := inv_withFact hI hσ1 hcons'
      simpa [htf, hpol] using this
    · rw [hterm']
      have htf' : (t == f) = false := by simpa using htf
      simp only [Term.targets, htf', Bool.false_eq_true, ↓reduceIte]
      rcases hbt with rfl | rfl
      · have : pol = true := by rw [hpol]; simp
        subst this
        simp [hσ1]
      · have : pol = false := by rw [hpol]; simpa [Ne.symm htf] using Ne.symm htf
        subst this
        simp [hσ1]

theorem good_edge (hs : Static cc args h0 pend0) {inn : BlockId → Option AbsState}
    (hver : ∀ b, b < cc.f.blocks.length → verifyBlock cc inn b = none)
    {b b' : BlockId} {blk blk' : Block} {σ σ1 : AbsState} {ds1 : DState}
    (hI1 : Inv cc args h0 σ1 ds1) (hterm : TermGood cc inn b blk σ)
    (hmem : (b', σ1) ∈ blk.term.targets cc σ) (hblk : cc.f.block? b = some blk)
    (hblk' : cc.f.block? b' = some blk') (hdef : EdgeDefined cc.c blk'.phis b)
    (hab : region cc b = false → ∀ t, ¬ ds1.abandoned t) :
    Good cc args h0 pend0 inn (.run b' 0 ((abandonNext ds1 (blk'.abandonFrom b)).enter cc.c blk'.phis b)) ∧
      ∀ o ∈ incoming cc.c blk'.phis b, (ds1.env o).alive ds1.heap := by
  obtain ⟨ec, hreg, σs, hin, hInv⟩ := edge_facts hs hI1 hterm hmem hblk' hdef
  refine ⟨?_, fun o ho => edge_alive ec o ho⟩
  intro blk2 hblk2
  rw [hblk'] at hblk2; cases hblk2
  have hbl : b' < cc.f.blocks.length := Function.block?_lt hblk'
  obtain ⟨σo', hrun', hterm''⟩ := verifyBlock_good (hver b' hbl) hin hblk'
  refine ⟨?_, σs, σo', Nat.zero_le _, hInv, by simpa using hrun', hterm''⟩
  -- nothing is abandoned unless the target is in the trap region
  intro hnr t ht
  have hA : blk'.abandonFrom b = [] :=
    Classical.byContradiction fun hne => by rw [hreg hne] at hnr; cases hnr
  have hb : region cc b = false := by
    cases hb : region cc b with
    | false => rfl
    | true => rw [region_succ hblk hb b' (targets_succs hmem)] at hnr; cases hnr
  have ht' : ds1.abandoned t ∨ t ∈ abandonedRoots ds1 (blk'.abandonFrom b) := ht
  rw [hA] at ht'
  rcases ht' with h | h
  · exact hab hb t h
  · simp [abandonedRoots] at h

/-- A block that is running with a terminator: no instruction is left. -/
theorem good_at_term {inn : BlockId → Option AbsState} {b : BlockId} {blk : Block}
    {ds : DState} (hblk : cc.f.block? b = some blk)
    (hc : Good cc args h0 pend0 inn (.run b blk.insts.length ds)) :
    ∃ σ, Inv cc args h0 σ ds ∧ TermGood cc inn b blk σ ∧ (region cc b = false → ∀ t, ¬ ds.abandoned t) := by
  obtain ⟨hab, σ, σo, hk, hI, hrun, hterm'⟩ := hc blk hblk
  rw [List.drop_of_length_le (Nat.le_refl _)] at hrun
  have hσ : σo = σ := hrun.nil_inv
  subst hσ
  exact ⟨σo, hI, hterm', hab⟩

/-- An instruction step leaves the abandoned trees alone. -/
theorem effect_abandoned {ctx : Ctx} {ds ds' : DState} {i : Inst}
    (hE : Effect ctx ds i ds') : ds'.abandoned = ds.abandoned := by
  rcases hE with ⟨_, rfl⟩ | ⟨_, r, _, _, _, _, _, _, _, hab⟩
  · rfl
  · exact hab

theorem good_step (hs : Static cc args h0 pend0) {inn : BlockId → Option AbsState}
    (hver : ∀ b, b < cc.f.blocks.length → verifyBlock cc inn b = none)
    {c c' : Config} (hc : Good cc args h0 pend0 inn c)
    (hst : Step (Ctx.entering cc.f cc.c args) c c') : Good cc args h0 pend0 inn c' := by
  cases hst with
  | inst hat hg hE =>
    rename_i b k i ds ds'
    simp only [entering_fn, Function.instAt, Option.bind_eq_some_iff] at hat
    obtain ⟨blk, hblk, hik⟩ := hat
    obtain ⟨hab, σ, σo, hk, hI, hrun, hterm⟩ := hc blk hblk
    have hlt : k < blk.insts.length := (List.getElem?_eq_some_iff.1 hik).1
    have hdrop : blk.insts.drop k = i :: blk.insts.drop (k + 1) := by
      rw [List.drop_eq_getElem_cons hlt]
      have : blk.insts[k] = i := by simpa [List.getElem?_eq_getElem hlt] using hik
      rw [this]
    rw [hdrop] at hrun
    obtain ⟨hfail, hrun'⟩ := hrun.cons_inv
    have hok := instOk_of_fail_none hfail
    have hbm : blk ∈ cc.f.blocks := Function.block?_mem hblk
    have hmem := mem_allInsts_of_block cc.f blk i hbm (List.mem_of_getElem? hik)
    intro blk2 hblk2
    rw [hblk] at hblk2
    cases hblk2
    refine ⟨fun hr t ht => hab hr t (by rw [← effect_abandoned hE]; exact ht), instNext cc σ i, σo, hlt,
      inst_step hs hI hok hmem hE, hrun', hterm⟩
  | instFault f hat hv =>
    rename_i b k i ds
    exfalso
    simp only [entering_fn, Function.instAt, Option.bind_eq_some_iff] at hat
    obtain ⟨blk, hblk, hik⟩ := hat
    obtain ⟨_, σ, σo, hk, hI, hrun, hterm⟩ := hc blk hblk
    have hlt : k < blk.insts.length := (List.getElem?_eq_some_iff.1 hik).1
    have hdrop : blk.insts.drop k = i :: blk.insts.drop (k + 1) := by
      rw [List.drop_eq_getElem_cons hlt]
      have : blk.insts[k] = i := by simpa [List.getElem?_eq_getElem hlt] using hik
      rw [this]
    rw [hdrop] at hrun
    obtain ⟨hfail, _⟩ := hrun.cons_inv
    exact inst_no_fault hs hI (instOk_of_fail_none hfail) f hv
  | instTrap hat => trivial
  | jump hb hterm' hb' hdef halive =>
    rename_i b blk blk' b' ds
    simp only [entering_fn] at hb hb'
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    have hmem : (b', σ) ∈ blk.term.targets cc σ := by simp [hterm', Term.targets]
    exact (good_edge hs hver hI hterm hmem hb hb' hdef hab).1
  | jumpFault hb hterm' hb' hdef hbad =>
    rename_i b blk blk' b' ds
    exfalso
    simp only [entering_fn] at hb hb'
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    have hmem : (b', σ) ∈ blk.term.targets cc σ := by simp [hterm', Term.targets]
    obtain ⟨o, ho, hna⟩ := hbad
    exact hna ((good_edge hs hver hI hterm hmem hb hb' hdef hab).2 o ho)
  | branch hb hterm' hbt hb' hcons hdef hcond halive =>
    rename_i b blk blk' c t f b' ds
    simp only [entering_fn] at hb hb'
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    obtain ⟨σ1, hI1, hmem⟩ := branch_edge hs hI hterm' hbt hcons
    exact (good_edge hs hver hI1 hterm hmem hb hb' hdef hab).1
  | branchFault hb hterm' hna =>
    rename_i b blk c t f ds
    exfalso
    simp only [entering_fn] at hb
    obtain ⟨σ, hI, hterm, _⟩ := good_at_term hb hc
    have hchk := hterm.chk
    rw [hterm'] at hchk
    have h1 := hchk (.j3, "branch-usable", cc.st c == .borrowed || usable cc σ c)
      (by simp [termChecks])
    have h2 := hchk (.j4, "branch-borrowed-usable", cc.st c != .borrowed || usable cc σ c)
      (by simp [termChecks])
    apply hna
    by_cases hb' : cc.st c = .borrowed
    · exact usable_alive hs hI (by simpa [hb'] using h2)
    · exact usable_alive hs hI (by simpa [hb'] using h1)
  | branchPhiFault hb hterm' hbt hb' hcons hdef hbad =>
    rename_i b blk blk' c t f b' ds
    exfalso
    simp only [entering_fn] at hb hb'
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    obtain ⟨σ1, hI1, hmem⟩ := branch_edge hs hI hterm' hbt hcons
    obtain ⟨o, ho, hna⟩ := hbad
    exact hna ((good_edge hs hver hI1 hterm hmem hb hb' hdef hab).2 o ho)
  | retNone hb hterm' =>
    rename_i b blk ds
    simp only [entering_fn] at hb
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    have hchk := hterm.chk
    rw [hterm'] at hchk
    exact ret_none_facts hs hI (hab (region_false_of_ret hb hterm')) hchk
  | retVal hb hterm' halive _ =>
    rename_i b blk v ds
    simp only [entering_fn] at hb
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    have hchk := hterm.chk
    rw [hterm'] at hchk
    exact (ret_some_facts hs hI (hab (region_false_of_ret hb hterm')) hchk).2
  | retFault hb hterm' hna =>
    rename_i b blk v ds
    exfalso
    simp only [entering_fn] at hb
    obtain ⟨σ, hI, hterm, hab⟩ := good_at_term hb hc
    have hchk := hterm.chk
    rw [hterm'] at hchk
    exact hna (ret_some_facts hs hI (hab (region_false_of_ret hb hterm')) hchk).1
  | retEscape hb hterm' hstk =>
    rename_i b blk v ds
    exfalso
    simp only [entering_fn] at hb
    obtain ⟨σ, hI, hterm, _⟩ := good_at_term hb hc
    have hchk := hterm.chk
    rw [hterm'] at hchk
    have hsk : cc.st v = .stack :=
      Classical.byContradiction fun hne => hI.nostk v hne hstk
    have := hchk (.j7, "ret-stack", cc.st v != .stack) (by
      unfold termChecks; cases cc.f.result <;> simp)
    simp [hsk] at this
  | unreachable hb hterm' => trivial

theorem good_star (hs : Static cc args h0 pend0) {inn : BlockId → Option AbsState}
    (hver : ∀ b, b < cc.f.blocks.length → verifyBlock cc inn b = none)
    {c c' : Config} (hc : Good cc args h0 pend0 inn c)
    (hst : Star (Ctx.entering cc.f cc.c args) c c') : Good cc args h0 pend0 inn c' := by
  induction hst with
  | refl => exact hc
  | step h _ ih => exact ih (good_step hs hver hc h)

theorem verifyBlocks_forall {inn : BlockId → Option AbsState} :
    ∀ (l : List BlockId), verifyBlocks cc inn l = none → ∀ b ∈ l, verifyBlock cc inn b = none := by
  intro l
  induction l with
  | nil => intro _ b hb; simp at hb
  | cons x xs ih =>
    intro h b hb
    simp only [verifyBlocks] at h
    cases hx : verifyBlock cc inn x with
    | some fl => rw [hx] at h; simp at h
    | none =>
      rw [hx] at h
      simp only at h
      rcases List.mem_cons.1 hb with rfl | hb'
      · exact hx
      · exact ih h b hb'

/-- What `check f c = true` says: the three phases of the verdict passed. -/
theorem check_spec {f : Function} {c : Certificate} (h : check f c = true) :
    (∀ p ∈ preChecks (mkCC f c), p.2.2 = true) ∧
    compatErr (solve (mkCC f c)) 0 (entryState (mkCC f c)) = none ∧
    verifyBlocks (mkCC f c) (solve (mkCC f c)) (List.range f.blocks.length) = none := by
  unfold check verdict at h
  dsimp only at h
  simp only [solve]
  cases hp : firstFail (preChecks (mkCC f c)) with
  | some jw => rw [hp] at h; simp at h
  | none =>
    rw [hp] at h
    simp only at h
    refine ⟨chk_all hp, ?_⟩
    cases hsh : abandonShapeBad (mkCC f c) with
    | some b => rw [hsh] at h; simp at h
    | none =>
      rw [hsh] at h
      simp only at h
      cases he : compatErr (solveFn (solveArr (mkCC f c))) 0 (entryState (mkCC f c)) with
      | some j => rw [he] at h; simp at h
      | none =>
        rw [he] at h
        simp only at h
        refine ⟨rfl, ?_⟩
        cases hv : verifyBlocks (mkCC f c) (solveFn (solveArr (mkCC f c))) (List.range f.blocks.length) with
        | some fl => rw [hv] at h; simp at h
        | none => rfl

theorem static_of_checks {f : Function} {c : Certificate} {args : Nat → Val} {h0 : Heap}
    {pend0 : Addr → String → Bool} (hpre : Pre f args h0 pend0)
    (h : ∀ p ∈ preChecks (mkCC f c), p.2.2 = true) :
    Static (mkCC f c) args h0 pend0 := by
  simp only [preChecks, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq] at h
  obtain ⟨hl, hp, hn, _, _, hd, _, _⟩ := h
  have hnd : (f.allInsts.filterMap (·.dst)).Nodup := by
    have := (nodupB_iff _).1 hd
    exact this.sublist (List.sublist_append_left _ _)
  exact ⟨hpre, by simpa using hl, hp, (nodupB_iff _).1 hn, mkCC_defEq f c hnd⟩

/-- What a checked function gives at entry: the static facts, the verified blocks, and the
reachability invariant at the entry configuration. -/
theorem check_start (f : Function) (c : Certificate) (h : check f c = true)
    (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool) (hpre : Pre f args h0 pend0)
    (hsc : ScalarArgs (mkCC f c) args) :
    Static (mkCC f c) args h0 pend0 ∧
    (∀ b, b < (mkCC f c).f.blocks.length → verifyBlock (mkCC f c) (solve (mkCC f c)) b = none) ∧
    Good (mkCC f c) args h0 pend0 (solve (mkCC f c)) (f.entry args h0 pend0) := by
  obtain ⟨hpc, hentry, hverall⟩ := check_spec h
  have hs := static_of_checks (c := c) hpre hpc
  have hver : ∀ b, b < (mkCC f c).f.blocks.length →
      verifyBlock (mkCC f c) (solve (mkCC f c)) b = none := fun b hb =>
    verifyBlocks_forall _ hverall b (List.mem_range.2 hb)
  refine ⟨hs, hver, ?_⟩
  intro blk hblk
  have hbl : 0 < (mkCC f c).f.blocks.length := Function.block?_lt hblk
  have hver0 := hver 0 hbl
  obtain ⟨σs, hin, hL, hS, hF, hD, hR⟩ := compatErr_none hentry
  obtain ⟨σo, hrun, hterm⟩ := verifyBlock_good hver0 hin hblk
  exact ⟨fun _ t h => h, σs, σo, Nat.zero_le _,
    (inv_entry (mkCC f c) args h0 pend0 hs hsc).conv hL hS hF hD hR, by simpa using hrun, hterm⟩

/-- **Soundness of the checker** (design §6, per function).  If `check f c = true`, then from
any state meeting the before-the-call condition no execution of `f` faults, and every normal
return meets the after-return condition. -/
theorem check_sound (f : Function) (c : Certificate) (h : check f c = true)
    (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool) (hpre : Pre f args h0 pend0)
    (hsc : ScalarArgs (mkCC f c) args) : Safe f c args h0 pend0 := by
  obtain ⟨hs, hver, hgood⟩ := check_start f c h args h0 pend0 hpre hsc
  intro c' hstar
  have := good_star hs hver hgood hstar
  cases c' with
  | run b k ds => exact ⟨by simp [Config.isFault], by intro ds v h; cases h⟩
  | ret ds v => exact ⟨by simp [Config.isFault], fun ds' v' h => by cases h; exact this⟩
  | trap => exact ⟨by simp [Config.isFault], by intro ds v h; cases h⟩
  | fault k => exact this.elim

end Own

#print axioms Own.check_sound
