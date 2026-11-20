import VerifyIr.FnValues
import Facts.Inv

/-!
# The SSA rule gives `SsaWf`

`ssaWf_of_check`: for a prepared fact context `c` (`Facts.CtxOK c`, which `ctxOf` gives for every function the fact
theorem considers), if the SSA rule accepts the skeleton of `c.f` with some tree `idom`, then `Facts.SsaWf c`.
`modWf_of_verdicts`: if the checker accepts every function of a module and the fact certificate's skeletons are the
translations of the module's functions (`translatesB`), then `Facts.ModWf` of the certificate, the hypothesis H2 of
`Facts.fact_certificates_sound`.

The proof uses, of `CtxOK c`, only that the definitions table records each item at its position (`defsOK`), that the
predecessor lists are the blocks whose terminators name the block (`edgesOK`) and that each phi has one edge per
predecessor (`phisOK`); of the check, only the reached set's closure, the tree's parent property, the definitions table
and the reads of each reached block. The dominator tree is any array the check accepts; the reached set any closed set.
-/

namespace VerifyIr

open Facts (CtxOK SsaWf Avail TDom Reach Walk Anc parentOf walkUp cfgSucc)

theorem match_some_true {o : Option Nat} {f : Nat → Bool}
    (h : (match o with | some d => f d | none => false) = true) : ∃ d, o = some d ∧ f d = true := by
  cases o with
  | none => simp at h
  | some d => exact ⟨d, rfl, h⟩

namespace Skel
variable {s : Skel} {idom : Array Nat}

/-- What an accepted check says, unfolded. -/
structure Accepts (s : Skel) (idom : Array Nat) : Prop where
  size : s.reach.size = s.blocks.size
  entry : s.reach[0]! = true
  closed : ∀ p, p < s.blocks.size → s.reach[p]! = true → ∀ x ∈ s.succ p,
    x < s.blocks.size ∧ s.reach[x]! = true ∧ x ≠ 0 ∧ ∃ d, parentOf idom x = some d ∧ walkUp idom d (s.blocks.size + 1) p = true
  table : s.tableOK s.table = true
  blocks : ∀ d, d < s.blocks.size → s.reach[d]! = true → s.blockOK s.reach s.table idom d s.blocks[d]! = true

theorem accepts_of_check (h : s.ssaCheck idom = true) (hn : s.blocks.size ≠ 0) : Accepts s idom := by
  unfold ssaCheck at h
  simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, List.all_eq_true, List.mem_range, Bool.not_eq_true',
    decide_eq_true_eq] at h
  rcases h with h | h
  · exact absurd h hn
  obtain ⟨⟨⟨⟨hsize, hentry⟩, hclosed⟩, htable⟩, hblocks⟩ := h
  refine ⟨hsize, hentry, ?_, htable, ?_⟩
  · intro p hp hr x hx
    have := hclosed p hp
    rcases this with h1 | h1
    · rw [hr] at h1; exact absurd h1 (by simp)
    · obtain ⟨⟨⟨hlt, hrx⟩, hne⟩, hpar⟩ := h1 x hx
      obtain ⟨d, hd, hw⟩ := match_some_true hpar
      exact ⟨hlt, hrx, by simpa using hne, d, hd, hw⟩
  · intro d hd hr
    rcases hblocks d hd with h1 | h1
    · rw [hr] at h1; exact absurd h1 (by simp)
    · exact h1

end Skel

/-! ## The skeleton of a certificate function -/

section Skeleton
variable (f : Facts.Function)

theorem skel_size : (skelOf f).blocks.size = f.blocks.size := by simp [skelOf]

theorem skel_block {d : Nat} {b : Facts.Block} (hb : f.blocks[d]? = some b) :
    (skelOf f).blocks[d]? = some
      { preds := b.preds, phis := b.phis.map fun p => ⟨p.value, p.edges.map fun e => (e.block, e.value)⟩,
        insts := b.insts.map fun i => ⟨i.value, Facts.regOps i⟩, term := b.term } := by
  simp [skelOf, Array.getElem?_map, hb]

theorem skel_succ (p : Nat) : (skelOf f).succ p = cfgSucc f p := by
  unfold Skel.succ cfgSucc
  cases hb : f.blocks[p]? with
  | none => simp [skelOf, Array.getElem?_map, hb]
  | some b => rw [skel_block f hb]

end Skeleton

/-! ## Reached blocks and the tree -/

section Graph
variable {c : Facts.Ctx} {idom : Array Nat}

