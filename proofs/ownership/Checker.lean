import Std.Data.HashMap
import Syntax

/-!
# The checker (design §5): `check : Function → Certificate → Bool`

An executable implementation of J1-J8, written the way a Zig validator would do it.

## Shape

The abstract state of a program point is `AbsState`:
* `L`, the **live set** of the design: owned values defined and not yet consumed (a `stack`
  value has no destruction obligation and is never in `L`);
* `D`, the borrowed values **defined** on every path to the point (a borrowed name left over
  from an earlier loop iteration must not look usable: see NOTES.md);
* `R`, the **roots** of each borrowed value of `D` on this path: the owned values (and
  `caller(i)`) it lives in. They follow ownership: when an owned phi or a constructor takes
  over an owner, the roots that named the owner now name the new holder, because the storage
  does not move;
* `P`, the **open takes**: pairs `(container, slot key)` (design §3, slots; J8);
* `G`, the **guarded takes**: a take that is open on one of the paths that met at a join and
  not on the others, with the test that tells them apart: `(container, slot, test, polarity)`
  is open exactly when the test came out `polarity`;
* `F`, the **decided tests**: the branch conditions already decided on this path, with the
  outcome when it is the same on every path that met here. A later branch on the same test
  decides the guarded takes (`resolveG`). Redefining a value a test depends on forgets the test.

`verdict` works in two phases.
1. `solve`: forward passes over the reachable blocks in reverse post-order, carrying the
   state, until the proposed entry states stop changing. A block's entry state is the join of
   the states its edges carry (`joinState`: the first arrival's `L` and `P`, `D` intersected,
   roots united). The pass proposes an entry state `inn b` for every block it reaches.
