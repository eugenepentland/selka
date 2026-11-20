import Facts.Sem
import Facts.Dom

/-!
# What an accepted preparation gives

The checker's preparation (`prepare`) computes the definitions, the list index, the dominator tree and the
reached set, and verifies them with total functions. This file turns those verdicts into statements about the
function the soundness proof can use.
-/

namespace Facts

theorem arr_get!_of_get? {α : Type} [Inhabited α] {xs : Array α} {i : Nat} {b : α} (h : xs[i]? = some b) :
    xs[i]! = b := by
  obtain ⟨hi, e⟩ := Array.getElem?_eq_some_iff.mp h
  rw [getElem!_pos xs i hi, e]

theorem arr_lt_of_get? {α : Type} {xs : Array α} {i : Nat} {b : α} (h : xs[i]? = some b) : i < xs.size :=
  (Array.getElem?_eq_some_iff.mp h).1

/-! ### The control-flow graph -/

/-- The control-flow graph of a function: a block goes to the targets of its terminator. -/
def cfgSucc (f : Function) (p : Nat) : List Nat :=
  match f.blocks[p]? with
  | some b => successors b.term
  | none => []

/-! ### Definitions -/

section Defs
variable {f : Function} {n : Nat} {defs : Array Def}

theorem defsOK_pre (h : defsOK f n defs = true) {i : Inst} {k : Nat} (hk : f.pre[k]? = some i) :
    defs[i.value]? = some (preDef i k) := by
  unfold defsOK at h
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  have := h.1.1.2 (i, k) (List.mk_mem_zipIdx_iff_getElem?.mpr hk)
  simpa using this

theorem defsOK_phi (h : defsOK f n defs = true) {pos k : Nat} {b : Block} {p : Phi}
    (hb : f.blocks[pos]? = some b) (hk : b.phis[k]? = some p) : defs[p.value]? = some (phiDef pos k p) := by
  unfold defsOK at h
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  have hpos : pos ∈ List.range f.blocks.size := List.mem_range.mpr (arr_lt_of_get? hb)
  have := (h.1.2 pos hpos).1 (p, k) (List.mk_mem_zipIdx_iff_getElem?.mpr (by rw [arr_get!_of_get? hb]; exact hk))
  simpa using this

theorem defsOK_inst (h : defsOK f n defs = true) {pos k : Nat} {b : Block} {i : Inst}
    (hb : f.blocks[pos]? = some b) (hk : b.insts[k]? = some i) : defs[i.value]? = some (instDef pos k i) := by
  unfold defsOK at h
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  have hpos : pos ∈ List.range f.blocks.size := List.mem_range.mpr (arr_lt_of_get? hb)
  have := (h.1.2 pos hpos).2 (i, k) (List.mk_mem_zipIdx_iff_getElem?.mpr (by rw [arr_get!_of_get? hb]; exact hk))
  simpa using this

theorem defsOK_conv (h : defsOK f n defs = true) {v : Nat} {d : Def} (hv : defs[v]? = some d) :
    defItemOK f v d = true := by
  unfold defsOK at h
  simp only [Bool.and_eq_true, decide_eq_true_eq, List.all_eq_true] at h
  have := h.2 v (List.mem_range.mpr (arr_lt_of_get? hv))
  rw [arr_get!_of_get? hv] at this
  exact this

theorem defItemOK_missing {v : Nat} {d : Def} (hk : d.kind = .missing) (h : defItemOK f v d = true) : d = {} := by
  unfold defItemOK at h
  rw [hk] at h
  simpa using h

theorem defItemOK_inst {v : Nat} {d : Def} (hk : d.kind = .inst) (h : defItemOK f v d = true) :
    ∃ pos b i, d.block = some pos ∧ f.blocks[pos]? = some b ∧ b.insts[d.index]? = some i ∧ i.value = v ∧
      d.inst = some i := by
  unfold defItemOK at h
  rw [hk] at h
  simp only at h
  split at h
  · rename_i pos i hb hi
    split at h
    · rename_i b hbl
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      exact ⟨pos, b, i, hb, hbl, h.1, h.2, hi⟩
    · simp at h
  · simp at h

