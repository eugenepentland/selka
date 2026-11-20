import Facts.ListDerive

/-!
# Reductions by accumulator chains

The reductions (design 5.5) whose growth is a chain of checked additions and subtractions of the accumulator: the
accumulator's definition, the data the rule computes (`ChainInfo`), the bound it proves (`ChainBound`), and the interval
arithmetic of the bound.
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- The hull of the growth of the live edges of a join phi (`Ctx.growthStep`'s `joinEdges`, without a budget): none
as soon as one live edge has no growth. -/
def Ctx.jEdges (c : Ctx) (low : Nat → Option Interval) (where_ : Nat) :
    List PhiEdge → Option Interval → Option Interval
  | [], out => out
  | e :: rest, out =>
    if !(edgeLive c e.block where_) then c.jEdges low where_ rest out
    else
      match low e.value with
      | none => none
      | some moved => c.jEdges low where_ rest (some (match out with | none => moved | some so => so.hull moved))

/-- How far `raw` lies from the accumulator `acc` in one iteration of the loop of the header `H`, when `raw` is `acc`
moved by checked additions and subtractions and by joins of such values (`Ctx.growthStep` without inner loops, with fuel
in place of a budget). A join must lie in a block the header dominates, other than the header. -/
def Ctx.jGrowth (c : Ctx) (H : Nat) : Nat → Nat → Nat → Option Interval
  | 0, _, _ => none
  | fuel + 1, acc, raw =>
    if raw == acc then some (Interval.point 0) else
    let d := c.def_ raw
    match d.block with
    | none => none
    | some where_ =>
      if d.kind == .phi then
        if where_ == H || !(c.dominates H where_) || c.f.aux.loops.any (fun l => l.header == where_) then none else
        match d.phi with
        | none => none
        | some q => c.jEdges (c.jGrowth H fuel acc) where_ q.edges none
      else
      match d.inst with
      | none => none
      | some i =>
        if i.op != .add && i.op != .sub then none
        else if i.check == .none then none
        else
          match i.operands.a with
          | none => none
          | some a =>
            match c.jGrowth H fuel acc a with
            | some x =>
              match c.operand i.operands.b where_ with
              | none => none
              | some y =>
                if i.op == .add then some ⟨x.lo + y.lo, x.hi + y.hi⟩
                else some ⟨x.lo - y.hi, x.hi - y.lo⟩
            | none =>
              if i.op == .sub then none else
              match i.operands.b with
              | none => none
              | some bv =>
                match c.jGrowth H fuel acc bv with
                | none => none
                | some y =>
                  match c.operand i.operands.a where_ with
                  | none => none
                  | some x => some ⟨x.lo + y.lo, x.hi + y.hi⟩

/-- The bound of the loop fits the counter's type, so no step of the counter wraps. -/
def CounterSafe (c : Ctx) (H : Nat) (k : Counted) (lim : Interval) : Prop :=
  ∀ I, c.operand (some k.bound) H = some I → I.hi ≤ lim.hi

/-- The data of a reduction phi `p` of the header `H` of a counted loop, as `Ctx.reduction` computes it, with the
growth by an accumulator chain. -/
structure ChainInfo (c : Ctx) (H : Nat) (p : Phi) where
  k : Counted
  latchE : PhiEdge
  entryE : PhiEdge
  step : Interval
  start : Interval
  trips : Int
  fuel : Nat
  hkind : (c.def_ p.value).kind = .phi
  hphi : (c.def_ p.value).phi = some p
  hblk : (c.def_ p.value).block = some H
  hcnt : c.countedAt H = some k
  hne : k.counter ≠ p.value
  hlen : p.edges.length = 2
  hlat : p.edges[k.latchIndex]? = some latchE
  hent : p.edges[1 - k.latchIndex]? = some entryE
  hstep : c.jGrowth H fuel p.value latchE.value = some step
  hstart : c.operand (some entryE.value) entryE.block = some start
  htrips : c.tripBound H = some trips

/-- The interval of a reduction phi that the chain rule proves: its entry view moved by at most `T` steps, where `T`
counts the counter's distance from its start, capped at the trips. -/
def ChainBound (c : Ctx) (R : Regs) {H : Nat} {p : Phi} (ch : ChainInfo c H p) (lim : Interval) : Prop :=
  ∃ np nc, R p.value = some (.int np) ∧ R ch.k.counter = some (.int nc) ∧
    0 ≤ nc - ((base c ch.k.start).getD lim).lo ∧
    ch.start.lo + min (nc - ((base c ch.k.start).getD lim).lo) ch.trips * min ch.step.lo 0 ≤ np ∧
    np ≤ ch.start.hi + min (nc - ((base c ch.k.start).getD lim).lo) ch.trips * max ch.step.hi 0

/-- A stated interval the chain rule proves for the phi `p` of the header `H`: the chain's bound is within it, or the meet
of that bound with the hull of the phi's live operands is (the phi's value lies in both). -/
def ChainProved (c : Ctx) (p : Phi) (H : Nat) (stated : Interval) : Prop :=
  ∃ ch : ChainInfo c H p, ∃ lim, (c.def_ ch.k.counter).ty.range = some lim ∧ CounterSafe c H ch.k lim ∧
    ((grown ch.start ch.step ch.trips).within stated = true ∨
      ∃ limits hull, p.ty.range = some limits ∧ c.phiHull p H limits = some hull ∧
        (hull.meet (grown ch.start ch.step ch.trips)).within stated = true)

