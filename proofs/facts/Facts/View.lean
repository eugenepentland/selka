import Facts.Prep

/-!
# Intervals as the checker sees them

`base`, `view` (an interval narrowed by the dominating branch edges and the fill caps), reachability and the
predicate algebra of branch refinement: design §3 and §5.1–§5.2, and the same functions of
`validate_facts.zig`.

`view` recurses through the bounds of the comparisons on the dominator chain; it is written with
*fuel*, which makes every definition total. The proofs hold for every fuel (an exhausted view is
the looser base interval, which is still sound); the checker runs with fuel for the whole tree.
-/

namespace Facts

/-- Everything the rules read: the module, the function, and what `prepare` computed. -/
structure Ctx where
  m : Module
  f : Function
  n : Nat
  defs : Array Def
  lists : Array (Option ListFact)
  caps : List Cap
  idom : Array Nat
  depth : Array Nat
  reached : Array Bool

namespace Ctx

/-- The definition of a value (a missing one for a name out of range). -/
def def_ (c : Ctx) (v : Nat) : Def := c.defs[v]?.getD {}

/-- The number of blocks. -/
def count (c : Ctx) : Nat := c.f.blocks.size

/-- The parent of a block in the dominator tree, if it has one (the entry has none here). -/
def parent? (c : Ctx) (x : Nat) : Option Nat := parentOf c.idom x

/-- `a` dominates `b` in the verified tree. -/
def dominates (c : Ctx) (a b : Nat) : Bool := walkUp c.idom a (c.count + 1) b

end Ctx

/-- The value of a constant of type `t` with bits `imm`, read at the type's signedness (`constant` in the validator). -/
def constVal (t : Ty) (imm : Nat) : Int :=
  if t = .bool then (if imm ≠ 0 then 1 else 0)
  else if t = .u64 then (imm : Int)
  else if imm ≥ 2 ^ 63 then (imm : Int) - 2 ^ 64 else (imm : Int)

/-- The value of a constant definition (`constant` in the validator). -/
def constantOf (d : Def) : Int :=
  match d.inst with
  | none => 0
  | some i => constVal d.ty i.imm

/-- The interval the function states for parameter `k`, when anyone outside the module cannot call it. -/
def paramClaim (c : Ctx) (k : Nat) : Option Interval :=
  if !c.f.header.internal || c.f.header.addressTaken || k ≥ c.f.boundary.params.length then none
  else (c.f.boundary.params[k]?).getD none

/-- The interval the function states for the parameter `i` reads. -/
def paramInterval (c : Ctx) (i : Inst) : Option Interval := paramClaim c i.imm

/-- The stated interval of a value as its own definition gives it (design §3, `base`). -/
def base (c : Ctx) (v : Nat) : Option Interval :=
  let d := c.def_ v
  match d.ty.range with
  | none => none
  | some limits =>
    match d.kind with
    | .missing => none
    | .phi => d.stated
    | .pre | .inst =>
      match d.inst with
      | none => none
      | some i =>
        match i.op with
        | .iconst => some (Interval.point (constantOf d))
        | .undef | .unionPayload | .unionTake | .recordTake | .boxTake => some limits
        | .param => some ((paramInterval c i).getD limits)
        | .call => some (d.stated.getD limits)
        | _ => d.stated

/-- The comparison predicates, in `ir.Predicate` order. -/
inductive Pred where
  | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr, Inhabited

/-- The predicate of an immediate, if it is one. -/
def Pred.ofImm : Nat → Option Pred
  | 0 => some .eq | 1 => some .ne | 2 => some .lt | 3 => some .le | 4 => some .gt | 5 => some .ge
  | _ => none

/-- The negated predicate. -/
def Pred.negate : Pred → Pred
  | .eq => .ne | .ne => .eq | .lt => .ge | .le => .gt | .gt => .le | .ge => .lt

/-- The predicate with its operands swapped. -/
def Pred.mirror : Pred → Pred
  | .lt => .gt | .le => .ge | .gt => .lt | .ge => .le | p => p

/-- A refining edge into a block (design §5.2): the comparison, whether the branch took it, and its source block. -/
structure Edge where
  cmp : Inst
  taken : Bool
  source : Nat

