import Facts.Avail

/-!
# Static facts about refining edges and definitions

What the structure of a function gives, before any execution: the shape of a refining edge, and where the operands
of its comparison are defined.
-/

set_option linter.unusedSimpArgs false

namespace Facts

section Refining
variable {c : Ctx}

/-- The shape of a refining edge into `x`: `x` has the single predecessor `e.source`, which ends in a two-way branch on
the comparison. -/
theorem refining_spec {x : Nat} {e : Edge} (h : refining c x = some e) :
    ∃ (blk pb : Block) (cond t el : Nat), c.f.blocks[x]? = some blk ∧ blk.preds = [e.source] ∧
      c.f.blocks[e.source]? = some pb ∧ pb.term = .branch cond t el ∧ (c.def_ cond).inst = some e.cmp ∧
      (c.def_ cond).kind ≠ .phi ∧ e.cmp.op = .cmp ∧ e.taken = (t == x) ∧ t ≠ el := by
  unfold refining at h
  cases hb : c.f.blocks[x]? with
  | none => simp [hb] at h
  | some blk =>
    simp only [hb] at h
    cases hp : blk.preds with
    | nil => simp [hp] at h
    | cons p rest =>
      cases rest with
      | cons _ _ => simp [hp] at h
      | nil =>
        simp only [hp] at h
        cases hpb : c.f.blocks[p]? with
        | none => simp [hpb] at h
        | some pb =>
          simp only [hpb] at h
          cases ht : pb.term with
          | jump _ => simp [ht] at h
          | ret _ => simp [ht] at h
          | unreachable => simp [ht] at h
          | branch cond t el =>
            simp only [ht] at h
            by_cases hte : (t == el) = true
            · simp [hte] at h
            · simp only [hte, ite_false] at h
              cases hi : (c.def_ cond).inst with
              | none => simp [hi] at h
              | some i =>
                simp only [hi] at h
                by_cases hc : ((c.def_ cond).kind == Kind.phi || i.op != Op.cmp) = true
                · simp [hc] at h
                · simp only [hc, Bool.false_eq_true, ite_false, Option.some.injEq] at h
                  subst h
                  simp only [Bool.or_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, not_or, Decidable.not_not] at hc
                  refine ⟨blk, pb, cond, t, el, rfl, hp, hpb, ht, hi, hc.1, hc.2, rfl, ?_⟩
                  intro heq
                  exact hte (by simp [heq])

end Refining

section Defs
variable {c : Ctx}

theorem CtxOK.def_missing (hc : CtxOK c) {v : Nat} (hk : (c.def_ v).kind = .missing) : c.def_ v = {} := by
  cases hv : c.defs[v]? with
  | none => simp [Ctx.def_, hv]
  | some d =>
    have h1 : c.def_ v = d := by simp [Ctx.def_, hv]
    rw [h1] at hk ⊢
    exact defItemOK_missing hk (defsOK_conv hc.defs hv)

theorem CtxOK.kind_of_inst (hc : CtxOK c) {v : Nat} {i : Inst} (h : (c.def_ v).inst = some i) :
    (c.def_ v).kind ≠ .missing := by
  intro hk
  rw [hc.def_missing hk] at h
  simp at h

theorem CtxOK.pre_of_def (hc : CtxOK c) {v : Nat} (hk : (c.def_ v).kind = .pre) :
    ∃ i, i ∈ c.f.pre ∧ (c.def_ v).inst = some i ∧ i.value = v := by
  have hd : c.defs[v]? = some (c.def_ v) := by
    cases hv : c.defs[v]? with
    | none => rw [Ctx.def_, hv] at hk; simp [Def.kind] at hk
    | some d => simp [Ctx.def_, hv]
  obtain ⟨i, hi, hv, hinst, _⟩ := defItemOK_pre hk (defsOK_conv hc.defs hd)
  exact ⟨i, List.mem_of_getElem? hi, hinst, hv⟩

