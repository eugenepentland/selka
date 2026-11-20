import VerifyIr.TagProof
import Facts.Avail

/-!
# The SSA rule on the fact certificate's form

The fact certificate (`proofs/facts`) describes a function differently from the IR: constants and parameters that no
block lists are `pre`, a block's phis are apart from its instructions, a copy is gone (every operand is followed to the
value it stands for), and the final terminator is the block's `term`. So an instruction's position in the certificate
excludes the block's phis and copies.

* `Skel` is what the SSA hypothesis `SsaWf` reads of a certificate function: the values of `pre`, and per block its
  predecessors, its phis' values and edges, its instructions' values and the registers they read (`regOps`), and its
  terminator. `skelOf` takes it from a certificate function.
* `translate` is the same skeleton made from the IR, the way `src/core/fact_export.zig` describes it. That an exported
  certificate's skeleton equals the translation of the exported IR is checked, not proved (`translatesB`, run over the
  corpus by `irverify --facts`).
* `ssaCheck` is the SSA rule on a skeleton, with a dominator tree given as a parent array: the blocks a walk reaches are
  closed under successors and never go back to the entry, the tree's parent of each successor is an ancestor of the
  block, and every register an instruction, a phi edge or a terminator reads is defined where it is read (a `pre` value
  anywhere; a phi in a dominating block; an instruction earlier in the same block or in a strictly dominating one).
  The checker runs it on the translation of every function it accepts (`checkFunction`), with the tree the body's rules
  computed; `SsaProof.lean` proves that it gives `SsaWf`.
-/

namespace VerifyIr

/-- An instruction as `SsaWf` reads it: its value and the registers it reads. -/
structure SInst where
  value : Nat
  ops : List Nat
  deriving DecidableEq, Repr

/-- A phi: its value and its edges (block, value). -/
structure SPhi where
  value : Nat
  edges : List (Nat × Nat)
  deriving DecidableEq, Repr

/-- A block. -/
structure SBlock where
  preds : List Nat
  phis : List SPhi
  insts : List SInst
  term : Facts.Term
  deriving DecidableEq, Repr, Inhabited

/-- A function. -/
structure Skel where
  pre : List Nat
  blocks : Array SBlock
  deriving DecidableEq, Repr

/-- The skeleton of a certificate function. -/
def skelOf (f : Facts.Function) : Skel :=
  { pre := f.pre.map (·.value),
    blocks := f.blocks.map fun b =>
      { preds := b.preds,
        phis := b.phis.map fun p => ⟨p.value, p.edges.map fun e => (e.block, e.value)⟩,
        insts := b.insts.map fun i => ⟨i.value, Facts.regOps i⟩,
        term := b.term } }