theorem defItemOK_phi {v : Nat} {d : Def} (hk : d.kind = .phi) (h : defItemOK f v d = true) :
    ∃ pos b p, d.block = some pos ∧ f.blocks[pos]? = some b ∧ b.phis[d.index]? = some p ∧ p.value = v ∧
      d.phi = some p := by
  unfold defItemOK at h
  rw [hk] at h
  simp only at h
  split at h
  · rename_i pos p hb hp
    split at h
    · rename_i b hbl
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      exact ⟨pos, b, p, hb, hbl, h.1, h.2, hp⟩
    · simp at h
  · simp at h

theorem defItemOK_pre {v : Nat} {d : Def} (hk : d.kind = .pre) (h : defItemOK f v d = true) :
    ∃ i, f.pre[d.index]? = some i ∧ i.value = v ∧ d.inst = some i ∧ d.block = none := by
  unfold defItemOK at h
  rw [hk] at h
  simp only at h
  split at h
  · rename_i i hi
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨i, h.1.1, h.1.2, hi, h.2⟩
  · simp at h

end Defs

section Shape
variable {f : Function}

theorem edgesOK_succ (h : edgesOK f = true) {pos t : Nat} {b : Block} (hb : f.blocks[pos]? = some b)
    (ht : t ∈ successors b.term) : ∃ tb, f.blocks[t]? = some tb ∧ pos ∈ tb.preds := by
  unfold edgesOK at h
  simp only [List.all_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
  have hpos : pos ∈ List.range f.blocks.size := List.mem_range.mpr (arr_lt_of_get? hb)
  have := (h pos hpos).1 t (by rw [arr_get!_of_get? hb]; exact ht)
  obtain ⟨hlt, hmem⟩ := this
  have hget : f.blocks[t]? = some f.blocks[t]! := by
    rw [getElem!_pos f.blocks t hlt]; exact Array.getElem?_eq_getElem hlt
  exact ⟨_, hget, hmem⟩

theorem edgesOK_pred (h : edgesOK f = true) {pos p : Nat} {b : Block} (hb : f.blocks[pos]? = some b)
    (hp : p ∈ b.preds) : ∃ pb, f.blocks[p]? = some pb ∧ pos ∈ successors pb.term := by
  unfold edgesOK at h
  simp only [List.all_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
  have hpos : pos ∈ List.range f.blocks.size := List.mem_range.mpr (arr_lt_of_get? hb)
  have := (h pos hpos).2 p (by rw [arr_get!_of_get? hb]; exact hp)
  obtain ⟨hlt, hmem⟩ := this
  have hget : f.blocks[p]? = some f.blocks[p]! := by
    rw [getElem!_pos f.blocks p hlt]; exact Array.getElem?_eq_getElem hlt
  exact ⟨_, hget, hmem⟩

theorem phisOK_edges (h : phisOK f = true) {pos : Nat} {b : Block} {p : Phi} (hb : f.blocks[pos]? = some b)
    (hp : p ∈ b.phis) : p.edges.map (·.block) = b.preds := by
  unfold phisOK at h
  simp only [List.all_eq_true, decide_eq_true_eq] at h
  have hpos : pos ∈ List.range f.blocks.size := List.mem_range.mpr (arr_lt_of_get? hb)
  have := h pos hpos p (by rw [arr_get!_of_get? hb]; exact hp)
  rw [arr_get!_of_get? hb] at this
  exact this

theorem entryOK_entry (h : entryOK f = true) {b : Block} (hb : f.blocks[0]? = some b) :
    b.preds = [] ∧ b.phis = [] := by
  unfold entryOK at h
  simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at h
  rcases h with h | h
  · have := arr_lt_of_get? hb
    omega
  · rw [arr_get!_of_get? hb] at h
    simp only [List.isEmpty_iff] at h
    exact h

theorem paramsOK_inst (h : paramsOK f = true) {pos : Nat} {b : Block} {i : Inst}
    (hb : f.blocks[pos]? = some b) (hi : i ∈ b.insts) (hp : i.op = .param) :
    f.header.params[i.imm]? = some i.ty := by
  unfold paramsOK at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 pos (List.mem_range.mpr (arr_lt_of_get? hb)) i (by rw [arr_get!_of_get? hb]; exact hi)
  simpa [hp] using this

theorem paramsOK_pre (h : paramsOK f = true) {i : Inst} (hi : i ∈ f.pre) (hp : i.op = .param) :
    f.header.params[i.imm]? = some i.ty := by
  unfold paramsOK at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have := h.1 i hi
  simpa [hp] using this

theorem listsOK_mem {lists : Array (Option ListFact)} (h : listsOK f lists = true) {v : Nat} {fact : ListFact}
    (hv : lists[v]? = some (some fact)) : fact.value = v ∧ fact ∈ f.aux.lists := by
  unfold listsOK at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have hlt := arr_lt_of_get? hv
  have := h.1 v (List.mem_range.mpr hlt)
  rw [arr_get!_of_get? hv] at this
  simpa using this

theorem listsOK_find {lists : Array (Option ListFact)} (h : listsOK f lists = true) {fact : ListFact}
    (hf : fact ∈ f.aux.lists) : lists[fact.value]? = some (some fact) := by
  unfold listsOK at h
  simp only [Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
  exact h.2 fact hf

end Shape

/-! ### Dominators and reachability -/

section DomFacts
variable {f : Function} {idom depth : Array Nat}

theorem domOK_size (h : domOK f idom depth = true) : idom.size = f.blocks.size := by
  unfold domOK at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1

theorem domOK_entry (h : domOK f idom depth = true) (hc : 0 < f.blocks.size) : idom[0]? = some 0 := by
  unfold domOK at h
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  rcases h.2 with h2 | h2
  · omega
  · exact h2.1.1

theorem domOK_succ (h : domOK f idom depth = true) {b s : Nat} (hb : b < f.blocks.size)
    (hi : idom[b]! ≠ noBlock) (hs : s ∈ successors f.blocks[b]!.term) :
    s < f.blocks.size ∧ idom[s]! ≠ noBlock := by
  unfold domOK at h
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq, List.all_eq_true, bne_iff_ne,
    ne_eq] at h
  rcases h.2 with h2 | h2
  · omega
  · have := (h2.2 b (List.mem_range.mpr hb)).1.2
    rcases this with h3 | h3
    · exact absurd h3 hi
    · exact h3 s hs

theorem domOK_pred (h : domOK f idom depth = true) {b p : Nat} (hb : b < f.blocks.size) (hb0 : b ≠ 0)
    (hi : idom[b]! ≠ noBlock) (hp : p ∈ f.blocks[b]!.preds) :
    p ≥ f.blocks.size ∨ idom[p]! = noBlock ∨ walkUp idom idom[b]! (f.blocks.size + 1) p = true := by
  unfold domOK at h
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq, List.all_eq_true, bne_iff_ne,
    ne_eq] at h
  rcases h.2 with h2 | h2
  · omega
  · have := (h2.2 b (List.mem_range.mpr hb)).2
    rcases this with (h3 | h3) | h3
    · exact absurd h3 hb0
    · exact absurd h3 hi
    · rcases h3 p hp with (h4 | h4) | h4
      · exact Or.inl h4
      · exact Or.inr (Or.inl h4)
      · exact Or.inr (Or.inr h4)

end DomFacts

/-- Walking up from `x` through at most `fuel` parents finds `a` only if `a` is an ancestor. -/
theorem walkUp_anc (idom : Array Nat) (a : Nat) :
    ∀ (fuel x : Nat), walkUp idom a fuel x = true → Anc (parentOf idom) a x := by
  intro fuel
  induction fuel with
  | zero =>
    intro x h
    simp [walkUp] at h
    subst h; exact Anc.refl _
  | succ n ih =>
    intro x h
    simp only [walkUp, Bool.or_eq_true, beq_iff_eq] at h
    rcases h with h | h
    · subst h; exact Anc.refl _
    · split at h
      · exact absurd h (by simp)
      · rename_i d hd
        exact Anc.step hd (ih d h)

section ReachFacts
variable {c : Ctx}

theorem reachOK_entry (h : reachOK c = true) (hc : 0 < c.f.blocks.size) : c.reached[0]? = some true := by
  unfold reachOK at h
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq] at h
  have hsz := h.1
  have hcount : c.count = c.f.blocks.size := rfl
  rcases h.2 with h2 | h2
  · rw [hcount] at h2; omega
  · have h0 : 0 < c.reached.size := by rw [hsz]; exact hc
    have h1 := h2.1
    rw [getElem!_pos c.reached 0 h0] at h1
    rw [Array.getElem?_eq_getElem h0, h1]

