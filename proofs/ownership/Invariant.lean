import Facts

/-!
# The run-time invariant of a checked function

`Inv cc args h0 σ ds` relates the checker's abstract state `σ = (L, D, R, P, G, F)` to the
machine state `ds` of an activation entered with arguments `args` in heap `h0`:

* shapes: a value in `L` holds an immediate or the root of a live tree; distinct values of `L`
  own distinct trees (`Linj`); a value of `D` holds an immediate or a pointer set; scalars,
  immortals, emptied aggregates and void values hold immediates; a stack value holds a stack
  allocation (`stk`; an immediate while it is not yet defined), and nothing else does (`nostk`);
* **coverage** (`Dcov`): while every owned root of a borrowed value is still in `L` (a root
  that stands for an owner taken later does not count), each cell it points at is a cell of one
  of its other roots' trees (the tree an owned root owns, or the
  tree of a borrowed parameter), the roots being those recorded in `R` (flow-sensitive);
* **pending takes** (`Pin`, `Gin`, `Pout`): the flag `pend t k` of a root held by a value of `L`
  is the one the open takes predict: set when `(v, k)` is in `P`, or in `G` under a test that
  came out as the guard says;
* **decided tests** (`Fin`): every test of `F` is decided on the machine state, with the
  outcome `F` records when it records one;
* **lent cells** (`lentSeen`, `lentCov`): a cell lent to a group that is still live is covered by a
  root of the loans of the live owned value that holds the group, which records itself as lent-to;
* heap bookkeeping against the entry heap `h0`: cells outside the owned arguments' trees are
  unchanged (`frame`), destroyed cells stay destroyed (`dead`), an unused cell was never used
  (`unused`), every live cell is in the tree of a value of `L` or is an unchanged frame cell
  (`acct`, which is "nothing is leaked or double-owned", except for the trees an edge into a trap region abandoned
  (C9.1): `DState.abandoned`, live, owned by no value of `L` (`abLive`, `Ldisj`); a `ret` is reached with none), and no
  value of `L` owns a tree labelled like a frame cell (`Lfree`).
-/

namespace Own

/-- The cells a root gives access to: the tree an owned value owns (or, for a slot root, the
tree of the aggregate: the semantics does not split a tree by slot), or the trees of a
borrowed parameter (read in the entry heap: they are frame cells and never change). -/
def Covers (cc : CCtx) (args : Nat → Val) (h0 : Heap) (ds : DState) : Root → Addr → Prop
  | .val n, x => ∃ t, ds.env n = .own t ∧ ds.heap x = .live t
  | .slot n _, x => ∃ t, ds.env n = .own t ∧ ds.heap x = .live t
  | .fwd _, _ => False
  | .caller i, x => cc.f.params[i]? = some .borrowed ∧ (args i).cells h0 x

/-- Whether a root is the placeholder of an owner that is taken later. -/
def Root.isFwd : Root → Bool
  | .fwd _ => true
  | _ => false

/-- Whether the open takes `P` and the guarded takes `G` of a state predict that the slot `k` of
the container `v` is pending, given the decided tests. -/
def AbsState.predicts (σ : AbsState) (facts : Key → Option Bool) (v : ValId) (k : String) : Bool :=
  σ.P.contains (v, k) ||
    σ.G.any fun g => g.1 == v && g.2.1 == k && facts g.2.2.1 == some g.2.2.2

