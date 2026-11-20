import VerifyIr.Rules

/-!
# The checker

`checkTypes` (the module's compound table), `checkHeader` (one declaration) and `checkFunction` (one body) give the
verdicts `selka verify-ir` prints. A rejection names the first rule a function breaks, in the order the Zig verifier
looks (`src/core/verify_ir.zig`: structure, then function references, then each listed instruction's signature, copy
rule and dominance), with the block and instruction it names.

The dominator tree is computed as the Zig verifier computes it (Cooper, Harvey and Kennedy, over the predecessors of
reachable blocks) and then *verified* (`treeOK`): the entry is the root, each reachable block's parent is reachable
and one level up, and each block's parent is an ancestor of each of its reachable predecessors. A wrong computation can
only make the checker reject (`dom-tree`, which the Zig verifier has no counterpart of and a correct computation never
gives); the dominance a rule reads is ancestry in the verified tree.
-/

namespace VerifyIr

/-- The rules, by the names both checkers print. -/
inductive Rule where
  | typeTable | equality | viewStorage | markerProvider | markerBorrowed | markerSelection
  | paramType | resultType | borrowContract
  | noBlocks | entryPreds | target | emptyBlock | listedRange | listedTwice | terminator | phiOrder | phiArity | edgePreds | predEdge
  | typeValid | extraRange | unusedOperand | operandRange | operandType | viewDef | unionTag | viewUse | insertProbe | signature | borrowResult | shallowCopy
  | domMissing | domRange | domForward | domUndefined | domOrder | domBlock
  /- Lean only: a verified result that failed (never expected), the SSA rule on the certificate's form (`Ssa.lean`), and
  the verified tag facts of the union-tag rule (`TagProof.lean`). -/
  | domTree | ssa | typed | tagFacts
  deriving DecidableEq, Repr, Inhabited

def Rule.label : Rule → String
  | .typeTable => "type-table" | .equality => "equality" | .viewStorage => "view-storage" | .markerProvider => "marker-provider"
  | .markerBorrowed => "marker-borrowed" | .markerSelection => "marker-selection" | .paramType => "param-type"
  | .resultType => "result-type" | .borrowContract => "borrow-contract" | .noBlocks => "no-blocks" | .entryPreds => "entry-preds"
  | .target => "target" | .emptyBlock => "empty-block" | .listedRange => "listed-range"
  | .listedTwice => "listed-twice" | .terminator => "terminator" | .phiOrder => "phi-order"
  | .phiArity => "phi-arity" | .edgePreds => "edge-preds" | .predEdge => "pred-edge" | .typeValid => "type-valid"
  | .extraRange => "extra-range" | .unusedOperand => "unused-operand" | .unionTag => "union-tag" | .operandRange => "operand-range" | .operandType => "operand-type" | .viewDef => "view-def" | .viewUse => "view-use"
  | .insertProbe => "insert-probe" | .signature => "signature" | .borrowResult => "borrow-result"
  | .shallowCopy => "shallow-copy" | .domMissing => "dom-missing" | .domRange => "dom-range"
  | .domForward => "dom-forward" | .domUndefined => "dom-undefined" | .domOrder => "dom-order"
  | .domBlock => "dom-block" | .domTree => "dom-tree" | .ssa => "ssa-skeleton" | .typed => "typed"
  | .tagFacts => "tag-facts"

/-- The first problem found: the rule, and the block and instruction it names. -/
structure Failure where
  rule : Rule
  block : Option Nat := none
  inst : Option Nat := none
  deriving Repr, Inhabited

abbrev Check := Except Failure

def reject {α : Type} (rule : Rule) (block : Option Nat := none) (inst : Option Nat := none) : Check α :=
  throw ⟨rule, block, inst⟩


/-! ## The module's types and the declarations -/

namespace Module
variable (m : Module)

/-- A read-only parameter type: a view, an overlay, or a two-case union of read-only and unmanaged cases. -/
def readOnlyParamF : Nat → Ty → Bool
  | 0, _ => false
  | n + 1, t =>
    if m.isView t || m.isBorrowed t then true else
    match m.compound? t with
    | some (.union cs) => cs.length == 2 && cs.all fun cse =>
        if m.containsBorrow cse then readOnlyParamF n cse else !m.managed cse
    | _ => false

def readOnlyParam (t : Ty) : Bool := m.readOnlyParamF m.fuel t

/-- `wanted` is on the read-only spine of parameter type `root`. -/
def spineContainsF : Nat → Ty → Ty → Bool
  | 0, _, _ => false
  | n + 1, root, wanted =>
    if !m.containsBorrow root || !m.readOnlyParam root then false else
    if root == wanted then true else
    match m.compound? root with
    | some (.union cs) => cs.any (spineContainsF n · wanted)
    | _ => false

/-- An option of an overlay or of a list view. -/
def borrowedOption (t : Ty) : Bool :=
  match m.compound? t with
  | some (.union [c0, c1]) => c0 == Ty.void && (m.isBorrowed c1 || m.kind? c1 == some .listView)
  | _ => false

/-- A record or union holding borrows that exists only in transit: an option of a borrow, a part of a read-only parameter,
or the result (or a step of the borrowed path into it) of a function with a borrow contract. -/
def canonicalTransient (t : Ty) : Bool :=
  m.borrowedOption t ||
  m.functions.any fun g =>
    g.sig.params.any (m.spineContainsF m.fuel · t) ||
    (!g.sig.sources.isEmpty &&
      (g.sig.ret == t ||
        (let rec walk : Ty → List Proj → Bool
          | _, [] => false
          | cur, st :: rest => match m.projectedType cur [st] with
            | some next => next == t || walk next rest
            | none => false
         walk g.sig.ret g.sig.path)))

/-- A task thunk's environment (FR58), or the record it boxes: the one place a view is stored. The first function whose
name has the task thunk's generated prefix (`stable_names.generatedRole`, which gives `#value` names another role), with
one parameter that is a box of a record and is `t` or boxes `t`, decides: every field of that record that holds a borrow
is a view. Keyed on the generated name as the Zig rule is (`taskEnvironment` in `src/core/verify_ir.zig`). -/
def taskEnvironment (t : Ty) : Bool :=
  let thunk (g : Function) : Option Ty :=
    if !g.name.startsWith "<task.thunk." || g.name.endsWith "#value" then none else
    match g.sig.params with
    | [env] => match m.compound? env with
      | some (.box r) => if t == env || t == r then some r else none
      | _ => none
    | _ => none
  match m.functions.toList.findSome? thunk with
  | some r => match m.compound? r with
    | some (.record fs) => fs.all fun f => !m.containsBorrow f || m.isView f
    | _ => false
  | none => false

/-- A compound type that would store a view: a list or dictionary of borrows other than a collection of overlays, a box
or array of one, an overlay of anything but plain managed storage, a record or union holding one outside transit, a
function type with view parameters, a borrow contract or a borrowed result. A task thunk's environment and its record
(`taskEnvironment`) are not. -/
def escapes (index : Nat) (c : Compound) : Bool :=
  let t := Ty.firstCompound + index
  match c with
  | .list e => m.containsBorrow e && !m.isBorrowed e
  | .box e => m.containsBorrow e && !m.taskEnvironment t
  | .listView _ => false
  | .borrowed u => !m.valid u || m.storageType u != u || !m.managed u || m.containsBorrow u
  | .dict k v => m.containsBorrow k || (m.containsBorrow v && !m.isBorrowed v)
  | .array e _ _ => m.containsBorrow e
  | .record ps | .union ps => ps.any m.containsBorrow && !m.canonicalTransient t && !m.taskEnvironment t
  | .fn s => Passing.hasViews s.passing || !s.sources.isEmpty || m.containsBorrow s.ret

/-- Every type a compound names is a type of the module. -/
def namesValid : Compound → Bool
  | .list e | .listView e | .box e | .borrowed e | .array e _ _ => m.valid e
  | .dict k v => m.valid k && m.valid v
  | .record ps | .union ps => ps.all m.valid
  | .fn s => m.valid s.ret && s.params.all m.valid

/-- The module-level rules: the table names only its own types, and no compound would store a view. -/
def checkTypes : Check Unit := do
  for c in m.compounds do
    if !m.namesValid c then reject .typeTable
  for (c, k) in m.compounds.toList.zipIdx do
    if m.escapes k c then reject .viewStorage

/-- The rules of one declaration. -/
def checkHeader (g : Function) : Check Unit := do
  let s := g.sig
  for (p, k) in s.params.zipIdx do
    let badSpan := Passing.viewAt s.passing k && !admittedView m s k
    if !m.valid p || badSpan || (m.containsBorrow p && !m.readOnlyParam p) then reject .paramType
  if !m.valid s.ret || !Passing.valid s.passing s.params.length ||
      (s.linkage == .internal && Passing.hasViews s.passing) then reject .resultType
  if !m.validBorrow s then reject .borrowContract

end Module

/-! ## Control flow -/

/-- A block's position in the instruction lists: block and index. -/
abbrev Pos := Nat × Nat

namespace Fn
variable (c : Fn)

/-- The blocks a block's terminator names, `then` first (`ir.unpackTargets`; a jump's target is the low 32 bits). -/
def successors (b : Nat) : Option Nat × Option Nat :=
  match c.f.blocks[b]? with
  | none => (none, none)
  | some blk => match blk.insts.back? with
    | some (some r) => match c.f.insts[r]? with
      | some i =>
        if i.op == .jump then (some (i.data % 2 ^ 32), none)
        else if i.op == .branch then (let (t, e) := branchTargets i.data; (some t, some e))
        else (none, none)
      | none => (none, none)
    | _ => (none, none)

