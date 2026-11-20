import Facts.View

/-!
# The transfer rules

Design §4–§6: what each rule derives (`derive`), loops and reductions (§5.5), the inter-procedural
and `proven` checks. Each rule is a pure function returning an *outcome* for one item; the checker
(`Run.lean`) takes the first fault in the validator's order, and an accepted function's statistics
are the counts of the outcomes.
-/

namespace Facts

/-- What a rule says of one stated item. -/
inductive Out where
  /-- Nothing to check. -/
  | skip
  /-- The stated interval contains what the rule derives. -/
  | derived
  /-- Accepted without a derivation (design §8, A6). -/
  | assumed
  /-- A `proven` check the rows validate. -/
  | proven
  /-- A `proven` check the checker has no row for or cannot validate (by reason). -/
  | unchecked (reason : Nat)
  /-- A fault. -/
  | bad (f : Fault)
  deriving Repr

/-- The fault of an outcome, if it is one. -/
def Out.fault? : Out → Option Fault
  | .bad f => some f
  | _ => none

/-! ### Interval arithmetic -/

/-- The exact interval of `x + y`, `x - y` or `x * y` (the validator saturates at the `i128` bounds, which lie
beyond every type range and so never change a comparison with one). -/
def arithmetic (op : Op) (x y : Interval) : Interval :=
  match op with
  | .add => ⟨x.lo + y.lo, x.hi + y.hi⟩
  | .sub => ⟨x.lo - y.hi, x.hi - y.lo⟩
  | _ =>
    let p0 := x.lo * y.lo
    let p1 := x.lo * y.hi
    let p2 := x.hi * y.lo
    let p3 := x.hi * y.hi
    ⟨min (min p0 p1) (min p2 p3), max (max p0 p1) (max p2 p3)⟩

/-- `start` after at most `trips` steps, each in `step`. -/
def grown (start step : Interval) (trips : Int) : Interval :=
  ⟨start.lo + min 0 (trips * step.lo), start.hi + max 0 (trips * step.hi)⟩

/-- The number of bits needed to write `n` (zero for zero). -/
def bitLength (n : Nat) : Nat := if n = 0 then 0 else Nat.log2 n + 1

/-- The interval of a value reread at the signedness of type `to`, of the same width, given the interval `r` it had. -/
def reshift (r : Interval) (to : Ty) (limits : Interval) : Interval :=
  let span : Int := (2 : Int) ^ to.bits
  if to.signed then
    let half : Int := span / 2
    if r.lo ≥ half then ⟨r.lo - span, r.hi - span⟩ else limits
  else if r.hi < 0 then ⟨r.lo + span, r.hi + span⟩ else limits

/-- The interval a callee sees for an argument of type `from_` passed to a parameter of type `to`: the same bits,
read at the parameter's signedness. -/
def reinterpret (r : Interval) (from_ to : Ty) : Interval :=
  match to.range with
  | none => r
  | some limits =>
    if r.within limits then r
    else if from_.bits != to.bits || from_.signed == to.signed then limits
    else reshift r to limits

/-- Whether the interval of this operation's result reads a list or a callee that passes after the facts rewrote
(design §8, A6). -/
def staleAfterFacts : Op → Bool
  | .listGet | .arrayGet | .call => true
  | _ => false

/-- Whether the operation has a row in the table of design §4. -/
def hasRow : Op → Bool
  | .add | .sub | .mul | .shiftLeft | .shiftRight | .div | .floorDiv | .rem | .floorRem | .neg | .convert
  | .arrayGet | .arraySet | .listGet | .listGetField | .listSet | .listPop => true
  | _ => false

/-! ### Lists -/

namespace Ctx

/-- The stated fact of list `v`. -/
def listFact? (c : Ctx) (v : Nat) : Option ListFact := (c.lists[v]?).getD none

/-- The value whose list fact a list operation reads: through views and borrows (`fuel` levels), and through a phi
with one live operand. -/
def liveList (c : Ctx) : Nat → Nat → Nat
  | 0, v => v
  | fuel + 1, v =>
    let d := c.def_ v
    match d.kind with
    | .inst =>
      match d.inst with
      | some i =>
        if i.op == .listViewOf || i.op == .borrow then
          match i.operands.a with
          | some a => liveList c fuel a
          | none => v
        else v
      | none => v
    | .phi =>
      match d.phi, d.block with
      | some p, some blk =>
        let live := p.edges.filter fun e => (c.reached[e.block]?.getD false) && edgeOpen c e.block blk
        match live with
        | [] => v
        | e :: rest => if rest.all (fun e' => e'.value == e.value) then e.value else v
      | _, _ => v
    | _ => v