/-- The invariant (see the file header). -/
structure Inv (cc : CCtx) (args : Nat → Val) (h0 : Heap) (σ : AbsState) (ds : DState) :
    Prop where
  imm : ∀ v, (cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .emptied ∨
    cc.st v = .none) → ds.env v = .imm
  stk : ∀ v, cc.st v = .stack → ds.env v = .imm ∨ ds.env v = .stk
  nostk : ∀ v, cc.st v ≠ .stack → ds.env v ≠ .stk
  Lown : ∀ v ∈ σ.L, (cc.st v).owning = true
  Lbd : ∀ v ∈ σ.L, v < cc.f.nvals
  Lval : ∀ v ∈ σ.L, ds.env v = .imm ∨ ∃ t, ds.env v = .own t ∧ ds.heap t = .live t
  Linj : ∀ v ∈ σ.L, ∀ w ∈ σ.L, ∀ t, ds.env v = .own t → ds.env w = .own t → v = w
  Dst : ∀ w ∈ σ.D, cc.st w = .borrowed
  Dbd : ∀ w ∈ σ.D, w < cc.f.nvals
  Dval : ∀ w ∈ σ.D, ds.env w = .imm ∨ ∃ fp, ds.env w = .bor fp
  Dcov : ∀ w ∈ σ.D, (∀ ρ ∈ Rget σ w, ρ.isFwd = true ∨ rootLive σ ρ = true) →
    ∀ fp, ds.env w = .bor fp →
    ∀ x ∈ fp, ∃ ρ ∈ Rget σ w, ρ.isFwd = false ∧ Covers cc args h0 ds ρ x
  Pin : ∀ p ∈ σ.P, p.1 ∈ σ.L ∧
    (ds.env p.1 = .imm ∨ ∃ t, ds.env p.1 = .own t ∧ ds.pend t p.2 = true)
  Gin : ∀ g ∈ σ.G, g.1 ∈ σ.L ∧ ds.facts g.2.2.1 ≠ none ∧
    (ds.env g.1 = .imm ∨ ∃ t, ds.env g.1 = .own t ∧
      (ds.pend t g.2.1 = true ↔ ds.facts g.2.2.1 = some g.2.2.2))
  Pout : ∀ v ∈ σ.L, ∀ t, ds.env v = .own t → ∀ k, ds.pend t k = true →
    σ.predicts ds.facts v k = true
  Fin : ∀ f ∈ σ.F, ds.facts f.1 ≠ none ∧ ∀ p, f.2 = some p → ds.facts f.1 = some p
  frame : ∀ x t, h0 x = .live t → ¬ OwnedArg cc.f args t → ds.heap x = .live t
  dead : ∀ x, h0 x = .dead → ds.heap x = .dead
  unused : ∀ x, ds.heap x = .unused → h0 x = .unused
  acct : ∀ x t, ds.heap x = .live t →
    (∃ v ∈ σ.L, ds.env v = .own t) ∨ (h0 x = .live t ∧ ¬ OwnedArg cc.f args t) ∨ ds.abandoned t
  /-- an abandoned tree is live, and no owner of `L` owns it (C9.1): the owners an edge abandons leave `L` and
  nothing else is ever given their tree -/
  abLive : ∀ t, ds.abandoned t → ds.heap t = .live t
  Ldisj : ∀ v ∈ σ.L, ∀ t, ds.env v = .own t → ¬ ds.abandoned t
  abFree : ∀ t, ds.abandoned t → ∀ x, h0 x = .live t → OwnedArg cc.f args t
  Lfree : ∀ v ∈ σ.L, ∀ t, ds.env v = .own t → ∀ x, h0 x = .live t → OwnedArg cc.f args t
  /-- a group that cells were lent to was allocated: it is live or destroyed, never unused -/
  lentSeen : ∀ g x, ds.lent g x → ds.heap g ≠ .unused
  /-- **the lent-cell invariant** (design §10.6): a cell lent to a live group is covered by a loan
  that the group's holder keeps.  The holder is a live owned value of `L` whose tree contains the
  group's root cell and that records itself as a lent-to value (`.val v ∈ Rget σ v`, the mark
  `groupJoinOk` reads); one of its roots, still alive, covers the cell. -/
  lentCov : ∀ g x, ds.lent g x → (∃ l, ds.heap g = .live l) →
    ∃ v ∈ σ.L, ∃ t, ds.env v = .own t ∧ ds.heap g = .live t ∧ Root.val v ∈ Rget σ v ∧
      ∃ ρ ∈ Rget σ v, ρ.isFwd = false ∧ rootLive σ ρ = true ∧ Covers cc args h0 ds ρ x
  /-- a cell held by a tree that was allocated was allocated -/
  heldSeen : ∀ g x, ds.held g x → ds.heap g ≠ .unused
  /-- **the loan invariant** (J4, design §5): a cell held by a live tree is in that tree or covered by a
  live root of the loans of the live owned value that owns it. -/
  heldCov : ∀ g x, ds.held g x → (∃ l, ds.heap g = .live l) →
    ∃ v ∈ σ.L, ∃ t, ds.env v = .own t ∧ ds.heap g = .live t ∧
      (ds.heap x = .live t ∨
        ∃ ρ ∈ Rget σ v, ρ.isFwd = false ∧ rootLive σ ρ = true ∧ Covers cc args h0 ds ρ x)