theorem CtxOK.pre_block (hc : CtxOK c) {v : Nat} (hk : (c.def_ v).kind = .pre) : (c.def_ v).block = none := by
  have hd : c.defs[v]? = some (c.def_ v) := by
    cases hv : c.defs[v]? with
    | none => rw [Ctx.def_, hv] at hk; simp [Def.kind] at hk
    | some d => simp [Ctx.def_, hv]
  obtain ⟨i, _, _, _, hb⟩ := defItemOK_pre hk (defsOK_conv hc.defs hd)
  exact hb

/-- The constants and parameters take no register operands, and are constants, parameters or unmodelled operations. -/
theorem CtxOK.pre_op (hc : CtxOK c) {i : Inst} (h : i ∈ c.f.pre) :
    (i.op = .iconst ∨ i.op = .param ∨ i.op.isFree = true) ∧ i.operands.a = none ∧ i.operands.b = none ∧
      i.operands.x = [] := by
  have := hc.pre
  unfold preOK at this
  simp only [List.all_eq_true, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, Option.isNone_iff_eq_none,
    List.isEmpty_iff] at this
  obtain ⟨⟨⟨ho, ha⟩, hb⟩, hx⟩ := (this i h)
  exact ⟨by rcases ho with (h1 | h1) | h1 <;> simp [h1], ha, hb, hx⟩

/-- The instruction that defines a value, if it is not a phi, has that value. -/
theorem CtxOK.value_of_inst (hc : CtxOK c) {w : Nat} {j : Inst} (hj : (c.def_ w).inst = some j)
    (hnp : (c.def_ w).kind ≠ .phi) : j.value = w := by
  cases hk : (c.def_ w).kind with
  | missing => exact absurd hk (hc.kind_of_inst hj)
  | phi => exact absurd hk hnp
  | pre =>
    obtain ⟨i, _, hinst, hv⟩ := hc.pre_of_def hk
    rw [hj] at hinst
    cases hinst
    exact hv
  | inst =>
    obtain ⟨D, b, i, _, _, _, hv, hinst⟩ := hc.inst_of_def hk
    rw [hj] at hinst
    cases hinst
    exact hv

/-- The phis of a block define distinct values. -/
theorem CtxOK.phi_values_nodup (hc : CtxOK c) {y : Nat} {tb : Block} (hb : c.f.blocks[y]? = some tb) :
    (tb.phis.map (·.value)).Nodup := by
  show List.Pairwise (fun a b => a ≠ b) (tb.phis.map (·.value))
  rw [List.pairwise_iff_getElem]
  intro i j hi hj hij
  simp only [List.length_map] at hi hj
  simp only [List.getElem_map]
  intro heq
  have h1 := hc.def_phi hb (List.getElem?_eq_getElem hi)
  have h2 := hc.def_phi hb (List.getElem?_eq_getElem hj)
  rw [heq] at h1
  rw [h1] at h2
  simp only [phiDef, Def.mk.injEq] at h2
  omega

/-- A phi has an operand for each predecessor, and `find?` picks one. -/
theorem CtxOK.phi_find (hc : CtxOK c) {y : Nat} {tb : Block} (hb : c.f.blocks[y]? = some tb) {p : Phi}
    (hp : p ∈ tb.phis) {from_ : Nat} (hf : from_ ∈ tb.preds) :
    ∃ e, p.edges.find? (·.block == from_) = some e ∧ e ∈ p.edges ∧ e.block = from_ := by
  have hm := phisOK_edges hc.phis hb hp
  have hex : (p.edges.find? (·.block == from_)).isSome = true := by
    rw [List.find?_isSome]
    rw [← hm] at hf
    obtain ⟨e, he, heq⟩ := List.exists_of_mem_map hf
    exact ⟨e, he, by simp [heq]⟩
  cases hfe : p.edges.find? (·.block == from_) with
  | none => rw [hfe] at hex; simp at hex
  | some e =>
    refine ⟨e, rfl, List.mem_of_find?_eq_some hfe, ?_⟩
    have := List.find?_some hfe
    simpa using this

end Defs

/-- The definition of `v` lies strictly above `x`: `v` is a constant or parameter, or defined in a block other than `x`
that dominates it. -/
def StrictAbove (c : Ctx) (v x : Nat) : Prop :=
  (c.def_ v).kind = .pre ∨ ∃ D, (c.def_ v).block = some D ∧ D ≠ x ∧ TDom c.succ D x