def succList (b : Nat) : List Nat := match c.successors b with
  | (x, y) => x.toList ++ y.toList

/-- The blocks reachable from the entry, by a depth-first walk whose stack and order are the Zig verifier's; a target
past the last block is refused at the block that names it. -/
def reach : Check (Array Bool) := do
  let n := c.f.blocks.size
  let mut seen := (Array.replicate n false).set! 0 true
  let mut stack : List Nat := [0]
  for _ in [0:n + 1] do
    match stack with
    | [] => break
    | b :: rest =>
      stack := rest
      for s in c.succList b do
        if s ≥ n then reject .target (some b)
        if seen[s]! then continue
        seen := seen.set! s true
        stack := s :: stack
  return seen

/-- How often `b` is among `s`'s predecessors. -/
def predCount (s b : Nat) : Nat := match c.f.blocks[s]? with
  | some blk => blk.preds.toList.count b
  | none => 0

/-- Each edge appears in its target's predecessors as often as the terminator names it, and every reachable predecessor
of a block names it. -/
def edges (reachable : Array Bool) (b : Nat) : Check Unit := do
  let (x, y) := c.successors b
  let both := x.isSome && x == y
  match x with
  | some s => if c.predCount s b != (if both then 2 else 1) then reject .edgePreds (some b)
  | none => pure ()
  match y with
  | some s => if !both && c.predCount s b != 1 then reject .edgePreds (some b)
  | none => pure ()
  for p in (c.f.blocks[b]!).preds do
    if p ≥ c.f.blocks.size then reject .predEdge (some b)
    if !reachable[p]! then continue
    if !(c.succList p).contains b then reject .predEdge (some b)