/-- The successors of a block of the reached set (none for any other block): the graph the tree is verified on. -/
def rsucc (c : Facts.Ctx) (p : Nat) : List Nat := if (skelOf c.f).reach[p]! = true then cfgSucc c.f p else []

theorem rsucc_of {c : Facts.Ctx} {p : Nat} (hp : (skelOf c.f).reach[p]! = true) : rsucc c p = cfgSucc c.f p := by
  simp [rsucc, hp]

theorem reach_lt (A : Skel.Accepts (skelOf c.f) idom) {p : Nat} (h : (skelOf c.f).reach[p]! = true) :
    p < c.f.blocks.size := by
  have hs : (skelOf c.f).reach.size = c.f.blocks.size := by rw [A.size, skel_size]
  rcases Nat.lt_or_ge p (skelOf c.f).reach.size with hlt | hge
  · rw [hs] at hlt; exact hlt
  · rw [getElem!_neg _ _ (by omega)] at h; exact absurd h (by decide)

/-- The graph of the reached set and the tree. -/
def graphOf (A : Skel.Accepts (skelOf c.f) idom) : Facts.Graph where
  succ := rsucc c
  par := parentOf idom
  tr p := (skelOf c.f).reach[p]! = true
  entry_tr := A.entry
  par_entry := by simp [parentOf]
  succ_tr := by
    intro p b hp hb
    rw [rsucc_of hp, ← skel_succ] at hb
    have hlt := reach_lt A hp
    rw [← skel_size] at hlt
    exact (A.closed p hlt hp b hb).2.1
  parent_anc := by
    intro p b hp hb _
    rw [rsucc_of hp, ← skel_succ] at hb
    have hlt := reach_lt A hp
    rw [← skel_size] at hlt
    obtain ⟨_, _, _, d, hd, hw⟩ := A.closed p hlt hp b hb
    exact ⟨d, hd, Facts.walkUp_anc idom d _ p hw⟩
  entry_nopred := by
    intro p hp
    unfold rsucc at hp
    split at hp
    · rename_i hr
      rw [← skel_succ] at hp
      have hlt := reach_lt A hr
      rw [← skel_size] at hlt
      exact (A.closed p hlt hr 0 hp).2.2.1 rfl
    · simp at hp