/-- The number the exporter writes for a value that resolves to nothing (`ir.Ref.none`'s index). -/
def noValue : Nat := 4294967295

namespace Fn
variable (c : Fn)

/-- The value a reference stands for, as the exporter writes it. -/
def exported (r : Option Nat) : Nat := ((r.bind fun x => c.resolve (some x))).getD noValue

/-- The registers the certificate says an instruction reads (`fact_export.zig`, `describeInst`, then `regOps`): `a` and
`b` followed through copies, except a call's `a` (its callee) and a constant's fields, then the extra list (an absent
entry is written `-` and read as none). -/
def tOps (i : Inst) : List Nat :=
  let skip := i.op.isConstant
  let a := if i.op == .call || skip then [] else match i.a with
    | some x => [c.exported (some x)]
    | none => []
  let b := if i.op == .call || skip then [] else match i.b with
    | some x => [c.exported (some x)]
    | none => []
  let x := if i.op.hasExtra then (c.extraOf i.data).filterMap fun o => o.bind fun y => c.resolve (some y) else []
  a ++ b ++ x

/-- A phi's edges: the block's predecessors in order, with the operands followed through copies. -/
def tPhi (preds : Array Nat) (r : Nat) (i : Inst) : SPhi :=
  ⟨r, (c.extraOf i.data).zipIdx.map fun (o, k) => (preds[k]?.getD 0, c.exported o)⟩

/-- A block's terminator: its last listed instruction when that terminates, else `unreachable`. -/
def tTerm (i : Inst) : Facts.Term :=
  match i.op with
  | .jump => .jump i.data
  | .branch => let (t, e) := branchTargets i.data; .branch (c.exported i.a) t e
  | .ret => .ret (i.a.map fun _ => c.exported i.a)
  | _ => .unreachable

/-- One block of the translation. -/
def tBlock (blk : Block) : SBlock := Id.run do
  let mut phis : Array SPhi := #[]
  let mut insts : Array SInst := #[]
  let mut term : Facts.Term := .unreachable
  let n := blk.insts.size
  for (entry, k) in blk.insts.toList.zipIdx do
    let some r := entry | continue
    let some i := c.f.insts[r]? | continue
    if k + 1 == n && i.op.terminates then
      term := c.tTerm i
      continue
    if i.op == .copy then continue
    if i.op == .phi then phis := phis.push (c.tPhi blk.preds r i)
    else insts := insts.push ⟨r, c.tOps i⟩
  return ⟨blk.preds.toList, phis.toList, insts.toList, term⟩

/-- The translation of the function: the constants no block lists, in table order, and every block. -/
def translate : Skel :=
  let placed : Array Bool := Id.run do
    let mut p := Array.replicate c.f.insts.size false
    for blk in c.f.blocks do
      for entry in blk.insts do
        match entry with
        | some r => p := p.set! r true
        | none => pure ()
    return p
  { pre := (c.f.insts.toList.zipIdx.filter fun (i, r) => i.op.isConstant && !(placed[r]?.getD false)).map (·.2),
    blocks := c.f.blocks.map c.tBlock }

end Fn

/-! ## The rule on a skeleton -/

namespace Skel
variable (s : Skel)

/-- A block's successors (`Facts.cfgSucc`). -/
def succ (p : Nat) : List Nat := match s.blocks[p]? with
  | some b => Facts.successors b.term
  | none => []

/-- The blocks a walk from the entry reaches, by a worklist (untrusted: `ssaCheck` verifies that the set holds the entry
and is closed under successors). -/
def reach : Array Bool := Id.run do
  let n := s.blocks.size
  if n == 0 then return #[]
  let mut seen := (Array.replicate n false).set! 0 true
  let mut stack : List Nat := [0]
  for _ in [0:n + 1] do
    match stack with
    | [] => break
    | b :: rest =>
      stack := rest
      for t in s.succ b do
        if t < n && !seen[t]! then
          seen := seen.set! t true
          stack := t :: stack
  return seen

/-- Where a value is defined. -/
inductive Loc where
  | pre (k : Nat)
  | phi (block k : Nat)
  | inst (block k : Nat)
  deriving DecidableEq, Repr

/-- The definition of each value, the first one met (untrusted: `tableOK` verifies each entry against the items). -/
def table : Array (Option Loc) := Id.run do
  let mut size := 0
  for v in s.pre do size := max size (v + 1)
  for b in s.blocks do
    for p in b.phis do size := max size (p.value + 1)
    for i in b.insts do size := max size (i.value + 1)
  let mut t : Array (Option Loc) := Array.replicate size none
  for (v, k) in s.pre.zipIdx do
    if t[v]!.isNone then t := t.set! v (some (.pre k))
  for (b, d) in s.blocks.toList.zipIdx do
    for (p, k) in b.phis.zipIdx do
      if t[p.value]!.isNone then t := t.set! p.value (some (.phi d k))
    for (i, k) in b.insts.zipIdx do
      if t[i.value]!.isNone then t := t.set! i.value (some (.inst d k))
  return t

/-- Each entry of the table names an item that defines that value. -/
def tableOK (t : Array (Option Loc)) : Bool :=
  (List.range t.size).all fun v => match t[v]! with
    | some (.pre k) => s.pre[k]? == some v
    | some (.phi d k) => ((s.blocks[d]?).bind fun b => b.phis[k]?).map (·.value) == some v
    | some (.inst d k) => ((s.blocks[d]?).bind fun b => b.insts[k]?).map (·.value) == some v
    | none => true

/-- Value `v` is defined where block `B` reads it at instruction position `k`. -/
def availS (t : Array (Option Loc)) (idom : Array Nat) (v B k : Nat) : Bool :=
  match t[v]? with
  | some (some (.pre _)) => true
  | some (some (.phi d _)) => Facts.walkUp idom d (s.blocks.size + 1) B
  | some (some (.inst d j)) => (d == B && decide (j < k)) || (d != B && Facts.walkUp idom d (s.blocks.size + 1) B)
  | _ => false

/-- The reads of one reached block: its instructions' operands at their positions, its terminator's at the end, and its
phis' operands at the end of each reached predecessor. -/
def blockOK (r : Array Bool) (t : Array (Option Loc)) (idom : Array Nat) (d : Nat) (b : SBlock) : Bool :=
  (b.insts.zipIdx.all fun (i, k) => i.ops.all fun v => s.availS t idom v d k) &&
  (match b.term with
   | .branch cnd _ _ => s.availS t idom cnd d b.insts.length
   | .ret (some v) => s.availS t idom v d b.insts.length
   | _ => true) &&
  (b.phis.all fun p => p.edges.all fun (e, v) =>
    !(r[e]?.getD false) || (match s.blocks[e]? with
      | some pb => s.availS t idom v e pb.insts.length
      | none => false))

/-- The SSA rule with the dominator tree `idom` (parents as `Facts.parentOf` reads them). -/
def ssaCheck (idom : Array Nat) : Bool :=
  let n := s.blocks.size
  let r := s.reach
  let t := s.table
  n == 0 || (
    r.size == n && r[0]! &&
    ((List.range n).all fun p => !r[p]! || (s.succ p).all fun x =>
      decide (x < n) && r[x]! && x != 0 &&
      (match Facts.parentOf idom x with
       | some d => Facts.walkUp idom d (n + 1) p
       | none => false)) &&
    s.tableOK t &&
    ((List.range n).all fun d => !r[d]! || s.blockOK r t idom d s.blocks[d]!))

end Skel

/-- The dominator tree the body's rules computed (empty for a function without a body). -/
def bodyIdom (m : Module) (g : Function) : Check (Array Nat) :=
  if g.sig.linkage == .internal then (do
    let c := Fn.mk m g
    let gr ← c.checkBody
    -- the union-tag rule runs after every per-instruction rule, as in `verify_ir.zig`
    match c.unionTags gr.reachable with
    | some (b, r) => reject .unionTag (some b) r
    | none =>
      -- the facts the rule accepted by are verified, so `payload_under_tag` holds of the function
      if c.tagOK gr.reachable then pure gr.idom else reject .tagFacts) else pure #[]

/-- The translations of every function of `mI` are the skeletons of the certificate `mF`, in module order: the check
that ties the proof to a build (`irverify --facts`). -/
def translatesB (mI : Module) (mF : Facts.Module) : Bool :=
  mF.functions.size == mI.functions.size &&
  (List.range mF.functions.size).all fun g =>
    match mI.functions[g]?, mF.functions[g]? with
    | some gI, some fF => skelOf fF == (Fn.mk mI gI).translate
    | _, _ => false

end VerifyIr
