import Facts.Rules

/-!
# The checks F5–F7 and the verdict

List facts, inter-procedural facts, `proven` checks, and the checker as a whole: the validator's `check` in its
order (F5, then F2/F3/F4 over the instructions, the list facts, F6, F7), reporting the first fault.
-/

namespace Facts

/-! ### List facts (design §5.5, A6) -/

/-- What the operation defining a list value derives: whether it knows, its length and its elements. -/
structure Derivation where
  known : Bool := false
  len : Option Interval := none
  elems : Option Interval := none

/-- A scalar operand's view, if it is an integer. -/
def Ctx.scalar (c : Ctx) (v : Option Nat) (here : Nat) : Option Interval :=
  match v with
  | none => none
  | some w => if (c.def_ w).ty.range.isNone then none else c.operand (some w) here

/-- The join of the lists a list phi can take. -/
def Ctx.joinLists (c : Ctx) (p : Phi) (blk : Nat) : Derivation :=
  let live := p.edges.filter fun e => edgeLive c e.block blk
  if live.isEmpty then {} else
  let lengthsKnown := live.all fun e => (c.listFact? e.value).bind (·.len) |>.isSome
  let elemsKnown := live.all fun e => (c.listFact? e.value).bind (·.elems) |>.isSome
  let hullOf (get : ListFact → Option Interval) : Option Interval :=
    live.foldl (fun (acc : Option Interval) e =>
      match (c.listFact? e.value).bind get with
      | none => acc
      | some r => some (match acc with | none => r | some so => so.hull r)) none
  { known := true, len := if lengthsKnown then hullOf (·.len) else none,
    elems := if elemsKnown then hullOf (·.elems) else none }

/-- One step of the element hull of a list built from its operands: the interval of the operand at position `k` joined
to what the earlier ones gave, unknown as soon as one operand is not an integer. -/
def Ctx.hullStep (c : Ctx) (here : Nat) (acc : Option Interval) (p : Option Nat × Nat) : Option Interval :=
  let value := c.scalar p.1 here
  if p.2 == 0 then value
  else
    match acc with
    | some held => match value with | some v => some (held.hull v) | none => none
    | none => none

/-- The length and element intervals the operation defining a list value gives it. -/
def Ctx.deriveList (c : Ctx) (d : Def) (here : Nat) : Derivation :=
  if d.kind == .phi then
    match d.phi, d.block with
    | some p, some blk => c.joinLists p blk
    | _, _ => {}
  else
    match d.inst with
    | none => {}
    | some i =>
      let fact (a : Option Nat) : Option (Option Interval × Option Interval) :=
        match a with
        | none => none
        | some v => some (((c.listFact? v).bind (·.len)), ((c.listFact? v).bind (·.elems)))
      match i.op with
      | .listNew => { known := true, len := some (Interval.point 0) }
      | .listPush =>
        match fact i.operands.a with
        | none => {}
        | some (oldLen, oldElems) =>
          let value := c.scalar i.operands.b here
          let len := oldLen.map fun l => (⟨l.lo + 1, min (l.hi + 1) maxListLength⟩ : Interval)
          let elems₀ : Option Interval :=
            match oldLen with
            | some l => if l.lo == 0 && l.hi == 0 then value else none
            | none => none
          let elems :=
            match elems₀ with
            | some e => some e
            | none =>
              match oldElems with
              | some held => match value with | some v => some (held.hull v) | none => none
              | none => none
          { known := true, len, elems }
      | .listPop =>
        match fact i.operands.a with
        | none => {}
        | some (oldLen, oldElems) =>
          { known := true, elems := oldElems,
            len := oldLen.map fun l => (⟨max (l.lo - 1) 0, max (l.hi - 1) 0⟩ : Interval) }
      | .listCopy | .listViewOf | .borrow =>
        match fact i.operands.a with
        | none => {}
        | some (l, e) => { known := true, len := l, elems := e }
      | .listSet | .arraySet =>
        match fact i.operands.a with
        | none => {}
        | some (l, e) =>
          let value := match i.operands.x with
            | [] => none
            | x0 :: _ => c.scalar x0 here
          { known := true, len := l,
            elems := match e with
              | some held => match value with | some v => some (held.hull v) | none => none
              | none => none }
      | .recordMake =>
        if i.ty != .list then {} else
        { known := true, len := some (Interval.point i.operands.x.length),
          elems := (i.operands.x.zipIdx).foldl (c.hullStep here) none }
      | _ => {}