end Ctx

/-! ### The rules for one instruction -/

/-- The interval a rule derives, and whether it is an assumption. -/
structure Derived where
  range : Interval
  assumed : Bool := false

/-- Whether the intervals decide the comparison `x p y`: true, false, or neither. -/
def decideCmp (p : Pred) (x y : Interval) : Option Bool :=
  match p with
  | .lt => if x.hi < y.lo then some true else if x.lo ≥ y.hi then some false else none
  | .le => if x.hi ≤ y.lo then some true else if x.lo > y.hi then some false else none
  | .gt => if x.lo > y.hi then some true else if x.hi ≤ y.lo then some false else none
  | .ge => if x.lo ≥ y.hi then some true else if x.hi < y.lo then some false else none
  | .eq => if x.lo == x.hi && y.lo == y.hi && x.lo == y.lo then some true
           else if x.hi < y.lo || y.hi < x.lo then some false else none
  | .ne => if x.hi < y.lo || y.hi < x.lo then some true
           else if x.lo == x.hi && y.lo == y.hi && x.lo == y.lo then some false else none

/-- A comparison decided by the operand intervals. -/
def Ctx.compare (c : Ctx) (i : Inst) (here : Nat) : Interval :=
  let undecided : Interval := ⟨0, 1⟩
  match c.operand i.operands.a here, c.operand i.operands.b here with
  | some x, some y =>
    match Pred.ofImm i.imm with
    | none => undecided
    | some p =>
      match decideCmp p x y with
      | some b => Interval.point (if b then 1 else 0)
      | none => undecided
  | _, _ => undecided

/-- The list fact view the operation reads: through `liveList`. -/
def Ctx.factLen (c : Ctx) (a : Option Nat) : Option Interval :=
  match a with
  | none => none
  | some v => (c.listFact? (c.liveList c.count v)).bind (·.len)

/-- The element interval of the list operand. -/
def Ctx.factElems (c : Ctx) (a : Option Nat) : Option Interval :=
  match a with
  | none => none
  | some v => (c.listFact? (c.liveList c.count v)).bind (·.elems)

/-- Whether the viewed interval of an operand is empty: the value is never produced. -/
def Ctx.emptyView (c : Ctx) (o : Option Nat) (here : Nat) : Bool :=
  match c.operandRaw o here with
  | some r => r.isEmpty
  | none => false

/-- Whether the rule of `i` reads an operand that is never produced. The rule reads its operands in order and stops at
the first that is not an integer, as the validator's `operand` calls do. -/
def Ctx.ruleVacuous (c : Ctx) (i : Inst) (here : Nat) : Bool :=
  match i.op with
  | .add | .sub | .mul | .saturatingAdd | .shiftRight | .floorDiv | .div | .floorRem | .rem | .bitXor | .cmp =>
    c.emptyView i.operands.a here || ((c.operandRaw i.operands.a here).isSome && c.emptyView i.operands.b here)
  | .convert | .not => c.emptyView i.operands.a here
  | _ => false