/-- Every block a walk of the function's graph reaches is in the reached set, and the walk is one of `rsucc`. -/
theorem walk_reached (A : Skel.Accepts (skelOf c.f) idom) {b : Nat} {l : List Nat} (h : Walk (cfgSucc c.f) b l) :
    (skelOf c.f).reach[b]! = true ∧ Walk (rsucc c) b l := by
  induction h with
  | start => exact ⟨A.entry, Walk.start⟩
  | step hw hs ih =>
    rename_i p b' l'
    obtain ⟨hp, hw'⟩ := ih
    have hs' : b' ∈ rsucc c p := by rw [rsucc_of hp]; exact hs
    have hlt := reach_lt A hp
    rw [← skel_size] at hlt
    rw [← skel_succ] at hs
    exact ⟨(A.closed p hlt hp b' hs).2.1, Walk.step hw' hs'⟩

theorem reached_of_reach (A : Skel.Accepts (skelOf c.f) idom) {b : Nat} (h : Reach (cfgSucc c.f) b) :
    (skelOf c.f).reach[b]! = true := by
  obtain ⟨l, hl⟩ := h
  exact (walk_reached A hl).1

/-- An ancestor in the verified tree truly dominates. -/
theorem tdom_of_walkUp (A : Skel.Accepts (skelOf c.f) idom) {a b fuel : Nat} (h : walkUp idom a fuel b = true) :
    TDom (cfgSucc c.f) a b := by
  intro l hl
  exact (graphOf A).tdom_of_anc (Facts.walkUp_anc idom a fuel b h) l (walk_reached A hl).2

end Graph

/-! ## Availability -/

section Avail
variable {c : Facts.Ctx} {idom : Array Nat}

theorem table_entry {s : Skel} (h : s.tableOK s.table = true) {v : Nat} {loc : Skel.Loc}
    (hv : s.table[v]? = some (some loc)) :
    match loc with
    | .pre k => s.pre[k]? = some v
    | .phi d k => ((s.blocks[d]?).bind fun b => b.phis[k]?).map (·.value) = some v
    | .inst d k => ((s.blocks[d]?).bind fun b => b.insts[k]?).map (·.value) = some v := by
  unfold Skel.tableOK at h
  simp only [List.all_eq_true, List.mem_range] at h
  have hlt : v < s.table.size := (Array.getElem?_eq_some_iff.mp hv).1
  have := h v hlt
  rw [Facts.arr_get!_of_get? hv] at this
  cases loc <;> simpa using this

/-- What the rule's `availS` gives: the value is available in the sense of `Facts.Avail`. -/
theorem avail_of_availS (hc : CtxOK c) (A : Skel.Accepts (skelOf c.f) idom) {v B k : Nat}
    (h : (skelOf c.f).availS (skelOf c.f).table idom v B k = true) : Avail c B k v := by
  unfold Skel.availS at h
  split at h
  · rename_i k' hv
    have he := table_entry A.table hv
    simp only [skelOf, List.getElem?_map, Option.map_eq_some_iff] at he
    obtain ⟨i, hi, hiv⟩ := he
    have hd := hc.def_pre hi
    rw [hiv] at hd
    unfold Avail; rw [hd]; simp [Facts.preDef]
  · rename_i d k' hv
    have he := table_entry A.table hv
    simp only [Option.map_eq_some_iff, Option.bind_eq_some_iff] at he
    obtain ⟨sp, ⟨sb, hsb, hsp⟩, hspv⟩ := he
    have hdlt : d < c.f.blocks.size := by
      rw [← skel_size]; exact (Array.getElem?_eq_some_iff.mp hsb).1
    have hb : c.f.blocks[d]? = some c.f.blocks[d]! := by
      rw [getElem!_pos c.f.blocks d hdlt]; exact Array.getElem?_eq_getElem hdlt
    rw [skel_block c.f hb] at hsb
    cases hsb
    simp only [List.getElem?_map, Option.map_eq_some_iff] at hsp
    obtain ⟨p, hp, hpe⟩ := hsp
    have hpv : p.value = v := by rw [← hspv, ← hpe]
    have hd := hc.def_phi hb hp
    rw [hpv] at hd
    unfold Avail; rw [hd]
    exact ⟨d, rfl, tdom_of_walkUp A h⟩
  · rename_i d j hv
    have he := table_entry A.table hv
    simp only [Option.map_eq_some_iff, Option.bind_eq_some_iff] at he
    obtain ⟨si, ⟨sb, hsb, hsi⟩, hsiv⟩ := he
    have hdlt : d < c.f.blocks.size := by
      rw [← skel_size]; exact (Array.getElem?_eq_some_iff.mp hsb).1
    have hb : c.f.blocks[d]? = some c.f.blocks[d]! := by
      rw [getElem!_pos c.f.blocks d hdlt]; exact Array.getElem?_eq_getElem hdlt
    rw [skel_block c.f hb] at hsb
    cases hsb
    simp only [List.getElem?_map, Option.map_eq_some_iff] at hsi
    obtain ⟨i, hi, hie⟩ := hsi
    have hiv : i.value = v := by rw [← hsiv, ← hie]
    have hd := hc.def_inst hb hi
    rw [hiv] at hd
    unfold Avail; rw [hd]
    simp only [Facts.instDef]
    refine ⟨d, rfl, ?_⟩
    simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, bne_iff_ne, ne_eq] at h
    rcases h with ⟨hdB, hjk⟩ | ⟨hdB, hw⟩
    · exact Or.inl ⟨hdB, hjk⟩
    · exact Or.inr ⟨hdB, tdom_of_walkUp A hw⟩
  · simp at h

end Avail

/-! ## The theorem -/

section Main
variable {c : Facts.Ctx} {idom : Array Nat}

/-- The rule's verdict on the reached block `d`. -/
theorem block_ok (A : Skel.Accepts (skelOf c.f) idom) {d : Nat} {b : Facts.Block} (hb : c.f.blocks[d]? = some b)
    (hr : (skelOf c.f).reach[d]! = true) :
    (skelOf c.f).blockOK (skelOf c.f).reach (skelOf c.f).table idom d
      { preds := b.preds, phis := b.phis.map fun p => ⟨p.value, p.edges.map fun e => (e.block, e.value)⟩,
        insts := b.insts.map fun i => ⟨i.value, Facts.regOps i⟩, term := b.term } = true := by
  have hlt : d < (skelOf c.f).blocks.size := by rw [skel_size]; exact Facts.arr_lt_of_get? hb
  have := A.blocks d hlt hr
  rw [Facts.arr_get!_of_get? (skel_block c.f hb)] at this
  exact this