/-- F2 for one stated component of a list fact: the stated interval contains the interval the defining operation
derives, or the fact is accepted as an assumption. -/
def listOne (known : Bool) (fault : Out) (stated got : Option Interval) : List Out :=
  match stated with
  | none => []
  | some s =>
    if known then
      match got with
      | some found => if found.within s then [Out.derived] else [fault]
      | none => [Out.assumed]
    else [Out.assumed]

/-- The derivation of the fact of the list value defined at `blk` by `d`. -/
def Ctx.listRest (c : Ctx) (fact : ListFact) (d : Def) (blk : Option Nat) : List Out :=
  let here := blk.getD 0
  let derived := c.deriveList d here
  let fault : Out := .bad ⟨.f2, some (d.block.getD noBlock), some fact.value⟩
  listOne derived.known fault fact.len derived.len ++ listOne derived.known fault fact.elems derived.elems

/-- F2 over the list facts: each stated length and element interval contains what the list operation derives. -/
def Ctx.listFactOut (c : Ctx) (fact : ListFact) : List Out :=
  let d := c.def_ fact.value
  match d.block with
  | some b => if !(c.reached[b]?.getD false) then [] else c.listRest fact d (some b)
  | none => c.listRest fact d none

/-! ### F6: inter-procedural facts -/

/-- The first inter-procedural fault of block `here` of the function. -/
def Ctx.interOut (c : Ctx) (blk : Block) (here : Nat) : Option Fault :=
  let calls := blk.insts.findSome? fun i =>
    if i.op != .call then none else
    match i.operands.a with
    | none => none
    | some index =>
      match c.m.functions[index]? with
      | none => none
      | some callee =>
        if !callee.header.internal || callee.header.addressTaken then none else
        (i.operands.x.zipIdx).findSome? fun (arg, k) =>
          match arg with
          | none => none
          | some a =>
            match (callee.boundary.params[k]?).bind id with
            | none => none
            | some claim =>
              match c.operandRaw (some a) here with
              | none => none
              | some seen =>
                if seen.isEmpty then none else
                let passed := reinterpret seen (c.def_ a).ty ((callee.header.params[k]?).getD .other)
                if passed.within claim then none else some ⟨.f6, some here, some i.value⟩
  calls <|>
  match blk.term with
  | .ret (some v) =>
    match c.f.boundary.returns with
    | some claim =>
      if (c.def_ v).ty.range.isSome then
        match c.operandRaw (some v) here with
        | some seen => if seen.isEmpty || seen.within claim then none else some ⟨.f6, some here, some v⟩
        | none => none
      else none
    | none => none
  | _ => none

/-! ### F7: proven checks -/

/-- The viewed operand intervals the check of `i` reads, as the checker derives them (design §10, Sites). -/
def Ctx.derivedParts (c : Ctx) (i : Inst) (here : Nat) : Option Interval × Option Interval :=
  match i.op with
  | .add | .sub | .mul | .div | .rem | .floorDiv | .floorRem =>
    (c.operand i.operands.a here, c.operand i.operands.b here)
  | .neg | .convert => (c.operand i.operands.a here, none)
  | .shiftLeft | .shiftRight | .arrayGet | .arraySet => (c.operand i.operands.b here, none)
  | .listGet | .listGetField | .listSet =>
    (c.operand i.operands.b here,
      match i.operands.a with
      | some a => (c.listFact? (c.liveList c.count a)).bind (·.len)
      | none => none)
  | .listPop =>
    (match i.operands.a with
      | some a => (c.listFact? (c.liveList c.count a)).bind (·.len)
      | none => none, none)
  | _ => (none, none)

/-- The interval a `proven` check is asked about when its site states none: wider than any 64-bit value. -/
def wideIv : Interval := ⟨-(2 : Int) ^ 65, (2 : Int) ^ 65⟩

