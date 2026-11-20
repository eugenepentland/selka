import Facts.Trans
import Facts.ViewSound
import Facts.Static
import Facts.Accept
import Facts.EnterRegs
import Facts.Reinterpret
import Facts.ListDerive
import Facts.Chain

/-!
# The invariant

What holds of every frame of every execution of an accepted module (design §7, "Proof sketch"), and the
assumptions `Adm` an execution must honour: the facts the checker accepts without a derivation (design §8, A6).
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-! ### Values -/

/-- `n` is within the interval `base` gives value `v` (its type's range when `base` gives none). -/
def InBase (c : Ctx) (v : Nat) (n : Int) : Prop :=
  ∀ lim, (c.def_ v).ty.range = some lim → ((base c v).getD lim).contains n

/-- `n` is within the interval stated for `v`. -/
def StatedOK (c : Ctx) (v : Nat) (n : Int) : Prop :=
  ∀ r lim, (c.def_ v).stated = some r → (c.def_ v).ty.range = some lim → r.contains n

/-- What a register holds: a value of its type, within its base and its stated interval. -/
def ValOK (c : Ctx) (v : Nat) (x : Val) : Prop :=
  ValTy (c.def_ v).ty x ∧ ∀ n, x = .int n → InBase c v n ∧ StatedOK c v n

/-- The refining edge into block `x`, if any, holds of the registers: its comparison had the value that selects the
arm, and its operands lie in their views at the block that holds it, at every depth. -/
def RefHolds (c : Ctx) (R : Regs) (x : Nat) : Prop :=
  match refining c x with
  | none => True
  | some e => ∀ fuel, EdgeFacts c R (viewN c fuel) e

/-- The register of instruction `i` is what `i` computes from the current registers. -/
def Cons (R : Regs) (args : List Val) (i : Inst) : Prop :=
  ∀ x, R i.value = some x → ∃ ch, evalInst R args i ch = .val x

/-- The arguments of a frame satisfy the parameter intervals the function states. -/
def ArgsOK (c : Ctx) (args : List Val) : Prop :=
  ∀ (k : Nat) (claim : Interval) (a : Val) (n : Int), paramClaim c k = some claim → args[k]? = some a →
    paramVal ((c.f.header.params[k]?).getD .other) a = .int n → claim.contains n

/-- The counter of the counted loop `k` with header `H` lies where design §5.5 puts it: from the base interval of its
start to the larger of that interval's top and the bound's top. -/
def CounterHolds (c : Ctx) (R : Regs) (H : Nat) (k : Counted) (lim : Interval) : Prop :=
  ∃ nc, R k.counter = some (.int nc) ∧ ∀ I, c.operand (some k.bound) H = some I →
    ((base c k.start).getD lim).lo ≤ nc ∧ nc ≤ max ((base c k.start).getD lim).hi I.hi

/-! ### The assumptions -/

/-- The value is the result of an instruction whose interval the checker accepts without a derivation. -/
def AssumedVal (c : Ctx) (v : Nat) : Prop :=
  ∃ i, (c.def_ v).inst = some i ∧ (c.def_ v).kind ≠ .phi ∧ c.instOut i ((c.def_ v).block.getD 0) = .assumed

/-- The value is a phi whose interval the checker accepts by a reduction (design §5.5), not by the hull of its operands
nor by a counted loop's counter (alone or met with the hull, `counterAccepts`). -/
def PhiLoop (c : Ctx) (v : Nat) : Prop :=
  ∃ (p : Phi) (H : Nat) (stated limits derived : Interval), (c.def_ v).phi = some p ∧ (c.def_ v).block = some H ∧
    p.range = some stated ∧ p.ty.range = some limits ∧ c.phiHull p H limits = some derived ∧
    ¬ derived.within stated = true ∧ ∀ b, c.counterBound p H = some b → ¬ counterAccepts b derived limits stated = true

/-- What the stated facts of the list `v` say of the list `l` it holds. -/
def ListHolds (c : Ctx) (v : Nat) (l : List Val) : Prop :=
  match c.listFact? (c.liveList c.count v) with
  | none => True
  | some fact =>
    (∀ I, fact.len = some I → I.contains l.length) ∧
    (∀ I, fact.elems = some I → ∀ e ∈ l, ∃ n, e = .int n ∧ I.contains n)

theorem listHolds_of_fact {c : Ctx} {v : Nat} {l : List Val} (h : FactHolds c (c.liveList c.count v) l) :
    ListHolds c v l := h

/-- The assumptions A6 (and the loop facts the proof does not yet derive) hold of the registers of a frame
at block `B`. -/
structure AdmFrame (c : Ctx) (R : Regs) (B : Nat) : Prop where
  /-- Results the checker accepts without derivation (A6). -/
  stated : ∀ v n, R v = some (.int n) → AssumedVal c v → StatedOK c v n
  /-- Phis the checker accepts by a counted loop or a reduction. -/
  phi : ∀ v n, R v = some (.int n) → PhiLoop c v → (∀ p H r, (c.def_ v).phi = some p → (c.def_ v).block = some H →
    p.range = some r → ¬ ChainProved c p H r) → StatedOK c v n
  /-- A fill cap: a bound `v <= M` in the blocks the exit of the fill loop dominates (A2, A6). -/
  caps : ∀ cap ∈ c.caps, TDom c.succ cap.block B → ∀ n, R cap.value = some (.int n) → n ≤ maxListLength
  /-- A stated list length the checker accepts without a derivation (A6). -/
  listLen : ∀ v l I, R v = some (.list l) → LenAssumed c v I → I.contains l.length
  /-- A stated element interval the checker accepts without a derivation (A6). -/
  listElems : ∀ v l I, R v = some (.list l) → ElemsAssumed c v I → ∀ e ∈ l, ∃ n, e = .int n ∧ I.contains n
  /-- A call to a function without a body returns within the interval that function states. -/
  calls : ∀ (w : Nat) (i : Inst) (g : Nat) (callee : Function) (r : Interval) (n : Int), (c.def_ w).inst = some i →
    i.op = .call → callee? c.m i = none → i.operands.a = some g → c.m.functions[g]? = some callee →
    callee.boundary.returns = some r → R w = some (.int n) → r.contains n

/-! ### The frame invariant -/

/-- What holds of a frame running the function of context `c`. -/
structure FrameInv (c : Ctx) (fr : Frame) : Prop where
  /-- The block can be reached. -/
  reach : Reach c.succ fr.blk
  /-- And the checker reached it. -/
  reached : c.reached[fr.blk]? = some true
  /-- Every register holds a value of its type, within its intervals. -/
  val : ∀ v x, fr.regs v = some x → ValOK c v x
  /-- Every value available here is defined. -/
  defd : ∀ v, Avail c fr.blk fr.pc v → ∃ x, fr.regs v = some x
  /-- Every instruction available here still has the value its operands give it. -/
  cons : ∀ v, Avail c fr.blk fr.pc v → ∀ i, (c.def_ v).kind ≠ .phi → (c.def_ v).inst = some i →
    Cons fr.regs fr.args i
  /-- Every refining edge on the way here holds. -/
  ref : ∀ x, TDom c.succ x fr.blk → RefHolds c fr.regs x
  /-- The arguments satisfy the stated parameter intervals. -/
  args : ArgsOK c fr.args
  /-- The counter of every counted loop whose header dominates here lies in its interval. -/
  counter : ∀ (H : Nat) (k : Counted) (lim : Interval), TDom c.succ H fr.blk → c.countedAt H = some k →
    (c.def_ k.counter).ty.range = some lim → CounterSafe c H k lim → CounterHolds c fr.regs H k lim
  /-- Every list a register holds satisfies the facts stated of it. -/
  lst : ListInv c fr.regs
  /-- The phi of a reduction by an accumulator chain, in the states its loop's header dominates, lies in its bound. -/
  red : ∀ (H : Nat) (p : Phi) (ch : ChainInfo c H p) (lim : Interval), TDom c.succ H fr.blk →
    (c.def_ ch.k.counter).ty.range = some lim → CounterSafe c H ch.k lim → ChainBound c fr.regs ch lim
  /-- The start of a counted loop whose header dominates here is produced: its stated interval is not empty. -/
  cstart : ∀ (H : Nat) (k : Counted) (lim : Interval), TDom c.succ H fr.blk → c.countedAt H = some k →
    (c.def_ k.counter).ty.range = some lim → ((base c k.start).getD lim).isEmpty = false
  /-- A join phi whose growth from a phi of the header `H` is derived holds it (the header dominates the join). -/
  jn : ∀ (H acc F q : Nat) (I lacc : Interval), (c.def_ acc).kind = .phi → (c.def_ acc).block = some H →
    (c.def_ acc).ty.range = some lacc → q ≠ acc → c.jGrowth H F acc q = some I → (c.def_ q).kind = .phi →
    Avail c fr.blk fr.pc q → ∃ nq na, fr.regs q = some (.int nq) ∧ fr.regs acc = some (.int na) ∧ I.contains (nq - na)


theorem isEmpty_false_of_contains {r : Interval} {n : Int} (h : r.contains n) : r.isEmpty = false := by
  have h1 := h.1
  have h2 := h.2
  simp only [Interval.isEmpty]
  exact decide_eq_false (by omega)

/-! ### Registers -/

/-- Reading the operands of an instruction depends only on the registers it names. -/
theorem readOps_congr {R R' : Regs} {args : List Val} {i : Inst} (h : ∀ w ∈ regOps i, R' w = R w) :
    readOps R' args i = readOps R args i := by
  unfold readOps
  have ha : (if i.op == Op.call then none else R'.read i.operands.a) =
      (if i.op == Op.call then none else R.read i.operands.a) := by
    by_cases hcall : (i.op == Op.call) = true
    · simp [hcall]
    · simp only [hcall, ite_false]
      cases hx : i.operands.a with
      | none => rfl
      | some w =>
        have hnc : i.op ≠ Op.call := by simpa using hcall
        simp only [Regs.read, Option.bind_some]
        exact h w (mem_regOps_a hnc hx)
  have hb : R'.read i.operands.b = R.read i.operands.b := by
    cases hx : i.operands.b with
    | none => rfl
    | some w =>
      simp only [Regs.read, Option.bind_some]
      exact h w (mem_regOps_b hx)
  have hxs : i.operands.x.map R'.read = i.operands.x.map R.read := by
    apply List.map_congr_left
    intro o ho
    cases o with
    | none => rfl
    | some w =>
      simp only [Regs.read, Option.bind_some]
      apply h
      unfold regOps
      simp only [List.mem_append, List.mem_filterMap, id]
      exact Or.inr ⟨some w, ho, rfl⟩
  rw [ha, hb, hxs]

/-- Consistency survives any change of registers the instruction does not read. -/
theorem Cons.congr {R R' : Regs} {args : List Val} {i : Inst} (h : ∀ w ∈ regOps i, R' w = R w)
    (hv : R' i.value = R i.value) (hc : Cons R args i) : Cons R' args i := by
  intro x hx
  rw [hv] at hx
  obtain ⟨ch, hch⟩ := hc x hx
  refine ⟨ch, ?_⟩
  unfold evalInst at hch ⊢
  rw [readOps_congr h]
  exact hch

/-- Edge facts survive any change of registers the comparison does not read. -/
theorem EdgeFacts.congr {c : Ctx} {R R' : Regs} {low : Nat → Nat → Option Interval} {e : Edge}
    (hnc : e.cmp.op ≠ .call) (h : ∀ w ∈ regOps e.cmp, R' w = R w) (hef : EdgeFacts c R low e) :
    EdgeFacts c R' low e := by
  intro a b ha hb
  obtain ⟨na, nb, ra, rb, hp, lowA, lowB⟩ := hef a b ha hb
  have h1 : R' a = R a := h a (mem_regOps_a hnc ha)
  have h2 : R' b = R b := h b (mem_regOps_b hb)
  refine ⟨na, nb, by rw [h1]; exact ra, by rw [h2]; exact rb, hp, ?_, ?_⟩
  · intro lim n hl hr
    rw [h1] at hr
    exact lowA lim n hl hr
  · intro lim n hl hr
    rw [h2] at hr
    exact lowB lim n hl hr


/-! ### One instruction -/

theorem refHolds_congr {c : Ctx} {R R' : Regs} {x : Nat} (hc : CtxOK c) (hw : SsaWf c) (hx : Reach c.succ x)
    (h : ∀ w, StrictAbove c w x → R' w = R w) (hr : RefHolds c R x) : RefHolds c R' x := by
  unfold RefHolds at hr ⊢
  cases he : refining c x with
  | none => trivial
  | some e =>
    rw [he] at hr
    intro fuel
    apply EdgeFacts.congr _ _ (hr fuel)
    · obtain ⟨_, _, _, _, _, _, _, _, _, _, _, hcmp, _⟩ := refining_spec he
      rw [hcmp]; intro h; cases h
    · intro w hwm
      exact h w (refining_operand_above hc hw hx he hwm)

/-- Executing an instruction, whose result is a good value of its register, preserves the invariant. -/
theorem inst_step_inv {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr) {b : Block}
    {i : Inst} (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) {v : Val}
    (hv : ValOK c i.value v) (hev : ∃ ch, evalInst fr.regs fr.args i ch = .val v)
    (hlst : ∀ l, v = .list l → ∀ fuel, FactHolds c (c.liveList fuel i.value) l) :
    FrameInv c { fr with regs := fr.regs.set i.value v, pc := fr.pc + 1 } := by
  have hdi := hc.def_inst hb hk
  have hnotavail := not_avail_self hc hb hk
  have hops : ∀ w ∈ regOps i, w ≠ i.value := by
    intro w hwm hwu
    apply hnotavail
    rw [← hwu]
    exact hw.inst hb hk hinv.reach hwm
  refine ⟨hinv.reach, hinv.reached, ?_, ?_, ?_, ?_, hinv.args, ?_, ?_, ?_, ?_, ?_⟩
  · intro w x hwx
    by_cases hwu : w = i.value
    · subst hwu
      simp only [Regs.set, ite_true, Option.some.injEq] at hwx
      subst hwx
      exact hv
    · simp only [Regs.set, hwu, ite_false] at hwx
      exact hinv.val w x hwx
  · intro w hav
    rcases (avail_step hc hb hk).mp hav with h | h
    · obtain ⟨x, hx⟩ := hinv.defd w h
      have hwu : w ≠ i.value := fun e => hnotavail (e ▸ h)
      exact ⟨x, by simp only [Regs.set, hwu, ite_false]; exact hx⟩
    · subst h
      exact ⟨v, by simp [Regs.set]⟩
  · intro w hav j hnp hj
    rcases (avail_step hc hb hk).mp hav with h | h
    · have hwu : w ≠ i.value := fun e => hnotavail (e ▸ h)
      have hcons := hinv.cons w h j hnp hj
      have hjv := hc.value_of_inst hj hnp
      apply Cons.congr (R := fr.regs) _ _ hcons
      · intro w' hw'
        exact Regs.set_ne _ _ (operand_ne_new hc hw hb hk hinv.reach h hnp hj w' hw')
      · rw [hjv]; exact Regs.set_ne _ _ hwu
    · subst h
      have hji : j = i := by
        rw [hdi] at hj
        simp only [instDef, Option.some.injEq] at hj
        exact hj.symm
      subst hji
      intro x hx
      simp only [Regs.set, ite_true, Option.some.injEq] at hx
      subst hx
      obtain ⟨ch, hch⟩ := hev
      refine ⟨ch, ?_⟩
      unfold evalInst at hch ⊢
      rw [readOps_congr (R := fr.regs)]
      · exact hch
      · intro w' hw'
        exact Regs.set_ne _ _ (hops w' hw')
  · intro x hx
    have hxr : Reach c.succ x := TDom.reach_of hx hinv.reach
    refine refHolds_congr hc hw hxr ?_ (hinv.ref x hx)
    intro w hwa
    apply Regs.set_ne
    intro hwu
    apply StrictAbove.not_def hc hwa hx hinv.reach
    rw [hwu, hdi]
    rfl
  · intro H k lim hH hcnt hlim hsafe
    obtain ⟨nc, hnc, hb'⟩ := hinv.counter H k lim hH hcnt hlim hsafe
    have hne : k.counter ≠ i.value := by
      have hcphi := (countedAt_phi hcnt).1
      intro heq
      rw [heq, hdi] at hcphi
      simp [instDef] at hcphi
    refine ⟨nc, ?_, hb'⟩
    dsimp only
    rw [Regs.set_ne _ _ hne]
    exact hnc
  · intro w l hwl fuel
    by_cases hwu : w = i.value
    · subst hwu
      simp only [Regs.set, ite_true, Option.some.injEq] at hwl
      exact hlst l hwl fuel
    · simp only [Regs.set, hwu, ite_false] at hwl
      exact hinv.lst w l hwl fuel
  · intro H p ch lim hH hlim hsafe
    obtain ⟨np, nc, hRp, hRc, h0, h1, h2⟩ := hinv.red H p ch lim hH hlim hsafe
    have hpne : p.value ≠ i.value := by
      intro heq
      have := ch.hphi
      rw [heq, hdi] at this
      simp [instDef] at this
    have hcne : ch.k.counter ≠ i.value := by
      have hcphi := (countedAt_phi ch.hcnt).1
      intro heq
      rw [heq, hdi] at hcphi
      simp [instDef] at hcphi
    refine ⟨np, nc, ?_, ?_, h0, h1, h2⟩
    · dsimp only
      rw [Regs.set_ne _ _ hpne]; exact hRp
    · dsimp only
      rw [Regs.set_ne _ _ hcne]; exact hRc
  · intro H k lim hH hcnt hlim
    exact hinv.cstart H k lim hH hcnt hlim
  · intro H acc F q I lacc hk hb' hlacc hqa hg hqk hav
    have hqne : q ≠ i.value := by
      intro heq
      rw [heq, hdi] at hqk
      simp [instDef] at hqk
    have hane : acc ≠ i.value := by
      intro heq
      rw [heq, hdi] at hk
      simp [instDef] at hk
    have hav' : Avail c fr.blk fr.pc q := by
      unfold Avail at hav ⊢
      rw [hqk] at hav ⊢
      exact hav
    obtain ⟨nq, na, hRq, hRa, hcont⟩ := hinv.jn H acc F q I lacc hk hb' hlacc hqa hg hqk hav'
    refine ⟨nq, na, ?_, ?_, hcont⟩
    · dsimp only
      rw [Regs.set_ne _ _ hqne]; exact hRq
    · dsimp only
      rw [Regs.set_ne _ _ hane]; exact hRa


/-! ### Views and operands -/

theorem reached_lt {c : Ctx} (hc : CtxOK c) {B : Nat} (h : c.reached[B]? = some true) : B < c.f.blocks.size := by
  have h1 := arr_lt_of_get? h
  have h2 : c.reached.size = c.count := by
    have := hc.reach
    unfold reachOK at this
    simp only [Bool.and_eq_true, decide_eq_true_eq] at this
    exact this.1
  have h3 : c.count = c.f.blocks.size := rfl
  omega

/-- A tree ancestor truly dominates. -/
theorem anc_tdom {c : Ctx} (hc : CtxOK c) (hpos : 0 < c.f.blocks.size) {a b : Nat}
    (h : Anc (parentOf c.idom) a b) : TDom c.succ a b := by
  exact (ctxGraph c hpos hc.dom hc.edges (fun tb htb => (entryOK_entry hc.entry htb).1)).tdom_of_anc h

/-- A block the checker finds to dominate another really does. -/
theorem dominates_tdom {c : Ctx} (hc : CtxOK c) (hpos : 0 < c.f.blocks.size) {a b : Nat}
    (h : c.dominates a b = true) : TDom c.succ a b :=
  anc_tdom hc hpos (walkUp_anc c.idom a _ b h)

theorem ofInt_exact {t : Ty} {ck : Check} {r n : Int} (hck : ck ≠ .none) (h : Res.ofInt t ck r = .val (.int n)) :
    n = r := by
  unfold Res.ofInt at h
  cases hr : t.range with
  | none => rw [hr] at h; simpa using h.symm
  | some lim =>
    rw [hr] at h
    simp only [] at h
    split at h
    · simpa using h.symm
    · cases ck <;> simp at h hck

/-- A square operand of a refining comparison holds the square of its factor, in any frame that satisfies the
invariant. -/
theorem sqFacts_of_inv {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr) {x : Nat}
    {e : Edge} (hx : TDom c.succ x fr.blk) (he : refining c x = some e) : SqFacts c fr.regs e := by
  intro raw w nraw nw hraw hsq hrr hrw
  have hxr : Reach c.succ x := TDom.reach_of hx hinv.reach
  have hraw' : raw ∈ regOps e.cmp := by
    obtain ⟨_, _, _, _, _, _, _, _, _, _, _, hcmp, _⟩ := refining_spec he
    have hnc : e.cmp.op ≠ .call := by rw [hcmp]; intro h; cases h
    rcases hraw with h | h
    · exact mem_regOps_a hnc h
    · exact mem_regOps_b h
  have hab := (refining_operand_above hc hw hxr he hraw').avail hc hx hinv.reach fr.pc
  unfold isSquareOf at hsq
  simp only [Option.some.injEq] at hsq
  cases hdi : (c.def_ raw).inst with
  | none => simp [hdi] at hsq
  | some i =>
    simp only [hdi, Bool.and_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] at hsq
    obtain ⟨⟨⟨⟨hnphi, hmul⟩, hck⟩, ha⟩, hb⟩ := hsq
    have hnp : (c.def_ raw).kind ≠ .phi := hnphi
    have hcons := hinv.cons raw hab i hnp hdi
    have hiv : i.value = raw := hc.value_of_inst hdi hnp
    have hrr' : fr.regs i.value = some (.int nraw) := by rw [hiv]; exact hrr
    obtain ⟨ch, hch⟩ := hcons (.int nraw) hrr'
    unfold evalInst evalOps at hch
    have hmul' : i.op = .mul := hmul
    simp only [hmul', readOps, Regs.read, ha, hb, Option.bind_some, hrw, Val.int?] at hch
    have hcall : (Op.mul == Op.call) = false := by decide
    simp only [hcall, Bool.false_eq_true, ite_false, Option.bind_some, Val.int?] at hch
    exact ofInt_exact hck (by simpa using hch)


theorem ValTy.int {t : Ty} {lim : Interval} {v : Val} (hr : t.range = some lim) (h : ValTy t v) :
    ∃ n, v = .int n ∧ lim.contains n := by
  unfold ValTy at h
  rw [hr] at h
  obtain ⟨n, h1, h2, h3⟩ := h
  exact ⟨n, h1, h2, h3⟩

/-- The view of a register at any block `D` that dominates the frame's block is sound. -/
theorem view_sound_at {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {D : Nat} (hD : TDom c.succ D fr.blk) (fuel : Nat) {v : Nat} {n : Int}
    {lim : Interval} (hty : (c.def_ v).ty.range = some lim) (hv : fr.regs v = some (.int n)) :
    ((viewN c fuel v D).getD lim).contains n := by
  have hpos : 0 < c.f.blocks.size := by
    have := reached_lt hc hinv.reached
    omega
  apply viewN_sound (c := c) (R := fr.regs) (B := D) _ _ _ _ fuel hty hv
  · intro v n lim hty hr
    exact ((hinv.val v _ hr).2 n rfl).1 lim hty
  · intro v n lim hty hr
    obtain ⟨n', h1, h2⟩ := ValTy.int hty (hinv.val v _ hr).1
    cases h1
    exact h2
  · intro cap hcap hd n hn
    exact hadm.caps cap hcap ((dominates_tdom hc hpos hd).trans hD) n hn
  · intro fuel y e hy he
    have hxt := (anc_tdom hc hpos hy).trans hD
    refine ⟨?_, sqFacts_of_inv hc hw hinv hxt he⟩
    have := hinv.ref y hxt
    unfold RefHolds at this
    rw [he] at this
    exact this fuel

/-- A register holding an integer has an integer type. -/
theorem int_typed {t : Ty} {n : Int} (h : ValTy t (.int n)) : ∃ lim, t.range = some lim := by
  unfold ValTy at h
  cases hr : t.range with
  | some lim => exact ⟨lim, rfl⟩
  | none =>
    rw [hr] at h
    cases t <;> first
      | (simp [Ty.range, Ty.bits] at hr; done)
      | (obtain ⟨l, hl, _⟩ := h; cases hl)
      | (simp only [] at h; cases h)

/-- The views of the registers of a frame are sound. -/
theorem view_sound {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) (fuel : Nat) {v : Nat} {n : Int} {lim : Interval}
    (hty : (c.def_ v).ty.range = some lim) (hv : fr.regs v = some (.int n)) :
    ((viewN c fuel v fr.blk).getD lim).contains n :=
  view_sound_at hc hw hinv hadm (TDom.refl _) fuel hty hv

/-- The operand intervals of an instruction hold the values of its registers. -/
theorem operandSound_inv {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst} (hb : c.f.blocks[fr.blk]? = some b)
    (hk : b.insts[fr.pc]? = some i) : OperandSound c fr.regs fr.blk (· ∈ regOps i) := by
  intro w I hwm hI
  cases hr : (c.def_ w).ty.range with
  | none => simp [Ctx.operandRaw, operandWith, hr] at hI
  | some lim =>
    simp only [Ctx.operandRaw, operandWith, hr, Option.some.injEq] at hI
    subst hI
    obtain ⟨x, hx⟩ := hinv.defd w (hw.inst hb hk hinv.reach hwm)
    obtain ⟨n, hn, hlc⟩ := ValTy.int hr (hinv.val w x hx).1
    subst hn
    exact ⟨n, lim, hx, view_sound hc hw hinv hadm _ hr hx, rfl, hlc⟩


/-! ### The result of an instruction -/

theorem outcome_stated {c : Ctx} {i : Inst} {here : Nat} {limits stated : Interval} {nv : Int}
    (hlim : i.ty.range = some limits) (hst : i.range = some stated) (hvl : limits.contains nv)
    (hok : (c.instOut i here).fault? = none)
    (hder : (c.derive i limits here).assumed = false → (c.derive i limits here).range.contains nv)
    (hasm : c.instOut i here = .assumed → stated.contains nv) : stated.contains nv := by
  unfold Ctx.instOut at hok hasm
  rw [hlim, hst] at hok hasm
  simp only [] at hok hasm
  by_cases hsk : (stated.lo == limits.lo && stated.hi == limits.hi) = true
  · simp only [Bool.and_eq_true, beq_iff_eq] at hsk
    obtain ⟨h1, h2⟩ := hsk
    exact ⟨by rw [h1]; exact hvl.1, by rw [h2]; exact hvl.2⟩
  · simp only [hsk, ite_false] at hok hasm
    by_cases hna : (c.derive i limits here).assumed = true
    · simp only [hna, ite_true] at hasm
      exact hasm rfl
    · have hna' : (c.derive i limits here).assumed = false := by simpa using hna
      simp only [hna, ite_false] at hok hasm
      by_cases hw : (c.derive i limits here).range.within stated = true
      · exact within_contains hw (hder hna')
      · simp only [hw, ite_false] at hok hasm
        by_cases hs : staleAfterFacts i.op = true
        · simp only [hs, ite_true] at hasm
          exact hasm rfl
        · simp only [hs, ite_false] at hok
          simp [Out.fault?] at hok

theorem getElem!_mem_list {l : List Val} {k : Nat} (h : k < l.length) : l[k]! ∈ l := by
  rw [getElem!_pos l k h]
  exact List.getElem_mem h

theorem readOps_a_list {R : Regs} {args : List Val} {i : Inst} {l : List Val} (hnc : i.op ≠ .call)
    (h : (readOps R args i).a.bind Val.list? = some l) : ∃ w, i.operands.a = some w ∧ R w = some (.list l) := by
  have hcall : (i.op == .call) = false := by simpa using hnc
  cases ha : i.operands.a with
  | none => simp [readOps, hcall, ha, Regs.read] at h
  | some w =>
    refine ⟨w, rfl, ?_⟩
    simp only [readOps, hcall, ha, Regs.read, Option.bind_some] at h
    simp only [Bool.false_eq_true, ite_false] at h
    cases hRw : R w with
    | none => rw [hRw] at h; simp at h
    | some val =>
      rw [hRw] at h
      cases val <;> simp [Val.list?] at h
      subst h; rfl

theorem read_int {R : Regs} {o : Option Nat} {n : Int} (h : (R.read o).bind Val.int? = some n) :
    ∃ a, o = some a ∧ R a = some (.int n) := by
  cases o with
  | none => simp [Regs.read] at h
  | some a =>
    refine ⟨a, rfl, ?_⟩
    simp only [Regs.read, Option.bind_some] at h
    cases hR : R a with
    | none => rw [hR] at h; simp at h
    | some v =>
      rw [hR] at h
      cases v <;> simp [Val.int?] at h
      subst h; rfl

/-- An integer operation that did not get stuck read two integer registers. -/
theorem two_ints_of_eval {R : Regs} {args : List Val} {i : Inst} {ch : Val}
    (hop : i.op = .add ∨ i.op = .sub ∨ i.op = .mul ∨ i.op = .saturatingAdd ∨ i.op = .shiftRight ∨ i.op = .floorDiv ∨
      i.op = .div ∨ i.op = .floorRem ∨ i.op = .rem ∨ i.op = .bitXor ∨ i.op = .cmp ∨ i.op = .shiftLeft)
    (hev : evalInst R args i ch ≠ .stuck) :
    ∃ wa wb na nb, i.operands.a = some wa ∧ i.operands.b = some wb ∧ R wa = some (.int na) ∧
      R wb = some (.int nb) := by
  have hnc : i.op ≠ .call := by
    rcases hop with h | h | h | h | h | h | h | h | h | h | h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hop with h | h | h | h | h | h | h | h | h | h | h | h <;>
    simp only [h, readOps_a_of_ne hnc, readOps_b] at hev <;>
  · cases hxa : (R.read i.operands.a).bind Val.int? with
    | none => rw [hxa] at hev; simp at hev
    | some na =>
      cases hxb : (R.read i.operands.b).bind Val.int? with
      | none => rw [hxa, hxb] at hev; simp at hev
      | some nb =>
        obtain ⟨wa, ha, hRa⟩ := read_int hxa
        obtain ⟨wb, hb, hRb⟩ := read_int hxb
        exact ⟨wa, wb, na, nb, ha, hb, hRa, hRb⟩

/-- An integer operation on one operand that did not get stuck read an integer register. -/
theorem one_int_of_eval {R : Regs} {args : List Val} {i : Inst} {ch : Val}
    (hop : i.op = .convert ∨ i.op = .not ∨ i.op = .neg) (hev : evalInst R args i ch ≠ .stuck) :
    ∃ wa na, i.operands.a = some wa ∧ R wa = some (.int na) := by
  have hnc : i.op ≠ .call := by rcases hop with h | h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hop with h | h | h <;> simp only [h, readOps_a_of_ne hnc] at hev <;>
  · cases hxa : (R.read i.operands.a).bind Val.int? with
    | none => rw [hxa] at hev; simp at hev
    | some na =>
      obtain ⟨wa, ha, hRa⟩ := read_int hxa
      exact ⟨wa, na, ha, hRa⟩

/-- A list access that did not get stuck read an integer index. -/
theorem index_int_of_eval {R : Regs} {args : List Val} {i : Inst} {ch : Val}
    (hop : i.op = .listGet ∨ i.op = .arrayGet ∨ i.op = .listSet ∨ i.op = .arraySet)
    (hev : evalInst R args i ch ≠ .stuck) : ∃ wb nb, i.operands.b = some wb ∧ R wb = some (.int nb) := by
  have hnc : i.op ≠ .call := by rcases hop with h | h | h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hop with h | h | h | h <;> simp only [h, readOps_a_of_ne hnc, readOps_b, readOps_x] at hev <;>
  · cases hxb : (R.read i.operands.b).bind Val.int? with
    | none => rw [hxb] at hev; simp at hev
    | some nb =>
      obtain ⟨wb, hb, hRb⟩ := read_int hxb
      exact ⟨wb, nb, hb, hRb⟩

/-- An instruction that produced a value reads no operand that is never produced: its rule is not vacuous. -/
theorem ruleVacuous_false {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch v : Val} {here : Nat}
    (hop : OperandSound c R here (· ∈ regOps i))
    (hint : ∀ w n, R w = some (.int n) → ∃ lim, (c.def_ w).ty.range = some lim)
    (hev : evalInst R args i ch = .val v) : c.ruleVacuous i here = false := by
  have hns : evalInst R args i ch ≠ .stuck := by rw [hev]; intro h; cases h
  unfold Ctx.ruleVacuous
  cases hopc : i.op
  case add | sub | mul | saturatingAdd | shiftRight | floorDiv | div | floorRem | rem | bitXor | cmp =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    obtain ⟨wa, wb, na, nb, ha, hb, hRa, hRb⟩ := two_ints_of_eval (by simp [hopc]) hns
    simp only [ha, hb, emptyView_false hop (mem_regOps_a hnc ha) hRa (hint wa na hRa),
      emptyView_false hop (mem_regOps_b hb) hRb (hint wb nb hRb), Bool.false_or, Bool.and_false]
  case convert | not =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    obtain ⟨wa, na, ha, hRa⟩ := one_int_of_eval (by simp [hopc]) hns
    simp only [ha, emptyView_false hop (mem_regOps_a hnc ha) hRa (hint wa na hRa)]
  all_goals rfl

/-- The interval a rule derives holds the value an instruction computes, from the soundness of its operands, the
parameter intervals, and the stated facts of lists and callees. -/
theorem derive_contains {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch v : Val} {limits : Interval}
    {here : Nat} (hop : OperandSound c R here (· ∈ regOps i)) (hty : OpTyped c i)
    (hdef : (c.def_ i.value).inst = some i ∧ (c.def_ i.value).ty = i.ty) (hlim : i.ty.range = some limits)
    (hev : evalInst R args i ch = .val v) (hvt : ValTy i.ty v) (hal : Allowed i v)
    (hint : ∀ w n, R w = some (.int n) → ∃ lim, (c.def_ w).ty.range = some lim)
    (hna : (c.derive i limits here).assumed = false) (hargs : ArgsOK c args)
    (hpar : i.op = .param → c.f.header.params[i.imm]? = some i.ty)
    (hlists : ∀ w l, w ∈ regOps i → R w = some (.list l) → (l.length : Int) ≤ maxListLength ∧ ListHolds c w l)
    (hcall : i.op = .call → ∀ n, v = .int n → ∀ (g : Nat) (callee : Function) (r : Interval),
      i.operands.a = some g → c.m.functions[g]? = some callee → callee.boundary.returns = some r → r.contains n) :
    ∃ n, v = .int n ∧ (c.derive i limits here).range.contains n := by
  have hnv : c.ruleVacuous i here = false := ruleVacuous_false hop hint hev
  have hd : c.derive i limits here = c.deriveRule i limits here := by
    simp only [Ctx.derive, hnv, Bool.false_eq_true, ite_false]
  rw [hd] at hna ⊢
  by_cases hsp : i.op = .param ∨ i.op = .listLen ∨ i.op = .listGet ∨ i.op = .arrayGet ∨ i.op = .call
  · obtain ⟨nv, hv, hvl⟩ : ∃ n, v = .int n ∧ limits.contains n := ValTy.int hlim hvt
    refine ⟨nv, hv, ?_⟩
    subst hv
    unfold evalInst evalOps at hev
    rcases hsp with hopc | hopc | hopc | hopc | hopc
    · -- param
      simp only [Ctx.deriveRule, hopc]
      simp only [hopc] at hev
      cases harg : (readOps R args i).arg with
      | none => rw [harg] at hev; cases hev
      | some a =>
        rw [harg] at hev
        simp only [Res.val.injEq] at hev
        have hharg : args[i.imm]? = some a := by simpa [readOps] using harg
        cases hpi : paramInterval c i with
        | none => exact hvl
        | some claim =>
          have hpc : paramClaim c i.imm = some claim := hpi
          have := hargs i.imm claim a nv hpc hharg (by rw [(hpar hopc)]; simpa using hev)
          exact this
    · -- listLen
      simp only [Ctx.deriveRule, hopc]
      simp only [hopc] at hev
      cases hl : (readOps R args i).a.bind Val.list? with
      | none => rw [hl] at hev; cases hev
      | some l =>
        rw [hl] at hev
        simp only [Res.val.injEq, Val.int.injEq] at hev
        subst hev
        have hcall' : (i.op == .call) = false := by simp [hopc]
        cases ha : i.operands.a with
        | none => simp [readOps, hcall', ha, Regs.read] at hl
        | some w =>
          have hrw : R w = some (.list l) := by
            simp only [readOps, hcall', ha, Regs.read, Option.bind_some] at hl
            cases hRw : R w with
            | none => rw [hRw] at hl; simp at hl
            | some val =>
              rw [hRw] at hl
              cases val <;> simp [Val.list?] at hl
              subst hl; rfl
          obtain ⟨hlen, hlh⟩ := hlists w l (mem_regOps_a (by rw [hopc]; intro h; cases h) ha) hrw
          unfold ListHolds at hlh
          apply meet_contains
          · simp only [Ctx.factLen, ha]
            cases hf : c.listFact? (c.liveList c.count w) with
            | none => simp only [hf, Option.bind_none, Option.getD_none]; exact ⟨Int.natCast_nonneg _, hlen⟩
            | some fact =>
              rw [hf] at hlh
              cases hfl : fact.len with
              | none => simp only [hf, hfl, Option.bind_some, Option.bind_none, Option.getD_none]; exact ⟨Int.natCast_nonneg _, hlen⟩
              | some I => simp only [hf, hfl, Option.bind_some, Option.getD_some]; exact hlh.1 I hfl
          · exact ⟨Int.natCast_nonneg _, hlen⟩
    · -- listGet
      simp only [Ctx.deriveRule, hopc]
      simp only [hopc] at hev
      have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
      cases hl : (readOps R args i).a.bind Val.list? with
      | none => rw [hl] at hev; cases hev
      | some l =>
        cases hk : (readOps R args i).b.bind Val.int? with
        | none => rw [hl, hk] at hev; cases hev
        | some k =>
          rw [hl, hk] at hev
          by_cases hin : 0 ≤ k ∧ k < (l.length : Int)
          · simp only [hin, and_self, ite_true, Res.val.injEq] at hev
            obtain ⟨w, ha, hrw⟩ := readOps_a_list hnc hl
            obtain ⟨hlen, hlh⟩ := hlists w l (mem_regOps_a hnc ha) hrw
            unfold ListHolds at hlh
            have hmem : (Val.int nv) ∈ l := by
              rw [← hev]
              exact getElem!_mem_list (by omega)
            simp only [Ctx.factElems, ha]
            cases hf : c.listFact? (c.liveList c.count w) with
            | none => simp only [hf, Option.bind_none, Option.getD_none]; exact hvl
            | some fact =>
              rw [hf] at hlh
              cases hfe : fact.elems with
              | none => simp only [hf, hfe, Option.bind_some, Option.bind_none, Option.getD_none]; exact hvl
              | some I =>
                simp only [hf, hfe, Option.bind_some, Option.getD_some]
                obtain ⟨n, hn, hIn⟩ := hlh.2 I hfe _ hmem
                simp only [Val.int.injEq] at hn
                subst hn
                exact hIn
          · simp only [hin, ite_false] at hev
            unfold failWith at hev
            cases hck : i.check <;> simp only [hck] at hev <;> cases hev
    · -- arrayGet
      simp only [Ctx.deriveRule, hopc]
      simp only [hopc] at hev
      have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
      cases hl : (readOps R args i).a.bind Val.list? with
      | none => rw [hl] at hev; cases hev
      | some l =>
        cases hk : (readOps R args i).b.bind Val.int? with
        | none => rw [hl, hk] at hev; cases hev
        | some k =>
          rw [hl, hk] at hev
          by_cases hin : 0 ≤ k ∧ k < (l.length : Int)
          · simp only [hin, and_self, ite_true, Res.val.injEq] at hev
            obtain ⟨w, ha, hrw⟩ := readOps_a_list hnc hl
            obtain ⟨hlen, hlh⟩ := hlists w l (mem_regOps_a hnc ha) hrw
            unfold ListHolds at hlh
            have hmem : (Val.int nv) ∈ l := by
              rw [← hev]
              exact getElem!_mem_list (by omega)
            simp only [Ctx.factElems, ha]
            cases hf : c.listFact? (c.liveList c.count w) with
            | none => simp only [hf, Option.bind_none, Option.getD_none]; exact hvl
            | some fact =>
              rw [hf] at hlh
              cases hfe : fact.elems with
              | none => simp only [hf, hfe, Option.bind_some, Option.bind_none, Option.getD_none]; exact hvl
              | some I =>
                simp only [hf, hfe, Option.bind_some, Option.getD_some]
                obtain ⟨n, hn, hIn⟩ := hlh.2 I hfe _ hmem
                simp only [Val.int.injEq] at hn
                subst hn
                exact hIn
          · simp only [hin, ite_false] at hev
            unfold failWith at hev
            cases hck : i.check <;> simp only [hck] at hev <;> cases hev
    · -- call
      simp only [Ctx.deriveRule, hopc]
      cases ha : i.operands.a with
      | none => exact hvl
      | some g =>
        cases hg : c.m.functions[g]? with
        | none => simp only [hg]; exact hvl
        | some callee =>
          cases hr : callee.boundary.returns with
          | none => simp only [hg, hr]; exact hvl
          | some r =>
            simp only [hg, hr]
            exact meet_contains (hcall hopc nv rfl g callee r ha hg hr) hvl
  · have h1 : i.op ≠ .param := fun h => hsp (Or.inl h)
    have h2 : i.op ≠ .listLen := fun h => hsp (Or.inr (Or.inl h))
    have h3 : i.op ≠ .listGet := fun h => hsp (Or.inr (Or.inr (Or.inl h)))
    have h4 : i.op ≠ .arrayGet := fun h => hsp (Or.inr (Or.inr (Or.inr (Or.inl h))))
    have h5 : i.op ≠ .call := fun h => hsp (Or.inr (Or.inr (Or.inr (Or.inr h))))
    exact derive_sound hop hty hdef hlim hev hvt hal hna h1 h2 h3 h4 h5


theorem inBase_core {c : Ctx} {here : Nat} {i : Inst} {n : Int} {limits : Interval}
    (hkind : (c.def_ i.value).kind = .inst ∨ (c.def_ i.value).kind = .pre) (hinst : (c.def_ i.value).inst = some i)
    (hty : (c.def_ i.value).ty = i.ty) (hst : (c.def_ i.value).stated = i.range) (hlim : i.ty.range = some limits)
    (hvl : limits.contains n) (hS : ∀ s, i.range = some s → s.contains n)
    (hD : (i.op = .iconst ∨ i.op = .param) → (c.derive i limits here).range.contains n) :
    ((base c i.value).getD limits).contains n := by
  unfold base
  simp only [hty, hlim]
  have hk : ∀ {α : Type} (f : α) (g : α), ((c.def_ i.value).kind = .inst ∨ (c.def_ i.value).kind = .pre) →
      True := fun _ _ _ => trivial
  rcases hkind with hk | hk <;> simp only [hk, hinst] <;>
  cases hop : i.op
  all_goals first
    | (have := hD (Or.inl hop)
       simp only [Ctx.derive, Ctx.ruleVacuous, Ctx.deriveRule, hop, Bool.false_eq_true, ite_false] at this
       simpa using this)
    | (have := hD (Or.inr hop)
       simp only [Ctx.derive, Ctx.ruleVacuous, Ctx.deriveRule, hop, Bool.false_eq_true, ite_false] at this
       simpa using this)
    | (simp only [Option.getD_some]; exact hvl)
    | (rw [hst]
       cases hs : i.range with
       | none => simpa using hvl
       | some s => simpa using hS s hs)

theorem valTy_list_len {t : Ty} {l : List Val} (h : ValTy t (.list l)) : (l.length : Int) ≤ maxListLength := by
  unfold ValTy at h
  cases hr : t.range with
  | some lim => rw [hr] at h; obtain ⟨n, hn, _⟩ := h; cases hn
  | none =>
    rw [hr] at h
    cases t <;> first
      | (simp [Ty.range, Ty.bits] at hr; done)
      | (obtain ⟨l', hl', hle⟩ := h; cases hl'; exact hle)
      | (simp only [] at h; cases h)

/-- The registers of an instruction that hold lists satisfy their stated facts. -/
theorem lists_of_inv {c : Ctx} {fr : Frame} (hinv : FrameInv c fr) :
    ∀ w l, fr.regs w = some (.list l) → (l.length : Int) ≤ maxListLength ∧ ListHolds c w l := fun w l h =>
  ⟨valTy_list_len (hinv.val w _ h).1, listHolds_of_fact (hinv.lst w l h c.count)⟩

/-- The registers that hold lists satisfy the facts stated of their own values. -/
theorem lists_fact_of_inv {c : Ctx} {fr : Frame} (hinv : FrameInv c fr) :
    ∀ w l, fr.regs w = some (.list l) → (l.length : Int) ≤ maxListLength ∧ FactHolds c w l := fun w l h =>
  ⟨valTy_list_len (hinv.val w _ h).1, hinv.lst w l h 0⟩

/-- The value an instruction (or a constant or parameter) gives its register is good, from the checks it passed. -/
theorem valok_core {c : Ctx} {here : Nat} {i : Inst} {v : Val}
    (hkind : (c.def_ i.value).kind = .inst ∨ (c.def_ i.value).kind = .pre)
    (hinst : (c.def_ i.value).inst = some i) (hty : (c.def_ i.value).ty = i.ty)
    (hst : (c.def_ i.value).stated = i.range) (hblk : (c.def_ i.value).block.getD 0 = here)
    (hok : (c.instOut i here).fault? = none) (hvt : ValTy i.ty v)
    (hD : ∀ limits n, i.ty.range = some limits → v = .int n → (c.derive i limits here).assumed = false →
      (c.derive i limits here).range.contains n)
    (hadmS : ∀ n, v = .int n → AssumedVal c i.value → StatedOK c i.value n) : ValOK c i.value v := by
  refine ⟨by rw [hty]; exact hvt, ?_⟩
  intro n hn
  subst hn
  cases hlim : i.ty.range with
  | none =>
    constructor
    · intro lim h; rw [hty, hlim] at h; cases h
    · intro r lim hr h; rw [hty, hlim] at h; cases h
  | some limits =>
    obtain ⟨n', hn', hvl⟩ := ValTy.int hlim hvt
    simp only [Val.int.injEq] at hn'
    subst hn'
    have hS : ∀ s, i.range = some s → s.contains n := by
      intro s hs
      apply outcome_stated hlim hs hvl hok (hD limits n hlim rfl)
      intro hasm
      have hnp : (c.def_ i.value).kind ≠ .phi := by
        rcases hkind with h | h <;> rw [h] <;> intro e <;> cases e
      have hav : AssumedVal c i.value := ⟨i, hinst, hnp, by rw [hblk]; exact hasm⟩
      exact hadmS n rfl hav s limits (by rw [hst]; exact hs) (by rw [hty]; exact hlim)
    have hbase := inBase_core (here := here) hkind hinst hty hst hlim hvl hS
      (fun hop => hD limits n hlim rfl (by rcases hop with h | h <;> simp [Ctx.derive, Ctx.ruleVacuous, Ctx.deriveRule, h]))
    constructor
    · intro lim h
      rw [hty, hlim] at h
      cases h
      exact hbase
    · intro r lim hr h
      rw [hty, hlim] at h
      cases h
      rw [hst] at hr
      exact hS r hr

/-- Executing an instruction produces a good value of its register. -/
theorem inst_valok {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) {ch v : Val}
    (hev : evalInst fr.regs fr.args i ch = .val v) (hvt : ValTy i.ty v) (hal : Allowed i v)
    (hadm' : AdmFrame c (fr.regs.set i.value v) fr.blk)
    (hcall : i.op = .call → ∀ n, v = .int n → ∀ (g : Nat) (callee : Function) (r : Interval),
      i.operands.a = some g → c.m.functions[g]? = some callee → callee.boundary.returns = some r → r.contains n)
    (hty : OpTyped c i) : ValOK c i.value v := by
  have hdi := hc.def_inst hb hk
  have hmem : i ∈ b.insts := List.mem_of_getElem? hk
  have hdef : (c.def_ i.value).inst = some i ∧ (c.def_ i.value).ty = i.ty := by
    rw [hdi]; exact ⟨rfl, rfl⟩
  refine valok_core (here := fr.blk) (Or.inl (by rw [hdi]; rfl)) hdef.1 hdef.2 (by rw [hdi]; rfl)
    (by rw [hdi]; rfl) (Ctx.inst_ok hff hb hinv.reached hmem) hvt ?_ ?_
  · intro limits n hlim hvn hna
    subst hvn
    obtain ⟨n2, hn2, hcon⟩ := derive_contains (operandSound_inv hc hw hinv hadm hb hk) hty hdef hlim hev hvt hal
      (fun w n h => int_typed (hinv.val w _ h).1) hna hinv.args (fun hp => paramsOK_inst hc.params hb hmem hp) (fun w l _ => lists_of_inv hinv w l) hcall
    simp only [Val.int.injEq] at hn2
    subst hn2
    exact hcon
  · intro n hvn hav
    subst hvn
    exact hadm'.stated i.value n (by simp [Regs.set]) hav

/-- The list an instruction computes satisfies the facts stated of it and of the lists it can be read through. -/
theorem inst_lst {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) {ch v : Val}
    (hev : evalInst fr.regs fr.args i ch = .val v) (hadm' : AdmFrame c (fr.regs.set i.value v) fr.blk) :
    ∀ l, v = .list l → ∀ fuel, FactHolds c (c.liveList fuel i.value) l := by
  intro l hl
  subst hl
  have hdi := hc.def_inst hb hk
  have hkind : (c.def_ i.value).kind = .inst := by rw [hdi]; rfl
  have hinst : (c.def_ i.value).inst = some i := by rw [hdi]; rfl
  have hblk : (c.def_ i.value).block = some fr.blk := by rw [hdi]; rfl
  have hhere : (c.def_ i.value).block.getD 0 = fr.blk := by rw [hblk]; rfl
  have hfp : FactHolds c i.value l := by
    refine factHolds_of_deriv hff hc (u := i.value) ?_ ?_ ?_ ?_
    · intro b' hb'
      rw [hblk] at hb'
      cases hb'
      exact hinv.reached
    · rw [hhere]
      exact deriveList_inst_sound (R := fr.regs) (args := fr.args) (ch := ch) (here := fr.blk)
        (by rw [hkind]; intro h; cases h) hinst (operandSound_inv hc hw hinv hadm hb hk)
        (lists_fact_of_inv hinv) hev
    · intro I h
      exact hadm'.listLen i.value l I (by simp [Regs.set]) h
    · intro I h
      exact hadm'.listElems i.value l I (by simp [Regs.set]) h
  intro fuel
  cases fuel with
  | zero => exact hfp
  | succ f =>
    rcases liveList_inst (fuel := f) hkind hinst with h | ⟨a, hop, ha, h⟩
    · rw [h]; exact hfp
    · rw [h]
      have hcopy : i.op = .listCopy ∨ i.op = .listViewOf ∨ i.op = .borrow := by
        rcases hop with h' | h'
        · exact Or.inr (Or.inl h')
        · exact Or.inr (Or.inr h')
      obtain ⟨w, hw', hRw⟩ := eval_copy hcopy hev
      rw [ha] at hw'
      cases hw'
      exact hinv.lst a l hRw f

/-! ### Typing read off the certificate -/

theorem tyEq_of {c : Ctx} {o : Option Nat} {t : Ty}
    (h : ((o.bind fun w => c.defs[w]?.map (·.ty)) == some t) = true) : ∃ w, o = some w ∧ (c.def_ w).ty = t := by
  cases o with
  | none => simp at h
  | some w =>
    refine ⟨w, rfl, ?_⟩
    simp only [Option.bind_some, beq_iff_eq] at h
    cases hd : c.defs[w]? with
    | none => rw [hd] at h; simp at h
    | some d => rw [hd] at h; simp only [Option.map_some, Option.some.injEq] at h; simp [Ctx.def_, hd, h]

theorem CtxOK.opTyped {c : Ctx} (hc : CtxOK c) {B : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[B]? = some b)
    (hi : i ∈ b.insts) : OpTyped c i := by
  have h := hc.typed
  unfold typedOK at h
  simp only [List.all_eq_true, Bool.and_eq_true] at h
  have h1 := (h B (List.mem_range.mpr (arr_lt_of_get? hb))).1 i (by rw [arr_get!_of_get? hb]; exact hi)
  unfold OpTyped
  cases hop : i.op <;> simp only [hop, Bool.and_eq_true] at h1 ⊢
  all_goals first
    | trivial
    | exact ⟨tyEq_of h1.1, tyEq_of h1.2⟩
    | exact tyEq_of h1

theorem CtxOK.phiTyped {c : Ctx} (hc : CtxOK c) {B : Nat} {b : Block} {p : Phi} {e : PhiEdge}
    (hb : c.f.blocks[B]? = some b) (hp : p ∈ b.phis) (he : e ∈ p.edges) : (c.def_ e.value).ty = p.ty := by
  have h := hc.typed
  unfold typedOK at h
  simp only [List.all_eq_true, Bool.and_eq_true] at h
  have h1 := (h B (List.mem_range.mpr (arr_lt_of_get? hb))).2 p (by rw [arr_get!_of_get? hb]; exact hp) e he
  obtain ⟨w, hw, hty⟩ := tyEq_of h1
  cases hw
  exact hty

/-! ### Entering a block -/

theorem edgeOpen_jump {c : Ctx} {B s t : Nat} {b : Block} (hb : c.f.blocks[B]? = some b) (ht : b.term = .jump t) :
    edgeOpen c B s = true := by
  unfold edgeOpen
  rw [hb]
  simp only [ht]

theorem edgeOpen_branch {c : Ctx} {B cond t el s : Nat} {k : Int} {b : Block} (hb : c.f.blocks[B]? = some b)
    (ht : b.term = .branch cond t el) (hk : (k = 1 ∧ s = t) ∨ (k = 0 ∧ s = el))
    (hbase : ∀ i, base c cond = some i → i.contains k) : edgeOpen c B s = true := by
  unfold edgeOpen
  rw [hb]
  simp only [ht]
  cases hbs : base c cond with
  | none => rfl
  | some i =>
    simp only []
    have hc := hbase i hbs
    obtain ⟨h1, h2⟩ := hc
    by_cases hone : (i.lo == 1 && i.hi == 1) = true
    · simp only [Bool.and_eq_true, beq_iff_eq] at hone
      simp only [Bool.and_eq_true, beq_iff_eq, hone.1, hone.2, and_self, ite_true]
      rcases hk with ⟨hk1, hs⟩ | ⟨hk0, _⟩
      · simp [hs]
      · omega
    · by_cases hzero : (i.lo == 0 && i.hi == 0) = true
      · simp only [Bool.and_eq_true, beq_iff_eq] at hzero
        simp only [hone, ite_false, Bool.and_eq_true, beq_iff_eq, hzero.1, hzero.2, and_self, ite_true]
        rcases hk with ⟨hk1, _⟩ | ⟨hk0, hs⟩
        · omega
        · simp [hs]
      · simp [hone, hzero]

theorem phiHull_foldl {c : Ctx} {here : Nat} {limits : Interval} {n : Int} :
    ∀ (l : List PhiEdge) (acc : Option Interval),
      ((∃ a, acc = some a ∧ a.contains n) ∨
        (∃ e ∈ l, edgeLive c e.block here = true ∧ ((c.operandRaw (some e.value) e.block).getD limits).contains n)) →
      ∃ h, l.foldl (phiHullStep c here limits) acc = some h ∧ h.contains n := by
  intro l
  induction l with
  | nil =>
    intro acc h
    rcases h with ⟨a, ha, hc⟩ | ⟨e, he, _⟩
    · exact ⟨a, ha, hc⟩
    · cases he
  | cons e rest ih =>
    intro acc h
    simp only [List.foldl_cons]
    apply ih
    by_cases hlive : edgeLive c e.block here = true
    · rcases h with ⟨a, ha, hc⟩ | ⟨e', he', hl', hc'⟩
      · left
        subst ha
        by_cases hre : ((c.operandRaw (some e.value) e.block).getD limits).isEmpty = true
        · exact ⟨a, by simp [phiHullStep, hlive, hre], hc⟩
        · exact ⟨a.hull ((c.operandRaw (some e.value) e.block).getD limits), by simp [phiHullStep, hlive, hre],
            hull_contains_left hc⟩
      · rcases List.mem_cons.mp he' with heq | hrest
        · subst heq
          left
          have hne := isEmpty_false_of_contains hc'
          cases acc with
          | none => exact ⟨_, by simp [phiHullStep, hl', hne], hc'⟩
          | some so => exact ⟨so.hull ((c.operandRaw (some e'.value) e'.block).getD limits),
              by simp [phiHullStep, hl', hne], hull_contains_right hc'⟩
        · right; exact ⟨e', hrest, hl', hc'⟩
    · rcases h with ⟨a, ha, hc⟩ | ⟨e', he', hl', hc'⟩
      · left
        exact ⟨a, by simp [phiHullStep, hlive, ha], hc⟩
      · rcases List.mem_cons.mp he' with heq | hrest
        · subst heq
          exact absurd hl' hlive
        · right; exact ⟨e', hrest, hl', hc'⟩

theorem phiHull_contains {c : Ctx} {p : Phi} {here : Nat} {limits : Interval} {n : Int} {e : PhiEdge}
    (he : e ∈ p.edges) (hlive : edgeLive c e.block here = true)
    (hn : ((c.operandRaw (some e.value) e.block).getD limits).contains n) :
    ∃ h, c.phiHull p here limits = some h ∧ h.contains n :=
  phiHull_foldl p.edges none (Or.inr ⟨e, he, hlive, hn⟩)


/-- A phi takes a good value when its block is entered. -/
theorem phi_valok {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb)
    (hopen : edgeOpen c fr.blk y = true) {p : Phi} (hp : p ∈ tb.phis) {val : Val}
    (hnew : phiNew fr.regs fr.blk p = some val) (R' : Regs) (hR' : R' p.value = some val)
    (hadm' : AdmFrame c R' y)
    (hcnt : ∀ (k : Counted) (lim : Interval), c.countedAt y = some k → k.counter = p.value →
      (c.def_ k.counter).ty.range = some lim → CounterSafe c y k lim → CounterHolds c R' y k lim)
    (hchain : ∀ n, val = .int n → ∀ (ch : ChainInfo c y p) (lim : Interval), (c.def_ ch.k.counter).ty.range = some lim →
      CounterSafe c y ch.k lim → (grown ch.start ch.step ch.trips).contains n)
    (hstart : ∀ (k : Counted) (lim : Interval), c.countedAt y = some k → (c.def_ k.counter).ty.range = some lim →
      ((base c k.start).getD lim).isEmpty = false) :
    ValOK c p.value val := by
  obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
  have hvok := hinv.val e.value val hrv
  obtain ⟨k, hk⟩ := List.mem_iff_getElem?.mp hp
  have hdp := hc.def_phi hy hk
  have hty : (c.def_ e.value).ty = p.ty := hc.phiTyped hy hp he
  have hpty : (c.def_ p.value).ty = p.ty := by rw [hdp]; rfl
  refine ⟨by rw [hpty, ← hty]; exact hvok.1, ?_⟩
  intro n hn
  subst hn
  cases hpl : p.ty.range with
  | none =>
    constructor
    · intro lim h; rw [hpty, hpl] at h; cases h
    · intro r lim hr h; rw [hpty, hpl] at h; cases h
  | some lim =>
    have hvt : ValTy p.ty (.int n) := by rw [← hty]; exact hvok.1
    obtain ⟨n', hn', hvl⟩ := ValTy.int hpl hvt
    simp only [Val.int.injEq] at hn'
    subst hn'
    have hety : (c.def_ e.value).ty.range = some lim := by rw [hty]; exact hpl
    have hview := view_sound hc hw hinv hadm (viewFuel c) hety hrv
    have hopI : ((c.operandRaw (some e.value) e.block).getD lim).contains n := by
      have : c.operandRaw (some e.value) e.block = some ((viewN c (viewFuel c) e.value fr.blk).getD lim) := by
        simp only [Ctx.operandRaw, operandWith, hety]
        rw [heb]
      rw [this]
      exact hview
    have hlive : edgeLive c e.block y = true := by
      unfold edgeLive
      rw [heb]
      simp [hinv.reached, hopen]
    obtain ⟨h, hh, hhn⟩ := phiHull_contains he hlive hopI
    have hS : ∀ r, p.range = some r → r.contains n := by
      intro r hr
      by_cases hwi : h.within r = true
      · exact within_contains hwi hhn
      · by_cases hcb : ∃ bb, c.counterBound p y = some bb ∧ counterAccepts bb h lim r = true
        · -- a counter: its value lies in the counter bound, so in the bound's meet with the hull too
          obtain ⟨bb, hbb, hbw⟩ := hcb
          unfold Ctx.counterBound at hbb
          cases hca : c.countedAt y with
          | none => rw [hca] at hbb; simp at hbb
          | some kk =>
            rw [hca] at hbb
            simp only [] at hbb
            by_cases hkc : (kk.counter != p.value) = true
            · simp [hkc] at hbb
            · simp only [hkc, Bool.false_eq_true, ite_false] at hbb
              rw [hpl] at hbb
              simp only [] at hbb
              cases hop : c.operand (some kk.bound) y with
              | none => rw [hop] at hbb; simp at hbb
              | some I =>
                rw [hop] at hbb
                simp only [Option.some.injEq] at hbb
                subst hbb
                have hkcnt : kk.counter = p.value := by simpa using hkc
                have hstw : r.within lim = true := by
                  apply hc.stated_within (v := p.value) (r := r) (lim := lim)
                  · rw [hdp]; simpa [phiDef] using hr
                  · rw [hpty]; exact hpl
                have hlimk : (c.def_ kk.counter).ty.range = some lim := by rw [hkcnt, hpty]; exact hpl
                have hne0 : ¬ (((base c kk.start).getD lim).hi < ((base c kk.start).getD lim).lo) := by
                  have := hstart kk lim hca hlimk
                  simp only [Interval.isEmpty, decide_eq_false_iff_not] at this
                  omega
                have hfit : max ((base c kk.start).getD lim).hi I.hi ≤ lim.hi := by
                  unfold counterAccepts at hbw
                  simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hbw
                  rcases hbw with hbw | ⟨hfit, _⟩
                  · rw [within_iff] at hbw hstw
                    dsimp only at hbw
                    have := Int.le_max_left ((base c kk.start).getD lim).hi I.hi
                    omega
                  · exact hfit
                have hsafe : CounterSafe c y kk lim := by
                  intro I' hI'
                  rw [hop] at hI'
                  cases hI'
                  have := Int.le_max_right ((base c kk.start).getD lim).hi I.hi
                  omega
                obtain ⟨nc, hnc, hbd⟩ := hcnt kk lim hca hkcnt hlimk hsafe
                have hR'k : R' kk.counter = some (.int n) := by rw [hkcnt]; exact hR'
                rw [hR'k] at hnc
                have hnc' : n = nc := by cases hnc; rfl
                have := hbd I hop
                subst hnc'
                have hbn : (⟨((base c kk.start).getD lim).lo, max ((base c kk.start).getD lim).hi I.hi⟩ : Interval).contains n := by
                  obtain ⟨h1, h2⟩ := this
                  exact ⟨h1, h2⟩
                unfold counterAccepts at hbw
                simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hbw
                rcases hbw with hbw | ⟨_, hmw⟩
                · exact within_contains hbw hbn
                · exact within_contains hmw (meet_contains hhn hbn)
        · by_cases hcp : ChainProved c p y r
          · obtain ⟨ch, lim', hlim', hsafe', hor⟩ := hcp
            have hg := hchain n rfl ch lim' hlim' hsafe'
            rcases hor with hwg | ⟨limits, hull, hpr, hph, hmw⟩
            · exact within_contains hwg hg
            · rw [hpl] at hpr
              cases hpr
              rw [hh] at hph
              cases hph
              exact within_contains hmw (meet_contains hhn hg)
          · have hpl' : PhiLoop c p.value := by
              refine ⟨p, y, r, lim, h, ?_, ?_, hr, hpl, hh, hwi, fun bb hb hw => hcb ⟨bb, hb, hw⟩⟩
              · rw [hdp]; rfl
              · rw [hdp]; rfl
            have hguard : ∀ p' H' r', (c.def_ p.value).phi = some p' → (c.def_ p.value).block = some H' →
                p'.range = some r' → ¬ ChainProved c p' H' r' := by
              intro p' H' r' hp' hb' hr'
              rw [hdp] at hp' hb'
              simp only [phiDef, Option.some.injEq] at hp' hb'
              subst hp'
              subst hb'
              rw [hr] at hr'
              cases hr'
              exact hcp
            exact hadm'.phi p.value n hR' hpl' hguard r lim (by rw [hdp]; simpa [phiDef] using hr)
              (by rw [hpty]; exact hpl)
    constructor
    · intro lim' h'
      rw [hpty, hpl] at h'
      cases h'
      unfold base
      rw [hdp]
      simp only [phiDef, hpl]
      cases hr : p.range with
      | none => exact hvl
      | some r => exact hS r hr
    · intro r lim' hr h'
      rw [hdp] at hr
      simp only [phiDef] at hr
      exact hS r hr


theorem readOps_a_val {R : Regs} {args : List Val} {i : Inst} (hnc : i.op ≠ .call) :
    (readOps R args i).a.bind Val.int? = (R.read i.operands.a).bind Val.int? := by
  rw [readOps_a_of_ne hnc]

theorem cmp_eval {R : Regs} {args : List Val} {i : Inst} {k : Int} (hcmp : i.op = .cmp)
    (hcons : ∃ ch, evalInst R args i ch = .val (.int k)) :
    ∃ a b na nb p0, i.operands.a = some a ∧ i.operands.b = some b ∧ R a = some (.int na) ∧
      R b = some (.int nb) ∧ Pred.ofImm i.imm = some p0 ∧ k = (if predEval p0 na nb = true then 1 else 0) := by
  obtain ⟨ch, hch⟩ := hcons
  have hnc : i.op ≠ .call := by rw [hcmp]; intro h; cases h
  unfold evalInst evalOps at hch
  simp only [hcmp, readOps_a_of_ne hnc, readOps_b] at hch
  cases hxa : (R.read i.operands.a).bind Val.int? with
  | none => rw [hxa] at hch; simp at hch
  | some na =>
    cases hxb : (R.read i.operands.b).bind Val.int? with
    | none => rw [hxa, hxb] at hch; simp at hch
    | some nb =>
      cases hq : Pred.ofImm i.imm with
      | none => rw [hxa, hxb, hq] at hch; simp at hch
      | some p0 =>
        rw [hxa, hxb, hq] at hch
        simp only [Res.val.injEq, Val.int.injEq] at hch
        obtain ⟨a, ha, hRa⟩ := read_int hxa
        obtain ⟨b, hb, hRb⟩ := read_int hxb
        exact ⟨a, b, na, nb, p0, ha, hb, hRa, hRb, rfl, hch.symm⟩


/-- Every phi of a block entered from a predecessor has an old operand to copy. -/
theorem phiNew_some {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr) {b : Block}
    (hb : c.f.blocks[fr.blk]? = some b) (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block}
    (hy : c.f.blocks[y]? = some tb) (hfrom : fr.blk ∈ tb.preds) {p : Phi} (hp : p ∈ tb.phis) :
    ∃ val, phiNew fr.regs fr.blk p = some val := by
  obtain ⟨e, hfe, he, heb⟩ := hc.phi_find hy hp hfrom
  have hav := hw.phi hy hp he (pb := b) (by rw [heb]; exact hb) (by rw [heb]; exact hinv.reach)
  rw [hpc] at hav
  rw [heb] at hav
  obtain ⟨val, hval⟩ := hinv.defd e.value hav
  refine ⟨val, ?_⟩
  unfold phiNew
  rw [hfe]
  exact hval

theorem constVal_one (t : Ty) : constVal t 1 = 1 := by
  unfold constVal
  by_cases hb : t = .bool
  · simp [hb]
  · by_cases hu : t = .u64
    · simp [hb, hu]
    · simp [hb, hu]

/-- An operand of an instruction available here is available at the end of this block. -/
theorem operand_avail_end {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {B pc : Nat} {b : Block}
    (hb : c.f.blocks[B]? = some b) (hr : Reach c.succ B) {w : Nat} {j : Inst} (hav : Avail c B pc w)
    (hnp : (c.def_ w).kind ≠ .phi) (hj : (c.def_ w).inst = some j) {v : Nat} (hv : v ∈ regOps j) :
    Avail c B b.insts.length v := by
  cases hk : (c.def_ w).kind with
  | missing => exact absurd hk (hc.kind_of_inst hj)
  | phi => exact absurd hk hnp
  | pre => rw [regOps_pre hc hk hj] at hv; simp at hv
  | inst =>
    obtain ⟨Dj, bj, jj, hDj, hbj, hkj, hvj, hjj⟩ := hc.inst_of_def hk
    rw [hj] at hjj
    cases hjj
    have hdj : TDom c.succ Dj B := by
      rcases hav.above with hpre | ⟨D, hD, hd⟩
      · rw [hk] at hpre; cases hpre
      · rw [hDj] at hD; cases hD; exact hd
    have hav2 := hw.inst hbj hkj (TDom.reach_of hdj hr) hv
    exact avail_end_of_above hc hb (hav2.above.trans hdj)

/-- The value of an operand with an interval at a block that dominates the frame's block lies in it. -/
theorem operand_at {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {D : Nat} (hD : TDom c.succ D fr.blk) {o : Option Nat} {y : Interval}
    (hy : c.operand o D = some y) (hdef : ∀ w, o = some w → ∃ x, fr.regs w = some x) :
    ∃ w n, o = some w ∧ fr.regs w = some (.int n) ∧ y.contains n := by
  obtain ⟨w, hwo⟩ := operand_some hy
  subst hwo
  cases hr : (c.def_ w).ty.range with
  | none => simp [Ctx.operand, Ctx.operandRaw, operandWith, hr] at hy
  | some lim =>
    obtain ⟨x, hx⟩ := hdef w rfl
    obtain ⟨n, hn, _⟩ := ValTy.int hr (hinv.val w x hx).1
    subst hn
    have hv := view_sound_at hc hw hinv hadm hD (viewFuel c) hr hx
    have hraw : c.operandRaw (some w) D = some ((viewN c (viewFuel c) w D).getD lim) := by
      simp only [Ctx.operandRaw, operandWith, hr]
    have hne := isEmpty_false_of_contains hv
    unfold Ctx.operand at hy
    rw [hraw] at hy
    simp only [hne, Bool.false_eq_true, ite_false, Option.some.injEq] at hy
    subst hy
    exact ⟨w, n, rfl, hx, hv⟩

/-- A checked addition or subtraction that produced a value gave the exact result of its operands. -/
theorem eval_addsub {R : Regs} {args : List Val} {i : Inst} {ch x : Val} (hop : i.op = .add ∨ i.op = .sub)
    (hck : i.check ≠ .none) (hev : evalInst R args i ch = .val x) :
    ∃ wa wb na nb, i.operands.a = some wa ∧ i.operands.b = some wb ∧ R wa = some (.int na) ∧
      R wb = some (.int nb) ∧ x = .int (if i.op = .add then na + nb else na - nb) := by
  have hnc : i.op ≠ .call := by rcases hop with h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hop with hop | hop <;> simp only [hop, readOps_a_of_ne hnc, readOps_b] at hev <;>
  · cases hxa : (R.read i.operands.a).bind Val.int? with
    | none => rw [hxa] at hev; simp at hev
    | some na =>
      cases hxb : (R.read i.operands.b).bind Val.int? with
      | none => rw [hxa, hxb] at hev; simp at hev
      | some nb =>
        rw [hxa, hxb] at hev
        obtain ⟨wa, ha, hRa⟩ := read_int hxa
        obtain ⟨wb, hb, hRb⟩ := read_int hxb
        refine ⟨wa, wb, na, nb, ha, hb, hRa, hRb, ?_⟩
        cases hr2 : i.ty.range with
        | none =>
          unfold Res.ofInt at hev
          rw [hr2] at hev
          simp only [Res.val.injEq] at hev
          simp [hop, ← hev]
        | some lim =>
          rcases ofInt_val hr2 hev with ⟨_, h1⟩ | ⟨_, h1, _⟩
          · simp [hop, h1]
          · exact absurd h1 hck

/-- Where an accumulator chain ends: in a frame whose block is finished, the value of `raw` lies in the growth
interval of `raw` from the accumulator `acc`, both read from the current registers. -/
theorem chain_sound {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} (hb : c.f.blocks[fr.blk]? = some b)
    (hpc : b.insts.length = fr.pc) {H acc : Nat} (hH : (c.def_ acc).kind = .phi ∧ (c.def_ acc).block = some H)
    {lacc : Interval} (hlacc : (c.def_ acc).ty.range = some lacc) (havacc : Avail c fr.blk fr.pc acc) :
    ∀ (F raw : Nat) (I : Interval), c.jGrowth H F acc raw = some I → Avail c fr.blk fr.pc raw →
      ∃ nr na, fr.regs raw = some (.int nr) ∧ fr.regs acc = some (.int na) ∧ I.contains (nr - na) := by
  intro F
  induction F with
  | zero => intro raw I h; simp [Ctx.jGrowth] at h
  | succ F ih =>
    intro raw I h hav
    have h0 := h
    unfold Ctx.jGrowth at h
    by_cases hr : (raw == acc) = true
    · simp only [hr, ite_true, Option.some.injEq] at h
      have hra : raw = acc := by simpa using hr
      subst hra
      subst h
      obtain ⟨x, hx⟩ := hinv.defd raw hav
      obtain ⟨n, hn, _⟩ := ValTy.int hlacc (hinv.val raw x hx).1
      subst hn
      exact ⟨n, n, hx, hx, by simp [Interval.point, Interval.contains]⟩
    · simp only [hr, Bool.false_eq_true, ite_false] at h
      cases hblk : (c.def_ raw).block with
      | none => simp [hblk] at h
      | some wh =>
        simp only [hblk] at h
        by_cases hphi : ((c.def_ raw).kind == .phi) = true
        · have hne : raw ≠ acc := by intro heq; apply hr; simp [heq]
          exact hinv.jn H acc (F + 1) raw I lacc hH.1 hH.2 hlacc hne h0 (by simpa using hphi) hav
        · simp only [hphi, Bool.false_eq_true, ite_false] at h
          cases hinst : (c.def_ raw).inst with
          | none => simp [hinst] at h
          | some i =>
            simp only [hinst] at h
            by_cases hopc : (i.op != .add && i.op != .sub) = true
            · simp [hopc] at h
            · simp only [hopc, Bool.false_eq_true, ite_false] at h
              by_cases hck : (i.check == .none) = true
              · simp [hck] at h
              · simp only [hck, Bool.false_eq_true, ite_false] at h
                have hop : i.op = .add ∨ i.op = .sub := by
                  cases h1 : i.op
                  case add => exact Or.inl rfl
                  case sub => exact Or.inr rfl
                  all_goals (rw [h1] at hopc; simp at hopc)
                have hckn : i.check ≠ .none := by simpa using hck
                have hnp : (c.def_ raw).kind ≠ .phi := by simpa using hphi
                have hnc : i.op ≠ .call := by rcases hop with h' | h' <;> rw [h'] <;> intro h'' <;> cases h''
                have hkind : (c.def_ raw).kind = .inst := by
                  cases hk : (c.def_ raw).kind with
                  | missing => exact absurd hk (hc.kind_of_inst hinst)
                  | phi => exact absurd hk hnp
                  | inst => rfl
                  | pre =>
                    exfalso
                    obtain ⟨i0, hi0, _, hiv0⟩ := hc.pre_of_def hk
                    obtain ⟨kk, hkk⟩ := List.mem_iff_getElem?.mp hi0
                    have := hc.def_pre hkk
                    rw [hiv0] at this
                    rw [this] at hblk
                    simp [preDef] at hblk
                have hD : TDom c.succ wh fr.blk := by
                  rcases hav.above with hpre | ⟨D, hD, hd⟩
                  · rw [hkind] at hpre; cases hpre
                  · rw [hblk] at hD
                    cases (Option.some.inj hD)
                    exact hd
                have havop : ∀ v, v ∈ regOps i → Avail c fr.blk fr.pc v := by
                  intro v hv
                  have := operand_avail_end hc hw hb hinv.reach hav hnp hinst hv
                  rw [hpc] at this
                  exact this
                obtain ⟨x, hx⟩ := hinv.defd raw hav
                have hcons := hinv.cons raw hav i hnp hinst
                have hiv : i.value = raw := hc.value_of_inst hinst hnp
                obtain ⟨ch, hch⟩ := hcons x (by rw [hiv]; exact hx)
                obtain ⟨wa, wb, na, nb, hwa, hwb, hRa, hRb, hxv⟩ := eval_addsub hop hckn hch
                have hdefs : ∀ w, w ∈ regOps i → ∃ x', fr.regs w = some x' := fun w hw' => hinv.defd w (havop w hw')
                have hdefb : ∀ w', i.operands.b = some w' → ∃ x', fr.regs w' = some x' := by
                  intro w' hw'
                  have e : w' = wb := Option.some.inj (hw'.symm.trans hwb)
                  rw [e]
                  exact hdefs wb (mem_regOps_b hwb)
                have hdefa : ∀ w', i.operands.a = some w' → ∃ x', fr.regs w' = some x' := by
                  intro w' hw'
                  have e : w' = wa := Option.some.inj (hw'.symm.trans hwa)
                  rw [e]
                  exact hdefs wa (mem_regOps_a hnc hwa)
                simp only [hwa] at h
                cases hga : c.jGrowth H F acc wa with
                | some xI =>
                  simp only [hga] at h
                  cases hy : c.operand i.operands.b wh with
                  | none => simp [hy] at h
                  | some y =>
                    simp only [hy] at h
                    obtain ⟨nr, na0, hRnr, hRacc, hcont⟩ := ih wa xI hga (havop wa (mem_regOps_a hnc hwa))
                    have e1 : na = nr := by have := hRa.symm.trans hRnr; simpa using this
                    obtain ⟨w, nb', hwo, hRw, hcb⟩ := operand_at hc hw hinv hadm hD hy hdefb
                    have e2 : wb = w := Option.some.inj (hwb.symm.trans hwo)
                    subst e2
                    have e3 : nb = nb' := by have := hRb.symm.trans hRw; simpa using this
                    by_cases hadd : (i.op == .add) = true
                    · have hadd' : i.op = .add := by simpa using hadd
                      simp only [hadd, ite_true, Option.some.injEq] at h
                      subst h
                      have hxv' : x = .int (na + nb) := by rw [hxv]; simp [hadd']
                      rw [hxv'] at hx
                      refine ⟨na + nb, na0, hx, hRacc, ?_⟩
                      simp only [Interval.contains] at hcont hcb ⊢
                      omega
                    · have hsub' : i.op = .sub := by
                        rcases hop with h1 | h1
                        · exact absurd (by simpa using h1) hadd
                        · exact h1
                      simp only [hadd, Bool.false_eq_true, ite_false, Option.some.injEq] at h
                      subst h
                      have hne : ¬ (i.op = .add) := by rw [hsub']; intro h'; cases h'
                      have hxv' : x = .int (na - nb) := by rw [hxv]; simp [hne]
                      rw [hxv'] at hx
                      refine ⟨na - nb, na0, hx, hRacc, ?_⟩
                      simp only [Interval.contains] at hcont hcb ⊢
                      omega
                | none =>
                  simp only [hga] at h
                  by_cases hsubc : (i.op == .sub) = true
                  · simp [hsubc] at h
                  · simp only [hsubc, Bool.false_eq_true, ite_false] at h
                    have hadd' : i.op = .add := by
                      rcases hop with h1 | h1
                      · exact h1
                      · exact absurd (by simpa using h1) hsubc
                    simp only [hwb] at h
                    cases hgb : c.jGrowth H F acc wb with
                    | none => simp [hgb] at h
                    | some yI =>
                      simp only [hgb] at h
                      cases hxo : c.operand (some wa) wh with
                      | none => simp [hxo] at h
                      | some xv =>
                        simp only [hxo, Option.some.injEq] at h
                        subst h
                        have hxo' : c.operand i.operands.a wh = some xv := by rw [hwa]; exact hxo
                        obtain ⟨nr, na0, hRnr, hRacc, hcont⟩ := ih wb yI hgb (havop wb (mem_regOps_b hwb))
                        have e1 : nb = nr := by have := hRb.symm.trans hRnr; simpa using this
                        obtain ⟨w, na', hwo, hRw, hca⟩ := operand_at hc hw hinv hadm hD hxo' hdefa
                        have e2 : wa = w := Option.some.inj (hwa.symm.trans hwo)
                        subst e2
                        have e3 : na = na' := by have := hRa.symm.trans hRw; simpa using this
                        have hxv' : x = .int (na + nb) := by rw [hxv]; simp [hadd']
                        rw [hxv'] at hx
                        refine ⟨na + nb, na0, hx, hRacc, ?_⟩
                        simp only [Interval.contains] at hcont hca ⊢
                        omega

/-- The two predecessors of a counted loop's header differ: if both were the latch, the header would dominate its only
predecessor. -/
theorem counted_preds_ne {c : Ctx} (hc : CtxOK c) {H : Nat} {k : Counted} (hcnt : c.countedAt H = some k)
    {tb : Block} (hy : c.f.blocks[H]? = some tb) (hreach : Reach c.succ H) : tb.preds[0]? ≠ tb.preds[1]? := by
  intro heq
  obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd,
    hnphi, hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, _, hli⟩ := countedAt_spec hcnt
  obtain rfl : tb = blk := Option.some.inj (hy.symm.trans hblkH)
  have hpos : 0 < c.f.blocks.size := by have := arr_lt_of_get? hy; omega
  have hbodysucc : loop.body ∈ c.succ H := by
    unfold Ctx.succ cfgSucc
    rw [hy]
    show loop.body ∈ successors tb.term
    rw [hterm]
    simp [successors, htb]
  have hreachbody : Reach c.succ loop.body := by
    obtain ⟨l, hl⟩ := hreach
    exact ⟨loop.body :: l, Walk.step hl hbodysucc⟩
  obtain ⟨hx0, hsingle, _, _⟩ := refining_facts hc hreachbody hrefine
  have hsingle' : ∀ q, loop.body ∈ c.succ q → q = H := fun q hq => by rw [hsingle q hq, hesrc]
  have hybody : TDom c.succ H loop.body := TDom.of_single hx0 hsingle' (TDom.refl H)
  have hblatch : TDom c.succ loop.body loop.latch := dominates_tdom hc hpos hdom
  have hHlatch : TDom c.succ H loop.latch := hybody.trans hblatch
  -- every predecessor of the header is the latch
  have hpred : ∀ q, q ∈ tb.preds → q = loop.latch := by
    intro q hq
    have hlen : tb.preds.length = 2 := hplen
    obtain ⟨a, b', hab⟩ : ∃ a b', tb.preds = [a, b'] := by
      match hp : tb.preds, hlen with
      | [a, b'], _ => exact ⟨a, b', rfl⟩
    have hq' : q = a ∨ q = b' := by
      rw [hab] at hq
      simpa using hq
    have hab' : a = b' := by
      rw [hab] at heq
      simpa using heq
    have hl2 : [a, b'][k.latchIndex]? = some loop.latch := by rw [← hab]; exact hlatch
    have hli' : k.latchIndex = 0 ∨ k.latchIndex = 1 := hli
    have hal : a = loop.latch := by
      rcases hli' with h0 | h1
      · rw [h0] at hl2; simpa using hl2
      · rw [h1] at hl2; simp at hl2; rw [hab']; exact hl2
    rcases hq' with h | h
    · rw [h]; exact hal
    · rw [h, ← hab']; exact hal
  have hsingleH : ∀ q, H ∈ c.succ q → q = loop.latch := by
    intro q hq
    unfold Ctx.succ cfgSucc at hq
    cases hbq : c.f.blocks[q]? with
    | none => simp [hbq] at hq
    | some bq =>
      rw [hbq] at hq
      obtain ⟨tb2, htb2, hmem⟩ := edgesOK_succ hc.edges hbq hq
      rw [hy] at htb2
      cases htb2
      exact hpred q hmem
  have hH0 : H ≠ 0 := by
    intro h0
    subst h0
    obtain ⟨tb0, htb0⟩ : ∃ tb0, c.f.blocks[0]? = some tb0 := ⟨tb, hy⟩
    have := (entryOK_entry hc.entry htb0).1
    rw [hy] at htb0
    cases htb0
    rw [this] at hplen
    simp at hplen
  have hreachlatch : Reach c.succ loop.latch := by
    obtain ⟨l, hl⟩ := hreach
    obtain ⟨q, l', hl', hwq, hqs⟩ := hl.prev hH0
    have hq : q = loop.latch := hsingleH q hqs
    exact ⟨l', by rw [← hq]; exact hwq⟩
  exact TDom.not_single hH0 hsingleH hreachlatch hHlatch

/-- The counter of a counted loop is in its interval after every entry to the header, and along the latch edge it
moves by exactly one below the bound. -/
theorem counter_enter_x {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} (hb : c.f.blocks[fr.blk]? = some b)
    (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb)
    (hfrom : fr.blk ∈ tb.preds) (hreachy : Reach c.succ y) {k : Counted} (hcnt : c.countedAt y = some k)
    {lim : Interval} (hlim : (c.def_ k.counter).ty.range = some lim) (hsafe : CounterSafe c y k lim) :
    CounterHolds c (enterRegs fr.regs tb fr.blk) y k lim ∧
      (tb.preds[k.latchIndex]? = some fr.blk → ∃ nc, fr.regs k.counter = some (.int nc) ∧
        enterRegs fr.regs tb fr.blk k.counter = some (.int (nc + 1)) ∧ ((base c k.start).getD lim).lo ≤ nc ∧
        ∀ I, c.operand (some k.bound) y = some I → nc + 1 ≤ I.hi) := by
  obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd,
    hnphi, hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, ⟨line, latchEdge, entryEdge, hline, hle, hee, hentryv, step,
    oneV, one, hstep, hstepnphi, hstepadd, hsteparg, hstepb, honeinst, honeop, honeimm⟩, hli⟩ := countedAt_spec hcnt
  obtain rfl : tb = blk := Option.some.inj (hy.symm.trans hblkH)
  obtain ⟨p, hp, hpv⟩ := mem_of_phi_def hc hy hcphi hcblock
  have hpl : p = line := by
    have := (phi_def_of_mem hc hy hp).2.2
    rw [hpv, hline] at this
    exact (Option.some.inj this).symm
  subst hpl
  obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hp
  have hnd := hc.phi_values_nodup hy
  have hR' : enterRegs fr.regs tb fr.blk p.value = some val := enterRegs_phi _ _ _ hnd hp hnew
  obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
  have hedges := phisOK_edges hc.phis hy hp
  have hlen2 : p.edges.length = 2 := by
    have := congrArg List.length hedges
    simpa [hplen] using this
  obtain ⟨idx, hidx⟩ := List.mem_iff_getElem?.mp he
  have hidx2 : idx < 2 := by
    have := (List.getElem?_eq_some_iff.mp hidx).1
    omega
  have hpty : (c.def_ p.value).ty = p.ty := by
    obtain ⟨kk, hkk⟩ := List.mem_iff_getElem?.mp hp
    rw [hc.def_phi hy hkk]; rfl
  have hetype : (c.def_ e.value).ty = p.ty := hc.phiTyped hy hp he
  have hvok := hinv.val e.value val hrv
  rw [hpv] at hR' hpty
  have hlim' : p.ty.range = some lim := by rw [← hpty]; exact hlim
  rcases (show idx = k.latchIndex ∨ idx = 1 - k.latchIndex by omega) with hidxl | hidxe
  · -- the back edge
    subst hidxl
    rw [hle] at hidx
    have hee' : latchEdge = e := Option.some.inj hidx
    subst hee'
    have hlb : latchEdge.block = loop.latch := by
      have := congrArg (fun l => l[k.latchIndex]?) hedges
      simp only [List.getElem?_map, hle, Option.map_some] at this
      rw [hlatch] at this
      exact Option.some.inj this
    have hfl : fr.blk = loop.latch := by rw [← heb, hlb]
    -- the body has the single predecessor `y`
    have hbodysucc : loop.body ∈ c.succ y := by
      unfold Ctx.succ cfgSucc
      rw [hy]
      show loop.body ∈ successors tb.term
      rw [hterm]
      simp [successors, htb]
    have hreachbody : Reach c.succ loop.body := by
      obtain ⟨l, hl⟩ := hreachy
      exact ⟨loop.body :: l, Walk.step hl hbodysucc⟩
    obtain ⟨hx0, hsingle, _, _⟩ := refining_facts hc hreachbody hrefine
    have hsingle' : ∀ q, loop.body ∈ c.succ q → q = y := fun q hq => by rw [hsingle q hq, hesrc]
    have hybody : TDom c.succ y loop.body := TDom.of_single hx0 hsingle' (TDom.refl y)
    have hblatch : TDom c.succ loop.body fr.blk := by
      rw [hfl]
      exact dominates_tdom hc (by have := reached_lt hc hinv.reached; omega) hdom
    have hyfr : TDom c.succ y fr.blk := hybody.trans hblatch
    obtain ⟨nc, hnc, hbound⟩ := hinv.counter y k lim hyfr hcnt hlim hsafe
    -- the comparison at the body's edge
    have href := hinv.ref loop.body hblatch
    unfold RefHolds at href
    rw [hrefine] at href
    obtain ⟨blk', pb, cond', t', el', hblk', hpreds', hpb', hterm', hdef', hnphi', hcmp', htaken', hne'⟩ :=
      refining_spec hrefine
    rw [hesrc, hy] at hpb'
    obtain rfl : pb = tb := (Option.some.inj hpb').symm
    rw [hterm] at hterm'
    obtain ⟨rfl, rfl, rfl⟩ : cond = cond' ∧ t = t' ∧ el = el' := by
      simp only [Term.branch.injEq] at hterm'
      exact hterm'
    have hecmp : e'.cmp = cmp := by
      rw [hcd] at hdef'
      exact (Option.some.inj hdef').symm
    have hef := href (viewFuel c)
    unfold EdgeFacts at hef
    simp only [hecmp] at hef
    obtain ⟨na, nb, hRa, hRb, hpred, lowA, lowB⟩ := hef k.counter k.bound ha hbo
    rw [hnc] at hRa
    have hna : nc = na := by cases hRa; rfl
    subst hna
    have htk : e'.taken = true := by rw [htaken', htb]; simp
    have hlt' : nc < nb := by
      have := hpred .lt hlt
      rw [htk] at this
      simpa [predEval] using this
    -- the step is the counter plus one
    have hav := hw.phi hy hp he (pb := b) (by rw [heb]; exact hb) (by rw [heb]; exact hinv.reach)
    rw [heb] at hav
    have hav' : Avail c fr.blk fr.pc latchEdge.value := by rw [← hpc]; exact hav
    have hcons := hinv.cons latchEdge.value hav' step hstepnphi hstep
    have hstepv : step.value = latchEdge.value := hc.value_of_inst hstep hstepnphi
    obtain ⟨ch, hch⟩ := hcons val (by rw [hstepv]; exact hrv)
    -- the constant one
    have honeav : Avail c fr.blk b.insts.length oneV :=
      operand_avail_end hc hw hb hinv.reach hav hstepnphi hstep (mem_regOps_b hstepb)
    have honeav' : Avail c fr.blk fr.pc oneV := by rw [← hpc]; exact honeav
    obtain ⟨x1, hx1⟩ := hinv.defd oneV honeav'
    have honenp := hc.inst_not_phi honeinst
    have hcone := hinv.cons oneV honeav' one honenp honeinst
    have honev : one.value = oneV := hc.value_of_inst honeinst honenp
    obtain ⟨ch1, hch1⟩ := hcone x1 (by rw [honev]; exact hx1)
    have hx1v : x1 = .int 1 := by
      unfold evalInst evalOps at hch1
      simp only [honeop] at hch1
      have : Res.val (Val.int (constVal one.ty one.imm)) = Res.val x1 := hch1
      simp only [Res.val.injEq] at this
      rw [honeimm, constVal_one] at this
      exact this.symm
    subst hx1v
    -- the step's type is the counter's
    have hnc_step : step.op ≠ .call := by rw [hstepadd]; intro h; cases h
    obtain ⟨Ds, bs, st, hDs, hbs, hsts, hstvv, hstinst⟩ := hc.inst_of_def
      (show (c.def_ latchEdge.value).kind = .inst from by
        cases hk : (c.def_ latchEdge.value).kind with
        | missing => exact absurd hk (hc.kind_of_inst hstep)
        | phi => exact absurd hk hstepnphi
        | inst => rfl
        | pre =>
          exfalso
          obtain ⟨i0, hi0, hinst0, _⟩ := hc.pre_of_def hk
          rw [hstep] at hinst0
          cases hinst0
          obtain ⟨hop0, _⟩ := hc.pre_op hi0
          rw [hstepadd] at hop0
          rcases hop0 with h1 | h1 | h1 <;> first | cases h1 | simp [Op.isFree] at h1)
    rw [hstep] at hstinst
    cases hstinst
    have hty := hc.opTyped hbs (List.mem_of_getElem? hsts)
    simp only [OpTyped, hstepadd] at hty
    obtain ⟨wc, hwc, hwct⟩ := hty.1
    rw [hsteparg] at hwc
    cases hwc
    have hsteplim : step.ty.range = some lim := by rw [← hwct]; exact hlim
    -- evaluate the addition
    have hcounterv : (fr.regs.read step.operands.a).bind Val.int? = some nc := by
      rw [hsteparg]; simp [Regs.read, hnc, Val.int?]
    have honev1 : (fr.regs.read step.operands.b).bind Val.int? = some 1 := by
      rw [hstepb]; simp [Regs.read, hx1, Val.int?]
    unfold evalInst evalOps at hch
    simp only [hstepadd, readOps_a_val hnc_step, readOps_b, hcounterv, honev1] at hch
    -- the counter is below the bound, and in its type
    have hnclim : lim.contains nc := by
      have hv := hinv.val k.counter _ hnc
      obtain ⟨n', hn', hc'⟩ := ValTy.int hlim hv.1
      simp only [Val.int.injEq] at hn'
      subst hn'
      exact hc'
    -- the bound operand and its interval
    have hRb' : fr.regs k.bound = some (.int nb) := hRb
    obtain ⟨limb, hlimb⟩ := int_typed (hinv.val k.bound _ hRb').1
    have hnbI : ((viewN c (viewFuel c) k.bound y).getD limb).contains nb := by
      have := lowB limb nb hlimb hRb'
      rw [hesrc] at this
      exact this
    have hIop : c.operand (some k.bound) y = some ((viewN c (viewFuel c) k.bound y).getD limb) := by
      have hraw : c.operandRaw (some k.bound) y = some ((viewN c (viewFuel c) k.bound y).getD limb) := by
        simp only [Ctx.operandRaw, operandWith, hlimb]
      unfold Ctx.operand
      rw [hraw]
      simp only [isEmpty_false_of_contains hnbI, Bool.false_eq_true, ite_false]
    have hsafeI := hsafe _ hIop
    have hcm : lim.contains (nc + 1) := ⟨by have := hnclim.1; omega, by have := hnbI.2; omega⟩
    have hvr : Res.ofInt step.ty step.check (nc + 1) = .val val := hch
    have hval : val = .int (nc + 1) := by
      rcases ofInt_val hsteplim hvr with ⟨_, hv⟩ | ⟨hout, _, _⟩
      · exact hv
      · exact absurd hcm hout
    obtain ⟨h1, h2⟩ := hbound _ hIop
    have hh : nb ≤ ((viewN c (viewFuel c) k.bound y).getD limb).hi := hnbI.2
    refine ⟨⟨nc + 1, by rw [hR', hval], ?_⟩, fun _ => ⟨nc, hnc, by rw [hR', hval], h1, ?_⟩⟩
    · intro I hI
      rw [hIop] at hI
      cases hI
      exact ⟨by omega, by omega⟩
    · intro I hI
      rw [hIop] at hI
      cases hI
      omega
  · -- the entry edge
    rw [hidxe, hee] at hidx
    have hee' : entryEdge = e := Option.some.inj hidx
    subst hee'
    have hstr : (c.def_ entryEdge.value).ty.range = some lim := by rw [hetype]; exact hlim'
    obtain ⟨ns, hns, hlc⟩ := ValTy.int hstr hvok.1
    subst hns
    have hib := (hvok.2 ns rfl).1 lim hstr
    rw [hentryv] at hib
    refine ⟨⟨ns, hR', ?_⟩, ?_⟩
    · intro I hI
      exact ⟨hib.1, Int.le_trans hib.2 (Int.le_max_left _ _)⟩
    · intro hpl
      -- the entry edge comes from the block the latch index names: the two predecessors would coincide
      have hent : tb.preds[1 - k.latchIndex]? = some fr.blk := by
        have := congrArg (fun l => l[1 - k.latchIndex]?) hedges
        simp only [List.getElem?_map, hee, Option.map_some] at this
        rw [← this, heb]
      rcases hli with h0 | h1
      · rw [h0] at hpl hent
        have hent1 : tb.preds[1]? = some fr.blk := hent
        exact absurd (hpl.trans hent1.symm) (counted_preds_ne hc hcnt hy hreachy)
      · rw [h1] at hpl hent
        have hent0 : tb.preds[0]? = some fr.blk := hent
        exact absurd (hent0.trans hpl.symm) (counted_preds_ne hc hcnt hy hreachy)

/-- The counter of a counted loop is in its interval after every entry to the header. -/
theorem counter_enter {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} (hb : c.f.blocks[fr.blk]? = some b)
    (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb)
    (hfrom : fr.blk ∈ tb.preds) (hreachy : Reach c.succ y) {k : Counted} (hcnt : c.countedAt y = some k)
    {lim : Interval} (hlim : (c.def_ k.counter).ty.range = some lim) (hsafe : CounterSafe c y k lim) :
    CounterHolds c (enterRegs fr.regs tb fr.blk) y k lim :=
  (counter_enter_x hc hw hinv hadm hb hpc hy hfrom hreachy hcnt hlim hsafe).1

/-- The trip count of a counted loop is read from the bound's view and the counter's start. -/
theorem tripBound_spec {c : Ctx} (hc : CtxOK c) {H : Nat} {tb : Block} (hy : c.f.blocks[H]? = some tb) {k : Counted}
    (hcnt : c.countedAt H = some k) {lim : Interval} (hlim : (c.def_ k.counter).ty.range = some lim) {trips : Int}
    (ht : c.tripBound H = some trips) :
    ∃ I0, c.operand (some k.bound) H = some I0 ∧ trips = max (I0.hi - ((base c k.start).getD lim).lo) 0 := by
  unfold Ctx.tripBound at ht
  simp only [hcnt] at ht
  cases hop : c.operand (some k.bound) H with
  | none => simp [hop] at ht
  | some I0 =>
    simp only [hop] at ht
    refine ⟨I0, rfl, ?_⟩
    cases hb : base c k.start with
    | some st =>
      simp only [hb, Option.some.injEq] at ht
      rw [← ht]
      simp [hb]
    | none =>
      simp only [hb] at ht
      obtain ⟨loop, _, _, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd, hnphi,
        hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, ⟨line, latchEdge, entryEdge, hline, hle, hee, hentryv, _⟩, hli⟩ :=
        countedAt_spec hcnt
      obtain rfl : tb = blk := Option.some.inj (hy.symm.trans hblkH)
      obtain ⟨pp, hpp, hpv⟩ := mem_of_phi_def hc hy hcphi hcblock
      have hpl : pp = line := by
        have := (phi_def_of_mem hc hy hpp).2.2
        rw [hpv, hline] at this
        exact (Option.some.inj this).symm
      subst hpl
      have hentry : entryEdge ∈ pp.edges := List.mem_of_getElem? hee
      have hety : (c.def_ entryEdge.value).ty = pp.ty := hc.phiTyped hy hpp hentry
      have hpty : (c.def_ pp.value).ty = pp.ty := by
        obtain ⟨kk, hkk⟩ := List.mem_iff_getElem?.mp hpp
        rw [hc.def_phi hy hkk]; rfl
      rw [hpv] at hpty
      have hr : (c.def_ k.start).ty.range = some lim := by
        rw [← hentryv, hety, ← hpty]; exact hlim
      rw [hr] at ht
      simp only [Option.some.injEq] at ht
      rw [← ht]
      simp [hb]

/-- The header of a counted loop dominates its latch. -/
theorem counted_dom_latch {c : Ctx} (hc : CtxOK c) {H : Nat} {k : Counted} (hcnt : c.countedAt H = some k)
    {tb : Block} (hy : c.f.blocks[H]? = some tb) (hreach : Reach c.succ H) {L : Nat}
    (hl : tb.preds[k.latchIndex]? = some L) : TDom c.succ H L := by
  obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd,
    hnphi, hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, _, hli⟩ := countedAt_spec hcnt
  obtain rfl : tb = blk := Option.some.inj (hy.symm.trans hblkH)
  have hLeq : L = loop.latch := Option.some.inj (hl.symm.trans hlatch)
  have hpos : 0 < c.f.blocks.size := by have := arr_lt_of_get? hy; omega
  have hbodysucc : loop.body ∈ c.succ H := by
    unfold Ctx.succ cfgSucc
    rw [hy]
    show loop.body ∈ successors tb.term
    rw [hterm]
    simp [successors, htb]
  have hreachbody : Reach c.succ loop.body := by
    obtain ⟨l, hl⟩ := hreach
    exact ⟨loop.body :: l, Walk.step hl hbodysucc⟩
  obtain ⟨hx0, hsingle, _, _⟩ := refining_facts hc hreachbody hrefine
  have hsingle' : ∀ q, loop.body ∈ c.succ q → q = H := fun q hq => by rw [hsingle q hq, hesrc]
  have hybody : TDom c.succ H loop.body := TDom.of_single hx0 hsingle' (TDom.refl H)
  rw [hLeq]
  exact hybody.trans (dominates_tdom hc hpos hdom)

/-- An edge of a phi sits at an index of the predecessor list. -/
theorem phi_edge_index {p : Phi} {preds : List Nat} (hedges : p.edges.map (·.block) = preds) {e : PhiEdge}
    (he : e ∈ p.edges) : ∃ i : Nat, p.edges[i]? = some e ∧ preds[i]? = some e.block := by
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp he
  refine ⟨i, hi, ?_⟩
  have := congrArg (fun l : List Nat => l[i]?) hedges
  simpa [List.getElem?_map, hi] using this.symm

/-- A phi that takes a list satisfies the facts stated of it and of the lists it can be read through. -/
theorem phi_lst {c : Ctx} (hc : CtxOK c) (hff : c.firstFault = none) {fr : Frame} (hinv : FrameInv c fr)
    {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb) (hreachedy : c.reached[y]? = some true)
    (hopen : edgeOpen c fr.blk y = true) {p : Phi} (hp : p ∈ tb.phis) {val : Val}
    (hnew : phiNew fr.regs fr.blk p = some val) (R' : Regs) (hR' : R' p.value = some val)
    (hadm' : AdmFrame c R' y) :
    ∀ l, val = .list l → ∀ fuel, FactHolds c (c.liveList fuel p.value) l := by
  intro l hl
  subst hl
  obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
  obtain ⟨k, hk⟩ := List.mem_iff_getElem?.mp hp
  have hdp := hc.def_phi hy hk
  have hlive : edgeLive c e.block y = true := by
    unfold edgeLive
    rw [heb, hinv.reached]
    simp [hopen]
  have hf0 : FactHolds c e.value l := hinv.lst e.value l hrv 0
  have hkind : (c.def_ p.value).kind = .phi := by rw [hdp]; rfl
  have hphi : (c.def_ p.value).phi = some p := by rw [hdp]; rfl
  have hblk : (c.def_ p.value).block = some y := by rw [hdp]; rfl
  have hfp : FactHolds c p.value l := by
    refine factHolds_of_deriv hff hc (u := p.value) ?_ ?_ ?_ ?_
    · intro b hb
      rw [hblk] at hb
      cases hb
      exact hreachedy
    · rw [deriveList_phi hkind hphi hblk]
      exact joinLists_sound he hlive hf0
    · intro I h
      exact hadm'.listLen p.value l I hR' h
    · intro I h
      exact hadm'.listElems p.value l I hR' h
  intro fuel
  cases fuel with
  | zero => exact hfp
  | succ f =>
    rcases liveList_phi (fuel := f) hkind hphi hblk he hlive with h | h
    · rw [h]; exact hfp
    · rw [h]; exact hf0

/-- The start of a counted loop is produced when its header is entered: its stated interval is not empty. -/
theorem counter_start_next {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    {b : Block} (hb : c.f.blocks[fr.blk]? = some b) (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block}
    (hy : c.f.blocks[y]? = some tb) (hfrom : fr.blk ∈ tb.preds) (hreachy : Reach c.succ y) {k : Counted}
    (hcnt : c.countedAt y = some k) {lim : Interval} (hlim : (c.def_ k.counter).ty.range = some lim) :
    ((base c k.start).getD lim).isEmpty = false := by
  obtain ⟨loop, _, _, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd, hnphi,
    hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, ⟨line, latchEdge, entryEdge, hline, hle, hee, hentryv, _⟩, hli⟩ :=
    countedAt_spec hcnt
  obtain rfl : tb = blk := Option.some.inj (hy.symm.trans hblkH)
  obtain ⟨pp, hpp, hpv⟩ := mem_of_phi_def hc hy hcphi hcblock
  have hpl : pp = line := by
    have := (phi_def_of_mem hc hy hpp).2.2
    rw [hpv, hline] at this
    exact (Option.some.inj this).symm
  subst hpl
  obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hpp
  obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
  have hedges := phisOK_edges hc.phis hy hpp
  obtain ⟨i, hi, hpi⟩ := phi_edge_index hedges he
  rw [heb] at hpi
  have hlen2 : pp.edges.length = 2 := by
    have := congrArg List.length hedges
    simpa [hplen] using this
  have hi2 : i < 2 := by
    have := (List.getElem?_eq_some_iff.mp hi).1
    omega
  by_cases hl : tb.preds[k.latchIndex]? = some fr.blk
  · exact hinv.cstart y k lim (counted_dom_latch hc hcnt hy hreachy hl) hcnt hlim
  · have hidx : i = 1 - k.latchIndex := by
      by_cases h : i = k.latchIndex
      · exfalso; rw [h] at hpi; exact hl hpi
      · omega
    have hee' : e = entryEdge := by
      rw [hidx] at hi
      exact Option.some.inj (hi.symm.trans hee)
    subst hee'
    have hetype : (c.def_ e.value).ty = pp.ty := hc.phiTyped hy hpp he
    have hpty : (c.def_ pp.value).ty = pp.ty := by
      obtain ⟨kk, hkk⟩ := List.mem_iff_getElem?.mp hpp
      rw [hc.def_phi hy hkk]; rfl
    rw [hpv] at hpty
    have hstr : (c.def_ e.value).ty.range = some lim := by rw [hetype, ← hpty]; exact hlim
    have hvok := hinv.val e.value val hrv
    obtain ⟨ns, hns, hlc⟩ := ValTy.int hstr hvok.1
    subst hns
    have hib := (hvok.2 ns rfl).1 lim hstr
    rw [hentryv] at hib
    exact isEmpty_false_of_contains hib

/-- A reduction phi of a counted loop's header stays within its bound when the header is entered. -/
theorem chain_next {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) {fr : Frame} (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} (hb : c.f.blocks[fr.blk]? = some b)
    (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb)
    (hfrom : fr.blk ∈ tb.preds) (hreachy : Reach c.succ y) {p : Phi} (hp : p ∈ tb.phis) (ch : ChainInfo c y p)
    {lim : Interval} (hlim : (c.def_ ch.k.counter).ty.range = some lim) (hsafe : CounterSafe c y ch.k lim) :
    ChainBound c (enterRegs fr.regs tb fr.blk) ch lim := by
  have hnd := hc.phi_values_nodup hy
  obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hp
  have hR' : enterRegs fr.regs tb fr.blk p.value = some val := enterRegs_phi _ _ _ hnd hp hnew
  obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
  obtain ⟨hch, hexact⟩ := counter_enter_x hc hw hinv hadm hb hpc hy hfrom hreachy ch.hcnt hlim hsafe
  obtain ⟨I0, hI0, htrips⟩ := tripBound_spec hc hy ch.hcnt hlim ch.htrips
  obtain ⟨nc', hnc', hbd'⟩ := hch
  have hbd'' := hbd' I0 hI0
  have hedges := phisOK_edges hc.phis hy hp
  obtain ⟨i, hi, hpi⟩ := phi_edge_index hedges he
  rw [heb] at hpi
  have hi2 : i < 2 := by
    have := (List.getElem?_eq_some_iff.mp hi).1
    have hlen : p.edges.length = 2 := ch.hlen
    omega
  have hli : ch.k.latchIndex = 0 ∨ ch.k.latchIndex = 1 := by
    obtain ⟨loop, _, _, blk, cond, t, el, hblkH, hplen, hterm, htb, hdom, ⟨e', hrefine, hesrc⟩, cmp, hcd, hnphi,
      hcmp, hlt, ha, hbo, hcphi, hcblock, hlatch, _, hli⟩ := countedAt_spec ch.hcnt
    exact hli
  have hne := counted_preds_ne hc ch.hcnt hy hreachy
  by_cases hl : tb.preds[ch.k.latchIndex]? = some fr.blk
  · -- the back edge
    have hidx : i = ch.k.latchIndex := by
      by_cases h : i = ch.k.latchIndex
      · exact h
      · exfalso
        have : (i = 0 ∧ ch.k.latchIndex = 1) ∨ (i = 1 ∧ ch.k.latchIndex = 0) := by omega
        rcases this with ⟨h0, h1⟩ | ⟨h0, h1⟩
        · rw [h0] at hpi; rw [h1] at hl; exact hne (hpi.trans hl.symm)
        · rw [h0] at hpi; rw [h1] at hl; exact hne (hl.trans hpi.symm)
    have hee : e = ch.latchE := by
      rw [hidx] at hi
      exact Option.some.inj (hi.symm.trans ch.hlat)
    subst hee
    have hyfr : TDom c.succ y fr.blk := counted_dom_latch hc ch.hcnt hy hreachy hl
    obtain ⟨np, nc, hRp, hRc, h0, hlo, hhi⟩ := hinv.red y p ch lim hyfr hlim hsafe
    -- the type of the accumulator
    have hentry : ch.entryE ∈ p.edges := List.mem_of_getElem? ch.hent
    obtain ⟨lacc, hlacc0⟩ : ∃ l, (c.def_ ch.entryE.value).ty.range = some l := by
      cases h : (c.def_ ch.entryE.value).ty.range with
      | none => have := ch.hstart; simp [Ctx.operand, Ctx.operandRaw, operandWith, h] at this
      | some l => exact ⟨l, rfl⟩
    have hpty : (c.def_ p.value).ty = p.ty := by
      obtain ⟨kk, hkk⟩ := List.mem_iff_getElem?.mp hp
      rw [hc.def_phi hy hkk]; rfl
    have hlacc : (c.def_ p.value).ty.range = some lacc := by
      rw [hpty, ← hc.phiTyped hy hp hentry]; exact hlacc0
    have havacc : Avail c fr.blk fr.pc p.value := by
      unfold Avail; rw [ch.hkind]; exact ⟨y, ch.hblk, hyfr⟩
    have havl : Avail c fr.blk fr.pc ch.latchE.value := by
      have := hw.phi hy hp he (pb := b) (by rw [heb]; exact hb) (by rw [heb]; exact hinv.reach)
      rw [heb, hpc] at this
      exact this
    obtain ⟨nr, na, hRl, hRp2, hcont⟩ := chain_sound hc hw hinv hadm hb hpc ⟨ch.hkind, ch.hblk⟩ hlacc havacc ch.fuel
      ch.latchE.value ch.step ch.hstep havl
    obtain ⟨nc2, hRc2, hRc', hs0, hbound⟩ := hexact hl
    have e1 : na = np := by have := hRp2.symm.trans hRp; simpa using this
    have e2 : nc = nc2 := by have := hRc.symm.trans hRc2; simpa using this
    have hvalv : val = .int nr := by rw [hrv] at hRl; exact Option.some.inj hRl
    have hR'' : enterRegs fr.regs tb fr.blk p.value = some (.int nr) := by rw [hR', hvalv]
    have hb1 := hbound I0 hI0
    refine ⟨nr, nc2 + 1, hR'', hRc', by omega, ?_, ?_⟩
    · have hT : min (nc2 + 1 - ((base c ch.k.start).getD lim).lo) ch.trips =
          min (nc - ((base c ch.k.start).getD lim).lo) ch.trips + 1 := by omega
      rw [hT, Int.add_mul, Int.one_mul]
      simp only [Interval.contains] at hcont
      have : min ch.step.lo 0 ≤ ch.step.lo := Int.min_le_left _ _
      omega
    · have hT : min (nc2 + 1 - ((base c ch.k.start).getD lim).lo) ch.trips =
          min (nc - ((base c ch.k.start).getD lim).lo) ch.trips + 1 := by omega
      rw [hT, Int.add_mul, Int.one_mul]
      simp only [Interval.contains] at hcont
      have : ch.step.hi ≤ max ch.step.hi 0 := Int.le_max_left _ _
      omega
  · -- the entry edge
    have hidx : i = 1 - ch.k.latchIndex := by
      by_cases h : i = ch.k.latchIndex
      · exfalso; rw [h] at hpi; exact hl hpi
      · omega
    have hee : e = ch.entryE := by
      rw [hidx] at hi
      exact Option.some.inj (hi.symm.trans ch.hent)
    subst hee
    have hdef : ∀ w, some ch.entryE.value = some w → ∃ x, fr.regs w = some x := by
      intro w hw'
      have := Option.some.inj hw'
      rw [← this]
      exact ⟨val, hrv⟩
    have hD : TDom c.succ ch.entryE.block fr.blk := by rw [heb]; exact TDom.refl _
    obtain ⟨w, n, hwo, hRw, hcn⟩ := operand_at hc hw hinv hadm hD ch.hstart hdef
    have hwe : w = ch.entryE.value := (Option.some.inj hwo).symm
    subst hwe
    have hvalv : val = .int n := by rw [hrv] at hRw; exact Option.some.inj hRw
    have hR'' : enterRegs fr.regs tb fr.blk p.value = some (.int n) := by rw [hR', hvalv]
    have hT0 : 0 ≤ min (nc' - ((base c ch.k.start).getD lim).lo) ch.trips := by omega
    have h1 : min (nc' - ((base c ch.k.start).getD lim).lo) ch.trips * min ch.step.lo 0 ≤ 0 :=
      Int.mul_nonpos_of_nonneg_of_nonpos hT0 (Int.min_le_right _ _)
    have h2 : 0 ≤ min (nc' - ((base c ch.k.start).getD lim).lo) ch.trips * max ch.step.hi 0 :=
      Int.mul_nonneg hT0 (Int.le_max_right _ _)
    simp only [Interval.contains] at hcn
    exact ⟨n, nc', hR'', hnc', by omega, by omega, by omega⟩

/-- Entering a block along an edge the execution takes preserves the invariant. -/
theorem enter_inv {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr)
    (hadm : AdmFrame c fr.regs fr.blk) {b : Block} (hb : c.f.blocks[fr.blk]? = some b)
    (hpc : b.insts.length = fr.pc) {y : Nat} {tb : Block} (hy : c.f.blocks[y]? = some tb)
    (hys : y ∈ successors b.term)
    (hbr : ∀ cond t el, b.term = .branch cond t el →
      ∃ k, fr.regs cond = some (.int k) ∧ ((k = 1 ∧ y = t) ∨ (k = 0 ∧ y = el)))
    (hadm' : AdmFrame c (enterRegs fr.regs tb fr.blk) y) :
    FrameInv c { fr with regs := enterRegs fr.regs tb fr.blk, blk := y, pc := 0 } := by
  have hB : fr.blk < c.f.blocks.size := reached_lt hc hinv.reached
  have hysucc : y ∈ c.succ fr.blk := by
    unfold Ctx.succ cfgSucc; rw [hb]; exact hys
  obtain ⟨tb', htb', hfrom'⟩ := edgesOK_succ hc.edges hb hys
  rw [hy] at htb'
  cases htb'
  have hfrom : fr.blk ∈ tb.preds := hfrom'
  have hreachy : Reach c.succ y := by
    obtain ⟨l, hl⟩ := hinv.reach
    exact ⟨y :: l, Walk.step hl hysucc⟩
  have hopen : edgeOpen c fr.blk y = true := by
    cases hterm : b.term with
    | jump t => exact edgeOpen_jump hb hterm
    | branch cond t el =>
      obtain ⟨k, hk, hkk⟩ := hbr cond t el hterm
      apply edgeOpen_branch hb hterm hkk
      intro i hi
      obtain ⟨n', hn', _⟩ : ∃ n', Val.int k = Val.int n' ∧ True := ⟨k, rfl, trivial⟩
      have hv := hinv.val cond _ hk
      cases hr : (c.def_ cond).ty.range with
      | none =>
        have := hv.1
        unfold ValTy at this
        rw [hr] at this
        cases hty : (c.def_ cond).ty <;> simp [hty, Ty.range, Ty.bits] at hr <;> simp [hty] at this
      | some lim =>
        have := (hv.2 k rfl).1 lim hr
        rw [hi] at this
        exact this
    | ret v => rw [hterm] at hys; simp [successors] at hys
    | unreachable => rw [hterm] at hys; simp [successors] at hys
  have hreachedy : c.reached[y]? = some true :=
    (reachOK_succ hc.reach hB hinv.reached (by rw [arr_get!_of_get? hb]; exact hys)).2 hopen
  have hnd := hc.phi_values_nodup hy
  have hphi : ∀ p ∈ tb.phis, ∀ val, phiNew fr.regs fr.blk p = some val →
      enterRegs fr.regs tb fr.blk p.value = some val := fun p hp val hn => enterRegs_phi _ _ _ hnd hp hn
  have hother : ∀ w, ¬((c.def_ w).kind = .phi ∧ (c.def_ w).block = some y) →
      enterRegs fr.regs tb fr.blk w = fr.regs w := fun w hnp =>
    enterRegs_other _ _ _ (not_phi_of_not_def hc hy hnp)
  refine ⟨hreachy, hreachedy, ?_, ?_, ?_, ?_, hinv.args, ?_, ?_, ?_, ?_, ?_⟩
  · -- values
    intro w x hwx
    dsimp only at hwx
    by_cases hphiw : (c.def_ w).kind = .phi ∧ (c.def_ w).block = some y
    · obtain ⟨p, hp, hpv⟩ := mem_of_phi_def hc hy hphiw.1 hphiw.2
      subst hpv
      obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hp
      have hR := hphi p hp val hnew
      rw [hR] at hwx
      cases hwx
      exact phi_valok hc hw hinv hadm hy hopen hp hnew _ hR hadm'
        (fun k lim hk hkc hl hs => counter_enter hc hw hinv hadm hb hpc hy hfrom hreachy hk hl hs)
        (fun n hn ch lim hlim hsafe => by
          have hcb := chain_next hc hw hinv hadm hb hpc hy hfrom hreachy hp ch hlim hsafe
          obtain ⟨np, nc, hRp, _, hT0, hlo, hhi⟩ := hcb
          have hRp' : enterRegs fr.regs tb fr.blk p.value = some (.int n) := by rw [hR]; rw [hn]
          have hnp : np = n := by have := hRp.symm.trans hRp'; simpa using this
          subst hnp
          have htrips : 0 ≤ ch.trips := by
            obtain ⟨I0, _, ht⟩ := tripBound_spec hc hy ch.hcnt hlim ch.htrips
            omega
          have hTle : min (nc - ((base c ch.k.start).getD lim).lo) ch.trips ≤ ch.trips := Int.min_le_right _ _
          have hlo' := chain_lo (lo := ch.start.lo) (s := ch.step.lo) (by omega) hTle
          have hhi' := chain_hi (hi := ch.start.hi) (s := ch.step.hi) (by omega) hTle
          simp only [grown, Interval.contains]
          exact ⟨by omega, by omega⟩)
        (fun k lim hk hl => counter_start_next hc hw hinv hb hpc hy hfrom hreachy hk hl)
    · rw [hother w hphiw] at hwx
      exact hinv.val w x hwx
  · -- definedness
    intro w hav
    dsimp only at hav ⊢
    by_cases hphiw : (c.def_ w).kind = .phi ∧ (c.def_ w).block = some y
    · obtain ⟨p, hp, hpv⟩ := mem_of_phi_def hc hy hphiw.1 hphiw.2
      subst hpv
      obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hp
      exact ⟨val, hphi p hp val hnew⟩
    · have hav2 := avail_enter hc hb hysucc hav hphiw
      rw [hpc] at hav2
      obtain ⟨x, hx⟩ := hinv.defd w hav2
      exact ⟨x, by rw [hother w hphiw]; exact hx⟩
  · -- consistency
    intro w hav j hnp hj
    dsimp only at hav ⊢
    have hnphi : ¬((c.def_ w).kind = .phi ∧ (c.def_ w).block = some y) := fun h => hnp h.1
    have hav2 := avail_enter hc hb hysucc hav hnphi
    rw [hpc] at hav2
    have hcons := hinv.cons w hav2 j hnp hj
    have hjv := hc.value_of_inst hj hnp
    apply Cons.congr (R := fr.regs) _ _ hcons
    · intro w' hw'
      exact hother w' (operand_ne_phi hc hw hreachy hav hnp hj w' hw')
    · rw [hjv]; exact hother w hnphi
  · -- refining edges
    intro x hx
    dsimp only at hx ⊢
    by_cases hxy : x = y
    · subst hxy
      unfold RefHolds
      cases he : refining c x with
      | none => trivial
      | some e =>
        intro fuel
        obtain ⟨blk, pb, cond, t, el, hblk, hpreds, hpb, hterm, hdef, hnphi, hcmp, htaken, hne⟩ := refining_spec he
        rw [hy] at hblk
        cases hblk
        have hsrc : e.source = fr.blk := by
          rw [hpreds] at hfrom
          exact (List.mem_singleton.mp hfrom).symm
        rw [hsrc] at hpb
        rw [hb] at hpb
        cases hpb
        obtain ⟨k, hk, hkk⟩ := hbr cond t el hterm
        have hav := hw.branch hb hterm hinv.reach
        rw [hpc] at hav
        have hcons := hinv.cons cond hav e.cmp hnphi hdef
        have hiv : e.cmp.value = cond := hc.value_of_inst hdef hnphi
        have hcons2 := hcons (.int k) (by rw [hiv]; exact hk)
        obtain ⟨a, bb, na, nb, p0, ha, hbb, hRa, hRb, hp0, hkeq⟩ := cmp_eval hcmp hcons2
        intro a' b2 ha' hb2
        rw [ha] at ha'
        rw [hbb] at hb2
        cases ha'
        cases hb2
        have hxr : Reach c.succ x := hreachy
        have hnc : e.cmp.op ≠ .call := by rw [hcmp]; intro h; cases h
        have hAa : StrictAbove c a x := refining_operand_above hc hw hxr he (mem_regOps_a hnc ha)
        have hAb : StrictAbove c bb x := refining_operand_above hc hw hxr he (mem_regOps_b hbb)
        have hna : ¬((c.def_ a).kind = .phi ∧ (c.def_ a).block = some x) := fun h =>
          StrictAbove.not_def hc hAa (TDom.refl _) hreachy h.2
        have hnb : ¬((c.def_ bb).kind = .phi ∧ (c.def_ bb).block = some x) := fun h =>
          StrictAbove.not_def hc hAb (TDom.refl _) hreachy h.2
        have hRa' : enterRegs fr.regs tb fr.blk a = some (.int na) := by rw [hother a hna]; exact hRa
        have hRb' : enterRegs fr.regs tb fr.blk bb = some (.int nb) := by rw [hother bb hnb]; exact hRb
        refine ⟨na, nb, hRa', hRb', ?_, ?_, ?_⟩
        · intro p0' hp0'
          rw [hp0] at hp0'
          cases hp0'
          rcases hkk with ⟨hk1, hxt⟩ | ⟨hk0, hxe⟩
          · have htk : e.taken = true := by rw [htaken, ← hxt]; simp
            rw [htk]
            simp only [ite_true]
            rw [hk1] at hkeq
            by_cases hpe : predEval p0 na nb = true
            · exact hpe
            · simp [hpe] at hkeq
          · have htk : e.taken = false := by
              rw [htaken]
              have : t ≠ x := by rw [hxe]; exact hne
              simp [this]
            rw [htk]
            simp only [Bool.false_eq_true, ite_false]
            rw [hk0] at hkeq
            rw [predEval_negate]
            by_cases hpe : predEval p0 na nb = true
            · simp [hpe] at hkeq
            · simp [hpe]
        · intro lim n hl hr
          rw [hother a hna] at hr
          rw [hsrc]
          exact view_sound hc hw hinv hadm fuel hl hr
        · intro lim n hl hr
          rw [hother bb hnb] at hr
          rw [hsrc]
          exact view_sound hc hw hinv hadm fuel hl hr
    · have hxB : TDom c.succ x fr.blk := TDom.of_succ hysucc hxy hx
      have hxr : Reach c.succ x := TDom.reach_of hx hreachy
      refine refHolds_congr hc hw hxr ?_ (hinv.ref x hxB)
      intro w hwa
      apply hother w
      exact fun h => StrictAbove.not_def hc hwa hx hreachy h.2
  · -- counters
    intro H k lim hH hcnt hlim hsafe
    dsimp only at hH ⊢
    by_cases hHy : H = y
    · subst hHy
      exact counter_enter hc hw hinv hadm hb hpc hy hfrom hreachy hcnt hlim hsafe
    · have hHB : TDom c.succ H fr.blk := TDom.of_succ hysucc hHy hH
      obtain ⟨nc, hnc, hbd⟩ := hinv.counter H k lim hHB hcnt hlim hsafe
      refine ⟨nc, ?_, hbd⟩
      rw [hother k.counter]
      · exact hnc
      · intro hcontra
        have hp := countedAt_phi hcnt
        rw [hp.2] at hcontra
        exact hHy (Option.some.inj hcontra.2)
  · -- lists
    intro w l hwl fuel
    dsimp only at hwl
    by_cases hphiw : (c.def_ w).kind = .phi ∧ (c.def_ w).block = some y
    · obtain ⟨p, hp, hpv⟩ := mem_of_phi_def hc hy hphiw.1 hphiw.2
      subst hpv
      obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hp
      have hR := hphi p hp val hnew
      rw [hR] at hwl
      cases hwl
      exact phi_lst hc hff hinv hy hreachedy hopen hp hnew _ hR hadm' l rfl fuel
    · rw [hother w hphiw] at hwl
      exact hinv.lst w l hwl fuel
  · -- reductions
    intro H p ch lim hH hlim hsafe
    dsimp only at hH ⊢
    by_cases hHy : H = y
    · subst hHy
      exact chain_next hc hw hinv hadm hb hpc hy hfrom hreachy
        (by
          obtain ⟨pp, hpp, hpv⟩ := mem_of_phi_def hc hy ch.hkind ch.hblk
          have : pp = p := by
            have h1 := (phi_def_of_mem hc hy hpp).2.2
            rw [hpv, ch.hphi] at h1
            exact (Option.some.inj h1).symm
          rw [← this]; exact hpp) ch hlim hsafe
    · have hHB : TDom c.succ H fr.blk := TDom.of_succ hysucc hHy hH
      obtain ⟨np, nc, hRp, hRc, h0, h1, h2⟩ := hinv.red H p ch lim hHB hlim hsafe
      refine ⟨np, nc, ?_, ?_, h0, h1, h2⟩
      · rw [hother p.value]
        · exact hRp
        · intro hcontra
          rw [ch.hblk] at hcontra
          exact hHy (Option.some.inj hcontra.2)
      · rw [hother ch.k.counter]
        · exact hRc
        · intro hcontra
          have hp := countedAt_phi ch.hcnt
          rw [hp.2] at hcontra
          exact hHy (Option.some.inj hcontra.2)
  · -- the start of a counted loop
    intro H k lim hH hcnt hlim
    dsimp only at hH
    by_cases hHy : H = y
    · subst hHy
      exact counter_start_next hc hw hinv hb hpc hy hfrom hreachy hcnt hlim
    · exact hinv.cstart H k lim (TDom.of_succ hysucc hHy hH) hcnt hlim
  · -- joins
    intro H acc F q I lacc hk hb' hlacc hqa hg hqk hav
    dsimp only at hav ⊢
    have hpos : 0 < c.f.blocks.size := by omega
    cases F with
    | zero => simp [Ctx.jGrowth] at hg
    | succ f =>
      obtain ⟨wh, qq, hqb, hqphi, hwhH, hdom, hedgesJ⟩ := jGrowth_phi hg hqa hqk
      have hHwh : TDom c.succ H wh := dominates_tdom hc hpos hdom
      have hwhy : TDom c.succ wh y := by
        unfold Avail at hav
        rw [hqk] at hav
        obtain ⟨D, hD, hd⟩ := hav
        rw [hqb] at hD
        cases (Option.some.inj hD)
        exact hd
      by_cases hwy : wh = y
      · subst hwy
        have hHy : H ≠ wh := fun h => hwhH h.symm
        have hHB : TDom c.succ H fr.blk := TDom.of_succ hysucc hHy hHwh
        have hnotphi : ¬((c.def_ acc).kind = .phi ∧ (c.def_ acc).block = some wh) := by
          rintro ⟨_, hbb⟩
          rw [hb'] at hbb
          exact hHy (Option.some.inj hbb)
        obtain ⟨pq, hpq, hpv⟩ := mem_of_phi_def hc hy hqk hqb
        have hpqq : pq = qq := by
          have h1 := (phi_def_of_mem hc hy hpq).2.2
          rw [hpv, hqphi] at h1
          exact (Option.some.inj h1).symm
        subst hpqq
        obtain ⟨val, hnew⟩ := phiNew_some hc hw hinv hb hpc hy hfrom hpq
        have hR := hphi pq hpq val hnew
        obtain ⟨e, he, heb, hrv⟩ := phiNew_edge hnew
        have hlive : edgeLive c e.block wh = true := by
          unfold edgeLive
          rw [heb]
          simp [hinv.reached, hopen]
        obtain ⟨hall, _⟩ := jEdges_spec pq.edges none I hedgesJ
        obtain ⟨moved, hlow, hmoved⟩ := hall e he hlive
        have havacc : Avail c fr.blk fr.pc acc := by
          unfold Avail; rw [hk]; exact ⟨H, hb', hHB⟩
        have hav_e : Avail c fr.blk fr.pc e.value := by
          have := hw.phi hy hpq he (pb := b) (by rw [heb]; exact hb) (by rw [heb]; exact hinv.reach)
          rw [heb, hpc] at this
          exact this
        obtain ⟨nr, na, hRe, hRacc, hcont⟩ := chain_sound hc hw hinv hadm hb hpc ⟨hk, hb'⟩ hlacc havacc f e.value
          moved hlow hav_e
        have hvalv : val = .int nr := by rw [hrv] at hRe; exact Option.some.inj hRe
        refine ⟨nr, na, ?_, ?_, hmoved _ hcont⟩
        · rw [← hpv, hR, hvalv]
        · rw [hother acc hnotphi]; exact hRacc
      · have hHy : H ≠ y := by
          intro h
          subst h
          exact hwy (TDom.antisymm hreachy hwhy hHwh)
        have hHB : TDom c.succ H fr.blk := TDom.of_succ hysucc hHy (hHwh.trans hwhy)
        have hnotphi : ¬((c.def_ acc).kind = .phi ∧ (c.def_ acc).block = some y) := by
          rintro ⟨_, hbb⟩
          rw [hb'] at hbb
          exact hHy (Option.some.inj hbb)
        have hnotphiq : ¬((c.def_ q).kind = .phi ∧ (c.def_ q).block = some y) := by
          rintro ⟨_, hbb⟩
          rw [hqb] at hbb
          exact hwy (Option.some.inj hbb)
        have hav2 := avail_enter hc hb hysucc hav hnotphiq
        rw [hpc] at hav2
        obtain ⟨nq, na, hRq, hRa, hcont⟩ := hinv.jn H acc (f + 1) q I lacc hk hb' hlacc hqa hg hqk hav2
        refine ⟨nq, na, ?_, ?_, hcont⟩
        · rw [hother q hnotphiq]; exact hRq
        · rw [hother acc hnotphi]; exact hRa


/-! ### Calling a function -/

theorem regOps_nil_pre {c : Ctx} (hc : CtxOK c) {i : Inst} (hi : i ∈ c.f.pre) : regOps i = [] := by
  obtain ⟨_, ha, hb, hx⟩ := hc.pre_op hi
  unfold regOps
  simp [ha, hb, hx]

theorem opTyped_pre {c : Ctx} (hc : CtxOK c) {i : Inst} (hi : i ∈ c.f.pre) : OpTyped c i := by
  obtain ⟨hop, _⟩ := hc.pre_op hi
  unfold OpTyped
  cases h : i.op <;> simp [h, Op.isFree] at hop ⊢

/-- The initial registers of a frame are good values. -/
theorem init_val {c : Ctx} (hc : CtxOK c) (hff : c.firstFault = none) {args : List Val} {regs : Regs}
    (hinit : InitRegs c.f args regs) (hargs : ArgsOK c args) (hadm : AdmFrame c regs 0) :
    ∀ v x, regs v = some x → ValOK c v x := by
  intro v x hx
  have hex : ∃ i ∈ c.f.pre, i.value = v := by
    by_cases h : ∃ i ∈ c.f.pre, i.value = v
    · exact h
    · have := hinit.2 v (fun i hi e => h ⟨i, hi, e⟩)
      rw [this] at hx
      cases hx
  obtain ⟨i, hi, hiv⟩ := hex
  subst hiv
  obtain ⟨ch, val, hev, hvt, hal, hr⟩ := hinit.1 i hi
  rw [hr] at hx
  cases hx
  obtain ⟨k, hk⟩ := List.mem_iff_getElem?.mp hi
  have hdp := hc.def_pre hk
  have hnc : i.op ≠ .call := by
    obtain ⟨hop, _⟩ := hc.pre_op hi
    intro h; rw [h] at hop; simp [Op.isFree] at hop
  have hnil := regOps_nil_pre hc hi
  refine valok_core (here := 0) (Or.inr (by rw [hdp]; rfl)) (by rw [hdp]; rfl) (by rw [hdp]; rfl)
    (by rw [hdp]; rfl) (by rw [hdp]; rfl) (Ctx.pre_ok hff hi) hvt ?_ ?_
  · intro limits n hlim hvn hna
    subst hvn
    obtain ⟨n2, hn2, hcon⟩ := derive_contains (R := fun _ => none) (here := 0)
      (by intro w I hw; rw [hnil] at hw; cases hw) (opTyped_pre hc hi)
      ⟨by rw [hdp]; rfl, by rw [hdp]; rfl⟩ hlim hev hvt hal (by intro w n h; cases h) hna hargs
      (fun hp => paramsOK_pre hc.params hi hp) (by intro w l hw; rw [hnil] at hw; cases hw)
      (fun h => absurd h hnc)
    simp only [Val.int.injEq] at hn2
    subst hn2
    exact hcon
  · intro n hvn hav
    subst hvn
    exact hadm.stated _ n hr hav


theorem tdom_zero {succ : Nat → List Nat} {x : Nat} (h : TDom succ x 0) : x = 0 := by
  have := h [0] Walk.start
  simpa using this

/-- A value available at the first instruction of the entry block is a constant or parameter. -/
theorem avail_entry_pre {c : Ctx} (hc : CtxOK c) (hpos : 0 < c.f.blocks.size) {v : Nat} (hav : Avail c 0 0 v) :
    (c.def_ v).kind = .pre := by
  unfold Avail at hav
  cases hk : (c.def_ v).kind with
  | missing => rw [hk] at hav; exact absurd hav id
  | pre => rfl
  | phi =>
    rw [hk] at hav
    obtain ⟨D, hD, hd⟩ := hav
    have hD0 := tdom_zero hd
    subst hD0
    obtain ⟨tb, htb⟩ : ∃ tb, c.f.blocks[0]? = some tb := ⟨c.f.blocks[0], Array.getElem?_eq_getElem hpos⟩
    obtain ⟨p, hp, _⟩ := mem_of_phi_def hc htb hk hD
    rw [(entryOK_entry hc.entry htb).2] at hp
    cases hp
  | inst =>
    rw [hk] at hav
    obtain ⟨D, hD, h⟩ := hav
    rcases h with ⟨_, hlt⟩ | ⟨hne, hd⟩
    · omega
    · exact absurd (tdom_zero hd) hne

/-- The lists a fresh activation holds satisfy their stated facts. -/
theorem init_lst {c : Ctx} (hc : CtxOK c) (hff : c.firstFault = none) {args : List Val} {regs : Regs}
    (hinit : InitRegs c.f args regs) (hadm : AdmFrame c regs 0) : ListInv c regs := by
  intro v l hv fuel
  have hex : ∃ i ∈ c.f.pre, i.value = v := by
    by_cases h : ∃ i ∈ c.f.pre, i.value = v
    · exact h
    · have := hinit.2 v (fun i hi e => h ⟨i, hi, e⟩)
      rw [this] at hv
      cases hv
  obtain ⟨i, hi, hiv⟩ := hex
  subst hiv
  obtain ⟨ch, val, hev, hvt, hal, hr⟩ := hinit.1 i hi
  rw [hr] at hv
  cases hv
  obtain ⟨k, hk⟩ := List.mem_iff_getElem?.mp hi
  have hdp := hc.def_pre hk
  have hnil := regOps_nil_pre hc hi
  have hkind : (c.def_ i.value).kind = .pre := by rw [hdp]; rfl
  have hinst : (c.def_ i.value).inst = some i := by rw [hdp]; rfl
  have hblk : (c.def_ i.value).block = none := by rw [hdp]; rfl
  have hfp : FactHolds c i.value l := by
    refine factHolds_of_deriv hff hc (u := i.value) ?_ ?_ ?_ ?_
    · intro b hb
      rw [hblk] at hb
      cases hb
    · exact deriveList_inst_sound (R := fun _ => none) (args := args) (ch := ch) (d := c.def_ i.value)
        (here := (c.def_ i.value).block.getD 0)
        (by rw [hkind]; intro h; cases h) hinst (by intro w I hw; rw [hnil] at hw; cases hw)
        (by intro w la hw; cases hw) hev
    · intro I h
      exact hadm.listLen i.value l I hr h
    · intro I h
      exact hadm.listElems i.value l I hr h
  cases fuel with
  | zero => exact hfp
  | succ f => rw [liveList_pre hkind]; exact hfp

/-- A function entered with good arguments starts with the invariant. -/
theorem init_inv {c : Ctx} (hc : CtxOK c) (hff : c.firstFault = none) {fn : Nat} {args : List Val} {regs : Regs}
    (hpos : 0 < c.f.blocks.size) (hinit : InitRegs c.f args regs) (hargs : ArgsOK c args)
    (hadm : AdmFrame c regs 0) : FrameInv c { fn := fn, args := args, regs := regs, blk := 0, pc := 0 } := by
  refine ⟨⟨[0], Walk.start⟩, reachOK_entry hc.reach hpos, init_val hc hff hinit hargs hadm, ?_, ?_, ?_, hargs, ?_,
    init_lst hc hff hinit hadm, ?_, ?_, ?_⟩
  · intro v hav
    have hk := avail_entry_pre hc hpos hav
    obtain ⟨i, hi, _, hiv⟩ := hc.pre_of_def hk
    obtain ⟨ch, val, _, _, _, hr⟩ := hinit.1 i hi
    exact ⟨val, by rw [← hiv]; exact hr⟩
  · intro v hav j hnp hj
    have hk := avail_entry_pre hc hpos hav
    obtain ⟨i, hi, hinst, hiv⟩ := hc.pre_of_def hk
    rw [hj] at hinst
    cases hinst
    obtain ⟨ch, val, hev, _, _, hr⟩ := hinit.1 _ hi
    intro x hx
    dsimp only at hx ⊢
    rw [hr] at hx
    cases hx
    refine ⟨ch, ?_⟩
    unfold evalInst at hev ⊢
    rw [readOps_congr (R := fun _ => none)]
    · exact hev
    · intro w hw
      rw [regOps_nil_pre hc hi] at hw
      cases hw
  · intro x hx
    dsimp only at hx ⊢
    have := tdom_zero hx
    subst this
    unfold RefHolds
    obtain ⟨tb, htb⟩ : ∃ tb, c.f.blocks[0]? = some tb := ⟨c.f.blocks[0], Array.getElem?_eq_getElem hpos⟩
    have hp := (entryOK_entry hc.entry htb).1
    have : refining c 0 = none := by
      unfold refining
      rw [htb]
      simp only [hp]
    rw [this]
    trivial
  · intro H k lim hH hcnt hlim hsafe
    dsimp only at hH
    have := tdom_zero hH
    subst this
    obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, _⟩ := countedAt_spec hcnt
    have hp := (entryOK_entry hc.entry hblkH).1
    rw [hp] at hplen
    simp at hplen
  · intro H p ch lim hH _ _
    dsimp only at hH
    have := tdom_zero hH
    subst this
    obtain ⟨tb0, htb0⟩ : ∃ tb0, c.f.blocks[0]? = some tb0 := ⟨c.f.blocks[0], Array.getElem?_eq_getElem hpos⟩
    have hp := (entryOK_entry hc.entry htb0).2
    obtain ⟨p', hp', _⟩ := mem_of_phi_def hc htb0 ch.hkind ch.hblk
    rw [hp] at hp'
    cases hp'
  · intro H k lim hH hcnt hlim
    dsimp only at hH
    have := tdom_zero hH
    subst this
    obtain ⟨loop, hloop, hhdr, blk, cond, t, el, hblkH, hplen, _⟩ := countedAt_spec hcnt
    have hp := (entryOK_entry hc.entry hblkH).1
    rw [hp] at hplen
    simp at hplen
  · intro H acc F q I lacc hk hb' hlacc hqa hg hqk hav
    dsimp only at hav
    have := avail_entry_pre hc hpos hav
    rw [hqk] at this
    cases this


/-! ### Calls and returns -/

theorem interOut_call {c : Ctx} {b : Block} {here : Nat} (h : c.interOut b here = none) {i : Inst} (hi : i ∈ b.insts)
    (hop : i.op = .call) {g : Nat} (ha : i.operands.a = some g) {callee : Function}
    (hg : c.m.functions[g]? = some callee) (hint : callee.header.internal = true)
    (hnaddr : callee.header.addressTaken = false) {k w : Nat} (hk : i.operands.x[k]? = some (some w))
    {claim : Interval} (hcl : (callee.boundary.params[k]?).bind id = some claim) {seen : Interval}
    (hseen : c.operandRaw (some w) here = some seen) (hne : seen.isEmpty = false) :
    (reinterpret seen (c.def_ w).ty ((callee.header.params[k]?).getD .other)).within claim = true := by
  unfold Ctx.interOut at h
  have h1 := (orElse_none.mp h).1
  rw [List.findSome?_eq_none_iff] at h1
  have h2 := h1 i hi
  simp only [hop, bne_self_eq_false, ha, hg, hint, hnaddr, Bool.not_true, Bool.or_false, Bool.false_eq_true, ite_false] at h2
  rw [List.findSome?_eq_none_iff] at h2
  have h3 := h2 (some w, k) (List.mk_mem_zipIdx_iff_getElem?.mpr hk)
  simp only [hcl, hseen, hne, Bool.false_eq_true, ite_false] at h3
  by_cases hwi : (reinterpret seen (c.def_ w).ty ((callee.header.params[k]?).getD .other)).within claim = true
  · exact hwi
  · simp [hwi] at h3

theorem interOut_ret {c : Ctx} {b : Block} {here : Nat} (h : c.interOut b here = none) {w : Nat}
    (hterm : b.term = .ret (some w)) {claim : Interval} (hclaim : c.f.boundary.returns = some claim)
    (hr : (c.def_ w).ty.range.isSome = true) {seen : Interval} (hseen : c.operandRaw (some w) here = some seen)
    (hne : seen.isEmpty = false) : seen.within claim = true := by
  unfold Ctx.interOut at h
  have h1 := (orElse_none.mp h).2
  rw [hterm] at h1
  simp only [hclaim, hr, ite_true, hseen, hne, Bool.false_or] at h1
  by_cases hw : seen.within claim = true
  · exact hw
  · simp [hw] at h1

/-- The context of function `g` of the module, when its preparation succeeds. -/
def ctxOf (m : Module) (g : Nat) : Option Ctx :=
  match m.functions[g]? with
  | some f => match prepare m f with | .ok c => some c | .error _ => none
  | none => none

theorem ctxOf_spec {m : Module} {g : Nat} {c : Ctx} (h : ctxOf m g = some c) :
    m.functions[g]? = some c.f ∧ c.m = m ∧ CtxOK c := by
  unfold ctxOf at h
  cases hf : m.functions[g]? with
  | none => rw [hf] at h; simp at h
  | some f =>
    rw [hf] at h
    simp only [] at h
    cases hp : prepare m f with
    | error _ => rw [hp] at h; simp at h
    | ok c' =>
      rw [hp] at h
      simp only [Option.some.injEq] at h
      subst h
      obtain ⟨hm, hf', hok⟩ := prepare_ok hp
      exact ⟨by rw [hf', ← hf], hm, hok⟩

/-- Every function of the module passes the checker. -/
def ModOK (m : Module) : Prop :=
  ∀ g f, m.functions[g]? = some f → ∃ c, ctxOf m g = some c ∧ c.firstFault = none

/-- Every function's uses are dominated by their definitions (what the IR verifier checks). -/
def ModWf (m : Module) : Prop := ∀ g c, ctxOf m g = some c → SsaWf c

theorem callee_spec {m : Module} {i : Inst} {g : Nat} {h : Function} (hc : callee? m i = some (g, h)) :
    i.operands.a = some g ∧ m.functions[g]? = some h := by
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
        exact ⟨rfl, hf⟩
      · simp [hb] at hc

/-- The arguments of a call satisfy the parameter intervals the callee states. -/
theorem call_args_ok {m : Module} {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none)
    {fr : Frame} (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) (hcm : c.m = m) (hop : i.op = .call)
    {g : Nat} {h : Function} (hcallee : callee? m i = some (g, h)) {cg : Ctx} (hcg : ctxOf m g = some cg) :
    ArgsOK cg (callArgs fr.regs i) := by
  obtain ⟨ha, hgh⟩ := callee_spec hcallee
  obtain ⟨hgf, _, _⟩ := ctxOf_spec hcg
  rw [hgh] at hgf
  cases hgf
  intro k claim a n hpc harg hpv
  -- the parameter has a claim, so the callee is internal and its address is not taken
  have hclaim : (cg.f.boundary.params[k]?).bind id = some claim := by
    unfold paramClaim at hpc
    by_cases hcnd : (!cg.f.header.internal || cg.f.header.addressTaken || k ≥ cg.f.boundary.params.length) = true
    · simp [hcnd] at hpc
    · simp only [hcnd, ite_false] at hpc
      cases hpk : cg.f.boundary.params[k]? with
      | none => rw [hpk] at hpc; simp at hpc
      | some o => rw [hpk] at hpc; simpa using hpc
  have hint : cg.f.header.internal = true ∧ cg.f.header.addressTaken = false := by
    unfold paramClaim at hpc
    by_cases hcnd : (!cg.f.header.internal || cg.f.header.addressTaken || k ≥ cg.f.boundary.params.length) = true
    · simp [hcnd] at hpc
    · simp only [Bool.or_eq_true, Bool.not_eq_true', decide_eq_true_eq, not_or] at hcnd
      refine ⟨?_, ?_⟩
      · cases h : cg.f.header.internal <;> simp_all
      · cases h : cg.f.header.addressTaken <;> simp_all
  -- the argument
  unfold callArgs at harg
  simp only [List.getElem?_map] at harg
  cases hxk : i.operands.x[k]? with
  | none => rw [hxk] at harg; simp at harg
  | some o =>
    rw [hxk] at harg
    simp only [Option.map_some, Option.some.injEq] at harg
    subst harg
    cases a_val : (fr.regs.read o).getD Val.other with
    | list l => rw [a_val] at hpv; simp [paramVal] at hpv
    | other => rw [a_val] at hpv; simp [paramVal] at hpv
    | int n0 =>
      rw [a_val] at hpv
      simp only [paramVal, Val.int.injEq] at hpv
      cases o with
      | none => simp [Regs.read] at a_val
      | some w =>
        have hRw : fr.regs w = some (.int n0) := by
          simp only [Regs.read, Option.bind_some] at a_val
          cases hR : fr.regs w with
          | none => rw [hR] at a_val; simp at a_val
          | some v => rw [hR] at a_val; simpa using a_val
        have hvok := hinv.val w _ hRw
        cases hty : (c.def_ w).ty.range with
        | none =>
          have := hvok.1
          unfold ValTy at this
          rw [hty] at this
          cases hT : (c.def_ w).ty <;> simp [hT, Ty.range, Ty.bits] at hty <;> simp [hT] at this
        | some lim =>
          obtain ⟨n1, hn1, hlc⟩ := ValTy.int hty hvok.1
          simp only [Val.int.injEq] at hn1
          subst hn1
          have hseen : c.operandRaw (some w) fr.blk = some ((viewN c (viewFuel c) w fr.blk).getD lim) := by
            simp only [Ctx.operandRaw, operandWith, hty]
          have hin := view_sound hc hw hinv hadm (viewFuel c) hty hRw
          have hout := Ctx.inter_ok hff hb hinv.reached
          have := interOut_call hout (List.mem_of_getElem? hk) hop ha (by rw [hcm]; exact hgh) hint.1 hint.2
            hxk hclaim hseen (isEmpty_false_of_contains hin)
          have hrs := reinterpret_sound hin hty hlc (to := (cg.f.header.params[k]?).getD .other)
          rw [← hpv]
          exact within_contains this hrs


/-- The value a function returns is within the interval it states. -/
theorem ret_claim {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {blk : Block}
    (hb : c.f.blocks[fr.blk]? = some blk) {rv : Option Nat} (hterm : blk.term = .ret rv) {n : Int}
    (hv : (fr.regs.read rv).getD .other = .int n) {r : Interval} (hr : c.f.boundary.returns = some r) :
    r.contains n := by
  cases rv with
  | none => simp [Regs.read] at hv
  | some w =>
    have hRw : fr.regs w = some (.int n) := by
      simp only [Regs.read, Option.bind_some] at hv
      cases hR : fr.regs w with
      | none => rw [hR] at hv; simp at hv
      | some v => rw [hR] at hv; simpa using hv
    have hvok := hinv.val w _ hRw
    cases hty : (c.def_ w).ty.range with
    | none =>
      have := hvok.1
      unfold ValTy at this
      rw [hty] at this
      cases hT : (c.def_ w).ty <;> simp [hT, Ty.range, Ty.bits] at hty <;> simp [hT] at this
    | some lim =>
      have hseen : c.operandRaw (some w) fr.blk = some ((viewN c (viewFuel c) w fr.blk).getD lim) := by
        simp only [Ctx.operandRaw, operandWith, hty]
      have hin := view_sound hc hw hinv hadm (viewFuel c) hty hRw
      have hout := Ctx.inter_ok hff hb hinv.reached
      have := interOut_ret hout hterm hr (by rw [hty]; rfl) hseen (isEmpty_false_of_contains hin)
      exact within_contains this hin

theorem evalInst_call {R : Regs} {args : List Val} {i : Inst} {ch : Val} (h : i.op = .call) :
    evalInst R args i ch = .val ch := by
  unfold evalInst evalOps
  simp [h]

end Facts