section Edges
variable {c : Ctx}

/-- The blocks around a refining edge: `x` has the single predecessor `e.source`, which has a walk to it. -/
theorem refining_facts (hc : CtxOK c) {x : Nat} {e : Edge} (hx : Reach c.succ x) (h : refining c x = some e) :
    x ≠ 0 ∧ (∀ q, x ∈ c.succ q → q = e.source) ∧ x ∈ c.succ e.source ∧ Reach c.succ e.source := by
  obtain ⟨blk, pb, cond, t, el, hblk, hpreds, hpb, hterm, _⟩ := refining_spec h
  have hsingle : ∀ q, x ∈ c.succ q → q = e.source := by
    intro q hq
    unfold Ctx.succ cfgSucc at hq
    cases hbq : c.f.blocks[q]? with
    | none => simp [hbq] at hq
    | some bq =>
      rw [hbq] at hq
      obtain ⟨tb, htb, hmem⟩ := edgesOK_succ hc.edges hbq hq
      rw [hblk] at htb
      cases htb
      rw [hpreds] at hmem
      simpa using hmem
  have hx0 : x ≠ 0 := by
    intro h0
    subst h0
    have := (entryOK_entry hc.entry hblk).1
    rw [hpreds] at this
    simp at this
  have hxs : x ∈ c.succ e.source := by
    obtain ⟨pb', hpb', hmem⟩ := edgesOK_pred hc.edges hblk (p := e.source) (by rw [hpreds]; simp)
    unfold Ctx.succ cfgSucc
    rw [hpb']
    exact hmem
  refine ⟨hx0, hsingle, hxs, ?_⟩
  obtain ⟨l, hl⟩ := hx
  obtain ⟨p, l', _, hwp, hs⟩ := hl.prev hx0
  have := hsingle p hs
  subst this
  exact ⟨l', hwp⟩

/-- The operands of the comparison of a refining edge are defined strictly above the block the edge enters. -/
theorem refining_operand_above (hc : CtxOK c) (hw : SsaWf c) {x : Nat} {e : Edge} (hx : Reach c.succ x)
    (h : refining c x = some e) {w : Nat} (hwm : w ∈ regOps e.cmp) : StrictAbove c w x := by
  obtain ⟨hx0, hsingle, hxs, hrp⟩ := refining_facts hc hx h
  obtain ⟨blk, pb, cond, t, el, hblk, hpreds, hpb, hterm, hdef, hnphi, hcmp, htaken, hne⟩ := refining_spec h
  -- the comparison is an instruction at a position
  have hkind : (c.def_ cond).kind = .inst := by
    cases hk : (c.def_ cond).kind with
    | missing => exact absurd hk (hc.kind_of_inst hdef)
    | phi => exact absurd hk hnphi
    | inst => rfl
    | pre =>
      exfalso
      obtain ⟨i, hi, hinst, _⟩ := hc.pre_of_def hk
      rw [hdef] at hinst
      cases hinst
      obtain ⟨hop, _⟩ := hc.pre_op hi
      rw [hcmp] at hop
      rcases hop with h1 | h1 | h1 <;> first | cases h1 | simp [Op.isFree] at h1
  obtain ⟨Dc, bc, ic, hDc, hbc, hic, hval, hinst⟩ := hc.inst_of_def hkind
  rw [hdef] at hinst
  cases hinst
  -- the condition is available at the end of the source block, so its block dominates the source
  have hav := hw.branch hpb hterm hrp
  have hdc : TDom c.succ Dc e.source := by
    have := hav.above
    rcases this with hpre | ⟨D, hD, hd⟩
    · rw [hkind] at hpre; cases hpre
    · rw [hDc] at hD; cases hD; exact hd
  have hreachDc : Reach c.succ Dc := TDom.reach_of hdc hrp
  -- the operand is available where the comparison runs, so it dominates that block
  have hav2 := hw.inst hbc hic hreachDc hwm
  have habove : StrictAbove c w x := by
    rcases hav2.above with hpre | ⟨Da, hDa, hda⟩
    · exact Or.inl hpre
    · refine Or.inr ⟨Da, hDa, ?_, ?_⟩
      · intro hDax
        subst hDax
        exact TDom.not_single hx0 hsingle hrp ((hda.trans hdc))
      · exact TDom.of_single hx0 hsingle (hda.trans hdc)
  exact habove

/-- A value defined strictly above `x` is available everywhere `x` dominates. -/
theorem StrictAbove.avail (hc : CtxOK c) {v x B : Nat} (h : StrictAbove c v x) (hd : TDom c.succ x B)
    (hB : Reach c.succ B) (pc : Nat) : Avail c B pc v := by
  rcases h with hpre | ⟨D, hD, hne, hdx⟩
  · unfold Avail; rw [hpre]; trivial
  · have hDB : TDom c.succ D B := hdx.trans hd
    cases hk : (c.def_ v).kind with
    | missing =>
      have := hc.def_missing hk
      rw [this] at hD
      simp at hD
    | pre =>
      unfold Avail; rw [hk]; trivial
    | phi =>
      unfold Avail; rw [hk]; exact ⟨D, hD, hDB⟩
    | inst =>
      unfold Avail; rw [hk]
      refine ⟨D, hD, Or.inr ⟨?_, hDB⟩⟩
      intro hDB'
      subst hDB'
      exact hne (TDom.antisymm (TDom.reach_of hd hB) hdx hd)

/-- A value defined strictly above `x` is not defined in a block that `x` dominates. -/
theorem StrictAbove.not_def (hc : CtxOK c) {v x B : Nat} (h : StrictAbove c v x) (hd : TDom c.succ x B)
    (hB : Reach c.succ B) : (c.def_ v).block ≠ some B := by
  rcases h with hpre | ⟨D, hD, hne, hdx⟩
  · intro hb
    rw [hc.pre_block hpre] at hb
    cases hb
  · intro hb
    rw [hD] at hb
    cases hb
    exact hne (TDom.antisymm (TDom.reach_of hd hB) hdx hd)

end Edges

section Operands
variable {c : Ctx}

/-- The registers of a constant or parameter: none. -/
theorem regOps_pre (hc : CtxOK c) {w : Nat} {j : Inst} (hk : (c.def_ w).kind = .pre) (hj : (c.def_ w).inst = some j) :
    regOps j = [] := by
  obtain ⟨i, hi, hinst, _⟩ := hc.pre_of_def hk
  rw [hj] at hinst
  cases hinst
  obtain ⟨_, ha, hb, hx⟩ := hc.pre_op hi
  unfold regOps
  simp [ha, hb, hx]

/-- An instruction available before the instruction at `(B, pc)` does not read the value that one defines. -/
theorem operand_ne_new (hc : CtxOK c) (hw : SsaWf c) {B pc : Nat} {b : Block} {i : Inst}
    (hb : c.f.blocks[B]? = some b) (hk : b.insts[pc]? = some i) (hr : Reach c.succ B) {w : Nat} {j : Inst}
    (hav : Avail c B pc w) (hnp : (c.def_ w).kind ≠ .phi) (hj : (c.def_ w).inst = some j) :
    ∀ v ∈ regOps j, v ≠ i.value := by
  intro v hv hvi
  subst hvi
  cases hkind : (c.def_ w).kind with
  | missing => exact hc.kind_of_inst hj hkind
  | phi => exact hnp hkind
  | pre => rw [regOps_pre hc hkind hj] at hv; simp at hv
  | inst =>
    obtain ⟨Dj, bj, jj, hDj, hbj, hkj, hvj, hjj⟩ := hc.inst_of_def hkind
    rw [hj] at hjj
    cases hjj
    have hreach : Reach c.succ Dj := by
      rcases hav.above with hpre | ⟨D, hD, hd⟩
      · rw [hkind] at hpre; cases hpre
      · rw [hDj] at hD; cases hD; exact TDom.reach_of hd hr
    have hav2 := hw.inst hbj hkj hreach hv
    have hdi := hc.def_inst hb hk
    unfold Avail at hav hav2
    rw [hkind] at hav
    rw [hdi] at hav2
    simp only [instDef] at hav2
    obtain ⟨D1, hD1, h1⟩ := hav
    obtain ⟨D2, hD2, h2⟩ := hav2
    rw [hDj] at hD1
    cases hD1
    cases hD2
    rcases h1 with ⟨e1, l1⟩ | ⟨n1, t1⟩ <;> rcases h2 with ⟨e2, l2⟩ | ⟨n2, t2⟩
    · omega
    · exact n2 (e1.symm)
    · exact n1 (e2.symm)
    · exact n1 (TDom.antisymm hr t1 t2)

/-- An instruction available at the start of block `y` does not read a phi of `y`. -/
theorem operand_ne_phi (hc : CtxOK c) (hw : SsaWf c) {y : Nat} (hr : Reach c.succ y) {w : Nat} {j : Inst}
    (hav : Avail c y 0 w) (hnp : (c.def_ w).kind ≠ .phi) (hj : (c.def_ w).inst = some j) :
    ∀ v ∈ regOps j, ¬ ((c.def_ v).kind = .phi ∧ (c.def_ v).block = some y) := by
  rintro v hv ⟨hvk, hvb⟩
  cases hkind : (c.def_ w).kind with
  | missing => exact hc.kind_of_inst hj hkind
  | phi => exact hnp hkind
  | pre => rw [regOps_pre hc hkind hj] at hv; simp at hv
  | inst =>
    obtain ⟨Dj, bj, jj, hDj, hbj, hkj, hvj, hjj⟩ := hc.inst_of_def hkind
    rw [hj] at hjj
    cases hjj
    unfold Avail at hav
    rw [hkind] at hav
    obtain ⟨D, hD, h1⟩ := hav
    rw [hDj] at hD
    cases hD
    have hreach : Reach c.succ Dj := by
      rcases h1 with ⟨_, hlt⟩ | ⟨_, hd⟩
      · omega
      · exact TDom.reach_of hd hr
    have hav2 := hw.inst hbj hkj hreach hv
    unfold Avail at hav2
    rw [hvk] at hav2
    obtain ⟨D2, hD2, h2⟩ := hav2
    rw [hvb] at hD2
    cases hD2
    rcases h1 with ⟨_, hlt⟩ | ⟨hne, hd⟩
    · omega
    · exact hne (TDom.antisymm hr hd h2)

end Operands


section Entering
variable {c : Ctx}

/-- A value available at the start of `y`, other than a phi of `y`, is available at the end of a predecessor. -/
theorem avail_enter (hc : CtxOK c) {B y : Nat} {b : Block} (hb : c.f.blocks[B]? = some b) (hys : y ∈ c.succ B)
    {w : Nat} (hav : Avail c y 0 w) (hnp : ¬((c.def_ w).kind = .phi ∧ (c.def_ w).block = some y)) :
    Avail c B b.insts.length w := by
  unfold Avail at hav ⊢
  cases hk : (c.def_ w).kind with
  | missing => rw [hk] at hav; exact hav
  | pre => trivial
  | phi =>
    rw [hk] at hav
    obtain ⟨D, hD, hd⟩ := hav
    have hne : D ≠ y := by
      intro e; subst e; exact hnp ⟨hk, hD⟩
    exact ⟨D, hD, TDom.of_succ hys hne hd⟩
  | inst =>
    rw [hk] at hav
    obtain ⟨D, hD, h⟩ := hav
    rcases h with ⟨_, hlt⟩ | ⟨hne, hd⟩
    · omega
    · refine ⟨D, hD, ?_⟩
      have hdB : TDom c.succ D B := TDom.of_succ hys hne hd
      by_cases hDB : D = B
      · left
        refine ⟨hDB, ?_⟩
        obtain ⟨D', bD, i, hD', hbD, hi, _, _⟩ := hc.inst_of_def hk
        rw [hD] at hD'
        cases hD'
        subst hDB
        rw [hb] at hbD
        cases hbD
        exact (List.getElem?_eq_some_iff.mp hi).1
      · exact Or.inr ⟨hDB, hdB⟩

/-- A phi of `y` defines a value that is a phi of `y` by the recorded definitions, and conversely. -/
theorem phi_def_of_mem (hc : CtxOK c) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb) {p : Phi}
    (hp : p ∈ tb.phis) : (c.def_ p.value).kind = .phi ∧ (c.def_ p.value).block = some y ∧
      (c.def_ p.value).phi = some p := by
  obtain ⟨k, hk⟩ := List.mem_iff_getElem?.mp hp
  rw [hc.def_phi hy hk]
  simp [phiDef]

