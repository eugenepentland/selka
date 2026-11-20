import Facts.Inv

/-!
# The soundness theorem

Every execution of an accepted module that honours the assumptions A6 keeps the invariant of `Inv.lean` in every
frame. The corollaries are the four items of design §7: stated intervals, dead blocks, proven checks.
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- The assumptions A6 hold of every frame of a configuration. -/
def AdmCfg (m : Module) (cfg : Config) : Prop :=
  ∀ fr ∈ cfg, ∀ c, ctxOf m fr.fn = some c → AdmFrame c fr.regs fr.blk

/-- The invariant holds of every frame of a configuration. -/
def CfgInv (m : Module) (cfg : Config) : Prop :=
  ∀ fr ∈ cfg, ∃ c, ctxOf m fr.fn = some c ∧ FrameInv c fr ∧ AdmFrame c fr.regs fr.blk

/-- The configurations an execution reaches that honour the assumptions A6 in every configuration. -/
inductive ReachA (m : Module) (cfg0 : Config) : Config → Prop where
  | refl : ReachA m cfg0 cfg0
  | step {cfg cfg' : Config} : ReachA m cfg0 cfg → Step m cfg cfg' → AdmCfg m cfg' → ReachA m cfg0 cfg'

theorem callee_blocks {m : Module} {i : Inst} {g : Nat} {h : Function} (hc : callee? m i = some (g, h)) :
    h.blocks.size > 0 := by
  unfold callee? at hc
  cases ha : i.operands.a with
  | none => rw [ha] at hc; simp at hc
  | some g' =>
    rw [ha] at hc
    simp only [] at hc
    cases hf : m.functions[g']? with
    | none => rw [hf] at hc; simp at hc
    | some h' =>
      rw [hf] at hc
      by_cases hb : h'.blocks.size > 0
      · simp only [hb, ite_true, Option.some.injEq, Prod.mk.injEq] at hc
        obtain ⟨rfl, rfl⟩ := hc
        exact hb
      · simp [hb] at hc

/-- What a frame of the configuration says about its function. -/
theorem frame_ctx {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg : Config} (hI : CfgInv m cfg) {fr : Frame}
    (hmem : fr ∈ cfg) : ∃ c, ctxOf m fr.fn = some c ∧ CtxOK c ∧ SsaWf c ∧ c.firstFault = none ∧ c.m = m ∧
      FrameInv c fr ∧ AdmFrame c fr.regs fr.blk := by
  obtain ⟨c, hc, hinv, hadm⟩ := hI fr hmem
  obtain ⟨hcf, hcm, hok⟩ := ctxOf_spec hc
  obtain ⟨c', hc', hff⟩ := hmod fr.fn c.f hcf
  rw [hc] at hc'
  cases hc'
  exact ⟨c, hc, hok, hwf fr.fn c hc, hff, hcm, hinv, hadm⟩


/-- The invariant is preserved by every step an honest execution takes. -/
theorem step_inv {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg cfg' : Config} (hI : CfgInv m cfg)
    (hstep : Step m cfg cfg') (hadm : AdmCfg m cfg') : CfgInv m cfg' := by
  cases hstep with
  | @inst fr rest f blk i ch v hf hb hk hcn harr hev hvt hal =>
    obtain ⟨c, hc, hok, hw, hff, hcm, hinv, hadmf⟩ := frame_ctx hmod hwf hI (List.mem_cons_self ..)
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hb' : c.f.blocks[fr.blk]? = some blk := by rw [hfc]; exact hb
    have hadm' : AdmFrame c (fr.regs.set i.value v) fr.blk := hadm _ (List.mem_cons_self ..) c hc
    have hdef : (c.def_ i.value).inst = some i := by rw [hok.def_inst hb' hk]; rfl
    have hvok := inst_valok hok hw hff hinv hadmf hb' hk hev hvt hal hadm'
      (fun hop n hv' g callee r ha hg hr => by
        subst hv'
        rw [hcm] at hg
        exact hadm'.calls i.value i g callee r n hdef hop (by rw [hcm]; exact hcn hop) ha (by rw [hcm]; exact hg) hr
          (by simp [Regs.set]))
      (hok.opTyped hb' (List.mem_of_getElem? hk))
    intro fr2 hmem2
    rcases List.mem_cons.mp hmem2 with rfl | hrest
    · exact ⟨c, hc, inst_step_inv hok hw hinv hb' hk hvok ⟨ch, hev⟩ (inst_lst hok hw hff hinv hadmf hb' hk hev hadm'), hadm'⟩
    · exact hI fr2 (List.mem_cons_of_mem _ hrest)
  | @call fr rest f blk i g h regs hf hb hk hop hcallee hinit =>
    obtain ⟨c, hc, hok, hw, hff, hcm, hinv, hadmf⟩ := frame_ctx hmod hwf hI (List.mem_cons_self ..)
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hb' : c.f.blocks[fr.blk]? = some blk := by rw [hfc]; exact hb
    intro fr2 hmem2
    rcases List.mem_cons.mp hmem2 with rfl | hrest
    · obtain ⟨cg, hcg, hffg⟩ := hmod g h (callee_spec hcallee).2
      obtain ⟨hgf, hgm, hgok⟩ := ctxOf_spec hcg
      have hgh : cg.f = h := by
        have := (callee_spec hcallee).2
        rw [this] at hgf
        exact (Option.some.inj hgf).symm
      have hadmg : AdmFrame cg regs 0 := hadm _ (List.mem_cons_self ..) cg hcg
      refine ⟨cg, hcg, ?_, hadmg⟩
      refine init_inv hgok hffg (by rw [hgh]; exact callee_blocks hcallee) ?_
        (call_args_ok hok hw hff hinv hadmf hb' hk hcm hop hcallee hcg) hadmg
      rw [hgh]; exact hinit
    · rcases List.mem_cons.mp hrest with rfl | hrest2
      · exact hI _ (List.mem_cons_self ..)
      · exact hI fr2 (List.mem_cons_of_mem _ hrest2)
  | @jump fr rest f blk tb t hf hb hpc hterm htb =>
    obtain ⟨c, hc, hok, hw, hff, hcm, hinv, hadmf⟩ := frame_ctx hmod hwf hI (List.mem_cons_self ..)
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hb' : c.f.blocks[fr.blk]? = some blk := by rw [hfc]; exact hb
    have htb' : c.f.blocks[t]? = some tb := by rw [hfc]; exact htb
    have hadm' : AdmFrame c (enterRegs fr.regs tb fr.blk) t := hadm _ (List.mem_cons_self ..) c hc
    intro fr2 hmem2
    rcases List.mem_cons.mp hmem2 with rfl | hrest
    · refine ⟨c, hc, enter_inv hok hw hff hinv hadmf hb' hpc htb' (by rw [hterm]; simp [successors]) ?_ hadm', hadm'⟩
      intro cond t' el h
      rw [hterm] at h
      cases h
    · exact hI fr2 (List.mem_cons_of_mem _ hrest)
  | @branch fr rest f blk tb cc t e s k hf hb hpc hterm hk hks htb =>
    obtain ⟨c, hc, hok, hw, hff, hcm, hinv, hadmf⟩ := frame_ctx hmod hwf hI (List.mem_cons_self ..)
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hb' : c.f.blocks[fr.blk]? = some blk := by rw [hfc]; exact hb
    have htb' : c.f.blocks[s]? = some tb := by rw [hfc]; exact htb
    have hadm' : AdmFrame c (enterRegs fr.regs tb fr.blk) s := hadm _ (List.mem_cons_self ..) c hc
    intro fr2 hmem2
    rcases List.mem_cons.mp hmem2 with rfl | hrest
    · refine ⟨c, hc, enter_inv hok hw hff hinv hadmf hb' hpc htb' ?_ ?_ hadm', hadm'⟩
      · rw [hterm]
        rcases hks with ⟨_, hs⟩ | ⟨_, hs⟩ <;> simp [successors, hs]
      · intro cond t' el h
        rw [hterm] at h
        cases h
        exact ⟨k, hk, hks⟩
    · exact hI fr2 (List.mem_cons_of_mem _ hrest)
  | @ret fr cr rest f cf blk cb i v rv h hf hb hpc hterm hv hcf hcb hci hop hcallee hvt =>
    obtain ⟨c, hc, hok, hw, hff, hcm, hinv, hadmf⟩ := frame_ctx hmod hwf hI (List.mem_cons_self ..)
    obtain ⟨cc, hcc, hokc, hwc, hffc, hcmc, hinvc, hadmc⟩ :=
      frame_ctx hmod hwf hI (List.mem_cons_of_mem _ (List.mem_cons_self ..))
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hcfc : cc.f = cf := by
      have := (ctxOf_spec hcc).1
      rw [hcf] at this
      exact (Option.some.inj this).symm
    have hb' : c.f.blocks[fr.blk]? = some blk := by rw [hfc]; exact hb
    have hcb' : cc.f.blocks[cr.blk]? = some cb := by rw [hcfc]; exact hcb
    have hadm' : AdmFrame cc (cr.regs.set i.value v) cr.blk :=
      hadm { cr with regs := cr.regs.set i.value v, pc := cr.pc + 1 } (List.mem_cons_self ..) cc hcc
    have hdef : (cc.def_ i.value).inst = some i := by rw [hokc.def_inst hcb' hci]; rfl
    have hvok : ValOK cc i.value v := by
      refine inst_valok hokc hwc hffc hinvc hadmc hcb' hci (ch := v) (evalInst_call hop) hvt ?_ hadm' ?_
        (hokc.opTyped hcb' (List.mem_of_getElem? hci))
      · simp [Allowed, hop]
      · intro _ n hvn g callee r ha hg hr
        subst hvn
        rw [hcmc] at hg
        obtain ⟨ha', hgh⟩ := callee_spec hcallee
        rw [ha] at ha'
        cases ha'
        rw [hgh] at hg
        cases hg
        have hcfg : c.f.boundary.returns = some r := by
          have := (ctxOf_spec hc).1
          rw [hgh] at this
          cases (Option.some.inj this)
          exact hr
        exact ret_claim hok hw hff hinv hadmf hb' hterm (n := n) hv.symm hcfg
    intro fr2 hmem2
    rcases List.mem_cons.mp hmem2 with rfl | hrest
    · exact ⟨cc, hcc, inst_step_inv hokc hwc hinvc hcb' hci hvok ⟨v, evalInst_call hop⟩
      (inst_lst hokc hwc hffc hinvc hadmc hcb' hci (ch := v) (evalInst_call hop) hadm'), hadm'⟩
    · exact hI fr2 (List.mem_cons_of_mem _ (List.mem_cons_of_mem _ hrest))


/-- The invariant holds in every configuration an honest execution reaches. -/
theorem reach_inv {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg0 cfg : Config} (h0 : CfgInv m cfg0)
    (hr : ReachA m cfg0 cfg) : CfgInv m cfg := by
  induction hr with
  | refl => exact h0
  | step _ hstep hadm ih => exact step_inv hmod hwf ih hstep hadm

/-- An external entry starts with the invariant, when its arguments satisfy the parameter intervals. -/
theorem entry_inv {m : Module} (hmod : ModOK m) {g : Nat} {args : List Val} {cfg0 : Config}
    (he : Entry m g args cfg0) (hargs : ∀ c, ctxOf m g = some c → ArgsOK c args) (hadm : AdmCfg m cfg0) :
    CfgInv m cfg0 := by
  obtain ⟨h, regs, hg, hblocks, hinit, rfl⟩ := he
  obtain ⟨c, hc, hff⟩ := hmod g h hg
  obtain ⟨hcf, hcm, hok⟩ := ctxOf_spec hc
  have hch : c.f = h := by
    rw [hg] at hcf
    exact (Option.some.inj hcf).symm
  have hadm0 : AdmFrame c regs 0 := hadm _ (List.mem_cons_self ..) c hc
  intro fr hmem
  have : fr = { fn := g, args := args, regs := regs, blk := 0, pc := 0 } := by simpa using hmem
  subst this
  refine ⟨c, hc, ?_, hadm0⟩
  exact init_inv hok hff (by rw [hch]; exact hblocks) (by rw [hch]; exact hinit) (hargs c hc) hadm0

/-- A function that anyone outside the module can call has no stated parameter intervals. -/
theorem entry_args {c : Ctx} {args : List Val} (hext : ¬(c.f.header.internal = true ∧ c.f.header.addressTaken = false)) :
    ArgsOK c args := by
  intro k claim a n hpc
  unfold paramClaim at hpc
  by_cases hcnd : (!c.f.header.internal || c.f.header.addressTaken || k ≥ c.f.boundary.params.length) = true
  · simp [hcnd] at hpc
  · exfalso
    apply hext
    refine ⟨?_, ?_⟩
    · cases h : c.f.header.internal <;> simp_all
    · cases h : c.f.header.addressTaken <;> simp_all


/-! ### The theorem: intervals and reachability -/

/-- Design §7, items 1 and 4: every integer or boolean value a frame holds lies in the interval stated for it, and in
the type's range. -/
theorem stated_intervals {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg0 cfg : Config} (h0 : CfgInv m cfg0)
    (hr : ReachA m cfg0 cfg) {fr : Frame} (hfr : fr ∈ cfg) {c : Ctx} (hc : ctxOf m fr.fn = some c) {v : Nat} {n : Int}
    (hv : fr.regs v = some (.int n)) :
    (∀ r lim, (c.def_ v).stated = some r → (c.def_ v).ty.range = some lim → r.contains n) ∧
      (∀ lim, (c.def_ v).ty.range = some lim → lim.contains n) := by
  obtain ⟨c', hc', hinv, _⟩ := reach_inv hmod hwf h0 hr fr hfr
  rw [hc] at hc'
  cases hc'
  have hvok := hinv.val v _ hv
  exact ⟨fun r lim hr hl => (hvok.2 n rfl).2 r lim hr hl, fun lim hl => (ValTy.int hl hvok.1).elim fun n' h => by
    simp only [Val.int.injEq] at h
    obtain ⟨h1, h2⟩ := h
    subst h1
    exact h2⟩

/-- Design §7, item 2: no block the certificate states dead is entered. -/
theorem no_dead_entered {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg0 cfg : Config} (h0 : CfgInv m cfg0)
    (hr : ReachA m cfg0 cfg) {fr : Frame} (hfr : fr ∈ cfg) {c : Ctx} (hc : ctxOf m fr.fn = some c) {b : Block}
    (hb : c.f.blocks[fr.blk]? = some b) : b.dead = false := by
  obtain ⟨c', hc', hinv, _⟩ := reach_inv hmod hwf h0 hr fr hfr
  rw [hc] at hc'
  cases hc'
  obtain ⟨hcf, _, _⟩ := ctxOf_spec hc
  obtain ⟨c2, hc2, hff⟩ := hmod fr.fn c.f hcf
  rw [hc] at hc2
  cases hc2
  by_cases hd : b.dead = true
  · exact absurd hinv.reached (Ctx.dead_ok hff hb hd)
  · simpa using hd

end Facts