/-- A value of a kind that owns nothing holds no cell: an immediate or a stack allocation. -/
theorem Inv.noOwn {cc : CCtx} {args : Nat → Val} {h0 : Heap} {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) {v : ValId}
    (h : cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .stack ∨ cc.st v = .emptied ∨
      cc.st v = .none) : ds.env v = .imm ∨ ds.env v = .stk := by
  rcases h with h | h | h | h | h
  · exact Or.inl (hI.imm v (by simp [h]))
  · exact Or.inl (hI.imm v (by simp [h]))
  · exact hI.stk v h
  · exact Or.inl (hI.imm v (by simp [h]))
  · exact Or.inl (hI.imm v (by simp [h]))

/-- The kinds a consumed no-op operand has (`Facts.InstOk.c2`) hold no tree. -/
theorem Inv.noOwn4 {cc : CCtx} {args : Nat → Val} {h0 : Heap} {σ : AbsState} {ds : DState}
    (hI : Inv cc args h0 σ ds) {v : ValId}
    (h : cc.st v = .scalar ∨ cc.st v = .immortal ∨ cc.st v = .stack ∨ cc.st v = .none) :
    ds.env v = .imm ∨ ds.env v = .stk :=
  hI.noOwn (by rcases h with h | h | h | h <;> simp [h])

/-- What the proof takes from the entry checks and the contract. -/
structure Static (cc : CCtx) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool) :
    Prop where
  pre : Pre cc.f args h0 pend0
  lens : cc.f.params.length = cc.f.paramVals.length
  pok : paramsOk cc.c 0 cc.f.paramVals cc.f.params = true
  nodup : cc.f.paramVals.Nodup
  /-- the checker's lookup of the defining instruction is the model's (values are defined once) -/
  defEq : ∀ x, cc.defOf[x]? = cc.f.defOf? x

/-! ## Lists -/

theorem idxOf?_spec (l : List ValId) (d : ValId) (n : Nat) (h : idxOf? l d = some n) :
    l[n]? = some d := by
  induction l generalizing n with
  | nil => simp [idxOf?] at h
  | cons x xs ih =>
    unfold idxOf? at h
    split at h
    · rename_i hx
      simp at h
      subst h
      simp at hx
      simp [hx]
    · cases hr : idxOf? xs d with
      | none => simp [hr] at h
      | some m =>
        simp [hr] at h
        subst h
        simpa using ih m hr

theorem idxOf?_of_nodup (l : List ValId) (hl : l.Nodup) (d : ValId) (n : Nat)
    (h : l[n]? = some d) : idxOf? l d = some n := by
  induction l generalizing n with
  | nil => simp at h
  | cons x xs ih =>
    rw [List.nodup_cons] at hl
    cases n with
    | zero =>
      simp at h
      subst h
      simp [idxOf?]
    | succ m =>
      simp at h
      have hne : x ≠ d := by
        intro hxd
        subst hxd
        exact hl.1 (List.mem_of_getElem? h)
      have := ih hl.2 m h
      simp [idxOf?, hne, this]

theorem mem_zip_idx {α β : Type} (l1 : List α) (l2 : List β) (a : α) (b : β) :
    (a, b) ∈ l1.zip l2 ↔ ∃ n : Nat, l1[n]? = some a ∧ l2[n]? = some b := by
  induction l1 generalizing l2 with
  | nil => simp
  | cons x xs ih =>
    cases l2 with
    | nil => simp
    | cons y ys =>
      simp only [List.zip_cons_cons, List.mem_cons, ih]
      constructor
      · rintro (h | ⟨n, h1, h2⟩)
        · obtain ⟨rfl, rfl⟩ := Prod.mk.inj h.symm
          exact ⟨0, by simp, by simp⟩
        · exact ⟨n + 1, by simpa using h1, by simpa using h2⟩
      · rintro ⟨n, h1, h2⟩
        cases n with
        | zero =>
          simp at h1 h2
          left; simp [h1, h2]
        | succ m => right; exact ⟨m, by simpa using h1, by simpa using h2⟩