theorem mem_of_phi_def (hc : CtxOK c) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb) {w : Nat}
    (hk : (c.def_ w).kind = .phi) (hb : (c.def_ w).block = some y) : ∃ p ∈ tb.phis, p.value = w := by
  obtain ⟨D, b', p, hD, hb', hp, hv, _⟩ := hc.phi_of_def hk
  rw [hb] at hD
  cases hD
  rw [hy] at hb'
  cases hb'
  exact ⟨p, List.mem_of_getElem? hp, hv⟩

theorem not_phi_of_not_def (hc : CtxOK c) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb) {w : Nat}
    (hnp : ¬((c.def_ w).kind = .phi ∧ (c.def_ w).block = some y)) : ∀ p ∈ tb.phis, p.value ≠ w := by
  intro p hp hpw
  subst hpw
  exact hnp ⟨(phi_def_of_mem hc hy hp).1, (phi_def_of_mem hc hy hp).2.1⟩

end Entering


theorem countedAt_spec {c : Ctx} {H : Nat} {k : Counted} (h : c.countedAt H = some k) :
    ∃ loop ∈ c.f.aux.loops, loop.header = H ∧ ∃ (blk : Block) (cond t el : Nat),
      c.f.blocks[H]? = some blk ∧ blk.preds.length = 2 ∧ blk.term = .branch cond t el ∧ t = loop.body ∧
      c.dominates loop.body loop.latch = true ∧ (∃ e, refining c loop.body = some e ∧ e.source = H) ∧
      ∃ cmp : Inst, (c.def_ cond).inst = some cmp ∧ (c.def_ cond).kind ≠ .phi ∧ cmp.op = .cmp ∧
        Pred.ofImm cmp.imm = some .lt ∧ cmp.operands.a = some k.counter ∧ cmp.operands.b = some k.bound ∧
        (c.def_ k.counter).kind = .phi ∧ (c.def_ k.counter).block = some H ∧
        blk.preds[k.latchIndex]? = some loop.latch ∧
        (∃ (line : Phi) (latchEdge entryEdge : PhiEdge), (c.def_ k.counter).phi = some line ∧
          line.edges[k.latchIndex]? = some latchEdge ∧ line.edges[1 - k.latchIndex]? = some entryEdge ∧
          entryEdge.value = k.start ∧
          ∃ (step : Inst) (oneV : Nat) (one : Inst), (c.def_ latchEdge.value).inst = some step ∧
            (c.def_ latchEdge.value).kind ≠ .phi ∧ step.op = .add ∧ step.operands.a = some k.counter ∧
            step.operands.b = some oneV ∧ (c.def_ oneV).inst = some one ∧ one.op = .iconst ∧ one.imm = 1) ∧
        (k.latchIndex = 0 ∨ k.latchIndex = 1) := by
  unfold Ctx.countedAt at h
  obtain ⟨l1, loop, l2, hl, hf, _⟩ := List.findSome?_eq_some_iff.mp h
  have hmem : loop ∈ c.f.aux.loops := by rw [hl]; simp
  refine ⟨loop, hmem, ?_⟩
  by_cases hh : (loop.header != H) = true
  · simp [hh] at hf
  · simp only [hh, Bool.false_eq_true, ite_false] at hf
    have hheader : loop.header = H := by simpa using hh
    refine ⟨hheader, ?_⟩
    cases hb : c.f.blocks[H]? with
    | none => simp [hb] at hf
    | some blk =>
      simp only [hb] at hf
      by_cases hp : (blk.preds.length != 2) = true
      · simp [hp] at hf
      · simp only [hp, Bool.false_eq_true, ite_false] at hf
        have hplen : blk.preds.length = 2 := by simpa using hp
        cases ht : blk.term with
        | jump _ => simp [ht] at hf
        | ret _ => simp [ht] at hf
        | unreachable => simp [ht] at hf
        | branch cond t el =>
          simp only [ht] at hf
          by_cases htb : (t != loop.body) = true
          · simp [htb] at hf
          · simp only [htb, Bool.false_eq_true, ite_false] at hf
            have htbody : t = loop.body := by simpa using htb
            by_cases hdom : (!c.dominates loop.body loop.latch || !(refining c loop.body).any (·.source == H)) = true
            · simp [hdom] at hf
            · simp only [hdom, Bool.false_eq_true, ite_false] at hf
              have hdom1 : c.dominates loop.body loop.latch = true := by
                cases hd : c.dominates loop.body loop.latch
                · rw [hd] at hdom; simp at hdom
                · rfl
              have hdom2 : ∃ e, refining c loop.body = some e ∧ e.source = H := by
                cases hr : refining c loop.body with
                | none => rw [hr] at hdom; simp at hdom
                | some e =>
                  rw [hr] at hdom
                  refine ⟨e, rfl, ?_⟩
                  simp at hdom
                  simpa using hdom.2
              cases hcd : (c.def_ cond).inst with
              | none => simp [hcd] at hf
              | some cmp =>
                simp only [hcd] at hf
                by_cases hc2 : ((c.def_ cond).kind == Kind.phi || cmp.op != Op.cmp || Pred.ofImm cmp.imm != some Pred.lt) = true
                · simp [hc2] at hf
                · simp only [hc2, Bool.false_eq_true, ite_false] at hf
                  simp only [Bool.or_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, not_or, Decidable.not_not] at hc2
                  cases ha : cmp.operands.a with
                  | none => simp [ha] at hf
                  | some counter =>
                    cases hbb : cmp.operands.b with
                    | none => simp [hbb] at hf
                    | some bound =>
                      simp only [ha, hbb] at hf
                      by_cases hc3 : ((c.def_ counter).kind != Kind.phi || (c.def_ counter).block != some H) = true
                      · simp [hc3] at hf
                      · simp only [hc3, Bool.false_eq_true, ite_false] at hf
                        simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or, Decidable.not_not] at hc3
                        generalize hli : (if (blk.preds[0]? == some loop.latch) = true then 0 else 1) = li at hf
                        by_cases hlp : (blk.preds[li]? != some loop.latch) = true
                        · simp [hlp] at hf
                        · simp only [hlp, Bool.false_eq_true, ite_false] at hf
                          have hlatch : blk.preds[li]? = some loop.latch := by simpa using hlp
                          cases hph : (c.def_ counter).phi with
                          | none => simp [hph] at hf
                          | some line =>
                            simp only [hph] at hf
                            cases hle : line.edges[li]? with
                            | none => simp [hle] at hf
                            | some latchEdge =>
                              cases hee : line.edges[1 - li]? with
                              | none => simp [hle, hee] at hf
                              | some entryEdge =>
                                simp only [hle, hee] at hf
                                cases hsi : (c.def_ latchEdge.value).inst with
                                | none => simp [hsi] at hf
                                | some step =>
                                  simp only [hsi] at hf
                                  by_cases hs2 : ((c.def_ latchEdge.value).kind == Kind.phi || step.op != Op.add ||
                                      step.operands.a != some counter) = true
                                  · simp [hs2] at hf
                                  · simp only [hs2, Bool.false_eq_true, ite_false] at hf
                                    simp only [Bool.or_eq_true, beq_iff_eq, bne_iff_ne, ne_eq, not_or,
                                      Decidable.not_not] at hs2
                                    cases hsb : step.operands.b with
                                    | none => simp [hsb] at hf
                                    | some oneV =>
                                      simp only [hsb] at hf
                                      cases hone : (c.def_ oneV).inst with
                                      | none => simp [hone] at hf
                                      | some one =>
                                        simp only [hone] at hf
                                        by_cases hs3 : (one.op != Op.iconst || one.imm != 1) = true
                                        · simp [hs3] at hf
                                        · simp only [hs3, Bool.false_eq_true, ite_false, Option.some.injEq] at hf
                                          simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, not_or,
                                            Decidable.not_not] at hs3
                                          subst hf
                                          exact ⟨blk, cond, t, el, rfl, hplen, ht, htbody, hdom1, hdom2, cmp, hcd,
                                            fun e => hc2.1.1 e, hc2.1.2, by simpa using hc2.2, ha, hbb, hc3.1, hc3.2,
                                            hlatch, ⟨line, latchEdge, entryEdge, hph, hle, hee, rfl, step, oneV, one,
                                            hsi, fun e => hs2.1.1 e, hs2.1.2, hs2.2, hsb, hone, hs3.1, hs3.2⟩,
                                            (by
                                              show li = 0 ∨ li = 1
                                              by_cases hc0 : (blk.preds[0]? == some loop.latch) = true
                                              · simp [hc0] at hli; omega
                                              · simp [hc0] at hli; omega)⟩