/-- The range of a value of a type that has none. -/
def anyIv : Interval := ⟨-(2 : Int) ^ 63, (2 : Int) ^ 64 - 1⟩

/-- Whether the row of `i`'s operation (design §4, last column) rules out its failure for the site `parts`; none for
an operation without a row. An interval the site does not state is the widest the row could be asked about. -/
def rowHolds (i : Inst) (p0 p1 : Option Interval) : Option Bool :=
  let limits : Interval := i.ty.range.getD anyIv
  let first := p0.getD wideIv
  let second := p1.getD wideIv
  match i.op with
  | .add | .sub | .mul =>
    some ((arithmetic i.op first second).within limits && (decide (limits.lo < 0) || (decide (first.lo ≥ 0) && decide (second.lo ≥ 0))))
  | .shiftLeft | .shiftRight => some (decide (first.lo ≥ 0) && decide (first.hi < (i.ty.bits : Int)))
  | .div | .floorDiv | .rem | .floorRem => some (decide (first.lo ≥ 0) && decide (second.lo > 0))
  | .neg => some (if limits.lo == 0 then (first.lo == 0 && first.hi == 0) else decide (first.lo > limits.lo))
  | .convert => some (first.within limits)
  | .arrayGet | .arraySet => some (decide (first.lo ≥ 0) && decide (first.hi < (i.aux : Int)))
  | .listGet | .listGetField | .listSet => some (p1.isSome && decide (first.lo ≥ 0) && decide (first.hi < second.lo))
  | .listPop => some (p0.isSome && decide (first.lo ≥ 1))
  | _ => none

/-- The reason numbers of `Out.unchecked`. -/
def reasonListBound : Nat := 0
def reasonListFill : Nat := 1
def reasonListKeys : Nat := 2
def reasonFloat : Nat := 3
def reasonEdgeChecked : Nat := 4
def reasonOtherOp : Nat := 5

/-- The site of a value (the last one stated), if any. -/
def Ctx.site? (c : Ctx) (v : Nat) : Option Site :=
  (c.f.aux.sites.filter (·.value == v)).getLast?

/-- Whether the viewed interval `actual` lies within the interval `claim` a site states (no claim is always met). -/
def provenCheck (claim actual : Option Interval) : Bool :=
  match claim with
  | none => true
  | some part => match actual with
    | none => false
    | some known => known.within part

/-- Whether the check of `i` reads an operand that is never produced: it never runs. The parts are read in the order of
`derivedParts`, none of them stopping the others. -/
def Ctx.partsVacuous (c : Ctx) (i : Inst) (here : Nat) : Bool :=
  match i.op with
  | .add | .sub | .mul | .div | .rem | .floorDiv | .floorRem =>
    c.emptyView i.operands.a here || c.emptyView i.operands.b here
  | .neg | .convert => c.emptyView i.operands.a here
  | .shiftLeft | .shiftRight | .arrayGet | .arraySet | .listGet | .listGetField | .listSet =>
    c.emptyView i.operands.b here
  | _ => false

/-- Whether two values are the same: one value, or two reads of the same field of the same record. -/
def Ctx.sameValue (c : Ctx) (x y : Nat) : Bool :=
  x == y ||
    match (c.def_ x).inst, (c.def_ y).inst with
    | some l, some r =>
      l.op == .recordGet && r.op == .recordGet && l.imm == r.imm &&
        (match l.operands.a, r.operands.a with | some p, some q => p == q | _, _ => false)
    | _, _ => false

/-- What an earlier checked operation has to look like: the operation, the constant, the base value and the field. -/
structure Earlier where
  op : Op
  amount : Int
  base : Nat
  field : Option Nat

/-- Whether instruction `earlier` is a checked `wanted` (other than `except`). -/
def Ctx.matchesEarlier (c : Ctx) (wanted : Earlier) (except : Nat) (earlier : Inst) : Bool :=
  if earlier.value == except || earlier.op != wanted.op || earlier.ty != .i64 || earlier.check == .none then false
  else
    match earlier.operands.b with
    | none => false
    | some bv =>
      let other := c.def_ bv
      match other.inst with
      | none => false
      | some oi =>
        if other.kind == .missing || oi.op != .iconst || constantOf other != wanted.amount then false
        else
          match earlier.operands.a with
          | none => false
          | some operandA =>
            match wanted.field with
            | some field =>
              match (c.def_ operandA).inst with
              | none => false
              | some read =>
                read.op == .recordGet && read.imm == field &&
                  (match read.operands.a with | some r => r == wanted.base | none => false)
            | none => c.sameValue operandA wanted.base