/-- The SSA rule on the skeleton of a prepared function gives the fact proof's SSA hypothesis. -/
theorem ssaWf_of_check (hc : CtxOK c) (h : (skelOf c.f).ssaCheck idom = true) : SsaWf c := by
  by_cases hn : (skelOf c.f).blocks.size = 0
  · have hnone : ∀ D : Nat, c.f.blocks[D]? = none := by
      intro D; rw [skel_size] at hn
      exact Array.getElem?_eq_none (by omega)
    refine ⟨?_, ?_, ?_, ?_⟩
    · intro D _ _ _ _ hb; rw [hnone D] at hb; cases hb
    · intro D _ _ _ _ hb; rw [hnone D] at hb; cases hb
    · intro D _ _ _ _ hb; rw [hnone D] at hb; cases hb
    · intro D _ _ hb; rw [hnone D] at hb; cases hb
  have A := Skel.accepts_of_check h hn
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro D k b i v hb hk hR hv
    have hok := block_ok A hb (reached_of_reach A hR)
    unfold Skel.blockOK at hok
    simp only [Bool.and_eq_true, List.all_eq_true] at hok
    have hmem : (⟨i.value, Facts.regOps i⟩, k) ∈ (b.insts.map fun i => (⟨i.value, Facts.regOps i⟩ : SInst)).zipIdx := by
      rw [List.mk_mem_zipIdx_iff_getElem?, List.getElem?_map, hk]; rfl
    exact avail_of_availS hc A (hok.1.1 _ hmem v hv)
  · intro D b p e pb hb hp he hpb hR
    -- The phi's block is reached: its edge's block is a reached predecessor that names it.
    have hpred : e.block ∈ b.preds := by
      have heq := Facts.phisOK_edges hc.phis hb hp
      rw [← heq]; exact List.mem_map_of_mem he
    obtain ⟨pb', hpb', hsucc⟩ := Facts.edgesOK_pred hc.edges hb hpred
    have hRD : Reach (cfgSucc c.f) D := by
      obtain ⟨l, hl⟩ := hR
      refine ⟨_, Walk.step hl ?_⟩
      unfold cfgSucc; rw [hpb']; exact hsucc
    have hok := block_ok A hb (reached_of_reach A hRD)
    unfold Skel.blockOK at hok
    simp only [Bool.and_eq_true, List.all_eq_true] at hok
    have hsp : (⟨p.value, p.edges.map fun e => (e.block, e.value)⟩ : SPhi) ∈
        b.phis.map fun p => (⟨p.value, p.edges.map fun e => (e.block, e.value)⟩ : SPhi) := List.mem_map_of_mem hp
    have hedge := hok.2 _ hsp (e.block, e.value) (List.mem_map_of_mem he)
    have hre : ((skelOf c.f).reach[e.block]?.getD false) = true := by
      have hr := reached_of_reach A hR
      have hlt : e.block < (skelOf c.f).reach.size := by
        rw [A.size, skel_size]; exact Facts.arr_lt_of_get? hpb
      rw [Array.getElem?_eq_getElem hlt]; rw [getElem!_pos (skelOf c.f).reach e.block hlt] at hr; simpa using hr
    simp only [hre, Bool.not_true, Bool.false_or] at hedge
    rw [skel_block c.f hpb] at hedge
    simpa using avail_of_availS hc A hedge
  · intro D b cnd t e hb ht hR
    have hok := block_ok A hb (reached_of_reach A hR)
    unfold Skel.blockOK at hok
    simp only [Bool.and_eq_true, ht] at hok
    simpa using avail_of_availS hc A hok.1.2
  · intro D b v hb ht hR
    have hok := block_ok A hb (reached_of_reach A hR)
    unfold Skel.blockOK at hok
    simp only [Bool.and_eq_true, ht] at hok
    simpa using avail_of_availS hc A hok.1.2

/-- The fact theorem's SSA hypothesis for every certificate whose functions' skeletons the rule accepts. -/
theorem modWf_of_skeletons {mF : Facts.Module}
    (h : ∀ (g : Nat) fF, mF.functions[g]? = some fF → ∃ idom, (skelOf fF).ssaCheck idom = true) : Facts.ModWf mF := by
  intro g c hc
  obtain ⟨hf, _, hok⟩ := Facts.ctxOf_spec hc
  obtain ⟨idom, hidom⟩ := h g c.f hf
  exact ssaWf_of_check hok hidom

/-- An accepted function's translation passes the SSA rule. -/
theorem ssaCheck_of_verdict {m : Module} {fr : Array Bool} {g : Function} (h : verdict m fr g = .ok ()) :
    ∃ idom, (Fn.mk m g).translate.ssaCheck idom = true := by
  unfold verdict at h
  cases h1 : m.checkHeader g with
  | error e => simp [h1, bind, Except.bind] at h
  | ok _ =>
    cases h2 : bodyIdom m g with
    | error e => simp [h1, h2, bind, Except.bind] at h
    | ok idom =>
      refine ⟨idom, ?_⟩
      simp only [h1, h2, bind, Except.bind] at h
      by_cases hs : (Fn.mk m g).translate.ssaCheck idom = true
      · exact hs
      · simp [hs, reject, throw, throwThe, MonadExceptOf.throw] at h

/-- **H2 discharged for a checked build.** If the checker accepts every function of the module `mI` (its final IR) and
the skeletons of the fact certificate `mF` are the translations of `mI`'s functions, then `Facts.ModWf mF`. -/
theorem modWf_of_verdicts {mI : Module} {mF : Facts.Module}
    {fr : Array Bool} (hacc : ∀ (g : Nat) gI, mI.functions[g]? = some gI → verdict mI fr gI = .ok ())
    (htr : translatesB mI mF = true) :
    Facts.ModWf mF := by
  apply modWf_of_skeletons
  intro g fF hf
  unfold translatesB at htr
  simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true, List.mem_range] at htr
  have hg : g < mF.functions.size := Facts.arr_lt_of_get? hf
  have := htr.2 g hg
  rw [hf] at this
  split at this
  · rename_i gI _ hgI hfF
    cases hfF
    have heq : skelOf fF = (Fn.mk mI gI).translate := by simpa using this
    obtain ⟨idom, hidom⟩ := ssaCheck_of_verdict (hacc g gI hgI)
    exact ⟨idom, by rw [heq]; exact hidom⟩
  · simp at this