/-! ## Parameters -/

theorem paramsOk_spec (c : Certificate) :
    ∀ (vs : List ValId) (ks : List St) (i : Nat), paramsOk c i vs ks = true →
    vs.length = ks.length ∧ ∀ n v k, vs[n]? = some v → ks[n]? = some k →
      (k = .scalar ∧ c.state v = .scalar) ∨ (k = .owned ∧ (c.state v = .owned ∨ c.state v = .scalar)) ∨
      (k = .borrowed ∧ c.state v = .borrowed ∧ c.parents v = [.caller (i + n)]) := by
  intro vs
  induction vs with
  | nil =>
    intro ks i h
    cases ks with
    | nil => simp
    | cons k ks => simp [paramsOk] at h
  | cons v vs ih =>
    intro ks i h
    cases ks with
    | nil => simp [paramsOk] at h
    | cons k ks =>
      simp only [paramsOk, Bool.and_eq_true] at h
      obtain ⟨hk, hrest⟩ := h
      obtain ⟨hlen, hsp⟩ := ih ks (i + 1) hrest
      refine ⟨by simp [hlen], ?_⟩
      intro n v' k' hv hk'
      cases n with
      | zero =>
        have hv0 : v = v' := by simpa using hv
        have hk0 : k = k' := by simpa using hk'
        subst hv0 hk0
        cases k <;> simp at hk
        · left; exact ⟨rfl, hk⟩
        · right; left; exact ⟨rfl, hk⟩
        · right; right
          exact ⟨rfl, hk.1, by simpa using hk.2⟩
      | succ m =>
        simp at hv hk'
        have := hsp m v' k' hv hk'
        have e : i + 1 + m = i + (m + 1) := by omega
        rw [e] at this
        exact this

/-! ## Bounds -/

theorem foldl_max_ge (l : List Nat) (m : Nat) :
    m ≤ l.foldl (fun m n => max m (n + 1)) m := by
  induction l generalizing m with
  | nil => simp
  | cons x xs ih =>
    simp only [List.foldl_cons]
    exact Nat.le_trans (Nat.le_max_left _ _) (ih _)

theorem lt_foldl_max (l : List Nat) (m : Nat) : ∀ x ∈ l, x < l.foldl (fun m n => max m (n + 1)) m := by
  induction l generalizing m with
  | nil => simp
  | cons y ys ih =>
    intro x hx
    simp only [List.foldl_cons]
    rcases List.mem_cons.1 hx with rfl | hx
    · exact Nat.lt_of_lt_of_le (Nat.lt_of_lt_of_le (Nat.lt_succ_self _) (Nat.le_max_right _ _))
        (foldl_max_ge ys _)
    · exact ih _ x hx

theorem paramVals_lt (f : Function) (v : ValId) (hv : v ∈ f.paramVals) : v < f.nvals := by
  unfold Function.nvals
  apply lt_foldl_max
  simp [hv]

theorem inst_dst_lt (f : Function) (i : Inst) (d : ValId) (hi : i ∈ f.allInsts)
    (hd : i.dst = some d) : d < f.nvals := by
  unfold Function.nvals
  apply lt_foldl_max
  simp only [List.mem_append, List.mem_filterMap]
  left; right
  exact ⟨i, hi, hd⟩

theorem phi_dst_lt (f : Function) (blk : Block) (φ : Phi) (hb : blk ∈ f.blocks)
    (hφ : φ ∈ blk.phis) : φ.dst < f.nvals := by
  unfold Function.nvals
  apply lt_foldl_max
  simp only [List.mem_append, List.mem_flatMap, List.mem_map]
  right
  exact ⟨blk, hb, φ, hφ, rfl⟩

theorem mem_allInsts_of_block (f : Function) (blk : Block) (i : Inst) (hb : blk ∈ f.blocks)
    (hi : i ∈ blk.insts) : i ∈ f.allInsts := by
  unfold Function.allInsts
  simp only [List.mem_append, List.mem_flatMap]
  right
  exact ⟨blk, hb, hi⟩

end Own