/-- Whether block `from_`, or a block that dominates it, holds a checked `wanted` other than `except` (walking the
dominator tree with `fuel` steps). -/
def Ctx.checkedBefore (c : Ctx) (wanted : Earlier) (except : Nat) : Nat → Nat → Bool
  | 0, _ => false
  | fuel + 1, at_ =>
    let here := match c.f.blocks[at_]? with
      | some b => b.insts.any (c.matchesEarlier wanted except)
      | none => false
    here || (match c.parent? at_ with
      | some d => c.checkedBefore wanted except fuel d
      | none => false)

/-- Whether a `proven` signed constant addition or subtraction has the shape the edge induction of `overflow_edges.zig`
proves: its left operand is a phi (or the read of a field of a record phi) of a block `H` that dominates it, and on the
path into each edge of `H` the same operation with the same constant is checked on the value the phi takes from that
edge (design change 16). It is counted, not validated. -/
def Ctx.edgeChecked (c : Ctx) (i : Inst) (here : Nat) : Bool :=
  if i.ty != .i64 then false else
  match i.operands.b, i.operands.a with
  | some bv, some av =>
    let right := c.def_ bv
    match right.inst with
    | none => false
    | some ri =>
      if right.kind == .missing || ri.op != .iconst then false else
      let amount := constantOf right
      let left := c.def_ av
      let field : Option Nat :=
        match left.inst with
        | some li => if left.kind == .inst && li.op == .recordGet then some li.imm else none
        | none => none
      let source : Option Def :=
        match field, left.inst with
        | some _, some li => (li.operands.a).map c.def_
        | _, _ => some left
      match source with
      | none => false
      | some src =>
        if src.kind != .phi then false else
        match src.block, src.phi with
        | some header, some line =>
          if !(c.dominates header here) then false else
          match c.f.blocks[header]? with
          | none => false
          | some hb =>
            if hb.preds.isEmpty then false else
            line.edges.all fun e =>
              c.checkedBefore ⟨i.op, amount, e.value, field⟩ i.value (c.count + 1) e.block
        | _, _ => false
  | _, _ => false

/-- F7 for one `proven` instruction. -/
def Ctx.provenOut (c : Ctx) (i : Inst) (here : Nat) : Out :=
  let fault : Out := .bad ⟨.f7, some here, some i.value⟩
  if !hasRow i.op then
    .unchecked (if i.op == .floatToInt then reasonFloat else reasonOtherOp)
  else
    match c.site? i.value with
    | none => fault
    | some site =>
      if c.partsVacuous i here then .proven else
      let (d0, d1) := c.derivedParts i here
      let claim0 : Option Interval := (site.parts[0]?).bind id
      let claim1 : Option Interval := (site.parts[1]?).bind id
      if !(provenCheck claim0 d0 && provenCheck claim1 d1) then fault
      else if (rowHolds i claim0 claim1).getD false then .proven
      else
        match i.op with
        | .listGet | .listGetField | .listSet =>
          match i.operands.a with
          | none => .unchecked reasonOtherOp
          | some a =>
            let list := c.liveList c.count a
            let hasBound := match i.operands.b with
              | some v => c.f.aux.bounds.any fun b => b.value == v && b.list == list
              | none => false
            if hasBound then .unchecked reasonListBound
            else if ((c.listFact? list).bind (·.length)).isSome then .unchecked reasonListFill
            else .unchecked reasonListKeys
        | .add | .sub => if c.edgeChecked i here then .unchecked reasonEdgeChecked else fault
        | _ => fault

/-! ### The verdict -/

/-- Statistics of an accepted function: what it derived, assumed, proved, and left unchecked. -/
structure Stats where
  derived : Nat := 0
  assumed : Nat := 0
  proven : Nat := 0
  unchecked : List Nat := [0, 0, 0, 0, 0, 0]
  deriving Repr