section AboveAvail
variable {c : Ctx}

/-- A value whose definition dominates the end of block `B` is available there. -/
theorem avail_end_of_above (hc : CtxOK c) {B : Nat} {b : Block} (hb : c.f.blocks[B]? = some b) {v : Nat}
    (hab : Above c v B) : Avail c B b.insts.length v := by
  unfold Avail
  cases hk : (c.def_ v).kind with
  | missing =>
    rcases hab with h | ⟨D, hD, _⟩
    · rw [hk] at h; cases h
    · rw [hc.def_missing hk] at hD; simp at hD
  | pre => trivial
  | phi =>
    rcases hab with h | ⟨D, hD, hd⟩
    · rw [hk] at h; cases h
    · exact ⟨D, hD, hd⟩
  | inst =>
    rcases hab with h | ⟨D, hD, hd⟩
    · rw [hk] at h; cases h
    · refine ⟨D, hD, ?_⟩
      by_cases hDB : D = B
      · left
        refine ⟨hDB, ?_⟩
        obtain ⟨D', bD, i, hD', hbD, hi, _, _⟩ := hc.inst_of_def hk
        rw [hD] at hD'
        cases hD'
        subst hDB
        rw [hb] at hbD
        cases hbD
        exact (List.getElem?_eq_some_iff.mp hi).1
      · exact Or.inr ⟨hDB, hd⟩

