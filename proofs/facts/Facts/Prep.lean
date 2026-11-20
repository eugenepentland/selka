import Facts.Types

/-!
# What the checker prepares: shape, dominators, reachability

The first three steps of `src/core/validate_facts.zig` (`prepare`): the shape checks F1, the
dominator tree, and the blocks some execution can reach.

The dominator tree and the reached set are *computed* by untrusted code (`partial` definitions,
the same algorithms as the validator's) and then *verified* by total checks. The theorem relies on
the verified properties only (`Prep.DomOK`, `Prep.ReachOK`); a wrong computation can make the
checker reject, never accept something unsound. The verification is extra to the Zig validator
and holds for any correct computation of the same tree and set.
-/

namespace Facts

/-- The checks of design §6. -/
inductive CheckId where
  | f1 | f2 | f3 | f4 | f5 | f6 | f7
  deriving DecidableEq, Repr, Inhabited

/-- `F1` … `F7`. -/
def CheckId.label : CheckId → String
  | .f1 => "F1" | .f2 => "F2" | .f3 => "F3" | .f4 => "F4" | .f5 => "F5" | .f6 => "F6" | .f7 => "F7"

/-- The first fault of a certificate: the check, the block and the value it names. -/
structure Fault where
  check : CheckId
  block : Option Nat := none
  value : Option Nat := none
  deriving DecidableEq, Repr, Inhabited

/-- What the checker knows of a value. -/
inductive Kind where
  | missing | pre | phi | inst
  deriving DecidableEq, Repr, Inhabited

/-- The definition of a value. `block` is the position of the defining block (none for constants and
parameters). -/
structure Def where
  kind : Kind := .missing
  block : Option Nat := none
  /-- The position among the constants and parameters, the block's phis, or the block's instructions. -/
  index : Nat := 0
  ty : Ty := .other
  stated : Option Interval := none
  inst : Option Inst := none
  phi : Option Phi := none
  deriving Repr, Inhabited, DecidableEq

/-- The definition recorded for the `k`-th constant or parameter. -/
def preDef (i : Inst) (k : Nat) : Def :=
  { kind := .pre, block := none, index := k, ty := i.ty, stated := i.range, inst := some i }

/-- The definition recorded for the `k`-th phi of block `pos`. -/
def phiDef (pos k : Nat) (p : Phi) : Def :=
  { kind := .phi, block := some pos, index := k, ty := p.ty, stated := p.range, phi := some p }

/-- The definition recorded for the `k`-th instruction of block `pos`. -/
def instDef (pos k : Nat) (i : Inst) : Def :=
  { kind := .inst, block := some pos, index := k, ty := i.ty, stated := i.range, inst := some i }

/-- A fill cap (design §5.2): `value <= M` in every block `block` dominates. -/
structure Cap where
  block : Nat
  value : Nat
  deriving Repr

/-- The successors of a block, in terminator order. -/
def successors : Term → List Nat
  | .jump t => [t]
  | .branch _ t e => [t, e]
  | _ => []

/-- The immediate-dominator array uses this for "none". -/
def noBlock : Nat := 4294967295

/-- The facts the checker prepares for one function. -/
structure Prep where
  n : Nat
  defs : Array Def
  lists : Array (Option ListFact)
  caps : List Cap
  idom : Array Nat
  depth : Array Nat
  reached : Array Bool

/-! ### F1: shape -/

/-- Scan one instruction for the largest value it names. -/
def scanInst (m : Nat) (i : Inst) : Nat :=
  let m := max m i.value
  let m := match i.operands.a with
    | some a => if i.op = .call then m else max m a
    | none => m
  let m := match i.operands.b with
    | some b => max m b
    | none => m
  i.operands.x.foldl (fun acc x => match x with | some v => max acc v | none => acc) m

/-- The largest value named anywhere in the function (the validator's `max_value`). -/
def maxValue (f : Function) : Nat :=
  let m := f.pre.foldl scanInst 0
  let m := f.blocks.foldl (fun m b =>
    let m := b.phis.foldl (fun m p => p.edges.foldl (fun m e => max m e.value) (max m p.value)) m
    let m := b.insts.foldl scanInst m
    match b.term with
    | .branch c _ _ => max m c
    | .ret (some v) => max m v
    | _ => m) m
  f.aux.lists.foldl (fun m l => max m l.value) m

/-- Define a value (F1): once, in range, with a range that is non-empty, inside the type, on an integer. -/
def define (n : Nat) (defs : Array Def) (v : Nat) (d : Def) : Except Fault (Array Def) :=
  if v ≥ n then .error ⟨.f1, none, some v⟩
  else if (defs[v]?.map (·.kind)) != some Kind.missing then .error ⟨.f1, none, some v⟩
  else
    match d.stated with
    | some r =>
      match d.ty.range with
      | none => .error ⟨.f1, none, some v⟩
      | some limits =>
        if !(r.within limits) then .error ⟨.f1, none, some v⟩
        else .ok (defs.set! v d)
    | none => .ok (defs.set! v d)

/-- The terminator targets exist, and the stated predecessors are exactly the blocks that jump here. -/
def edgesFault (f : Function) : Option Fault :=
  let count := f.blocks.size
  -- the sources of each block, by source position
  let seen : Array (List Nat) := Id.run do
    let mut s : Array (List Nat) := Array.replicate count []
    for pos in [0:count] do
      for t in successors f.blocks[pos]!.term do
        if t < count then s := s.set! t (s[t]! ++ [pos])
    return s
  let bad1 := (List.range count).findSome? fun pos =>
    (successors f.blocks[pos]!.term).findSome? fun t =>
      if t ≥ count then some (⟨.f1, some pos, none⟩ : Fault) else none
  bad1 <|> (List.range count).findSome? fun pos =>
    let b := f.blocks[pos]!
    (b.preds.findSome? fun pred =>
      if pred ≥ count then some (⟨.f1, some pos, none⟩ : Fault)
      else if !(seen[pos]!.contains pred) then some ⟨.f1, some pos, none⟩ else none)
    <|> (seen[pos]!.findSome? fun from_ =>
      if !(b.preds.contains from_) then some (⟨.f1, some pos, none⟩ : Fault) else none)

/-- The shape of a function (F1, and the entry block stated dead, F5): the definitions and the list facts. -/
def shape (f : Function) : Except Fault (Nat × Array Def × Array (Option ListFact) × List Cap) := do
  let n := maxValue f + 1
  let mut defs : Array Def := Array.replicate n {}
  for (i, k) in f.pre.zipIdx do
    defs ← define n defs i.value (preDef i k)
  let count := f.blocks.size
  for pos in [0:count] do
    if f.blocks[pos]!.id != pos then throw ⟨.f1, some f.blocks[pos]!.id, none⟩
  for pos in [0:count] do
    let b := f.blocks[pos]!
    for (p, k) in b.phis.zipIdx do
      if p.edges.length != b.preds.length then throw ⟨.f1, some pos, some p.value⟩
      if (p.edges.zip b.preds).any (fun (e, pr) => e.block != pr) then throw ⟨.f1, some pos, some p.value⟩
      defs ← define n defs p.value (phiDef pos k p)
    for (i, k) in b.insts.zipIdx do
      defs ← define n defs i.value (instDef pos k i)
  match edgesFault f with
  | some fl => throw fl
  | none => pure ()
  -- Not in the Zig validator (see NOTES.md, finding 1): the entry block has no predecessor, since an
  -- edge into block 0 would refine a value on the function's first entry, which no edge reaches.
  if count != 0 && !f.blocks[0]!.preds.isEmpty then throw ⟨.f1, some 0, none⟩
  let mut lists : Array (Option ListFact) := Array.replicate n none
  for l in f.aux.lists do
    if (defs[l.value]?.map (·.kind)) == some Kind.missing || l.value ≥ n then throw ⟨.f1, none, some l.value⟩
    if lists[l.value]!.isSome then throw ⟨.f1, none, some l.value⟩
    lists := lists.set! l.value (some l)
  if count != 0 && f.blocks[0]!.dead then throw ⟨.f5, some 0, none⟩
  for pos in [0:count] do
    let b := f.blocks[pos]!
    for p in b.phis do
      for e in p.edges do
        if (defs[e.value]?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, some p.value⟩
    for i in b.insts do
      match i.operands.a with
      | some a => if i.op != .call && (defs[a]?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, some i.value⟩
      | none => pure ()
      match i.operands.b with
      | some b' => if (defs[b']?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, some i.value⟩
      | none => pure ()
      for x in i.operands.x do
        match x with
        | some xv => if (defs[xv]?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, some i.value⟩
        | none => pure ()
    match b.term with
    | .branch c _ _ => if (defs[c]?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, none⟩
    | .ret (some v) => if (defs[v]?.map (·.kind)) == some Kind.missing then throw ⟨.f1, some pos, none⟩
    | _ => pure ()
  let mut caps : List Cap := []
  for loop in f.aux.loops do
    if loop.header ≥ count || loop.exit ≥ count then throw ⟨.f1, none, none⟩
    for p in f.blocks[loop.header]!.phis do
      match lists[p.value]! with
      | some fact =>
        if fact.pattern then
          match fact.length with
          | some len => caps := caps ++ [⟨loop.exit, len⟩]
          | none => pure ()
      | none => pure ()
  return (n, defs, lists, caps)

/-! ### Dominators

The validator's algorithm (Cooper, Harvey and Kennedy) is ported as untrusted code; `domOK`
verifies the tree it returns. -/

/-- The reverse postorder of the blocks reachable from the entry by terminator edges. -/
partial def reversePostorder (f : Function) : Array Nat := Id.run do
  let count := f.blocks.size
  if count == 0 then return #[]
  let mut visited : Array Bool := Array.replicate count false
  let mut post : Array Nat := #[]
  -- stack of (block, next successor index)
  let mut stack : Array (Nat × Nat) := #[(0, 0)]
  visited := visited.set! 0 true
  while !stack.isEmpty do
    let (b, k) := stack.back!
    let targets := successors f.blocks[b]!.term
    if k < targets.length then
      stack := stack.pop.push (b, k + 1)
      let next := targets[k]!
      if next < count && !visited[next]! then
        visited := visited.set! next true
        stack := stack.push (next, 0)
    else
      post := post.push b
      stack := stack.pop
  return post.reverse

/-- The immediate dominators: `noBlock` for a block no path reaches; the entry is its own. -/
partial def computeIdom (f : Function) : Array Nat := Id.run do
  let count := f.blocks.size
  let mut idom : Array Nat := Array.replicate count noBlock
  if count == 0 then return idom
  let rpo := reversePostorder f
  let mut order : Array Nat := Array.replicate count noBlock
  for i in [0:rpo.size] do
    order := order.set! rpo[i]! i
  idom := idom.set! 0 0
  let mut changed := true
  while changed do
    changed := false
    for i in [1:rpo.size] do
      let b := rpo[i]!
      let mut chosen := noBlock
      for pred in f.blocks[b]!.preds do
        if pred < count && idom[pred]! != noBlock then
          if chosen == noBlock then chosen := pred
          else
            let mut x := pred
            let mut y := chosen
            while x != y do
              while order[x]! > order[y]! do x := idom[x]!
              while order[y]! > order[x]! do y := idom[y]!
            chosen := x
      if chosen != noBlock && idom[b]! != chosen then
        idom := idom.set! b chosen
        changed := true
  return idom

/-- The depth of each block in the tree (0 for the entry and for blocks without a parent). -/
partial def computeDepth (idom : Array Nat) : Array Nat := Id.run do
  let count := idom.size
  let mut depth : Array Nat := Array.replicate count 0
  for b in [0:count] do
    let mut x := b
    let mut d := 0
    let mut steps := 0
    while x != 0 && idom[x]! != noBlock && steps ≤ count do
      x := idom[x]!
      d := d + 1
      steps := steps + 1
    depth := depth.set! b d
  return depth

/-- The parent of a block in the verified tree (none for the entry and for a block no path reaches). -/
def parentOf (idom : Array Nat) (x : Nat) : Option Nat :=
  if x == 0 then none
  else
    let d := idom[x]?.getD noBlock
    if d == noBlock then none else some d

/-- Whether `a` is `x` or one of its ancestors: walk up from `x` at most `fuel` steps (the validator's `dominates`). -/
def walkUp (idom : Array Nat) (a : Nat) : Nat → Nat → Bool
  | 0, x => x == a
  | fuel + 1, x => x == a || (match parentOf idom x with
      | none => false
      | some d => walkUp idom a fuel d)

/-- The verified properties of the tree: the entry is the root; a block with a parent has depth one more
than its parent's; every block a reachable block can jump to has a parent; and the parent of a block
is an ancestor of each predecessor that has one (the property of a dominator tree the soundness proof
uses). -/
def domOK (f : Function) (idom depth : Array Nat) : Bool :=
  let count := f.blocks.size
  decide (idom.size = count) && decide (depth.size = count) &&
  (count == 0 || (decide (idom[0]? = some 0) && decide (depth[0]? = some 0) &&
  (List.range count).all fun b =>
    (b == 0 || idom[b]! == noBlock ||
      (decide (idom[b]! < count) && decide (idom[idom[b]!]! != noBlock) &&
       decide (depth[b]! = depth[idom[b]!]! + 1))) &&
    (idom[b]! == noBlock ||
      ((successors f.blocks[b]!.term).all fun s => decide (s < count) && decide (idom[s]! != noBlock))) &&
    (b == 0 || idom[b]! == noBlock ||
      (f.blocks[b]!.preds.all fun p =>
        decide (p ≥ count) || idom[p]! == noBlock || walkUp idom idom[b]! (count + 1) p))))

/-! ### Verifying what `shape` recorded

`shape` is imperative code; the soundness proof does not reason about it. It reads what the checks below say
instead, each a total function of the function and of what `shape` returned. A shape that is wrong makes the checker
reject; it cannot make it accept something unsound. -/

/-- A recorded definition names the item at its position: the constant or parameter, phi or instruction that defines
value `v`. -/
def defItemOK (f : Function) (v : Nat) (d : Def) : Bool :=
  match d.kind with
  | .missing => decide (d = {})
  | .pre =>
    match d.inst with
    | some i => decide (f.pre[d.index]? = some i) && decide (i.value = v) && decide (d.block = none)
    | none => false
  | .phi =>
    match d.block, d.phi with
    | some pos, some p =>
      match f.blocks[pos]? with
      | some b => decide (b.phis[d.index]? = some p) && decide (p.value = v)
      | none => false
    | _, _ => false
  | .inst =>
    match d.block, d.inst with
    | some pos, some i =>
      match f.blocks[pos]? with
      | some b => decide (b.insts[d.index]? = some i) && decide (i.value = v)
      | none => false
    | _, _ => false

/-- Every constant, parameter, phi and instruction is recorded as its own definition, at its own position, and every
recorded definition is one of them. -/
def defsOK (f : Function) (n : Nat) (defs : Array Def) : Bool :=
  decide (defs.size = n) &&
  f.pre.zipIdx.all (fun (i, k) => decide (defs[i.value]? = some (preDef i k))) &&
  (List.range f.blocks.size).all (fun pos =>
    (f.blocks[pos]!.phis.zipIdx.all fun (p, k) => decide (defs[p.value]? = some (phiDef pos k p))) &&
    (f.blocks[pos]!.insts.zipIdx.all fun (i, k) => decide (defs[i.value]? = some (instDef pos k i)))) &&
  (List.range defs.size).all fun v => defItemOK f v defs[v]!

/-- The predecessor lists are exactly the blocks whose terminators name the block. -/
def edgesOK (f : Function) : Bool :=
  let count := f.blocks.size
  (List.range count).all fun pos =>
    ((successors f.blocks[pos]!.term).all fun t => decide (t < count) && decide (pos ∈ f.blocks[t]!.preds)) &&
    (f.blocks[pos]!.preds.all fun p => decide (p < count) && decide (pos ∈ successors f.blocks[p]!.term))

/-- Each phi has one operand per predecessor, in the predecessors' order. -/
def phisOK (f : Function) : Bool :=
  (List.range f.blocks.size).all fun pos =>
    f.blocks[pos]!.phis.all fun p => decide (p.edges.map (·.block) = f.blocks[pos]!.preds)

/-- The entry block has no predecessor and no phi. -/
def entryOK (f : Function) : Bool :=
  f.blocks.size == 0 || (f.blocks[0]!.preds.isEmpty && f.blocks[0]!.phis.isEmpty)

/-- The constants and parameters are constants, parameters, or operations whose result is not derived. -/
def preOK (f : Function) : Bool :=
  f.pre.all fun i =>
    (i.op == .iconst || i.op == .param || i.op.isFree) && i.operands.a.isNone && i.operands.b.isNone &&
      i.operands.x.isEmpty

/-- A `param` instruction has the type of the parameter it reads. -/
def paramsOK (f : Function) : Bool :=
  let ok (i : Inst) : Bool := i.op != .param || decide (f.header.params[i.imm]? = some i.ty)
  f.pre.all ok && (List.range f.blocks.size).all fun pos => f.blocks[pos]!.insts.all ok

/-- The operands of integer arithmetic have the instruction's type, and the operands of a phi the phi's (the IR
verifier's signature check, read off the certificate). -/
def typedOK (f : Function) (defs : Array Def) : Bool :=
  let ty (v : Option Nat) : Option Ty := v.bind fun w => defs[w]?.map (·.ty)
  (List.range f.blocks.size).all fun pos =>
    (f.blocks[pos]!.insts.all fun i =>
      match i.op with
      | .add | .sub | .mul | .saturatingAdd | .floorDiv | .div | .floorRem | .rem | .bitXor =>
        ty i.operands.a == some i.ty && ty i.operands.b == some i.ty
      | .neg | .shiftLeft | .shiftRight => ty i.operands.a == some i.ty
      | _ => true) &&
    (f.blocks[pos]!.phis.all fun p => p.edges.all fun e => ty (some e.value) == some p.ty)

/-- A stated interval lies within the type's range (an empty one says the value is never produced) and is stated only
of an integer (F1, read off the recorded definitions). -/
def statedOK (defs : Array Def) : Bool :=
  (List.range defs.size).all fun v =>
    match defs[v]!.stated with
    | none => true
    | some r =>
      match defs[v]!.ty.range with
      | some lim => r.within lim
      | none => false

/-- A constant fits its type (F1; a type with no interval has nothing to fit). -/
def constsOK (f : Function) : Bool :=
  let ok (i : Inst) : Bool :=
    i.op != .iconst ||
      match i.ty.range with
      | none => true
      | some lim =>
        let value : Int :=
          if i.ty == .bool then (if i.imm != 0 then 1 else 0)
          else if i.ty == .u64 then (i.imm : Int)
          else if i.imm ≥ 2 ^ 63 then (i.imm : Int) - 2 ^ 64 else (i.imm : Int)
        decide (lim.lo ≤ value) && decide (value ≤ lim.hi)
  f.pre.all ok && (List.range f.blocks.size).all fun pos => f.blocks[pos]!.insts.all ok

/-- The list facts the checker indexed are exactly the stated ones. -/
def listsOK (f : Function) (lists : Array (Option ListFact)) : Bool :=
  (List.range lists.size).all (fun v =>
    match lists[v]! with
    | some fact => decide (fact.value = v) && decide (fact ∈ f.aux.lists)
    | none => true) &&
  f.aux.lists.all fun fact => decide (lists[fact.value]? = some (some fact))

/-- Everything `shape` recorded, verified. -/
def structOK (f : Function) (n : Nat) (defs : Array Def) (lists : Array (Option ListFact)) : Bool :=
  defsOK f n defs && edgesOK f && phisOK f && entryOK f && listsOK f lists && preOK f && paramsOK f && typedOK f defs && statedOK defs

end Facts