/-- Add the statistics of one outcome. -/
def Stats.add (s : Stats) : Out → Stats
  | .derived => { s with derived := s.derived + 1 }
  | .assumed => { s with assumed := s.assumed + 1 }
  | .proven => { s with proven := s.proven + 1 }
  | .unchecked r => { s with unchecked := s.unchecked.mapIdx fun k n => if k == r then n + 1 else n }
  | _ => s

/-- A function's verdict. -/
inductive Verdict where
  | accepted (s : Stats)
  | rejected (f : Fault)
  deriving Repr

/-- The outcomes of F2/F3/F4 in the validator's order: the constants and parameters, then each reached block's phis
and instructions. -/
def Ctx.intervalOuts (c : Ctx) : List Out :=
  (c.f.pre.map fun i => c.instOut i 0) ++
  (List.range c.count).flatMap fun pos =>
    if !(c.reached[pos]?.getD false) then [] else
    let b := c.f.blocks[pos]!
    (b.phis.map fun p => c.phiOut p pos) ++ (b.insts.map fun i => c.instOut i pos)

/-- The outcomes of the list facts. -/
def Ctx.listOuts (c : Ctx) : List Out := c.f.aux.lists.flatMap c.listFactOut

/-- F5: a block stated dead is reached by no execution. -/
def Ctx.deadFault (c : Ctx) : Option Fault :=
  (List.range c.count).findSome? fun pos =>
    let b := c.f.blocks[pos]!
    if !b.dead then none
    else if c.reached[pos]?.getD false then some ⟨.f5, some pos, none⟩
    else b.preds.findSome? fun pred => if edgeLive c pred pos then some ⟨.f5, some pos, none⟩ else none

/-- F6 over every reached block. -/
def Ctx.interFault (c : Ctx) : Option Fault :=
  (List.range c.count).findSome? fun pos =>
    if !(c.reached[pos]?.getD false) then none else c.interOut c.f.blocks[pos]! pos

/-- The outcomes of F7 over every reached block. -/
def Ctx.provenOuts (c : Ctx) : List Out :=
  (List.range c.count).flatMap fun pos =>
    if !(c.reached[pos]?.getD false) then [] else
    (c.f.blocks[pos]!.insts.filter (·.check == .proven)).map fun i => c.provenOut i pos

/-- Build the context of a function: shape, dominators, reachability (F1 and the verified structure). -/
def prepare (m : Module) (f : Function) : Except Fault Ctx := do
  let (n, defs, lists, caps) ← shape f
  if !structOK f n defs lists then throw ⟨.f1, none, none⟩
  if !constsOK f then throw ⟨.f1, none, none⟩
  let idom := computeIdom f
  let depth := computeDepth idom
  if !domOK f idom depth then throw ⟨.f1, none, none⟩
  let c0 : Ctx := { m, f, n, defs, lists, caps, idom, depth, reached := #[] }
  let reached := computeReached c0
  let c : Ctx := { c0 with reached }
  if !reachOK c then throw ⟨.f1, none, none⟩
  return c

/-- The first fault of the checks after `prepare`, in the validator's order. -/
def Ctx.firstFault (c : Ctx) : Option Fault :=
  c.deadFault <|>
  (c.intervalOuts.findSome? Out.fault?) <|>
  (c.listOuts.findSome? Out.fault?) <|>
  c.interFault <|>
  (c.provenOuts.findSome? Out.fault?)

/-- The statistics of an accepted function. -/
def Ctx.stats (c : Ctx) : Stats :=
  (c.intervalOuts ++ c.listOuts ++ c.provenOuts).foldl Stats.add {}

/-- Check one function of a module. -/
def checkFunction (m : Module) (f : Function) : Verdict :=
  match prepare m f with
  | .error fl => .rejected fl
  | .ok c =>
    match c.firstFault with
    | some fl => .rejected fl
    | none => .accepted c.stats

/-- Check every function of a module. -/
def checkModule (m : Module) : List Verdict := m.functions.toList.map (checkFunction m)

end Facts
