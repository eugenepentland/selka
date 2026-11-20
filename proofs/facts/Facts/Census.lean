import Facts.Run
import Facts.Chain

/-!
# A census of what the checker accepts on trust

Not part of the checker or the proof: for each accepted function, how many values rest on each kind of acceptance
(`lake exe factcheck --census`). The soundness theorem assumes exactly the items counted as `assumed`
(`AXIOMS.md`); the census says how much of a corpus rests on each.
-/

namespace Facts

/-- Counts of the ways values are accepted. -/
structure Census where
  phiHull : Nat := 0
  phiCounter : Nat := 0
  phiReduction : Nat := 0
  /-- Reductions in a function with more than one stated loop (an upper bound for those through an inner loop). -/
  phiReductionNested : Nat := 0
  instDerived : Nat := 0
  instAssumed : Nat := 0
  listDerived : Nat := 0
  listAssumed : Nat := 0
  caps : Nat := 0
  /-- Values whose stated interval is empty: never produced (design change 15). -/
  emptyStated : Nat := 0
  /-- Proven checks counted as unchecked because the checks on every edge prove them (design change 16). -/
  edgeChecked : Nat := 0
  deriving Repr

/-- Whether an outcome is an assumption. -/
def Out.isAssumed : Out → Bool
  | .assumed => true
  | _ => false

/-- Whether an outcome is a derivation. -/
def Out.isDerived : Out → Bool
  | .derived => true
  | _ => false

/-- How the phi `p` of block `pos` was accepted. -/
def Ctx.phiKind (c : Ctx) (p : Phi) (pos : Nat) : Census :=
  match p.range, p.ty.range with
  | some stated, some limits =>
    match c.phiHull p pos limits with
    | none => {}
    | some derived =>
      if derived.within stated then { phiHull := 1 }
      else
        match c.counterBound p pos with
        | some b => if counterAccepts b derived limits stated then { phiCounter := 1 } else
            match c.reduction p pos with
            | some b' => if (derived.meet b').within stated then { phiReduction := 1 } else {}
            | none => {}
        | none =>
            match c.reduction p pos with
            | some b' => if (derived.meet b').within stated then { phiReduction := 1 } else {}
            | none => {}
  | _, _ => {}

/-- Add two censuses. -/
def Census.add (a b : Census) : Census :=
  { phiHull := a.phiHull + b.phiHull, phiCounter := a.phiCounter + b.phiCounter,
    phiReduction := a.phiReduction + b.phiReduction,
    phiReductionNested := a.phiReductionNested + b.phiReductionNested, instDerived := a.instDerived + b.instDerived,
    instAssumed := a.instAssumed + b.instAssumed, listDerived := a.listDerived + b.listDerived,
    listAssumed := a.listAssumed + b.listAssumed, caps := a.caps + b.caps,
    emptyStated := a.emptyStated + b.emptyStated, edgeChecked := a.edgeChecked + b.edgeChecked }

/-- The census of one accepted function. -/
def Ctx.census (c : Ctx) : Census := Id.run do
  let empties := c.defs.toList.filter fun d => (d.stated.map (·.isEmpty)).getD false
  let edge : Nat := (c.stats.unchecked[reasonEdgeChecked]?).getD 0
  let mut t : Census := { caps := c.caps.length, emptyStated := empties.length, edgeChecked := edge }
  for pos in List.range c.count do
    if c.reached[pos]?.getD false then
      let b := c.f.blocks[pos]!
      for p in b.phis do
        let k := c.phiKind p pos
        t := t.add { k with phiReductionNested := if c.f.aux.loops.length > 1 then k.phiReduction else 0 }
      for i in b.insts do
        let o := c.instOut i pos
        t := { t with instDerived := t.instDerived + (if o.isDerived then 1 else 0),
                      instAssumed := t.instAssumed + (if o.isAssumed then 1 else 0) }
  for i in c.f.pre do
    let o := c.instOut i 0
    t := { t with instDerived := t.instDerived + (if o.isDerived then 1 else 0),
                  instAssumed := t.instAssumed + (if o.isAssumed then 1 else 0) }
  for o in c.listOuts do
    t := { t with listDerived := t.listDerived + (if o.isDerived then 1 else 0),
                  listAssumed := t.listAssumed + (if o.isAssumed then 1 else 0) }
  return t