theorem reachOK_succ (h : reachOK c = true) {b s : Nat} (hb : b < c.f.blocks.size)
    (hr : c.reached[b]? = some true) (hs : s ∈ successors c.f.blocks[b]!.term) :
    s < c.f.blocks.size ∧ (edgeOpen c b s = true → c.reached[s]? = some true) := by
  unfold reachOK at h
  simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, beq_iff_eq, List.all_eq_true,
    Bool.not_eq_true'] at h
  have hcount : c.count = c.f.blocks.size := rfl
  rcases h.2 with h2 | h2
  · rw [hcount] at h2; omega
  · have h3 := h2.2 b (by rw [hcount]; exact List.mem_range.mpr hb)
    rw [arr_get!_of_get? hr] at h3
    rcases h3 with h3 | h3
    · exact absurd h3 (by simp)
    · obtain ⟨hlt, hopen⟩ := h3 s hs
      refine ⟨by rw [hcount] at hlt; exact hlt, fun ho => ?_⟩
      rcases hopen with h4 | h4
      · rw [ho] at h4; exact absurd h4 (by simp)
      · have hs' : s < c.reached.size := by rw [h.1, hcount] at *; omega
        rw [Array.getElem?_eq_getElem hs']
        rw [getElem!_pos c.reached s hs'] at h4
        rw [h4]

end ReachFacts

/-! ### The tree as a graph -/

theorem parentOf_eq {idom : Array Nat} {b d : Nat} (hb : b ≠ 0) (hd : idom[b]? = some d) (hn : d ≠ noBlock) :
    parentOf idom b = some d := by
  simp [parentOf, hb, hd, hn]

/-- The graph of a prepared function: its terminators and the verified tree. -/
def ctxGraph (c : Ctx) (hc : 0 < c.f.blocks.size) (hdom : domOK c.f c.idom c.depth = true)
    (hedge : edgesOK c.f = true) (hentry : ∀ tb, c.f.blocks[0]? = some tb → tb.preds = []) : Graph where
  succ := cfgSucc c.f
  par := parentOf c.idom
  tr b := b < c.f.blocks.size ∧ c.idom[b]! ≠ noBlock
  entry_tr := by
    refine ⟨hc, ?_⟩
    have := domOK_entry hdom hc
    rw [arr_get!_of_get? this]
    simp [noBlock]
  par_entry := by simp [parentOf]
  succ_tr := by
    intro p b hp hb
    obtain ⟨hplt, hpi⟩ := hp
    have hpb : c.f.blocks[p]? = some c.f.blocks[p]! := by
      rw [getElem!_pos c.f.blocks p hplt]; exact Array.getElem?_eq_getElem hplt
    unfold cfgSucc at hb
    rw [hpb] at hb
    exact domOK_succ hdom hplt hpi hb
  parent_anc := by
    intro p b hp hb hb0
    obtain ⟨hplt, hpi⟩ := hp
    have hpb : c.f.blocks[p]? = some c.f.blocks[p]! := by
      rw [getElem!_pos c.f.blocks p hplt]; exact Array.getElem?_eq_getElem hplt
    unfold cfgSucc at hb
    rw [hpb] at hb
    obtain ⟨hblt, hbi⟩ := domOK_succ hdom hplt hpi hb
    obtain ⟨tb, htb, hmem⟩ := edgesOK_succ hedge hpb hb
    have htb' : c.f.blocks[b]! = tb := arr_get!_of_get? htb
    have hp' : p ∈ c.f.blocks[b]!.preds := by rw [htb']; exact hmem
    have hsz : c.idom.size = c.f.blocks.size := domOK_size hdom
    have hidx : c.idom[b]? = some c.idom[b]! := by
      have : b < c.idom.size := by rw [hsz]; exact hblt
      rw [getElem!_pos c.idom b this]; exact Array.getElem?_eq_getElem this
    refine ⟨c.idom[b]!, parentOf_eq hb0 hidx hbi, ?_⟩
    rcases domOK_pred hdom hblt hb0 hbi hp' with h | h | h
    · omega
    · exact absurd h hpi
    · exact walkUp_anc c.idom _ _ _ h
  entry_nopred := by
    intro p hp
    unfold cfgSucc at hp
    split at hp
    · rename_i pb hpb
      obtain ⟨tb, htb, hmem⟩ := edgesOK_succ hedge hpb hp
      rw [hentry tb htb] at hmem
      simp at hmem
    · simp at hp

/-! ### What `prepare` gives -/

/-- The verified parts of a prepared context. -/
structure CtxOK (c : Ctx) : Prop where
  struct : structOK c.f c.n c.defs c.lists = true
  dom : domOK c.f c.idom c.depth = true
  reach : reachOK c = true

theorem prepare_ok {m : Module} {f : Function} {c : Ctx} (h : prepare m f = .ok c) :
    c.m = m ∧ c.f = f ∧ CtxOK c := by
  unfold prepare at h
  cases hsh : shape f with
  | error e => simp [hsh, bind, Except.bind] at h
  | ok r =>
    obtain ⟨n, defs, lists, caps⟩ := r
    simp only [hsh, bind, Except.bind] at h
    split at h
    · simp at h
    · rename_i h1
      split at h
      · simp at h
      · rename_i h0
        split at h
        · simp at h
        · rename_i h2
          split at h
          · simp at h
          · rename_i h3
            simp only [pure, Except.pure, Except.ok.injEq] at h
            subst h
            exact ⟨rfl, rfl, ⟨by simpa using h1, by simpa using h2, by simpa using h3⟩⟩

namespace CtxOK
variable {c : Ctx}

theorem defs (h : CtxOK c) : defsOK c.f c.n c.defs = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.1.1.1.1.1

theorem edges (h : CtxOK c) : edgesOK c.f = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.1.1.1.1.2

theorem phis (h : CtxOK c) : phisOK c.f = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.1.1.1.2

theorem entry (h : CtxOK c) : entryOK c.f = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.1.1.2

theorem lists (h : CtxOK c) : listsOK c.f c.lists = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.1.2

theorem pre (h : CtxOK c) : preOK c.f = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.1.2

theorem params (h : CtxOK c) : paramsOK c.f = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.1.2

theorem typed (h : CtxOK c) : typedOK c.f c.defs = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.1.2

theorem statedOk (h : CtxOK c) : statedOK c.defs = true := by
  have := h.struct
  unfold structOK at this
  simp only [Bool.and_eq_true] at this
  exact this.2

end CtxOK

end Facts