/-- The refining edge into block `x`, if any. -/
def refining (c : Ctx) (x : Nat) : Option Edge :=
  match c.f.blocks[x]? with
  | none => none
  | some blk =>
    match blk.preds with
    | [p] =>
      match c.f.blocks[p]? with
      | none => none
      | some pb =>
        match pb.term with
        | .branch cond t e =>
          if t == e then none
          else
            let d := c.def_ cond
            match d.inst with
            | none => none
            | some i => if d.kind == .phi || i.op != .cmp then none else some ⟨i, t == x, p⟩
        | _ => none
    | _ => none

/-- Whether `raw` is a checked or proven product `v * v`. -/
def isSquareOf (c : Ctx) (raw : Option Nat) (v : Nat) : Bool :=
  match raw with
  | none => false
  | some r =>
    let d := c.def_ r
    match d.inst with
    | none => false
    | some i => d.kind != .phi && i.op == .mul && i.check != .none && i.operands.a == some v && i.operands.b == some v

/-- The integer square root. -/
def isqrt (n : Nat) : Nat := Nat.sqrt n

/-- The view of an operand for a rule: `low`'s view, else its type's range; none for a non-integer. An operand that is
never produced has an empty view. -/
def operandWith (c : Ctx) (low : Nat → Nat → Option Interval) (v : Option Nat) (at_ : Nat) : Option Interval :=
  match v with
  | none => none
  | some w =>
    match (c.def_ w).ty.range with
    | none => none
    | some limits => some ((low w at_).getD limits)

/-- Narrow `r` by `x p bound` for the unknown `x`. -/
def refineBy (p : Pred) (r bound : Interval) : Interval :=
  match p with
  | .lt => { r with hi := min r.hi (bound.hi - 1) }
  | .le => { r with hi := min r.hi bound.hi }
  | .gt => { r with lo := max r.lo (bound.lo + 1) }
  | .ge => { r with lo := max r.lo bound.lo }
  | .eq => r.meet bound
  | .ne => r

/-- Narrow `r`, the interval of `v`, when `v * v <= top`: `|v| <= ⌊√top⌋`. -/
def cutTop (top : Int) (r : Interval) : Interval :=
  if top < 0 then r
  else
    let root : Int := (isqrt top.toNat : Nat)
    r.meet ⟨-root, root⟩

/-- Narrow `r`, the interval of `v`, when `v * v p bound` holds. -/
def squareCut (p : Pred) (r bound : Interval) : Interval :=
  match p with
  | .lt => cutTop (bound.hi - 1) r
  | .le | .eq => cutTop bound.hi r
  | _ => r

/-- The square rule (NEW-CORE-F1-OVERFLOW-2): on an edge where `v * v <= y`, `|v| <= sqrt(top)`. -/
def refineSquareWith (c : Ctx) (low : Nat → Nat → Option Interval) (r : Interval) (v : Nat) (e : Edge) : Interval :=
  let onLeft := isSquareOf c e.cmp.operands.a v
  if !onLeft && !isSquareOf c e.cmp.operands.b v then r
  else
    match Pred.ofImm e.cmp.imm with
    | none => r
    | some p0 =>
      let p1 := if e.taken then p0 else p0.negate
      let p2 := if !onLeft then p1.mirror else p1
      match operandWith c low (if onLeft then e.cmp.operands.b else e.cmp.operands.a) e.source with
      | none => r
      | some bound => if bound.isEmpty then r else squareCut p2 r bound

/-- Narrow `r`, the interval of `v`, by the comparison of edge `e` (design §5.2). -/
def refineWith (c : Ctx) (low : Nat → Nat → Option Interval) (r : Interval) (v : Nat) (e : Edge) : Interval :=
  match e.cmp.operands.a, e.cmp.operands.b with
  | some left, some right =>
    if left != v && right != v then refineSquareWith c low r v e
    else
      match Pred.ofImm e.cmp.imm with
      | none => r
      | some p0 =>
        let p1 := if e.taken then p0 else p0.negate
        let other := if left == v then right else left
        let p2 := if left != v then p1.mirror else p1
        match operandWith c low (some other) e.source with
        | none => r
        | some bound => if bound.isEmpty then r else refineBy p2 r bound
  | _, _ => r