theorem chain_lo {lo T trips s : Int} (hT0 : 0 ≤ T) (hTt : T ≤ trips) : lo + min 0 (trips * s) ≤ lo + T * min s 0 := by
  by_cases hs : 0 ≤ s
  · have h1 : min s 0 = 0 := by omega
    have h2 : 0 ≤ trips * s := Int.mul_nonneg (by omega) hs
    rw [h1, Int.mul_zero]
    omega
  · have h1 : min s 0 = s := by omega
    have h2 : trips * s ≤ T * s := Int.mul_le_mul_of_nonpos_right hTt (by omega)
    have h3 : trips * s ≤ 0 := Int.mul_nonpos_of_nonneg_of_nonpos (by omega) (by omega)
    rw [h1]
    omega

theorem chain_hi {hi T trips s : Int} (hT0 : 0 ≤ T) (hTt : T ≤ trips) : hi + T * max s 0 ≤ hi + max 0 (trips * s) := by
  by_cases hs : 0 ≤ s
  · have h1 : max s 0 = s := by omega
    have h2 : T * s ≤ trips * s := Int.mul_le_mul_of_nonneg_right hTt hs
    have h3 : 0 ≤ trips * s := Int.mul_nonneg (by omega) hs
    rw [h1]
    omega
  · have h1 : max s 0 = 0 := by omega
    have h3 : trips * s ≤ 0 := Int.mul_nonpos_of_nonneg_of_nonpos (by omega) (by omega)
    rw [h1, Int.mul_zero]
    omega

theorem chain_succ_lo {lo T s st np d : Int} (hs : min s 0 ≤ s) (hnp : lo + T * min s 0 ≤ np) (hd : st ≤ d)
    (hst : min st 0 ≤ st) (hse : s = st) :
    lo + (T + 1) * min s 0 ≤ np + d := by
  subst hse
  rw [Int.add_mul, Int.one_mul]
  omega

theorem chain_succ_hi {hi T s np d : Int} (hnp : np ≤ hi + T * max s 0) (hd : d ≤ s) :
    np + d ≤ hi + (T + 1) * max s 0 := by
  rw [Int.add_mul, Int.one_mul]
  have : s ≤ max s 0 := Int.le_max_left _ _
  omega

/-- What a successful join of edges says of each live edge. -/
theorem jEdges_spec {c : Ctx} {low : Nat → Option Interval} {wh : Nat} :
    ∀ (edges : List PhiEdge) (out : Option Interval) (J : Interval), c.jEdges low wh edges out = some J →
      (∀ e ∈ edges, edgeLive c e.block wh = true → ∃ moved, low e.value = some moved ∧
        ∀ n, moved.contains n → J.contains n) ∧
      (∀ K, out = some K → ∀ n, K.contains n → J.contains n) := by
  intro edges
  induction edges with
  | nil =>
    intro out J h
    simp only [Ctx.jEdges] at h
    refine ⟨fun e he => (by cases he), ?_⟩
    intro K hK n hn
    rw [h] at hK
    cases hK
    exact hn
  | cons e rest ih =>
    intro out J h
    unfold Ctx.jEdges at h
    by_cases hl : (!(edgeLive c e.block wh)) = true
    · simp only [hl, ite_true] at h
      obtain ⟨h1, h2⟩ := ih out J h
      refine ⟨?_, h2⟩
      intro e' he' hlive
      rcases List.mem_cons.mp he' with rfl | hrest
      · simp at hl
        rw [hl] at hlive
        cases hlive
      · exact h1 e' hrest hlive
    · simp only [hl, Bool.false_eq_true, ite_false] at h
      cases hlow : low e.value with
      | none => simp [hlow] at h
      | some moved =>
        simp only [hlow] at h
        obtain ⟨h1, h2⟩ := ih _ J h
        constructor
        · intro e' he' hlive
          rcases List.mem_cons.mp he' with rfl | hrest
          · refine ⟨moved, hlow, ?_⟩
            intro n hn
            apply h2 _ rfl n
            cases out with
            | none => exact hn
            | some so => exact hull_contains_right hn
          · exact h1 e' hrest hlive
        · intro K hK n hn
          apply h2 _ rfl n
          rw [hK]
          exact hull_contains_left hn

/-- A join in a growth derivation: where it lies and what its edges give. -/
theorem jGrowth_phi {c : Ctx} {H F acc raw : Nat} {I : Interval} (h : c.jGrowth H (F + 1) acc raw = some I)
    (hne : raw ≠ acc) (hphi : (c.def_ raw).kind = .phi) :
    ∃ wh q, (c.def_ raw).block = some wh ∧ (c.def_ raw).phi = some q ∧ wh ≠ H ∧ c.dominates H wh = true ∧
      c.jEdges (c.jGrowth H F acc) wh q.edges none = some I := by
  unfold Ctx.jGrowth at h
  have hne' : ¬ (raw == acc) = true := by simpa using hne
  simp only [hne', Bool.false_eq_true, ite_false] at h
  cases hblk : (c.def_ raw).block with
  | none => simp [hblk] at h
  | some wh =>
    simp only [hblk, hphi, beq_self_eq_true, ite_true] at h
    by_cases hbad : (wh == H || !(c.dominates H wh) || c.f.aux.loops.any (fun l => l.header == wh)) = true
    · simp [hbad] at h
    · simp only [hbad, Bool.false_eq_true, ite_false] at h
      cases hq : (c.def_ raw).phi with
      | none => simp [hq] at h
      | some q =>
        simp only [hq] at h
        refine ⟨wh, q, rfl, rfl, ?_, ?_, h⟩
        · intro heq
          apply hbad
          simp [heq]
        · by_cases hd : c.dominates H wh = true
          · exact hd
          · exfalso
            apply hbad
            simp [hd]

end Facts