end AboveAvail


theorem countedAt_phi {c : Ctx} {H : Nat} {k : Counted} (h : c.countedAt H = some k) :
    (c.def_ k.counter).kind = .phi ∧ (c.def_ k.counter).block = some H := by
  obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, he, cmp, hcd, hnphi, hcmp, hlt, ha,
    hbo, hcphi, hcblock, _⟩ := countedAt_spec h
  exact ⟨hcphi, hcblock⟩


theorem CtxOK.inst_not_phi {c : Ctx} (hc : CtxOK c) {v : Nat} {i : Inst} (h : (c.def_ v).inst = some i) :
    (c.def_ v).kind ≠ .phi := by
  intro hk
  obtain ⟨D, b, p, hD, hb, hp, hv, _⟩ := hc.phi_of_def hk
  have hd := hc.def_phi hb hp
  rw [hv] at hd
  rw [hd] at h
  simp [phiDef] at h


theorem CtxOK.stated_within {c : Ctx} (hc : CtxOK c) {v : Nat} {r lim : Interval}
    (hs : (c.def_ v).stated = some r) (hl : (c.def_ v).ty.range = some lim) : r.within lim = true := by
  have hd : c.defs[v]? = some (c.def_ v) := by
    cases hv : c.defs[v]? with
    | none => rw [Ctx.def_, hv] at hs; simp [Def.stated] at hs
    | some d => simp [Ctx.def_, hv]
  have h := hc.statedOk
  unfold statedOK at h
  simp only [List.all_eq_true] at h
  have := h v (List.mem_range.mpr (arr_lt_of_get? hd))
  rw [arr_get!_of_get? hd, hs, hl] at this
  exact this

end Facts