/-- Blocks, terminators, listings, phi order and arity, then edges; where each listed instruction sits. -/
def listing (reachable : Array Bool) : Check (Array (Option Pos)) := do
  let mut pos : Array (Option Pos) := Array.replicate c.f.insts.size none
  for (blk, b) in c.f.blocks.toList.zipIdx do
    if !reachable[b]! then continue
    if blk.insts.size == 0 then reject .emptyBlock (some b)
    let mut phisDone := false
    for (entry, k) in blk.insts.toList.zipIdx do
      let some r := entry | reject .listedRange (some b)
      if r ≥ c.f.insts.size then reject .listedRange (some b)
      if pos[r]!.isSome then reject .listedTwice (some b) (some r)
      pos := pos.set! r (some (b, k))
      let i := c.f.insts[r]!
      let last := k + 1 == blk.insts.size
      if i.op.terminates != last then reject .terminator (some b) (some r)
      if i.op == .copy then continue
      if i.op == .phi then
        if phisDone then reject .phiOrder (some b) (some r)
        if (extraSlice i.data).2 != blk.preds.size then reject .phiArity (some b) (some r)
      else phisDone := true
    c.edges reachable b
  return pos

/-- The control-flow facts: reachability, positions, the verified dominator tree. -/
structure Graph where
  reachable : Array Bool
  pos : Array (Option Pos)
  idom : Array Nat
  depth : Array Nat
  /-- Whether any block, reachable or not, lists the instruction. -/
  listed : Array Bool