2. `verifyBlocks`: the **recheck**. Every block with an entry state is run again from that
   state, every instruction is checked, and every outgoing edge is compared with the entry
   state of its target (`compatErr`): `L` and `P` must be *equal* (the join equality of B5 and
   B6, and the loop headers' recheck once their back edges are known), `D` must contain the
   target's `D`, and the roots of each name of the target's `D` must contain the edge's.

`check` is the verdict of phase 2. Phase 1 only proposes.

## Task groups (design §10)

A lend (`box_make` with `lent %G`, a `Construct`) reads the lender and the group, consumes nothing
and hands the roots of the lender to the group `%G`, which holds them as loans until it is consumed
(`instNext`).  The state also records that `%G` has been lent to: the group holds a loan on itself
(`.val G` among its own roots), which `groupJoinOk` reads: such a group is consumed only by a call
that returns nothing, the join.  Everything else is the existing loan machinery: `loansOk` refuses
to consume a root of the loans of a live holder, and (design §9, entry 41) a constructor that
destroys what it consumes (an `emptied` result) is no longer exempt.  A group is never abandoned
(`abandonChecks`).

## Trap regions (C9.1, design entry 55)

`own.zig` schedules no drop on a path that ends in a trap, so the edges into such a path may disagree about the
owners that are live.  They say what they leak: the block carries `abandon bP %V,…` lines, and the edge from `bP`
removes those owners from `L` (`AbsState.abandon`) before the block's phis read their operands.  Every block is then an
ordinary block (`joinCompat`).  The region where an edge may abandon is the least fixpoint "ends in `unreachable`, or has
successors and all of them are in the region" (`region`).  An abandon is a no-op on memory in the semantics
(`abandonNext`); the proof keeps the roots of the abandoned trees in a ghost set and asks for it to be empty at a `ret`.

## Reports

A rejection names the check (`J1`-`J8`), the block (`none` for the signature, the
pseudo-block and the function-wide checks) and the position in the block: the instruction
index, or the number of instructions for the terminator and the edges leaving it.
-/

namespace Own

/-! ## Verdicts -/

/-- The judgments of design §5. -/
inductive J where
  | j1 | j2 | j3 | j4 | j5 | j6 | j7 | j8
  deriving DecidableEq, Repr

/-- `J1` ... `J8`. -/
def J.label : J → String
  | .j1 => "J1" | .j2 => "J2" | .j3 => "J3" | .j4 => "J4"
  | .j5 => "J5" | .j6 => "J6" | .j7 => "J7" | .j8 => "J8"

/-- Where a check failed. -/
structure Failure where
  j : J
  blk : Option BlockId
  idx : Option Nat
  /-- a short tag naming the sub-check that failed (printed by `certcheck --explain`) -/
  why : String := ""
  deriving DecidableEq, Repr

/-- A check with its tag. -/
abbrev Chk := J × String × Bool

/-- The first failing check of a list: the judgment and its tag. -/
def firstFail (l : List Chk) : Option (J × String) :=
  (l.find? fun p => !p.2.2).map fun p => (p.1, p.2.1)

/-- The checker's answer for one function. -/
inductive Verdict where
  | accept
  | reject (fl : Failure)
  deriving DecidableEq, Repr

/-! ## Abstract state and small helpers -/

/-- The state carried through a function (see the file header). -/
structure AbsState where
  L : List ValId
  D : List ValId
  R : List (ValId × List Root)
  P : List (ValId × String)
  G : List (ValId × String × Key × Bool)
  F : List (Key × Option Bool)
  deriving DecidableEq, Repr

/-- `a ⊆ b` as sets. -/
def sub {α : Type} [BEq α] (a b : List α) : Bool := a.all b.contains

/-- Equal as sets. -/
def same {α : Type} [BEq α] (a b : List α) : Bool := sub a b && sub b a

/-- `l` without the elements of `rm`. -/
def without {α : Type} [BEq α] (l rm : List α) : List α := l.filter fun x => !rm.contains x

/-- No element occurs twice. -/
def nodupB {α : Type} [BEq α] : List α → Bool
  | [] => true
  | x :: xs => !xs.contains x && nodupB xs

/-- Whether a value of this state owns a tree that must be consumed exactly once. A `stack`
value has no destruction obligation (design §2) and an `emptied` aggregate owns nothing. -/
def St.owning : St → Bool
  | .owned => true
  | _ => false

/-- Facts about the function under check: the IR, the certificate and the defining
instruction of each value. -/
structure CCtx where
  f : Function
  c : Certificate
  /-- the instruction that defines a value -/
  defOf : Std.HashMap ValId Inst

/-- The test a value stands for (design §5, guarded takes). -/
def CCtx.keyOf (cc : CCtx) (v : ValId) : Key := keyOfWith (fun x => cc.defOf[x]?) v

/-- The certificate's state of a value. -/
def CCtx.st (cc : CCtx) (v : ValId) : St := cc.c.state v

/-- Whether `v` is an `undef` of a managed type, the null owner (state `immortal`): a join, a store or a drop may take
it, but no operation may read it, since it points at nothing (lane FX12; the Zig validator's `nullOwner`). -/
def CCtx.nullOwner (cc : CCtx) (v : ValId) : Bool :=
  cc.st v == .immortal && (match cc.defOf[v]? with
    | some d => d.op == "undef"
    | none => false)

/-- The state the certificate gives to the value an instruction defines. -/
def CCtx.sd (cc : CCtx) (i : Inst) : St :=
  match i.dst with
  | some d => cc.c.state d
  | none => .none

/-- The parents the certificate gives to the value an instruction defines. -/
def CCtx.pd (cc : CCtx) (i : Inst) : List Root :=
  match i.dst with
  | some d => cc.c.parents d
  | none => []

/-- The values an instruction consumes that own a tree. -/
def CCtx.ownConsumed (cc : CCtx) (i : Inst) : List ValId :=
  i.consumes.filter fun k => (cc.st k).owning

/-- Whether a container has an open take, guarded or not. -/
def AbsState.pendingAny (σ : AbsState) (c : ValId) : Bool :=
  σ.P.any (fun p => p.1 == c) || σ.G.any fun g => g.1 == c

/-- Whether the slot `k` of the container `c` is open, guarded or not. -/
def AbsState.slotOpen (σ : AbsState) (c : ValId) (k : String) : Bool :=
  σ.P.contains (c, k) || σ.G.any fun g => g.1 == c && g.2.1 == k

/-! ## Roots (design §2) -/

/-- Whether the root lives in the value `k` (the value itself or one of its slots). -/
def Root.ownedBy : Root → ValId → Bool
  | .val n, k => n == k
  | .slot n _, k => n == k
  | .caller _, _ => false
  | .fwd _, _ => false

/-- A root list without repeats (roots are compared as sets everywhere). -/
def normRoots (l : List Root) : List Root := l.eraseDups

/-- The roots recorded for a borrowed value. -/
def Rget (σ : AbsState) (w : ValId) : List Root := (σ.R.lookup w).getD []

/-- Where the lifetime of a value ends: an owned value is its own root, a borrowed value has
the roots recorded for it, anything else lives for the whole call. -/
def rootsOf (cc : CCtx) (σ : AbsState) (p : ValId) : List Root :=
  match cc.st p with
  | .owned => [.val p]
  | .borrowed => Rget σ p
  | _ => []

/-- The roots of the parents a certificate gives to a value. -/
def parentRoots (cc : CCtx) (σ : AbsState) (ps : List Root) : List Root :=
  normRoots (ps.flatMap fun p => match p with
    | .val n => rootsOf cc σ n
    | .caller i => [.caller i]
    | .slot n k => [.slot n k]
    | .fwd n => [.fwd n])

/-- The roots of the borrowed result of `i`: a view of one slot of an owned container is
rooted at that slot (it ends when the slot is taken or stored into, or the container is
consumed, design §3 Project); every other parent contributes its own roots. -/
def resultRoots (cc : CCtx) (σ : AbsState) (i : Inst) : List Root :=
  normRoots ((cc.pd i).flatMap fun p => match p with
    | .val n =>
      if forwardTakeWith (fun x => cc.defOf[x]?) cc.c i n then [.fwd n]
      else if i.cls == .project && cc.st n == .owned && i.reads.head? == some n then
        (match i.slot with
          | some k => [.slot n k]
          | none => [.val n])
      else rootsOf cc σ n
    | .caller j => [.caller j]
    | .slot n k => [.slot n k]
    | .fwd n => [.fwd n])

/-- Owners became other owners (owned phis or a constructor took them over): the storage stays
where it is, so a root that named an old owner now names its new holder.  All moves happen at
once.  A slot of an owner is the same slot of the new holder after a phi, and some unknown slot
of it after a constructor (`wild`). -/
def renameRoot1 (moves : List (ValId × ValId)) (wild : Bool) : Root → Root
  | .val n => match moves.lookup n with
    | some h => .val h
    | none => .val n
  | .slot n k => match moves.lookup n with
    | some h => .slot h (if wild then "*" else k)
    | none => .slot n k
  | .caller j => .caller j
  | .fwd n => .fwd n

/-- Every recorded root renamed (see `renameRoot1`). -/
def renameAll (R : List (ValId × List Root)) (moves : List (ValId × ValId)) (wild : Bool) :
    List (ValId × List Root) :=
  R.map fun p => (p.1, normRoots (p.2.map (renameRoot1 moves wild)))

/-- The roots recorded for the borrowed values still in `D` and the owned values still in `L`
(an owned value that holds loans is recorded too). -/
def keepR (σ : AbsState) (D L : List ValId) : List (ValId × List Root) :=
  σ.R.filter fun p => D.contains p.1 || L.contains p.1

/-- The loans of the owned holders move with their values: the holder `o` is now `h`. -/
def moveHolders (R : List (ValId × List Root)) (moves : List (ValId × ValId)) :
    List (ValId × List Root) :=
  (R.filterMap fun p => (moves.lookup p.1).map fun h => (h, p.2)) ++
    R.filter fun p => (moves.lookup p.1).isNone && !moves.any (·.2 == p.1)

/-- A holder does not hold a loan on itself. -/
def dropSelf (R : List (ValId × List Root)) (h : ValId) : List (ValId × List Root) :=
  R.map fun p => if p.1 == h then
      (p.1, p.2.filter fun r => match r with
        | .val n => n != h
        | .slot n _ => n != h
        | .caller _ => true
        | .fwd _ => true)
    else p

/-! ## Guarded takes and decided tests (design §5)

A take that is open on one of the paths that met at a join and not on the others carries the
test that tells the paths apart.  The test came out `pol` exactly when the take is open. -/

/-- The state of one slot of a container at a point: open, not open, or open exactly when a
test came out one way. -/
inductive SlotVal where
  | open_
  | closed
  | guarded (key : Key) (pol : Bool)
  deriving DecidableEq, Repr

/-- The outcome a decided test has in the state, if it has one. -/
def AbsState.fact (σ : AbsState) (key : Key) : Option (Option Bool) :=
  (σ.F.find? (·.1 == key)).map (·.2)

/-- Open takes whose test is decided leave `G`: an open one joins `P`, the others are dropped. -/
def resolveG (σ : AbsState) : AbsState :=
  { σ with
    P := σ.G.filterMap (fun g => match σ.fact g.2.2.1 with
      | some (some p) => if p == g.2.2.2 then some (g.1, g.2.1) else none
      | _ => none) ++ σ.P,
    G := σ.G.filter fun g => match σ.fact g.2.2.1 with
      | some (some _) => false
      | _ => true }

/-- What the state says of a slot. -/
def AbsState.slotVal (σ : AbsState) (c : ValId) (k : String) : SlotVal :=
  if σ.P.contains (c, k) then .open_
  else
    match σ.G.find? (fun g => g.1 == c && g.2.1 == k) with
    | some g => .guarded g.2.2.1 g.2.2.2
    | none => .closed

/-- Every slot the state mentions. -/
def AbsState.slots (σ : AbsState) : List (ValId × String) :=
  σ.P ++ σ.G.map fun g => (g.1, g.2.1)

/-! ## Usability (J3, J4) -/

/-- Whether a root is still alive: an owned root is in `L`; the caller keeps its allocation
alive for the whole call. -/
def rootLive (σ : AbsState) : Root → Bool
  | .val n => σ.L.contains n
  | .caller _ => true
  | .slot n _ => σ.L.contains n
  | .fwd n => σ.L.contains n

/-- A loan an owned value lists is on an allocation that is still there: an owned loan operand is
live, a borrowed one is usable (defined, all its roots alive). -/
def loanAlive (cc : CCtx) (σ : AbsState) : Root → Bool
  | .val n =>
    match cc.st n with
    | .owned => σ.L.contains n
    | .borrowed => σ.D.contains n && (Rget σ n).all (rootLive σ)
    | _ => true
  | _ => true

/-- A value is usable at a point (design §2): a scalar, an immortal or a stack value always
(and an emptied aggregate, which only takes read); an owned value when it is in `L`, every loan
it holds is on an allocation that is still there (the roots recorded for it are alive and the loan
operands it lists are usable); a borrowed value when it is defined on every path here and all its
owned roots are alive. -/
def usable (cc : CCtx) (σ : AbsState) (v : ValId) : Bool :=
  match cc.st v with
  | .scalar => true
  | .immortal => true
  | .stack => true
  | .emptied => true
  | .owned => σ.L.contains v && (Rget σ v).all (rootLive σ) && (cc.c.parents v).all (loanAlive cc σ)
  | .borrowed => σ.D.contains v && (Rget σ v).all (rootLive σ)
  | .none => false

/-! ## Instructions (J1-J8) -/

/-- A take (design §3, slots): a `Project` whose state is `owned` or `emptied`. -/
def isTakeI (cc : CCtx) (i : Inst) : Bool :=
  i.cls == .project && (cc.sd i == .owned || cc.sd i == .emptied)

/-- The slot a take reads, with its container (the first operand it reads). -/
def takeSlot (i : Inst) : Option (ValId × String) :=
  match i.reads.head?, i.slot with
  | some c, some k => some (c, k)
  | _, _ => none

/-- The class table of design §3, reduced to what a certificate can say about the result of an
instruction: the states and consumption its class allows. This part of J1 enforces the
exporter's table (A1); the soundness proof does not need it. -/
def classOk (cc : CCtx) (i : Inst) : Bool :=
  let sd := cc.sd i
  -- the stated class is the class table's
  !i.misclassified &&
  -- a unit value that an instruction names has a name and the state `none` (design §4.1)
  (i.dst.isSome == (sd != .none) || ((i.cls == .constant || i.cls == .call) && i.dst.isSome)) &&
  match i.cls with
  | .parameter =>
    -- a `param` the exporter placed in a block re-reads an argument: the value is already
    -- defined at entry, so it must be one of the parameters, and nothing else changes
    i.consumes.isEmpty && i.reads.isEmpty &&
      (match i.dst with
        | some d => cc.f.paramVals.contains d
        | none => false)
  | .constant =>
    i.consumes.isEmpty && i.reads.isEmpty &&
      (if i.op == "undef" then sd == .none || sd == .scalar || sd == .immortal
       else sd == .scalar || sd == .immortal)
  | .join => false
  | .forward => false
  | .jump => false
  | .branch => false
  | .ret => false
  | .trap => false
  | .pure => sd == .scalar && i.consumes.isEmpty
  | .inspect => sd == .scalar && i.consumes.isEmpty
  | .output => sd == .none && i.consumes.isEmpty
  | .trace => sd == .none && i.consumes.isEmpty
  | .fresh => (sd == .owned || sd == .stack) && i.consumes.isEmpty
  | .copy => (sd == .owned || sd == .scalar) && i.consumes.isEmpty
  | .project =>
      i.consumes.isEmpty &&
        (sd == .scalar || sd == .borrowed ||
          ((sd == .owned || sd == .emptied) && i.slot.isSome && !i.reads.isEmpty))
  | .view => i.consumes.isEmpty && (sd == .scalar || sd == .borrowed)
  | .borrow => i.consumes.isEmpty && (sd == .scalar || sd == .borrowed)
  | .textFrame => i.consumes.isEmpty && (sd == .scalar || sd == .borrowed)
  | .character => (sd == .owned || sd == .immortal) && i.consumes.isEmpty
  | .update =>
      match i.consumes.head? with
      | some k =>
        if cc.st k == .stack then sd == .stack
        else sd == .owned || sd == .scalar || sd == .emptied
      | none => false
  | .construct => sd == .owned || sd == .scalar || sd == .borrowed || sd == .emptied
  | .take => i.consumes.length == 1 && (sd == .owned || sd == .scalar || sd == .emptied)
  | .drop => i.consumes.length == 1 && sd == .none
  | .call => sd == .none || sd == .scalar || sd == .owned || sd == .borrowed || sd == .emptied

/-- A take out of the container the instruction (or a view it reads) is a view of, defined
later: the view is written first and the owner taken out of the aggregate follows (design §3,
Project). A projection of the view then borrows from the owner that took its place. -/
def forwardTake (cc : CCtx) (i : Inst) (n : ValId) : Bool :=
  forwardTakeWith (fun x => cc.defOf[x]?) cc.c i n

/-- Whether `n` is one of the `from` values of the call that the value `a` is, or that `a` is projected from
by projections (design §3, Project: a view reached from a call result borrows what the callee's `from`
contract names).  The call may return an `emptied` record, which lists no parents of its own.  The fuel stops
a cycle of definitions. -/
def callFromOperand (cc : CCtx) : Nat → ValId → ValId → Bool
  | 0, _, _ => false
  | fuel + 1, a, n =>
    match cc.defOf[a]? with
    | some d =>
      if d.cls == .call then d.fromVals.contains n
      else if d.cls == .project then
        match d.reads.head? with
        | some b => callFromOperand cc fuel b n
        | none => false
      else false
    | none => false

/-- Whether `n` is an operand the instruction reads, a parent of a read operand that is
borrowed or an owned call result holding loans (a projection of such a value is lent by the
same owners, design §3, Project), a later take of the container it reads, or, for a projection, a `from`
value of the call its container comes from (`callFromOperand`). -/
def parentOperand (cc : CCtx) (i : Inst) (n : ValId) : Bool :=
  i.reads.contains n ||
    i.reads.any (fun a => (cc.st a == .borrowed || cc.st a == .owned) &&
      (cc.c.parents a).contains (.val n)) ||
    forwardTake cc i n ||
    (i.cls == .project && match i.reads.head? with
      | some a => callFromOperand cc (cc.f.nvals + 1) a n
      | none => false)

/-- Parents are written only for borrowed values (and as loans on owned aggregates), and an
instruction borrows only from operands it reads, or from the owners a read operand borrows
from (J1; the premise the proof needs for J4's borrowed results). -/
def parentsOk (cc : CCtx) (i : Inst) : Bool :=
  let pd := cc.pd i
  let sd := cc.sd i
  if sd == .borrowed then
    pd.all fun p => match p with
      | .val n => parentOperand cc i n
      | .caller _ => false
      | .slot _ _ => false
      | .fwd _ => false
  else if sd == .owned then
    pd.all fun p => match p with
      | .val n => i.reads.contains n
      | .caller _ => false
      | .slot _ _ => false
      | .fwd _ => false
  else pd.isEmpty

/-- Every parent of a borrowed result is usable where the result is defined (J4), except a take
that comes later. -/
def parentsUsable (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  (cc.pd i).all fun p => match p with
    | .val n => usable cc σ n || forwardTake cc i n
    | .caller _ => true
    | .slot _ _ => false
    | .fwd _ => false

/-- J7: a stack value is consumed only by an update whose result is the same stack list (a
filling push), and a stack list holds no managed elements: what is pushed into it is not an
owned, emptied or stack value (the pass schedules no destruction for a stack list, so an owned
element would leak). -/
def stackOk (cc : CCtx) (i : Inst) : Bool :=
  (i.consumes.all fun k =>
    cc.st k != .stack ||
      (i.cls == .update && i.consumes.head? == some k && cc.sd i == .stack)) &&
  (!(i.consumes.any fun k => cc.st k == .stack) ||
    i.consumes.tail.all fun s => !(cc.st s == .owned || cc.st s == .emptied || cc.st s == .stack))

/-- J8, take: the container of a take is owned and live with the slot not pending, or an
`emptied` aggregate (its takes are complete moves). -/
def takeOk (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  !isTakeI cc i ||
    match takeSlot i with
    | some (c, k) =>
      cc.st c == .emptied || (cc.st c == .owned && σ.L.contains c && !σ.slotOpen c k)
    | none => false

/-- J8, closing: the store or pop of an open take agrees with its `released` mark
(`closeAgrees`, shared with the semantics). -/
def closeOk (_cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  if !i.isClosing then true
  else
    match i.consumes.head? with
    | none => false
    | some c =>
      -- a slot whose state still depends on an undecided test cannot be closed
      (queriedKeys i).all (fun k => !σ.G.any fun g => g.1 == c && g.2.1 == k) &&
      closeAgrees (fun k => σ.P.contains (c, k)) i

/-- J8, consuming a container: while a take is open on it, only the closing update consumes it
(as its first consumed operand). A closing update whose result is not owned has no other open
take to pass on. -/
def pendingOk (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  (cc.ownConsumed i).all (fun k =>
    !σ.pendingAny k || (i.isClosing && i.consumes.head? == some k)) &&
  (!i.isClosing ||
    match i.consumes.head? with
    | some c =>
      cc.sd i == .owned ||
        (!σ.P.any (fun p => p.1 == c && !(closedKeys i).contains p.2) &&
         !σ.G.any fun g => g.1 == c && !(closedKeys i).contains g.2.1)
    | none => true)

/-- A constructor that takes an owner into the aggregate it builds may also read a view of that
owner: an owned aggregate holds the view as a loan (it lists the view among its parents), and an
`emptied` one (a record built only to have its parts taken straight out) lists no parents at all;
either way the storage does not move (design §3, Construct; lane 1's entries 19 and 28). -/
def loanOfOwnedConstruct (cc : CCtx) (i : Inst) (o : ValId) : Bool :=
  i.cls == .construct &&
    (cc.sd i == .emptied || (cc.sd i == .owned && (cc.pd i).contains (.val o)))

/-- J1 `views` (format v2): only a constructor lists views, and each is an operand it reads. -/
def viewsOk (i : Inst) : Bool :=
  i.views.isEmpty || (i.cls == .construct && i.views.all fun v => i.reads.contains v)

/-- J6 `construct-read` (lane VAL, after lane FX6): a constructor whose result is owned or `emptied`, and that is not a
lend, reads a borrowed operand only when every root recorded for it is an owner the constructor consumes, or a slot of
one (the aggregate takes the owner over and reads a view of it, design entries 19 and 28), or when the result is owned
and lists the operand among its parents and among its `views` (an aggregate that holds a view as a loan, design §3,
Construct; a view is a value the aggregate's destruction does not destroy, format v2). A borrowed
operand with no recorded root satisfies neither. Otherwise the aggregate would destroy, or an owned take out of it would
hand out, storage it never received: the plan of FX6 freed a dictionary's keys twice that way. The model cannot show the
fault (a take out of an `emptied` aggregate yields a fresh tree, NOTES item 13), so the theorem does not use this check;
it is the Zig validator's rule, checked here so that the two checkers agree. -/
def constructReadOk (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  !(i.cls == .construct && i.lent.isNone && (cc.sd i == .owned || cc.sd i == .emptied)) ||
    i.reads.all fun r =>
      cc.st r != .borrowed ||
        (cc.sd i == .owned && (cc.pd i).contains (.val r) && i.views.contains r) ||
        (!(Rget σ r).isEmpty && (Rget σ r).all fun ρ => (cc.ownConsumed i).any fun k => ρ.ownedBy k)

/-- J1, a lend (design §10.2): `lent %G` appears only on a constructor that reads the lender and
the group `%G`, in that order, consumes nothing, is owned and has no parents; the group is an owned
value other than the lender. -/
def lendOk (cc : CCtx) (i : Inst) : Bool :=
  match i.lent with
  | none => true
  | some g =>
    i.cls == .construct && i.consumes.isEmpty && cc.sd i == .owned && (cc.pd i).isEmpty &&
      i.reads.length == 2 && i.reads[1]? == some g && i.reads[0]? != some g && cc.st g == .owned

/-- The roots a lend hands to its group: those of the lender (its first operand). -/
def lentRoots (cc : CCtx) (σ : AbsState) (i : Inst) : List Root :=
  match i.lent, i.reads.head? with
  | some _, some a => rootsOf cc σ a
  | _, _ => []

/-- J2, the join (design §10.4): a group, an owned value that has been lent to (the state records it
as a loan the group holds on itself), is consumed only by a call that returns nothing
(`myl_core_owned_group_end`), never by a constructor, an update, a take, a drop or a call with a
result. -/
def groupJoinOk (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  (cc.ownConsumed i).all fun k =>
    !(Rget σ k).contains (.val k) || (i.cls == .call && cc.sd i == .none)

/-- The slot a take of an owned container opens: the slot roots it ends. -/
def takenSlot (cc : CCtx) (i : Inst) : Option (ValId × String) :=
  if isTakeI cc i then
    match takeSlot i with
    | some (c, k) => if cc.st c == .owned then some (c, k) else none
    | none => none
  else none

/-- The owners an instruction destroys or invalidates: what it consumes, except that a
constructor with an owned result moves the trees it takes into the aggregate it builds, so the loans
on them move too; one with an `emptied` result destroys them (design §9, entry 41). -/
def dyingOwners (cc : CCtx) (i : Inst) : List ValId :=
  if i.cls == .construct && cc.sd i == .owned then [] else cc.ownConsumed i

/-- Whether the root ends at the instruction: its owner dies, or its slot is taken (a taken slot
and the wildcard slot of the same container). -/
def Root.endsAt (dying : List ValId) (taken : Option (ValId × String)) : Root → Bool
  | .val n => dying.contains n
  | .slot n k => dying.contains n ||
      (match taken with
        | some (c, kk) => c == n && (k == kk || k == "*")
        | none => false)
  | .caller _ => false
  | .fwd _ => false

/-- Whether the instruction hands the loans of what it consumes on to an owned result: every
instruction with an owned result does, except a take (**A13**: a take moves a part out of an aggregate,
and the checker cannot tell a part that holds a view from one that holds nothing). -/
def carries (cc : CCtx) (i : Inst) : Bool := cc.sd i == .owned && !i.dropsLoans

/-- J4, loans on owned aggregates: no owned value that is still live holds a loan whose root
ends at this instruction.  A holder the instruction consumes is exempt only if its loans end with it
(`carries` is false: the result is not owned, or the instruction is a take); one handed on to an owned
result keeps its loans, which must not end (C3.8). -/
def loansOk (cc : CCtx) (σ : AbsState) (i : Inst) : Bool :=
  let dying := dyingOwners cc i
  let taken := takenSlot cc i
  σ.L.all fun x => ((cc.ownConsumed i).contains x && !carries cc i) ||
    (Rget σ x).all fun r => !r.endsAt dying taken

/-! ## Calls name their callee (C9.2, design entry 57) -/

/-- The callee entry of a call line (none for another class, or when the line names none). -/
def CCtx.entryOf (cc : CCtx) (i : Inst) : Option CalleeEntry := cc.f.entryOf i

/-- J1 `call-entry`: a call line names an entry of its function's table, and the entry is an indirect one iff the line
is a `call_indirect`; no other line names an entry. -/
def callEntryOk (cc : CCtx) (i : Inst) : Bool :=
  if i.cls == .call then
    match cc.entryOf i with
    | some e => (e.kind == .indirect) == (i.op == "call_indirect")
    | none => false
  else i.entry.isNone

/-- J1 `call-arity`: the call consumes as many values as the callee takes and reads as many as it does not (an
indirect call reads its function value besides). -/
def callArityOk (cc : CCtx) (i : Inst) : Bool :=
  i.cls != .call ||
    match cc.entryOf i with
    | some e =>
      i.consumes.length == (e.params.filter (·.takes)).length &&
      i.reads.length == (e.params.filter (fun t => !t.takes)).length + (if e.kind == .indirect then 1 else 0)
    | none => true

/-- Whether the entry is judged against the call line: a program callee or a call through a function value (A5
judges a runtime function, an extern function and a marker). -/
def CalleeEntry.judged (e : CalleeEntry) : Bool := e.kind == .program || e.kind == .indirect

/-- J1 `call-scalar`: an argument of a parameter whose value the callee's certificate calls scalar is a scalar, an
immortal or a unit value (A9). -/
def callScalarOk (cc : CCtx) (i : Inst) : Bool :=
  i.cls != .call ||
    match cc.entryOf i with
    | some e =>
      !e.judged ||
        ((i.argsOf e).zip e.params).all fun (a, t) =>
          !t.scalarVal || cc.st a.1 == .scalar || cc.st a.1 == .immortal || cc.st a.1 == .none
    | none => true

/-- J1 `call-result`: the value of the call follows what the callee returns: an owned or `emptied` value needs an owner
result, a borrowed value a borrowed result, anything else (a scalar, an immortal, a unit value, no value) a scalar result
(a unit function returns `scalar`). -/
def callResultOk (cc : CCtx) (i : Inst) : Bool :=
  i.cls != .call ||
    match cc.entryOf i with
    | some e =>
      !e.judged ||
        match i.dst with
        | none => e.result == .scalar
        | some d =>
          match cc.st d with
          | .owned => e.result == .owned
          | .emptied => e.result == .owned
          | .borrowed => e.result == .borrowed
          | .stack => true
          | _ => e.result == .scalar
    | none => true

/-- J1 `call-from`: a borrowed value of the call lists, as parents, the argument at each position of the callee's
borrow contract that is an owned or borrowed value; the position is a read parameter. -/
def callFromOk (cc : CCtx) (i : Inst) : Bool :=
  i.cls != .call ||
    match cc.entryOf i with
    | some e =>
      !e.judged ||
        match i.dst with
        | some d =>
          cc.st d != .borrowed ||
            e.from_.all fun p =>
              match (i.argsOf e)[p]?, e.params[p]? with
              | some a, some t =>
                !t.takes && (cc.st a.1 == .scalar || cc.st a.1 == .immortal || cc.st a.1 == .none ||
                  (cc.c.parents d).contains (.val a.1))
              | _, _ => false
        | none => true
    | none => true

/-- J1 `callee-table`, at the signature: the entries are numbered 0, 1, 2, ... in order, an entry has the name `-` iff
it is an indirect one, and a position of a borrow contract is a parameter of the entry. -/
def calleeTableOk (cc : CCtx) : Bool :=
  (cc.f.callees.zipIdx).all fun (e, n) =>
    e.id == n && ((e.name == "-") == (e.kind == .indirect)) && e.from_.all (· < e.params.length)

/-- The checks of one instruction at state `σ`, in the order they are reported. -/
def instChecks (cc : CCtx) (σ : AbsState) (i : Inst) : List Chk :=
  let oc := cc.ownConsumed i
  [ (.j1, "classOk", classOk cc i),
    (.j1, "lend", lendOk cc i),
    (.j1, "views", viewsOk i),
    (.j1, "parentsOk", parentsOk cc i),
    (.j1, "call-entry", callEntryOk cc i),
    (.j1, "call-arity", callArityOk cc i),
    (.j1, "call-scalar", callScalarOk cc i),
    (.j1, "call-result", callResultOk cc i),
    (.j1, "call-from", callFromOk cc i),
    -- J3 / J4: every operand read is usable
    (.j3, "read-usable", i.reads.all fun r => cc.st r == .borrowed || usable cc σ r),
    (.j4, "read-borrowed-usable", i.reads.all fun r => cc.st r != .borrowed || usable cc σ r),
    (.j4, "parents-usable", parentsUsable cc σ i),
    -- J5: no borrowed value is consumed
    (.j5, "consume-borrowed", i.consumes.all fun k => cc.st k != .borrowed),
    -- J2: a consumed owned value is live; a scalar, an immortal, a stack value or a void value
    -- (state `none`: a void-typed `undef` stored into a set) is a no-op
    (.j2, "consume-live", i.consumes.all fun k =>
      match cc.st k with
      | .owned => σ.L.contains k
      | .scalar => true
      | .immortal => true
      | .stack => true
      | .borrowed => true
      | .emptied => false
      | .none => true),
    -- J2: a group is consumed only by its join
    (.j2, "group-join", groupJoinOk cc σ i),
    -- J7
    (.j7, "stack", stackOk cc i),
    -- J6: one instruction never takes what it also reads
    (.j6, "consume-twice", nodupB oc),
    (.j6, "consume-and-read", oc.all fun k => !i.reads.contains k),
    (.j6, "consume-root-of-operand", oc.all fun k => (i.reads ++ i.consumes).all fun o =>
      o == k || !(rootsOf cc σ o).any (·.ownedBy k) || loanOfOwnedConstruct cc i o),
    (.j6, "construct-read", constructReadOk cc σ i),
    -- J8: the take protocol
    (.j8, "take", takeOk cc σ i),
    (.j8, "pending", pendingOk cc σ i),
    (.j8, "close", closeOk cc σ i),
    -- J4: a loan held by a live aggregate ends with its root
    (.j4, "loan-outlives-root", loansOk cc σ i),
    -- J8: redefining a value a guard depends on loses the guard
    (.j8, "guard-redefined", match i.dst with
      | some d => i.cls == .parameter || !σ.G.any fun g => g.2.2.1.mentions d
      | none => true),
    -- J2: a defined owned value is new
    (.j2, "dst-fresh", i.cls == .parameter || match i.dst with
      | some d => !(cc.st d).owning || !σ.L.contains d
      | none => true),
    -- J3: no operand read is the null owner (an `undef` of a managed type, lane FX12)
    (.j3, "read-null-owner", i.reads.all fun r => !cc.nullOwner r) ]

/-- The first failing check of an instruction. -/
def instFail (cc : CCtx) (σ : AbsState) (i : Inst) : Option (J × String) :=
  firstFail (instChecks cc σ i)

/-- The open takes after an instruction: consumed containers leave `P`; the closing update
passes the container's other open takes on to the container it returns; a take of an owned
container opens its slot. -/
def nextP (cc : CCtx) (σ : AbsState) (i : Inst) : List (ValId × String) :=
  let oc := cc.ownConsumed i
  let kept := σ.P.filter fun p => !oc.contains p.1
  let passed :=
    match i.dst, i.consumes.head? with
    | some d, some c =>
      if i.isClosing && cc.sd i == .owned then
        (σ.P.filter fun p => p.1 == c && !(closedKeys i).contains p.2).map fun p => (d, p.2)
      else []
    | _, _ => []
  let opened :=
    match takenSlot cc i with
    | some (c, k) => [(c, k)]
    | none => []
  opened ++ passed ++ kept

/-- The guarded takes after an instruction: they move with their container like `nextP`. -/
def nextG (cc : CCtx) (σ : AbsState) (i : Inst) : List (ValId × String × Key × Bool) :=
  let oc := cc.ownConsumed i
  let kept := σ.G.filter fun g => !oc.contains g.1
  let passed :=
    match i.dst, i.consumes.head? with
    | some d, some c =>
      if i.isClosing && cc.sd i == .owned then
        (σ.G.filter fun g => g.1 == c && !(closedKeys i).contains g.2.1).map fun g =>
          (d, g.2.1, g.2.2.1, g.2.2.2)
      else []
    | _, _ => []
  passed ++ kept

/-- The decided tests after an instruction: defining a value forgets the tests that depend on
it. -/
def nextF (σ : AbsState) (i : Inst) : List (Key × Option Bool) :=
  match i.dst with
  | some d => σ.F.filter fun f => !f.1.mentions d
  | none => σ.F

/-- The borrowed names that survive the slot an instruction takes: a view rooted at that slot
ends. -/
def instD0 (cc : CCtx) (σ : AbsState) (i : Inst) : List ValId :=
  match takenSlot cc i with
  | none => σ.D
  | some tk => σ.D.filter fun w => (Rget σ w).all fun r => !r.endsAt [] (some tk)

/-- The state after an instruction that passed its checks: consumed values leave `L`, an
owned result enters `L` (taking over the owners a constructor consumed, whose roots now name
it, and the loans they held) and every borrowed name that depends on the value it redefines,
or lives in a slot it takes, leaves `D`; a borrowed result enters `D` with the roots of its
parents; the open takes move (`nextP`, `nextG`). -/
def instNext (cc : CCtx) (σ : AbsState) (i : Inst) : AbsState :=
  if i.cls == .parameter then σ else
  let oc := cc.ownConsumed i
  let L1 := without σ.L oc
  let P2 := nextP cc σ i
  let G2 := nextG cc σ i
  let F2 := nextF σ i
  let D0 := instD0 cc σ i
  match i.dst with
  | none => { σ with L := L1, D := D0, P := P2, G := G2, F := F2 }
  | some d =>
    match cc.st d with
    | .owned =>
      let D1 := D0.filter fun w => !(Rget σ w).any (·.ownedBy d)
      let isC := i.cls == .construct
      let moved := if isC then oc.map (·, d) else []
      -- an owned result keeps the loans of the owners it consumes: a constructor takes the trees into the
      -- aggregate, any other instruction hands the cells it keeps on; a take is the exception (A13)
      let inherited := if !i.dropsLoans then oc.flatMap (Rget σ ·) else []
      -- a lend hands the roots of its lender to the box and to the group it is lent to (§10.3)
      let lent := lentRoots cc σ i
      let loans := normRoots (parentRoots cc σ (cc.pd i) ++ inherited ++ lent)
      let R1 := (d, loans) :: σ.R.filter fun p => p.1 != d
      let R2 := match i.lent with
        | some b => (b, normRoots (Rget σ b ++ (.val b :: lent))) :: R1.filter fun p => p.1 != b
        | none => R1
      { L := d :: L1, D := D1,
        R := if isC then dropSelf (renameAll R2 moved true) d else R2,
        P := P2, G := G2, F := F2 }
    | .borrowed =>
      { L := L1, D := d :: D0.filter (· != d),
        R := (d, resultRoots cc σ i) :: σ.R.filter fun p => p.1 != d,
        P := P2, G := G2, F := F2 }
    | _ => { σ with L := L1, D := D0, P := P2, G := G2, F := F2 }

/-- Run the checks over the instructions of a block from position `k`. -/
def runInsts (cc : CCtx) (b : BlockId) : Nat → AbsState → List Inst → Except Failure AbsState
  | _, σ, [] => .ok σ
  | k, σ, i :: is =>
    match instFail cc σ i with
    | some jw => .error { j := jw.1, blk := some b, idx := some k, why := jw.2 }
    | none => runInsts cc b (k + 1) (instNext cc σ i) is

/-! ## Edges and phis (J1, J2, J4, J8) -/

/-- The phis that carry a value: a dead phi (state `none`) is skipped (design §3, Phis). -/
def livePhis (cc : CCtx) (phis : List Phi) : List Phi :=
  phis.filter (Phi.live cc.c)

/-- Whether the phi operand `o` fits the phi's state (design §3, "Phis"): an owned phi takes
owned or immortal operands (an `undef` of a managed type is immortal: the null owner), a
stack phi takes stack operands, a borrowed phi takes borrowed or immortal operands or the
owned value it selects between. -/
def phiShape (cc : CCtx) (φ : Phi) (o : ValId) : Bool :=
  match cc.st φ.dst with
  | .scalar => cc.st o == .scalar
  | .immortal => cc.st o == .immortal
  | .owned => cc.st o == .owned || cc.st o == .immortal
  | .stack => cc.st o == .stack
  | .borrowed => cc.st o == .borrowed || cc.st o == .immortal || cc.st o == .owned
  | .emptied => false
  | .none => false

/-- The operand each live phi takes along the edge from `b`. -/
def edgeOps (cc : CCtx) (b : BlockId) (phis : List Phi) : List (Phi × ValId) :=
  (livePhis cc phis).filterMap fun φ => (φ.edges.lookup b).map (φ, ·)

/-- The owners the edge's owned phis take over: operand and phi value. -/
def edgeMoves (cc : CCtx) (b : BlockId) (phis : List Phi) : List (ValId × ValId) :=
  ((edgeOps cc b phis).filter fun p => (cc.st p.1.dst).owning && (cc.st p.2).owning).map
    fun p => (p.2, p.1.dst)

/-- The operands the edge consumes: those of owned phis that are owned. -/
def edgeConsumed (cc : CCtx) (b : BlockId) (phis : List Phi) : List ValId :=
  (edgeMoves cc b phis).map (·.1)

/-- The owned values the phis define. -/
def edgeDsts (cc : CCtx) (phis : List Phi) : List ValId :=
  ((livePhis cc phis).filter fun φ => (cc.st φ.dst).owning).map (·.dst)

/-- The borrowed values the phis define. -/
def edgeBdsts (cc : CCtx) (phis : List Phi) : List ValId :=
  ((livePhis cc phis).filter fun φ => cc.st φ.dst == .borrowed).map (·.dst)

/-- The checks of the edge from block `b` into a block with phis `phis`, at the state `σ`
at the end of `b`. -/
def edgeChecks (cc : CCtx) (σ : AbsState) (b : BlockId) (phis : List Phi) : List Chk :=
  let live := livePhis cc phis
  let ops := edgeOps cc b phis
  let consumed := edgeConsumed cc b phis
  let dsts := edgeDsts cc phis
  [ (.j1, "phi-operand", ops.length == live.length),
    (.j1, "phi-dst-twice", nodupB (live.map (·.dst))),
    (.j1, "phi-shape", ops.all fun p => phiShape cc p.1 p.2),
    (.j1, "phi-parents", ops.all fun p => cc.st p.1.dst == .borrowed || (cc.c.parents p.1.dst).isEmpty),
    -- the operand an owned phi consumes is live
    (.j2, "phi-consume-live", ops.all fun p => !(cc.st p.2).owning || !(cc.st p.1.dst).owning || σ.L.contains p.2),
    -- the operand a borrowed phi reads is usable
    (.j4, "phi-read-usable", ops.all fun p => cc.st p.1.dst != .borrowed || usable cc σ p.2),
    (.j2, "phi-consume-twice", nodupB consumed),
    -- a container with an open take cannot move through a phi
    (.j8, "phi-pending", consumed.all fun o => !σ.pendingAny o),
    -- a guard that depends on a value the phis define is lost
    (.j8, "guard-redefined", σ.G.all fun g => live.all fun φ => !g.2.2.1.mentions φ.dst),
    -- a phi's owned value is new
    (.j2, "phi-dst-fresh", dsts.all fun d => !(without σ.L consumed).contains d) ]

/-- The roots of the borrowed phi values: those of their operand on this edge, renamed. -/
def edgeFresh (cc : CCtx) (σ : AbsState) (b : BlockId) (phis : List Phi) :
    List (ValId × List Root) :=
  ((edgeOps cc b phis).filter fun p => cc.st p.1.dst == .borrowed).map
    fun p => (p.1.dst,
      normRoots ((rootsOf cc σ p.2).map (renameRoot1 (edgeMoves cc b phis) false)))

/-- The state after the edge: consumed operands leave `L` and their owners' roots now name the
phi that took them over (and the loans they held), owned phi values enter `L`, borrowed phi
values enter `D` with the roots of their operand on this edge (V5, R6), every name that depends
on a value the edge redefines leaves `D`, and so does every test that depends on one. -/
def edgeNext (cc : CCtx) (σ : AbsState) (b : BlockId) (phis : List Phi) : AbsState :=
  let consumed := edgeConsumed cc b phis
  let dsts := edgeDsts cc phis
  let bdsts := edgeBdsts cc phis
  let moves := edgeMoves cc b phis
  let D1 := σ.D.filter fun w => !bdsts.contains w && dsts.all fun d => !(Rget σ w).any (·.ownedBy d)
  let phiDsts := (livePhis cc phis).map (·.dst)
  { L := dsts ++ without σ.L consumed, D := bdsts ++ D1,
    R := edgeFresh cc σ b phis ++ renameAll (moveHolders σ.R moves) moves false,
    P := σ.P, G := σ.G,
    F := σ.F.filter fun f => phiDsts.all fun d => !f.1.mentions d }

/-- Successors of a terminator. -/
def Term.succs : Term → List BlockId
  | .jump b => [b]
  | .branch _ t f => [t, f]
  | .ret _ => []
  | .unreachable => []

/-- The state after an edge abandons the owners `A` (C9.1, design entry 55): they leave `L`, and the open and
guarded takes of an abandoned container leave `P` and `G`.  Nothing else changes: `D` and `R` stay, so a view of an
abandoned owner, and an owned value that holds a loan on one, is no longer usable (its root is not live), the way a
drop ends it, and the loans an abandoned holder holds are not looked at again. -/
def AbsState.abandon (σ : AbsState) (A : List ValId) : AbsState :=
  { σ with L := without σ.L A, P := σ.P.filter (fun p => !A.contains p.1),
           G := σ.G.filter (fun g => !A.contains g.1) }

/-- The trap region (C9.1): the least fixpoint of "ends in `unreachable`, or has successors and all of them are in
the region".  `regionIn cc k b` holds when `b` is in the region by a derivation of depth below `k`. -/
def regionIn (cc : CCtx) : Nat → BlockId → Bool
  | 0, _ => false
  | k + 1, b =>
    match cc.f.block? b with
    | none => false
    | some blk =>
      match blk.term with
      | .unreachable => true
      | t => !t.succs.isEmpty && t.succs.all (regionIn cc k)

/-- Whether block `b` is in the trap region (a derivation has at most as many steps as the function has blocks). -/
def region (cc : CCtx) (b : BlockId) : Bool := regionIn cc (cc.f.blocks.length + 1) b

/-- The checks of the abandon list `A` of the edge into the block `b'` at the state `σ` at the end of the
predecessor (J2): only a trap-region block may abandon, an abandoned value is an owned value live on the edge, and a
group (a lent-to value) is never abandoned, because its tasks read the lent cells until the process ends. -/
def abandonChecks (cc : CCtx) (σ : AbsState) (b' : BlockId) (A : List ValId) : List Chk :=
  [ (.j2, "abandon-region", A.isEmpty || region cc b'),
    (.j2, "abandon-live", A.all fun a => cc.st a == .owned && σ.L.contains a),
    (.j2, "abandon-group", A.all fun a => !(Rget σ a).contains (.val a)) ]

/-- The state flowing into block `b'` from `b` at state `σ`: the edge abandons what the block's `abandon` line
for `b` names, then its phis take their operands.  An edge whose phi operand is an `undef` of a managed type is live
(design A3): the operand is the null owner, immortal. -/
def edgeTo (cc : CCtx) (b : BlockId) (σ : AbsState) (b' : BlockId) :
    Except (J × String) (Option AbsState) :=
  match cc.f.block? b' with
  | none => .error (.j1, "edge-target")
  | some blk' =>
    let A := blk'.abandonFrom b
    match firstFail (abandonChecks cc σ b' A) with
    | some jw => .error jw
    | none =>
      let σ1 := σ.abandon A
      match firstFail (edgeChecks cc σ1 b blk'.phis) with
      | some jw => .error jw
      | none => .ok (some (edgeNext cc σ1 b blk'.phis))

/-- The live outgoing edges of a block, with the state each carries, for a list of targets and
the state each is entered with. -/
def liveEdgesOf (cc : CCtx) (b : BlockId) :
    List (BlockId × AbsState) → Except (J × String) (List (BlockId × AbsState))
  | [] => .ok []
  | (t, σ) :: ts =>
    match edgeTo cc b σ t with
    | .error jw => .error jw
    | .ok none => liveEdgesOf cc b ts
    | .ok (some σe) =>
      match liveEdgesOf cc b ts with
      | .error jw => .error jw
      | .ok es => .ok ((t, σe) :: es)

/-- The state decided tests give a branch edge: the test the condition stands for came out
`pol`, which resolves the guarded takes of the same test; an edge the decided tests rule out
is not taken. -/
def withFact (cc : CCtx) (σ : AbsState) (c : ValId) (pol : Bool) : Option AbsState :=
  let key := cc.keyOf c
  match σ.F.find? (·.1 == key) with
  | some (_, some p) => if p == pol then some σ else none
  | _ => some (resolveG { σ with F := (key, some pol) :: σ.F.filter (·.1 != key) })

/-- The targets of a terminator with the state each is entered with. -/
def Term.targets (cc : CCtx) (σ : AbsState) : Term → List (BlockId × AbsState)
  | .jump b => [(b, σ)]
  | .branch c t f =>
    if t == f then [(t, σ), (f, σ)]
    else
      (match withFact cc σ c true with | some s => [(t, s)] | none => []) ++
      (match withFact cc σ c false with | some s => [(f, s)] | none => [])
  | .ret _ => []
  | .unreachable => []

/-- The live outgoing edges of block `b` at the state `σ` at its end. -/
def liveEdges (cc : CCtx) (b : BlockId) (σ : AbsState) (t : Term) :
    Except (J × String) (List (BlockId × AbsState)) :=
  liveEdgesOf cc b (t.targets cc σ)

/-- The checks of a terminator at state `σ` (J2, J3, J4, J5, J7, J8 at `ret`). -/
def termChecks (cc : CCtx) (σ : AbsState) : Term → List Chk
  | .jump _ => []
  | .unreachable => []
  | .branch c _ _ =>
    [ (.j3, "branch-usable", cc.st c == .borrowed || usable cc σ c),
      (.j4, "branch-borrowed-usable", cc.st c != .borrowed || usable cc σ c) ]
  | .ret none => [ (.j8, "ret-pending", σ.P.isEmpty && σ.G.isEmpty), (.j2, "ret-live", σ.L.isEmpty) ]
  | .ret (some v) =>
    match cc.f.result with
    | .owned =>
      [ (.j8, "ret-pending", σ.P.isEmpty && σ.G.isEmpty),
        (.j7, "ret-stack", cc.st v != .stack),
        (.j5, "ret-borrowed", cc.st v != .borrowed),
        (.j1, "ret-state", cc.st v == .owned || cc.st v == .immortal),
        -- the returned value is consumed, and nothing else is left
        (.j2, "ret-live", if cc.st v == .owned then σ.L == [v] else σ.L.isEmpty) ]
    | .borrowed =>
      [ (.j8, "ret-pending", σ.P.isEmpty && σ.G.isEmpty),
        (.j7, "ret-stack", cc.st v != .stack),
        (.j5, "ret-owned", cc.st v != .owned),
        (.j1, "ret-state", cc.st v == .borrowed || cc.st v == .immortal || cc.st v == .scalar),
        (.j4, "ret-usable", cc.st v != .borrowed || usable cc σ v),
        -- the returned value borrows only from the parameters named by `from`
        (.j5, "ret-from", cc.st v != .borrowed || (Rget σ v).all fun r => match r with
          | .caller i => cc.f.from_.contains i
          | .val _ => false
          | .slot _ _ => false
          | .fwd _ => false),
        (.j2, "ret-live", σ.L.isEmpty) ]
    | _ =>
      [ (.j8, "ret-pending", σ.P.isEmpty && σ.G.isEmpty),
        (.j7, "ret-stack", cc.st v != .stack),
        (.j1, "ret-state", cc.st v == .scalar || cc.st v == .immortal),
        (.j2, "ret-live", σ.L.isEmpty) ]

/-! ## The recheck (phase 2) -/

/-- The value an instruction defines that is new: a re-read of a parameter (`Parameter`) defines none. -/
def Inst.freshDst (i : Inst) : Option ValId := if i.cls == .parameter then none else i.dst

/-- The new values the instructions of a block define. -/
def blockDsts (blk : Block) : List ValId := blk.insts.filterMap Inst.freshDst

/-- Whether a guarded take of the entry state is what the edge state says: open when the test
came out as the guard says, closed when it came out the other way, the same guard while it is
undecided. -/
def guardFits (σe : AbsState) (g : ValId × String × Key × Bool) : Bool :=
  match σe.fact g.2.2.1 with
  | some (some p) =>
    if p == g.2.2.2 then σe.P.contains (g.1, g.2.1) else !σe.slotOpen g.1 g.2.1
  | some none => σe.G.contains g
  | none => false

/-- Whether the open and guarded takes of the edge state fit those of the entry state: what the
entry says is open is open on the edge; a guarded take fits (`guardFits`); an open take of the
edge is open in the entry, or guarded there under a test the edge decided that way; a guarded
take of the edge is guarded in the entry. -/
def slotsFit (σs σe : AbsState) : Bool :=
  σs.P.all (fun p => σe.P.contains p) &&
  σs.G.all (guardFits σe) &&
  σs.G.all (fun g => σs.L.contains g.1) &&
  σe.P.all (fun p => σs.P.contains p ||
    σs.G.any fun g => g.1 == p.1 && g.2.1 == p.2 && σe.fact g.2.2.1 == some (some g.2.2.2)) &&
  σe.G.all (fun g => σs.G.contains g)

/-- Whether the decided tests of the edge state fit those of the entry state: every test the
entry decides is decided on the edge, with the same outcome when the entry knows it. -/
def factsFit (σs σe : AbsState) : Bool :=
  σs.F.all fun f =>
    match σe.fact f.1 with
    | some pe => f.2.isNone || pe == f.2
    | none => false

/-- Why the state `σe` flowing into the ordinary block `s` does not fit the entry state `σs`
recorded for it. -/
def joinCompat (σs σe : AbsState) (s : BlockId) : Option (J × String) :=
  if !same σs.L σe.L then some (.j2, s!"join-live b{s}")
  else if !slotsFit σs σe then some (.j8, s!"join-pending b{s}")
  else if !factsFit σs σe then some (.j8, s!"join-tests b{s}")
  else if !sub σs.D σe.D then some (.j4, s!"join-defined b{s}")
  else if !(σs.D ++ σs.L).all (fun w => sub (Rget σe w) (Rget σs w)) then
    some (.j4, s!"join-roots b{s}")
  else none

/-- Why the state `σe` flowing into `s` does not fit the entry state recorded for `s`: every block's entry
state is the join of its edges (`joinCompat`); a trap region is no exception (C9.1: the owners a path leaks
are named by the `abandon` lines of the edge). -/
def compatErr (inn : BlockId → Option AbsState) (s : BlockId) (σe : AbsState) :
    Option (J × String) :=
  match inn s with
  | none => some (.j1, "no-entry-state")
  | some σs => joinCompat σs σe s

/-- Check block `b` from its recorded entry state: its instructions, its terminator and
every live edge leaving it. -/
def verifyBlock (cc : CCtx) (inn : BlockId → Option AbsState) (b : BlockId) : Option Failure :=
  match inn b, cc.f.block? b with
  | some σ, some blk =>
    match runInsts cc b 0 σ blk.insts with
    | .error fl => some fl
    | .ok σo =>
      let n := blk.insts.length
      match firstFail (termChecks cc σo blk.term) with
      | some jw => some { j := jw.1, blk := some b, idx := some n, why := jw.2 }
      | none =>
        match liveEdges cc b σo blk.term with
        | .error jw => some { j := jw.1, blk := some b, idx := some n, why := jw.2 }
        | .ok es =>
          es.findSome? fun e =>
            (compatErr inn e.1 e.2).map fun jw =>
              { j := jw.1, blk := some b, idx := some n, why := jw.2 }
  | _, _ => none

/-- Check the blocks in the list. -/
def verifyBlocks (cc : CCtx) (inn : BlockId → Option AbsState) : List BlockId → Option Failure
  | [] => none
  | b :: bs =>
    match verifyBlock cc inn b with
    | some fl => some fl
    | none => verifyBlocks cc inn bs

/-! ## The entry (parameters) and the function-wide checks -/

/-- The parameters' states follow the signature (J1): `scalar`, `owned` (or `scalar`: a value
of an unmanaged type passed to a taking parameter owns nothing), or `borrowed` from
`caller(i)`. -/
def paramsOk (c : Certificate) : Nat → List ValId → List St → Bool
  | _, [], [] => true
  | i, v :: vs, k :: ks =>
    (match k with
      | .scalar => c.state v == .scalar
      | .owned => c.state v == .owned || c.state v == .scalar
      | .borrowed => c.state v == .borrowed && c.parents v == [.caller i]
      | _ => false) && paramsOk c (i + 1) vs ks
  | _, _, _ => false

/-- A pseudo-block instruction defines a parameter or a constant (design §4.1); `undef` of a
void type defines no value. -/
def preInstOk (cc : CCtx) (i : Inst) : Bool :=
  i.reads.isEmpty && i.consumes.isEmpty &&
  match i.cls with
  | .parameter => i.dst.isSome
  | .constant =>
    if i.op == "undef" then cc.sd i == .none || cc.sd i == .scalar || cc.sd i == .immortal
    else i.dst.isSome && (cc.sd i == .scalar || cc.sd i == .immortal)
  | _ => false

/-- One use of a value: the block, whether it is the first read of a `Project`, and the slot
that `Project` takes. -/
structure Use where
  blk : Nat
  head : Bool
  slot : Option String
  deriving Repr

/-- Every use of every value of the function. -/
def usesOf (f : Function) : Std.HashMap ValId (List Use) :=
  let add := fun (m : Std.HashMap ValId (List Use)) (v : ValId) (u : Use) =>
    m.insert v (u :: m.getD v [])
  (f.blocks.zipIdx).foldl
    (fun m (blk, b) =>
      let m := blk.insts.foldl
        (fun m i =>
          let m := (i.reads.zipIdx).foldl
            (fun m (v, k) =>
              add m v { blk := b, head := i.cls == .project && k == 0 && !i.consumes.contains v,
                        slot := i.slot })
            m
          i.consumes.foldl (fun m v => add m v { blk := b, head := false, slot := none }) m)
        m
      let m := blk.phis.foldl
        (fun m φ => φ.edges.foldl (fun m e => add m e.2 { blk := b, head := false, slot := none }) m)
        m
      match blk.term with
      | .branch c _ _ => add m c { blk := b, head := false, slot := none }
      | .ret (some v) => add m v { blk := b, head := false, slot := none }
      | _ => m)
    {}

/-- J8, emptied aggregates (design §3, slots; §4.1 `slots`): an `emptied` value is defined by an
instruction, and every use of it is the first read of a projection in the block that defines
it; each of its `slots` is taken exactly once, and no other slot is taken. -/
def emptiedOk (cc : CCtx) : Bool :=
  let uses := usesOf cc.f
  (cc.f.blocks.zipIdx).all fun (blk, b) =>
    (blk.phis.all fun φ => cc.st φ.dst != .emptied) &&
    (blk.insts.all fun i =>
      match i.dst with
      | some e =>
        cc.st e != .emptied ||
          (let us := uses.getD e []
           us.all (fun u => u.head && u.blk == b) &&
           i.slots.all (fun k => (us.filter fun u => u.slot == some k).length == 1) &&
           us.all (fun u => match u.slot with
             | some k => i.slots.contains k
             | none => true))
      | none => true)

/-- The first instruction that misuses an `emptied` aggregate: it consumes it, reads it other than as
the container of a take, takes a slot already taken in its block, or takes a slot the aggregate does
not list.  This is where the Zig validator reports the misuse (`b0 3` for a second take, `b0 2` for a
consumption), where `emptiedOk` can only say that the function is wrong. -/
def emptiedBadUse (cc : CCtx) : Option (BlockId × Nat) :=
  (cc.f.blocks.zipIdx).findSome? fun (blk, b) =>
    (blk.insts.zipIdx).findSome? fun (i, k) =>
      let wholeUse := i.consumes.any (cc.st · == .emptied) ||
        (i.reads.zipIdx.any fun (v, j) => cc.st v == .emptied && !(i.cls == .project && j == 0))
      let badTake :=
        match i.reads.head?, i.slot with
        | some e, some slot =>
          i.cls == .project && cc.st e == .emptied &&
            (match cc.defOf[e]? with
             | some d0 => !d0.slots.contains slot ||
                 (blk.insts.take k).any fun j =>
                   j.cls == .project && j.reads.head? == some e && j.slot == some slot
             | none => false)
        | _, _ => false
      if wholeUse || badTake then some (b, k) else none

/-- The failure a failed function-wide check is reported as: a bad take of an `emptied` aggregate
is reported at the instruction. -/
def preFailure (cc : CCtx) (jw : J × String) : Failure :=
  match (if jw.2 == "emptied" then emptiedBadUse cc else none) with
  | some (b, k) => { j := jw.1, blk := some b, idx := some k, why := jw.2 }
  | none => { j := jw.1, blk := none, idx := none, why := jw.2 }

/-- Strictly ascending. -/
def strictAsc : List Nat → Bool
  | a :: b :: rest => a < b && strictAsc (b :: rest)
  | _ => true

/-- The first block whose `abandon` lines are not well formed (J1 `abandon-shape`, reported at the block, no
instruction): a line names a block that is not a predecessor, a predecessor twice, or values that are not strictly
ascending. -/
def abandonShapeBad (cc : CCtx) : Option BlockId :=
  (cc.f.blocks.zipIdx).findSome? fun (blk, b) =>
    if (blk.abandons.map (·.1)).all blk.preds.contains && nodupB (blk.abandons.map (·.1)) &&
        blk.abandons.all (fun a => strictAsc a.2) then none else some b

/-- The checks of the signature, the pseudo-block and the function as a whole. -/
def preChecks (cc : CCtx) : List Chk :=
  [ (.j1, "params-length", cc.f.params.length == cc.f.paramVals.length),
    (.j1, "params-states", paramsOk cc.c 0 cc.f.paramVals cc.f.params),
    (.j2, "params-twice", nodupB cc.f.paramVals),
    (.j1, "pre-block", cc.f.pre.all (preInstOk cc)),
    (.j1, "block0-phis", match cc.f.block? 0 with
      | some blk => blk.phis.isEmpty
      | none => false),
    (.j1, "dst-unique", nodupB (cc.f.allInsts.filterMap (·.dst) ++
      cc.f.blocks.flatMap fun b => b.phis.map (·.dst))),
    (.j1, "callee-table", calleeTableOk cc),
    (.j8, "emptied", emptiedOk cc) ]

/-- The state at entry: owned parameters are live, borrowed parameters are defined. -/
def entryState (cc : CCtx) : AbsState :=
  let bor := cc.f.paramVals.filter fun v => cc.st v == .borrowed
  { L := cc.f.paramVals.filter fun v => cc.st v == .owned,
    D := bor,
    R := bor.map fun v => (v, normRoots (cc.c.parents v)),
    P := [], G := [], F := [] }

/-! ## Phase 1: the forward pass -/

/-- Depth-first search with a fuel bound over an array of blocks: the visited marks and the
blocks in reverse postorder (each block is put in front of the list when it finishes). A block
outside the array counts as visited. -/
def dfsRpo (blocks : Array Block) : Nat → Array Bool → List BlockId → BlockId →
    Array Bool × List BlockId
  | 0, vis, post, _ => (vis, post)
  | fuel + 1, vis, post, b =>
    if vis.getD b true then (vis, post)
    else
      let vis := vis.set! b true
      let succs := match blocks[b]? with
        | some blk => blk.term.succs
        | none => []
      let r := succs.foldl
        (fun (vp : Array Bool × List BlockId) s => dfsRpo blocks fuel vp.1 vp.2 s)
        (vis, post)
      (r.1, b :: r.2)

/-- The reachable blocks in reverse postorder. -/
def Function.rpo (f : Function) : List BlockId :=
  let blocks := f.blocks.toArray
  (dfsRpo blocks (blocks.size + 1) (Array.replicate blocks.size false) [] 0).2

/-- The blocks some edge returns to: a successor that is not after its source in the order
(the Zig validator's `loopHeads`), as marks by block. -/
def Function.loopHeads (f : Function) (order : List BlockId) : Array Bool :=
  let blocks := f.blocks.toArray
  let pos := order.zipIdx.foldl (fun (m : Array Nat) (b, i) => m.set! b i)
    (Array.replicate blocks.size blocks.size)
  order.foldl
    (fun (heads : Array Bool) s =>
      match blocks[s]? with
      | some blk =>
        blk.term.succs.foldl
          (fun (heads : Array Bool) b =>
            if pos.getD b blocks.size ≤ pos.getD s blocks.size && b < blocks.size
            then heads.set! b true else heads)
          heads
      | none => heads)
    (Array.replicate blocks.size false)

/-- The state a block is first entered with: the decisions known when a loop is entered need not
hold on its back edges, so a loop head forgets them (the recheck compares every back edge with
this state). -/
def firstEntry (head : Bool) (σ : AbsState) : AbsState :=
  if head then { σ with F := [] } else σ

/-- The decided tests two paths share: those decided on both, with the outcome they agree on. -/
def joinF (Fs Fe : List (Key × Option Bool)) : List (Key × Option Bool) :=
  Fs.filterMap fun f =>
    match Fe.find? (·.1 == f.1) with
    | some g => some (f.1, if f.2 == g.2 then f.2 else none)
    | none => none

/-- A decided test with a known outcome on both paths, the outcomes differing: it tells the
paths apart. Returns the key and the outcome on the first path. -/
def distinguishing (σs σe : AbsState) : Option (Key × Bool) :=
  σs.F.findSome? fun f =>
    match f.2, σe.fact f.1 with
    | some ps, some (some pe) => if ps != pe then some (f.1, ps) else none
    | _, _ => none

/-- The joined state of one slot: equal on both paths, or open on one and not on the other,
told apart by a test; a slot already guarded keeps its guard (the recheck verifies it). -/
def joinSlot (σs σe : AbsState) (c : ValId) (k : String) : SlotVal :=
  let vs := σs.slotVal c k
  let ve := σe.slotVal c k
  match vs, ve with
  | .guarded _ _, _ => vs
  | _, .guarded _ _ => ve
  | .open_, .closed =>
    match distinguishing σs σe with
    | some (key, ps) => .guarded key ps
    | none => vs
  | .closed, .open_ =>
    match distinguishing σs σe with
    | some (key, ps) => .guarded key (!ps)
    | none => vs
  | _, _ => vs

/-- The join of the states arriving at a block: the first arrival's `L`, the names defined on
every path, the union of their roots, the slots as `joinSlot` says and the shared tests. -/
def joinState (σs σe : AbsState) : AbsState :=
  let D := σs.D.filter σe.D.contains
  let slots := (σs.slots ++ σe.slots).eraseDups
  let vals := slots.map fun p => (p, joinSlot σs σe p.1 p.2)
  { L := σs.L, D := D,
    R := (D ++ σs.L).map fun w => (w, normRoots (Rget σs w ++ Rget σe w)),
    P := (vals.filter fun v => v.2 == .open_).map (·.1),
    G := vals.filterMap fun v => match v.2 with
      | .guarded key pol => some (v.1.1, v.1.2, key, pol)
      | _ => none,
    F := joinF σs.F σe.F }

/-- Whether two states agree as sets (the solver stops when a round changes nothing). -/
def stateEq (σ σ' : AbsState) : Bool :=
  same σ.L σ'.L && same σ.P σ'.P && same σ.G σ'.G && same σ.F σ'.F && same σ.D σ'.D &&
    (σ.D ++ σ.L).all fun w => same (Rget σ w) (Rget σ' w)

/-- One forward pass in reverse postorder: run every block that has a state and join what its
live edges carry into the states of its successors. -/
def solveRound (cc : CCtx) (blocks : Array Block) (order : List BlockId) (heads : Array Bool)
    (inn : Array (Option AbsState)) : Array (Option AbsState) :=
  order.foldl
    (fun inn b =>
      match inn.getD b none, blocks[b]? with
      | some σ, some blk =>
        match runInsts cc b 0 σ blk.insts with
        | .error _ => inn
        | .ok σo =>
          match liveEdges cc b σo blk.term with
          | .error _ => inn
          | .ok es =>
            es.foldl
              (fun inn e =>
                match inn.getD e.1 none with
                | none => inn.set! e.1 (some (firstEntry (heads.getD e.1 false) e.2))
                | some σs => inn.set! e.1 (some (joinState σs e.2)))
              inn
      | _, _ => inn)
    inn

/-- The entry states proposed by forward passes until nothing changes (loops need a few), by
block.  (An array, not a function: a definition whose type is a function type is compiled with
the function's parameters, and its body would be run again at every application.) -/
def solveArr (cc : CCtx) : Array (Option AbsState) :=
  let blocks := cc.f.blocks.toArray
  let n := blocks.size
  let order := cc.f.rpo
  let heads := cc.f.loopHeads order
  let init : Array (Option AbsState) :=
    (Array.replicate n none).set! 0 (some (entryState cc))
  let rec go (fuel : Nat) (inn : Array (Option AbsState)) : Array (Option AbsState) :=
    match fuel with
    | 0 => inn
    | fuel + 1 =>
      let next := solveRound cc blocks order heads inn
      let stable := (List.range n).all fun b =>
        match inn.getD b none, next.getD b none with
        | none, none => true
        | some a, some b => stateEq a b
        | _, _ => false
      if stable then next else go fuel next
  go (n + 3) init

/-- The proposed entry states, as a function of the block. -/
def solveFn (arr : Array (Option AbsState)) : BlockId → Option AbsState :=
  fun b => arr.getD b none

/-- The entry states proposed for the blocks. -/
def solve (cc : CCtx) : BlockId → Option AbsState := solveFn (solveArr cc)

/-! ## The verdict -/

/-- The checker's context for a function and its certificate. -/
def mkCC (f : Function) (c : Certificate) : CCtx :=
  { f := f, c := c,
    defOf := f.allInsts.foldl
      (fun m i => match i.dst with
        | some d => m.insert d i
        | none => m)
      {} }

/-- The checker. -/
def verdict (f : Function) (c : Certificate) : Verdict :=
  let cc := mkCC f c
  match firstFail (preChecks cc) with
  | some jw => .reject (preFailure cc jw)
  | none =>
  match abandonShapeBad cc with
  | some b => .reject { j := .j1, blk := some b, idx := none, why := "abandon-shape" }
  | none =>
    let arr := solveArr cc
    match compatErr (solveFn arr) 0 (entryState cc) with
    | some jw => .reject { j := jw.1, blk := none, idx := none, why := jw.2 }
    | none =>
      match verifyBlocks cc (solveFn arr) (List.range f.blocks.length) with
      | some fl => .reject fl
      | none => .accept

/-- `check f c`: the function passes J1-J8. This is the function the soundness theorem is
about, and the function `certcheck` runs. -/
def check (f : Function) (c : Certificate) : Bool :=
  match verdict f c with
  | .accept => true
  | .reject _ => false

end Own