/-- What the transfer rule of `i` derives at block `here` when every operand it reads is produced (design §4). -/
def Ctx.deriveRule (c : Ctx) (i : Inst) (limits : Interval) (here : Nat) : Derived :=
  let full : Derived := ⟨limits, false⟩
  let unknown : Derived := ⟨limits, true⟩
  match i.op with
  | .iconst => ⟨Interval.point (constantOf (c.def_ i.value)), false⟩
  | .param => ⟨(paramInterval c i).getD limits, false⟩
  | .add | .sub | .mul =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some y =>
      let e := arithmetic i.op x y
      if e.within limits then ⟨e, false⟩
      else ⟨if i.check == .none then limits else e.meet limits, false⟩
    | _, _ => full
  | .saturatingAdd =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some y =>
      let clamp (v : Int) : Int := max limits.lo (min limits.hi v)
      ⟨⟨clamp (x.lo + y.lo), clamp (x.hi + y.hi)⟩, false⟩
    | _, _ => full
  | .shiftRight =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some count =>
      if count.lo < 0 ∨ count.hi ≥ (i.ty.bits : Int) then full
      else
        let lo := count.lo.toNat
        let hi := count.hi.toNat
        ⟨⟨min (x.lo >>> lo) (x.lo >>> hi), max (x.hi >>> lo) (x.hi >>> hi)⟩, false⟩
    | _, _ => full
  | .floorDiv | .div =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some d =>
      if d.lo ≤ 0 ∨ x.lo < 0 then full else ⟨⟨x.lo / d.hi, x.hi / d.lo⟩, false⟩
    | _, _ => full
  | .floorRem =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some d =>
      if d.lo ≤ 0 then full
      else if x.lo ≥ 0 ∧ x.hi < d.lo then ⟨x, false⟩
      else ⟨⟨0, d.hi - 1⟩, false⟩
    | _, _ => full
  | .rem =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some d =>
      if d.lo ≤ 0 ∨ x.lo < 0 then full else ⟨⟨0, min x.hi (d.hi - 1)⟩, false⟩
    | _, _ => full
  | .bitXor =>
    match c.operand i.operands.a here, c.operand i.operands.b here with
    | some x, some y =>
      if x.lo < 0 ∨ y.lo < 0 then full
      else
        let bits := bitLength (max x.hi y.hi).toNat
        let bound : Int := if bits = 0 then 0 else (2 : Int) ^ bits - 1
        ⟨(Interval.mk 0 bound).meet limits, false⟩
    | _, _ => full
  | .convert =>
    match c.operand i.operands.a here with
    | some x => if i.check == .none ∧ !x.within limits then full else ⟨x.meet limits, false⟩
    | none => full
  | .cmp => ⟨c.compare i here, false⟩
  | .not =>
    match c.operand i.operands.a here with
    | some x => ⟨⟨1 - x.hi, 1 - x.lo⟩, false⟩
    | none => full
  | .listLen =>
    let m : Interval := ⟨0, maxListLength⟩
    ⟨((c.factLen i.operands.a).getD m).meet m, false⟩
  | .strLen | .dictEntries => ⟨⟨0, maxListLength⟩, false⟩
  | .listGet | .arrayGet => ⟨(c.factElems i.operands.a).getD limits, false⟩
  | .call =>
    match i.operands.a with
    | none => full
    | some callee =>
      match c.m.functions[callee]? with
      | none => full
      | some g =>
        match g.boundary.returns with
        | none => full
        | some r => ⟨r.meet limits, false⟩
  | _ => unknown

/-- What the transfer rule of `i` derives at block `here`: the empty interval when an operand it reads is never produced
(the instruction never runs, design change 15). -/
def Ctx.derive (c : Ctx) (i : Inst) (limits : Interval) (here : Nat) : Derived :=
  if c.ruleVacuous i here then ⟨⟨1, 0⟩, false⟩ else c.deriveRule i limits here

/-- F2 for one instruction (also the constants and parameters, at block 0). -/
def Ctx.instOut (c : Ctx) (i : Inst) (here : Nat) : Out :=
  match i.ty.range, i.range with
  | some limits, some stated =>
    if stated.lo == limits.lo && stated.hi == limits.hi then .skip
    else
      let d := c.derive i limits here
      if d.assumed then .assumed
      else if d.range.within stated then .derived
      else if staleAfterFacts i.op then .assumed
      else
        .bad ⟨.f2, if (c.def_ i.value).kind == .pre then none else some here, some i.value⟩
  | _, _ => .skip

/-! ### Counted loops and reductions (design §5.5) -/

/-- A counted loop recognised on the IR. -/
structure Counted where
  counter : Nat
  start : Nat
  bound : Nat
  latchIndex : Nat