/-- Marks a block without a parent. -/
def noBlock : Nat := 2 ^ 32 - 1

/-- Reverse postorder of the reachable blocks, by the Zig verifier's explicit depth-first walk. -/
def reversePostorder : Array Nat := Id.run do
  let n := c.f.blocks.size
  let mut visited := (Array.replicate n false).set! 0 true
  let mut stack : List (Nat × Nat) := [(0, 0)]
  let mut post : Array Nat := #[]
  for _ in [0:3 * n + 3] do
    match stack with
    | [] => break
    | (b, next) :: rest =>
      if next < 2 then
        stack := (b, next + 1) :: rest
        let (x, y) := c.successors b
        match (if next == 0 then x else y) with
        | some s => if s < n && !visited[s]! then
            visited := visited.set! s true
            stack := (s, 0) :: stack
        | none => pure ()
      else
        post := post.push b
        stack := rest
  return post.reverse

/-- Cooper, Harvey and Kennedy's iterative dominators over reachable predecessors (untrusted: `treeOK` verifies). -/
def computeIdom (reachable : Array Bool) : Array Nat := Id.run do
  let n := c.f.blocks.size
  let rpo := c.reversePostorder
  let mut order := Array.replicate n noBlock
  for (b, k) in rpo.toList.zipIdx do order := order.set! b k
  let mut idom := (Array.replicate n noBlock).set! 0 0
  for _ in [0:n + 3] do
    let mut changed := false
    for b in rpo.toList.drop 1 do
      let mut chosen := noBlock
      for p in (c.f.blocks[b]!).preds do
        if p ≥ n || !reachable[p]! || idom[p]! == noBlock then continue
        if chosen == noBlock then chosen := p
        else
          let mut x := p
          let mut y := chosen
          for _ in [0:2 * n + 2] do
            if x == y then break
            for _ in [0:n + 1] do
              if order[x]! > order[y]! then x := idom[x]! else break
            for _ in [0:n + 1] do
              if order[y]! > order[x]! then y := idom[y]! else break
          chosen := x
      if chosen != idom[b]! then
        idom := idom.set! b chosen
        changed := true
    if !changed then break
  return idom

/-- Depths in the tree, by walking up (a walk that does not reach the entry gives `noBlock`). -/
def depths (idom : Array Nat) : Array Nat :=
  (Array.range idom.size).map fun b => Id.run do
    let mut x := b
    let mut d := 0
    for _ in [0:idom.size + 1] do
      if x == 0 then return d
      let p := idom[x]!
      if p == noBlock || p ≥ idom.size then return noBlock
      x := p
      d := d + 1
    return noBlock

/-- `a` is `b` or an ancestor of `b` in the tree. -/
def walkUp (idom : Array Nat) (a b : Nat) : Bool := Id.run do
  let mut x := b
  for _ in [0:idom.size + 1] do
    if x == a then return true
    if x == 0 then return false
    let p := idom[x]!
    if p == noBlock || p ≥ idom.size then return false
    x := p
  return false

/-- The verified properties of the tree. -/
def treeOK (reachable : Array Bool) (idom depth : Array Nat) : Bool :=
  let n := c.f.blocks.size
  idom.size == n && depth.size == n && idom[0]? == some 0 && depth[0]? == some 0 &&
  (List.range n).all fun b =>
    !reachable[b]! || b == 0 ||
      (let p := idom[b]!
       decide (p < n) && reachable[p]! && depth[b]! == depth[p]! + 1 &&
       (c.f.blocks[b]!).preds.all fun q => decide (q ≥ n) || !reachable[q]! || walkUp idom p q)