end Main

/-- An accepted function with a body has verified tag facts. -/
theorem tagOK_of_verdict {m : Module} {fr : Array Bool} {g : Function} (h : verdict m fr g = .ok ())
    (hl : g.sig.linkage = .internal) : ∃ reachable, (Fn.mk m g).tagOK reachable = true := by
  unfold verdict at h
  cases h1 : m.checkHeader g with
  | error e => simp [h1, bind, Except.bind] at h
  | ok _ =>
    cases h2 : bodyIdom m g with
    | error e => simp [h1, h2, bind, Except.bind] at h
    | ok idom =>
      unfold bodyIdom at h2
      simp only [hl, beq_self_eq_true, ite_true] at h2
      cases h3 : (Fn.mk m g).checkBody with
      | error e => simp [h3, bind, Except.bind] at h2
      | ok gr =>
        simp only [h3, bind, Except.bind] at h2
        refine ⟨gr.reachable, ?_⟩
        split at h2
        · simp [reject, throw, throwThe, MonadExceptOf.throw] at h2
        · by_cases ht : (Fn.mk m g).tagOK gr.reachable = true
          · exact ht
          · simp [ht, reject, throw, throwThe, MonadExceptOf.throw] at h2

/-- **F-VL-10 for a checked function.** In a function the checker accepts, every run that runs block `b` and reads there,
by a `union_payload k` or `union_take k`, a value that is not a `list_get` (shape M) holding a union value of case `j`,
has `j = k`. -/
theorem payload_of_verdict {m : Module} {fr : Array Bool} {g : Function} (h : verdict m fr g = .ok ())
    (hl : g.sig.linkage = .internal) {b : Nat} {ρ ρ' : Env} (hx : (Fn.mk m g).Exec b ρ)
    (hstep : (Fn.mk m g).BlockStep b ρ ρ') {blk : Block} (hblk : g.blocks[b]? = some blk) {r : Nat}
    (he : some r ∈ blk.insts) {i : Inst} (hi : g.insts[r]? = some i) (hop : i.op = .unionPayload ∨ i.op = .unionTake)
    {v : Nat} (hv : (Fn.mk m g).canonical i.a = some v) (hm : (Fn.mk m g).instOp v ≠ .listGet) {j : Nat}
    (hval : ρ' v = some (.union j)) : j = i.data := by
  obtain ⟨reachable, hok⟩ := tagOK_of_verdict h hl
  unfold Fn.tagOK at hok
  split at hok
  · simp at hok
  · exact payload_under_tag hok hx hstep hblk he hi hop hv hm hval

end VerifyIr