/-- The counted loop whose header is block `header`: two predecessors (the entry and the latch), a branch
`counter < bound` into the body, and `counter = phi(start, counter + 1)`. -/
def Ctx.countedAt (c : Ctx) (header : Nat) : Option Counted :=
  c.f.aux.loops.findSome? fun loop =>
    if loop.header != header then none else
    match c.f.blocks[header]? with
    | none => none
    | some blk =>
      if blk.preds.length != 2 then none else
      match blk.term with
      | .branch cond t _ =>
        if t != loop.body then none else
        -- Not in the Zig validator (NOTES.md, finding 2): the body is entered only from the header, and every
        -- path to the latch passes through it, so the bound `counter < n` holds at the latch.
        if !(c.dominates loop.body loop.latch) || !((refining c loop.body).any (·.source == header)) then none else
        let cd := c.def_ cond
        match cd.inst with
        | none => none
        | some cmp =>
          if cd.kind == .phi || cmp.op != .cmp || Pred.ofImm cmp.imm != some Pred.lt then none else
          match cmp.operands.a, cmp.operands.b with
          | some counter, some bound =>
            let counterDef := c.def_ counter
            if counterDef.kind != .phi || counterDef.block != some header then none else
            let latchIndex := if blk.preds[0]? == some loop.latch then 0 else 1
            if blk.preds[latchIndex]? != some loop.latch then none else
            match counterDef.phi with
            | none => none
            | some line =>
              match line.edges[latchIndex]?, line.edges[1 - latchIndex]? with
              | some latchEdge, some entryEdge =>
                let stepDef := c.def_ latchEdge.value
                match stepDef.inst with
                | none => none
                | some step =>
                  if stepDef.kind == .phi || step.op != .add || step.operands.a != some counter then none else
                  match step.operands.b with
                  | none => none
                  | some oneV =>
                    match (c.def_ oneV).inst with
                    | none => none
                    | some one =>
                      if one.op != .iconst || one.imm != 1 then none
                      else some ⟨counter, entryEdge.value, bound, latchIndex⟩
              | _, _ => none
          | _, _ => none
      | _ => none

/-- The interval of a counted loop's counter at its header (design §5.5, Counter). -/
def Ctx.counterBound (c : Ctx) (p : Phi) (here : Nat) : Option Interval :=
  match c.countedAt here with
  | none => none
  | some k =>
    if k.counter != p.value then none else
    match p.ty.range with
    | none => none
    | some limits =>
      let start := (base c k.start).getD limits
      match c.operand (some k.bound) here with
      | none => none
      | some bound => some ⟨start.lo, max start.hi bound.hi⟩

/-- At most this many iterations of the counted loop at `header` complete (design §5.5, Trips). -/
def Ctx.tripBound (c : Ctx) (header : Nat) : Option Int :=
  match c.countedAt header with
  | none => none
  | some k =>
    match c.operand (some k.bound) header with
    | none => none
    | some bound =>
      match (base c k.start) with
      | some start => some (max (bound.hi - start.lo) 0)
      | none =>
        match (c.def_ k.start).ty.range with
        | none => none
        | some r => some (max (bound.hi - r.lo) 0)

/-- How many values one reduction may look through before it gives up. -/
def growthBudget : Nat := 64

/-- The growth of a phi in the header of an inner counted loop: its entry value's growth, plus at most the inner loop's
trips of its own per-iteration growth. `low` computes growth for the nested values. -/
def Ctx.innerGrowth (c : Ctx) (low : Nat → Nat → Nat → Option Interval × Nat)
    (acc phiValue header budget : Nat) : Option Interval × Nat :=
  match c.countedAt header with
  | none => (none, budget)
  | some inner =>
    match (c.def_ phiValue).phi with
    | none => (none, budget)
    | some line =>
      if line.edges.length != 2 then (none, budget) else
      match line.edges[1 - inner.latchIndex]?, line.edges[inner.latchIndex]? with
      | some entryE, some latchE =>
        match low acc entryE.value budget with
        | (none, b1) => (none, b1)
        | (some entry, b1) =>
          match low phiValue latchE.value b1 with
          | (none, b2) => (none, b2)
          | (some step, b2) =>
            match c.tripBound header with
            | none => (none, b2)
            | some trips => (some (grown entry step trips), b2)
      | _, _ => (none, budget)