def structure_ : Check Graph := do
  if c.f.blocks.size == 0 then reject .noBlocks
  if (c.f.blocks[0]!).preds.size != 0 then reject .entryPreds (some 0)
  for p in c.f.sig.params do
    if !c.m.valid p then reject .paramType
  let reachable ← c.reach
  let pos ← c.listing reachable
  let idom := c.computeIdom reachable
  let depth := depths idom
  if !c.treeOK reachable idom depth then reject .domTree
  let listed := Id.run do
    let mut l := Array.replicate c.f.insts.size false
    for blk in c.f.blocks do
      for entry in blk.insts do
        match entry with
        | some r => if r < l.size then l := l.set! r true
        | none => pure ()
    return l
  return ⟨reachable, pos, idom, depth, listed⟩

/-! ## Signatures and dominance -/

def signature (b : Nat) (r : Nat) (i : Inst) : Check Unit := do
  if !c.m.valid i.ty then reject .typeValid (some b) (some r)
  if i.op.hasExtra && (c.extraOf? i.data).isNone then reject .extraRange (some b) (some r)
  -- an operation that reads only its extra list has nothing in `a` and `b` (a call's `a` is its callee)
  if (i.op == .print || i.op == .recordMake || i.op == .call) && ((i.op != .call && i.a.isSome) || i.b.isSome) then
    reject .unusedOperand (some b) (some r)
  for o in c.valueOperands i do
    match o with
    | some x => if x ≥ c.f.insts.size then reject .operandRange (some b) (some r)
    | none => reject .operandRange (some b) (some r)
  for o in c.valueOperands i do
    let some v := c.resolve o | reject .domForward (some b) (some r)
    if !c.m.valid (c.f.insts[v]!).ty then reject .operandType (some b) (some r)
  let s := c.shape i
  if !c.viewDefOk s then reject .viewDef (some b) (some r)
  for (o, k) in (c.valueOperands i).zipIdx do
    let t := match o with | some x => c.typeOf x | none => noTy
    if !c.m.isView t then continue
    if !c.viewUseOk s k t then reject .viewUse (some b) (some r)
  if i.op == .dictInsert && !c.insertProbe s then reject .insertProbe (some b) (some r)
  if !c.sigOk s then reject .signature (some b) (some r)

/-- `operand` is defined before `use` on every path from the entry. -/
def available (g : Graph) (b r : Nat) (raw : Option Nat) (use : Pos) : Check Unit := do
  let some x := raw | reject .domMissing (some b) (some r)
  if x ≥ c.f.insts.size then reject .domRange (some b) (some r)
  let some o := c.resolve (some x) | reject .domForward (some b) (some r)
  -- a constant no block lists is materialized at each use; a listed one is an instruction of its block
  if (c.f.insts[o]!).op.isConstant && !(g.listed[o]?.getD false) then return
  let some (db, di) := g.pos[o]! | reject .domUndefined (some b) (some r)
  if db == use.1 then
    if di < use.2 then return
    reject .domOrder (some b) (some r)
  if !walkUp g.idom db use.1 then reject .domBlock (some b) (some r)

def dominance (g : Graph) (b k r : Nat) (i : Inst) : Check Unit := do
  if i.op == .phi then
    for (o, p) in (c.extraOf i.data).zip (c.f.blocks[b]!).preds.toList do
      if !g.reachable[p]! then continue
      available c g b r o (p, (c.f.blocks[p]!).insts.size)
  else
    for o in c.valueOperands i do available c g b r o (b, k)

/-- The checks of one function with a body; the control-flow facts they computed. -/
def checkBody : Check Graph := do
  let g ← c.structure_
  -- Constants and parameters are defined outside every block: each one of the table is checked.
  for (i, r) in c.f.insts.toList.zipIdx do
    if i.op.isConstant then c.signature 0 r i
  for (blk, b) in c.f.blocks.toList.zipIdx do
    if !g.reachable[b]! then continue
    for (entry, k) in blk.insts.toList.zipIdx do
      let r := entry.getD 0
      let i := c.f.insts[r]!
      if i.op == .copy then continue
      c.signature b r i
      -- As the Zig verifier: exempt exactly when `data` is the place-copy flag alone.
      if i.data != placeCopyFlag && c.shallowManagedCopy i then reject .shallowCopy (some b) (some r)
      c.dominance g b k r i
  return g

end Fn

/-- The verdict on one function: its declaration's rules and, with a body, the body's. -/
def checkFunction (m : Module) (g : Function) : Check Unit := do
  m.checkHeader g
  if g.sig.linkage == .internal then discard (Fn.mk m g).checkBody

end VerifyIr

/-! ## Rules the Zig verifier does not have (candidates, `irverify --strict`)

Each is a property a proof's hypothesis needs, or hygiene the IR's documentation states, that the Zig verifier does
not check. `--strict` runs them after the mirrored rules, so a function they refuse is one the Zig verifier accepts:
on the gate's corpus, a refusal is a finding (a hole, or an over-strict candidate). -/

namespace VerifyIr

/-- The candidate rules. -/
inductive Strict where
  /-- An instruction whose rule does not read `a` or `b` has none there. -/
  | unusedOperand
  /-- A lane comparison's mask, and a select's mask, are as long as the lanes; a Boolean comparison reads scalars. -/
  | laneMask
  /-- A function without a body (C or the runtime) returns no function value, nor anything that holds one, unless it takes
  a value of its result type (the runtime's deep copies return a copy of their argument): a function value is made only by
  `func_ref`, so the function it points to is one of the module's. -/
  | externFn
  deriving DecidableEq, Repr

def Strict.label : Strict → String
  | .unusedOperand => "strict-unused" | .laneMask => "strict-lanes"
  | .externFn => "strict-extern-fn"

namespace Fn
variable (c : Fn)

def strictInst (i : Inst) : Option Strict :=
  let t := i.ty
  match i.op with
  | .jump | .phi | .print | .recordMake | .call =>
    if (i.op != .call && i.a.isSome) || i.b.isSome then some .unusedOperand else none
  | .fcmp =>
    let s := c.shape i
    let ok := if t == Ty.bool then Ty.isFloat s.a else c.maskOver t s.a
    if ok then none else some .laneMask
  | .vectorSelect =>
    let s := c.shape i
    if c.maskOver s.a t then none else some .laneMask
  | _ => none

/-- The instructions a listed instruction of a reachable block reads, and every instruction their copies forward to:
the values the program can use. A dead entry of the table (a tombstone `copy` of nothing) is not among them. -/
def used : Array Bool := Id.run do
  let n := c.f.insts.size
  let mut out := Array.replicate n false
  let mut todo : List Nat := []
  for blk in c.f.blocks do
    for entry in blk.insts do
      match entry with
      | some r =>
        if r < n then
          todo := r :: todo
          match c.f.insts[r]? with
          | some i => for o in c.valueOperands i do
              match o with | some x => todo := x :: todo | none => pure ()
          | none => pure ()
      | none => pure ()
  for _ in [0:todo.length + n + 1] do
    match todo with
    | [] => break
    | x :: rest =>
      todo := rest
      if x ≥ n || out[x]! then continue
      out := out.set! x true
      match c.f.insts[x]? with
      | some i =>
        if i.op == .copy then
          match i.a with
          | some y => todo := y :: todo
          | none => pure ()
      | none => pure ()
  return out

/-- The candidate rules over a function the mirrored rules accept: every used instruction (constants are not listed in
blocks), then the entry. -/
def strictBody : Except (Strict × Option Nat) Unit := do
  let u := c.used
  for (i, r) in c.f.insts.toList.zipIdx do
    if !u[r]! then continue
    match c.strictInst i with
    | some s => throw (s, some r)
    | none => pure ()

end Fn

namespace Module
variable (m : Module)

/-- The candidate rule on a declaration. -/
def strictHeader (g : Function) : Option Strict :=
  if g.sig.linkage != .internal && m.holdsFn g.sig.ret && !g.sig.params.contains g.sig.ret then some .externFn
  else none

end Module

end VerifyIr