/-- Walk the dominator chain from `x`, refining by each refining edge. -/
def chainRefineWith (c : Ctx) (low : Nat → Nat → Option Interval) (v : Nat) (x : Nat) :
    Nat → Interval → Interval
  | 0, r => r
  | steps + 1, r =>
    let r' := match refining c x with
      | some e => refineWith c low r v e
      | none => r
    match c.parent? x with
    | some d => chainRefineWith c low v d steps r'
    | none => r'

/-- One level of `view`: the interval of `v` where block `at_` executes, with nested bounds read by `low`. -/
def viewStep (c : Ctx) (low : Nat → Nat → Option Interval) (v at_ : Nat) : Option Interval :=
  match base c v with
  | none => none
  | some r0 =>
    let r1 := c.caps.foldl (fun (r : Interval) (cap : Cap) =>
      if cap.value == v && c.dominates cap.block at_ then { r with hi := min r.hi maxListLength } else r) r0
    some (chainRefineWith c low v at_ (c.count + 1) r1)

/-- The interval of `v` where block `at_` executes, with `fuel` levels of nested bounds (design §5.2). -/
def viewN (c : Ctx) : Nat → Nat → Nat → Option Interval
  | 0 => fun v _ => base c v
  | fuel + 1 => viewStep c (viewN c fuel)

/-- The fuel the checker gives views: more than the depth of any dominator tree. -/
def viewFuel (c : Ctx) : Nat := c.count + 2

/-- A view with the checker's fuel. -/
def Ctx.view (c : Ctx) (v at_ : Nat) : Option Interval := viewN c (viewFuel c) v at_

/-- The view of an operand with the checker's fuel (empty when the operand is never produced). -/
def Ctx.operandRaw (c : Ctx) (v : Option Nat) (at_ : Nat) : Option Interval := operandWith c (viewN c (viewFuel c)) v at_

/-- The interval of an operand for a rule: its view, else its type's range; none for a non-integer. An operand that is
never produced reads as its type's range (the rule is then vacuous: `Ctx.derive`, `Ctx.provenOut`). -/
def Ctx.operand (c : Ctx) (v : Option Nat) (at_ : Nat) : Option Interval :=
  match c.operandRaw v at_ with
  | none => none
  | some r => if r.isEmpty then (v.bind fun w => (c.def_ w).ty.range) else some r

/-! ### Reachability (design §5.1) -/

/-- Whether the branch at the end of `from_` leaves the edge to `to` open: it is not decided against it. -/
def edgeOpen (c : Ctx) (from_ to : Nat) : Bool :=
  match c.f.blocks[from_]? with
  | none => true
  | some b =>
    match b.term with
    | .branch cond t e =>
      match base c cond with
      | none => true
      | some i =>
        if i.lo == 1 && i.hi == 1 then t == to
        else if i.lo == 0 && i.hi == 0 then e == to
        else true
    | _ => true

/-- Whether the edge `from_ → to` can execute, by the computed reachability and the branch's decided condition. -/
def edgeLive (c : Ctx) (from_ to : Nat) : Bool :=
  (c.reached[from_]?.getD false) && edgeOpen c from_ to

/-- The blocks some execution can reach, from the entry along every edge a decided branch does not rule out. -/
partial def computeReached (c : Ctx) : Array Bool := Id.run do
  let count := c.f.blocks.size
  let mut reached : Array Bool := Array.replicate count false
  if count == 0 then return reached
  reached := reached.set! 0 true
  let mut work : Array Nat := #[0]
  while !work.isEmpty do
    let b := work.back!
    work := work.pop
    for next in successors c.f.blocks[b]!.term do
      if next < count && !reached[next]! && edgeOpen c b next then
        reached := reached.set! next true
        work := work.push next
  return reached

/-- Verified: the entry is reached, and a reached block's open successors are reached. -/
def reachOK (c : Ctx) : Bool :=
  decide (c.reached.size = c.count) &&
  (c.count == 0 || (c.reached[0]! &&
    (List.range c.count).all fun b =>
      !c.reached[b]! ||
        (successors c.f.blocks[b]!.term).all fun s => decide (s < c.count) && (!edgeOpen c b s || c.reached[s]!)))

end Facts