/-- The census of a function, if the checker accepts it. -/
def censusFunction (m : Module) (f : Function) : Option Census :=
  match prepare m f with
  | .error _ => none
  | .ok c => match c.firstFault with
    | some _ => none
    | none => some c.census

/-! ### Which reductions rest on what -/

/-- One edge-join of `growthStep`, with `low` the level below (a copy of `Ctx.growthStep`'s local `joinEdges`). -/
def Ctx.joinEdgesR (c : Ctx) (low : Nat → Nat → Nat → Option Interval × Nat) (acc where_ : Nat) :
    List PhiEdge → Option Interval → Nat → Option Interval × Nat
  | [], out, b => (out, b)
  | e :: rest, out, b =>
    if !(edgeLive c e.block where_) then Ctx.joinEdgesR c low acc where_ rest out b
    else
      match low acc e.value b with
      | (none, b') => (none, b')
      | (some moved, b') =>
        Ctx.joinEdgesR c low acc where_ rest (some (match out with | none => moved | some so => so.hull moved)) b'

/-- `Ctx.growthStep` with joins and inner loops switched on or off (the census asks which a reduction needs). -/
def Ctx.growthStepR (c : Ctx) (allowJoin allowInner : Bool) (low : Nat → Nat → Nat → Option Interval × Nat)
    (acc raw budget : Nat) : Option Interval × Nat :=
  if budget == 0 then (none, 0) else
  let budget := budget - 1
  if raw == acc then (some (Interval.point 0), budget) else
  let d := c.def_ raw
  match d.block with
  | none => (none, budget)
  | some where_ =>
    if d.kind == .phi then
      if c.f.aux.loops.any (fun l => l.header == where_) then
        (if allowInner then c.innerGrowth low acc raw where_ budget else (none, budget))
      else
        match d.phi with
        | none => (none, budget)
        | some p => if allowJoin then c.joinEdgesR low acc where_ p.edges none budget else (none, budget)
    else
      match d.inst with
      | none => (none, budget)
      | some i =>
        if i.op != .add && i.op != .sub then (none, budget)
        else if i.check == .none then (none, budget)
        else
          match i.operands.a with
          | none => (none, budget)
          | some a =>
            match low acc a budget with
            | (some x, b1) =>
              match c.operand i.operands.b where_ with
              | none => (none, b1)
              | some y =>
                if i.op == .add then (some ⟨x.lo + y.lo, x.hi + y.hi⟩, b1)
                else (some ⟨x.lo - y.hi, x.hi - y.lo⟩, b1)
            | (none, b1) =>
              if i.op == .sub then (none, b1) else
              match i.operands.b with
              | none => (none, b1)
              | some bv =>
                match low acc bv b1 with
                | (none, b2) => (none, b2)
                | (some y, b2) =>
                  match c.operand i.operands.a where_ with
                  | none => (none, b2)
                  | some x => (some ⟨x.lo + y.lo, x.hi + y.hi⟩, b2)

/-- `Ctx.growthN` with the switches. -/
def Ctx.growthNR (c : Ctx) (allowJoin allowInner : Bool) : Nat → Nat → Nat → Nat → Option Interval × Nat
  | 0 => fun _ _ b => (none, b)
  | fuel + 1 => c.growthStepR allowJoin allowInner (c.growthNR allowJoin allowInner fuel)

/-- `Ctx.reduction` with the switches. -/
def Ctx.reductionR (c : Ctx) (allowJoin allowInner : Bool) (p : Phi) (here : Nat) : Option Interval :=
  match c.countedAt here with
  | none => none
  | some k =>
    if k.counter == p.value || p.edges.length != 2 then none else
    match p.edges[k.latchIndex]?, p.edges[1 - k.latchIndex]? with
    | some latchE, some entryE =>
      match (c.growthNR allowJoin allowInner (growthBudget + 2) p.value latchE.value growthBudget).1 with
      | none => none
      | some step =>
        match c.operand (some entryE.value) entryE.block with
        | none => none
        | some start =>
          match c.tripBound here with
          | none => none
          | some trips => some (grown start step trips)
    | _, _ => none

/-- Whether the meet of `b` with the hull of the live operands of the phi `p` of block `here` is within `stated`. -/
def Ctx.hullMeetWithin (c : Ctx) (p : Phi) (here : Nat) (b stated : Interval) : Bool :=
  match p.ty.range with
  | none => false
  | some limits =>
    match c.phiHull p here limits with
    | none => false
    | some hull => (hull.meet b).within stated

theorem Ctx.hullMeetWithin_spec {c : Ctx} {p : Phi} {here : Nat} {b stated : Interval}
    (h : c.hullMeetWithin p here b stated = true) :
    ∃ limits hull, p.ty.range = some limits ∧ c.phiHull p here limits = some hull ∧ (hull.meet b).within stated = true := by
  unfold Ctx.hullMeetWithin at h
  cases hl : p.ty.range with
  | none => simp [hl] at h
  | some limits =>
    simp only [hl] at h
    cases hh : c.phiHull p here limits with
    | none => simp [hh] at h
    | some hull => simp only [hh] at h; exact ⟨limits, hull, rfl, hh, h⟩

/-- What a reduction needs: only additions and subtractions of the accumulator, joins too, or an inner counted loop. -/
def Ctx.reductionClass (c : Ctx) (p : Phi) (here : Nat) (stated : Interval) : String :=
  let ok (j i : Bool) : Bool := match c.reductionR j i p here with | some b => c.hullMeetWithin p here b stated | none => false
  if ok false false then "chain" else if ok true false then "join" else "inner"

/-- The reduction phis the checker accepts in an accepted function, one line each. -/
def Ctx.reductionLines (c : Ctx) (file name : String) : List String := Id.run do
  let mut out : List String := []
  for pos in List.range c.count do
    if c.reached[pos]?.getD false then
      let b := c.f.blocks[pos]!
      for p in b.phis do
        let k := c.phiKind p pos
        if k.phiReduction == 1 then
          match p.range with
          | some stated => out := out ++ [s!"{file} {name} %{p.value} b{pos} {c.reductionClass p pos stated}"]
          | none => pure ()
  return out

/-- Whether the chain rule (`ChainProved`) proves the stated interval of the reduction phi `p` of the header `here`: the
Boolean image of the definition, with a fixed fuel (a census, not a proof). -/
def Ctx.chainProvedB (c : Ctx) (p : Phi) (here : Nat) (stated : Interval) : Bool :=
  match c.countedAt here with
  | none => false
  | some k =>
    if k.counter == p.value || p.edges.length != 2 then false else
    match p.edges[k.latchIndex]?, p.edges[1 - k.latchIndex]?, (c.def_ k.counter).ty.range with
    | some latchE, some entryE, some lim =>
      match c.jGrowth here (growthBudget + 2) p.value latchE.value, c.operand (some entryE.value) entryE.block,
          c.tripBound here, c.operand (some k.bound) here with
      | some step, some start, some trips, some bound =>
        decide (bound.hi ≤ lim.hi) &&
          ((grown start step trips).within stated || c.hullMeetWithin p here (grown start step trips) stated)
      | _, _, _, _ => false
    | _, _, _ => false

/-- The reduction phis the chain rule proves in an accepted function. -/
def Ctx.chainCount (c : Ctx) : Nat := Id.run do
  let mut n := 0
  for pos in List.range c.count do
    if c.reached[pos]?.getD false then
      let b := c.f.blocks[pos]!
      for p in b.phis do
        if (c.phiKind p pos).phiReduction == 1 then
          match p.range with
          | some stated => if c.chainProvedB p pos stated then n := n + 1
          | none => pure ()
  return n

end Facts