/-- One level of `growth`: how far value `raw` lies from `acc` in the same iteration, as an interval of `raw - acc`,
or none when `raw` is not `acc` moved by checked additions and subtractions, joins of such values, and inner counted
loops that move it. `low` is the level below, threading the budget. -/
def Ctx.growthStep (c : Ctx) (low : Nat → Nat → Nat → Option Interval × Nat)
    (acc raw budget : Nat) : Option Interval × Nat :=
  if budget == 0 then (none, 0) else
  let budget := budget - 1
  if raw == acc then (some (Interval.point 0), budget) else
  let d := c.def_ raw
  match d.block with
  | none => (none, budget)
  | some where_ =>
    if d.kind == .phi then
      if c.f.aux.loops.any (fun l => l.header == where_) then c.innerGrowth low acc raw where_ budget
      else
        match d.phi with
        | none => (none, budget)
        | some p =>
          let rec joinEdges : List PhiEdge → Option Interval → Nat → Option Interval × Nat
            | [], out, b => (out, b)
            | e :: rest, out, b =>
              if !(edgeLive c e.block where_) then joinEdges rest out b
              else
                match low acc e.value b with
                | (none, b') => (none, b')
                | (some moved, b') => joinEdges rest (some (match out with | none => moved | some so => so.hull moved)) b'
          joinEdges p.edges none budget
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

/-- `growth` with `fuel` levels of nesting (the budget bounds the nesting in practice). -/
def Ctx.growthN (c : Ctx) : Nat → Nat → Nat → Nat → Option Interval × Nat
  | 0 => fun _ _ b => (none, b)
  | fuel + 1 => c.growthStep (c.growthN fuel)

/-- The interval a reduction phi of a counted loop stays in: its entry value moved by at most `trips` steps. -/
def Ctx.reduction (c : Ctx) (p : Phi) (here : Nat) : Option Interval :=
  match c.countedAt here with
  | none => none
  | some k =>
    if k.counter == p.value || p.edges.length != 2 then none else
    match p.edges[k.latchIndex]?, p.edges[1 - k.latchIndex]? with
    | some latchE, some entryE =>
      match (c.growthN (growthBudget + 2) p.value latchE.value growthBudget).1 with
      | none => none
      | some step =>
        match c.operand (some entryE.value) entryE.block with
        | none => none
        | some start =>
          match c.tripBound here with
          | none => none
          | some trips => some (grown start step trips)
    | _, _ => none

/-- One step of the hull of what a phi's live operands are at their predecessors. -/
def phiHullStep (c : Ctx) (here : Nat) (limits : Interval) (acc : Option Interval) (e : PhiEdge) : Option Interval :=
  if !(edgeLive c e.block here) then acc
  else
    let r := (c.operandRaw (some e.value) e.block).getD limits
    if r.isEmpty then acc else some (match acc with | none => r | some so => so.hull r)

/-- The hull of what a phi's live operands are at their predecessors (design §5.3), none when no operand is live. -/
def Ctx.phiHull (c : Ctx) (p : Phi) (here : Nat) (limits : Interval) : Option Interval :=
  p.edges.foldl (phiHullStep c here limits) none

/-- The counter bound `b` of a phi accepts its stated interval: `b` alone is within it, or `b` fits the type
(`b.hi ≤ limits.hi`, so the counter cannot wrap) and its meet with the operand hull `derived` is within it. -/
def counterAccepts (b derived limits stated : Interval) : Bool :=
  b.within stated || (decide (b.hi ≤ limits.hi) && (derived.meet b).within stated)

/-- F3 for one phi: its stated interval contains the hull of the live operands, or the meet of that hull with the counter
or the reduction bound (`validate_facts.zig`, `Checker.loopBound`). -/
def Ctx.phiOut (c : Ctx) (p : Phi) (here : Nat) : Out :=
  match p.range, p.ty.range with
  | some stated, some limits =>
    match c.phiHull p here limits with
    | none => .derived
    | some derived =>
      if derived.within stated then .derived
      else
        match c.counterBound p here with
        | some b => if counterAccepts b derived limits stated then .derived else
            match c.reduction p here with
            | some b' => if (derived.meet b').within stated then .derived else .bad ⟨.f3, some here, some p.value⟩
            | none => .bad ⟨.f3, some here, some p.value⟩
        | none =>
            match c.reduction p here with
            | some b' => if (derived.meet b').within stated then .derived else .bad ⟨.f3, some here, some p.value⟩
            | none => .bad ⟨.f3, some here, some p.value⟩
  | _, _ => .skip

end Facts
