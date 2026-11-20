/-!
# Syntax of the ownership model (design §2, §3, §4.1)

The IR fragment the model sees: the exporter (`ownership-certificate-v2`, design §4.1)
reduces every Core IR function to blocks of class-level instructions.  Values are
numbered (`%N`), blocks are numbered (`bN`), `caller(i)` (`^I`) names the allocation
behind borrowed parameter `i`.

* `Function` is the *IR reduction*: signature, the pseudo-block `b-` (parameters and
  constants), and the blocks with their phis, instructions and terminator.  An
  instruction is reduced to its operation class, the operands it reads and the operands
  it consumes (design §3).
* `Certificate` holds the claims the checker verifies: `state[v]` for every value and
  `parents[v]` for every borrowed value (design §4).

Nothing here depends on the semantics or the checker.
-/

namespace Own

/-- A value of a function (`%N`). -/
abbrev ValId := Nat
/-- A basic block (`bN`); block `i` is the `i`-th entry of `Function.blocks`. -/
abbrev BlockId := Nat

/-- Where a borrowed value's lifetime can end: a value of this function, or the
caller's allocation behind borrowed parameter `i` (design §2, `^I`). -/
inductive Root where
  | val (n : ValId)
  | caller (i : Nat)
  /-- slot `k` of the owned aggregate `n` (`"*"`: any slot): a view of that part of it.  It
  arises inside the checker, never in a certificate file. -/
  | slot (n : ValId) (k : String)
  /-- the owner `n` that will be taken out of a container later in the block: a borrowed value
  written before its take is rooted there (design §3, Project); it has no cells of its own. -/
  | fwd (n : ValId)
  deriving DecidableEq, Repr

/-- The state a certificate assigns to a value (design §2).  `stack` has no destruction
obligation and is never live in the checker's sense; `emptied` is an aggregate all of whose
managed parts were taken (design §3, slots), which owns nothing and is never consumed;
`none` is the state of an instruction that defines no value (`inst -`) and of a dead phi. -/
inductive St where
  | scalar
  | immortal
  | owned
  | stack
  | borrowed
  | emptied
  | none
  deriving DecidableEq, Repr

/-- The ownership class of an operation (design §3).  The export names every
`ir.Op`'s class; `join`, `forward`, `jump`, `branch`, `ret` and `trap` classify `phi`, `copy`, `jump`,
`branch`, `ret` and `unreachable`; none of them appears on an `inst` line. -/
inductive Class where
  | parameter | constant | pure | inspect | fresh | copy | project | view | character
  | textFrame | borrow | update | construct | take | drop | call | output | trace
  | join | forward | jump | branch | ret | trap
  deriving DecidableEq, Repr

/-! ## The callee table (C9.2, design entry 57) -/

/-- What a call line says about the callee (`callee N NAME KIND PARAMS RESULT FROM`): the kind of function. -/
inductive CalleeKind where
  /-- a function of the program: `name` is its `function` line -/
  | program
  /-- a `myl_core_*` runtime function: its contract is assumption A5 -/
  | runtime
  /-- an `extern func` -/
  | extern
  /-- a reserved borrow marker call -/
  | marker
  /-- a call through a function value: the entry is the function type's signature, `name` is `-` -/
  | indirect
  deriving DecidableEq, Repr

/-- One parameter of a callee entry: whether the callee takes the argument (it is then in `consumes`) or only reads
it (`reads`), and the state the callee's own certificate gives the parameter's value. -/
inductive ParamTok where
  /-- consumed, the callee's value is owned -/
  | take
  /-- consumed, the callee's value is a scalar: an unmanaged value passed to a taking parameter -/
  | takeScalar
  /-- read, the callee's value is borrowed -/
  | read
  /-- read, the callee's value is a scalar -/
  | readScalar
  deriving DecidableEq, Repr

/-- Whether the argument of this parameter is consumed. -/
def ParamTok.takes : ParamTok → Bool
  | .take => true
  | .takeScalar => true
  | _ => false

/-- Whether the callee's value of this parameter is a scalar (assumption A9). -/
def ParamTok.scalarVal : ParamTok → Bool
  | .takeScalar => true
  | .readScalar => true
  | _ => false

/-- What the callee returns, as its `function` line says: a unit function returns `scalar`. -/
inductive ResTok where
  | scalar
  | owned
  | borrowed
  deriving DecidableEq, Repr

/-- A callee table entry (design entry 57).  The table is the function's own; `id` is the number the line states. -/
structure CalleeEntry where
  id : Nat
  /-- the callee's name as on its `function` line, or `-` for an indirect call -/
  name : String
  kind : CalleeKind
  params : List ParamTok
  result : ResTok
  /-- the parameter positions of the borrow contract -/
  from_ : List Nat
  deriving DecidableEq, Repr

/-- The state the callee's own certificate gives a parameter of this kind (the `param` line). -/
def ParamTok.state : ParamTok → St
  | .take => .owned
  | .takeScalar => .scalar
  | .read => .borrowed
  | .readScalar => .scalar

/-- The result state the token stands for. -/
def ResTok.state : ResTok → St
  | .scalar => .scalar
  | .owned => .owned
  | .borrowed => .borrowed

/-- A class-level instruction: `inst %N <op> <Class> reads … consumes … state … parents …`
without the last two fields, which live in the certificate.  `reads` and `consumes` are
the value operands after `copy` resolution, in operand order; a value both read and
consumed appears in both lists. -/
structure Inst where
  dst : Option ValId
  op : String
  cls : Class
  reads : List ValId
  consumes : List ValId
  /-- The function a `call` instruction calls, as an index into a program's function list.
  The export has no callee (the per-function theorem does not need one); only the
  whole-program corollary does. -/
  callee : Option Nat := none
  /-- `callee N` (C9.2): the entry of the function's callee table this call line names. -/
  entry : Option Nat := none
  /-- `slot KEY` (design §3, slots): the slot a container instruction reads, takes or stores:
  `f<k>`, `e<I>` (with a field path), `k<I>`, `v<I>` or `tail`. -/
  slot : Option String := none
  /-- `released PARTS`: what a store destroys of the old content (`old`, `-`, `key,value`,
  `key`, `value`). -/
  released : Option String := none
  /-- `taken PARTS`: for `dict_remove`, the parts (`key`, `value`, `key,value` or `-`) the removal
  finds already moved out by a take; the parts it destroys are in `released`. -/
  taken : Option String := none
  /-- `slots KEYS`: the managed fields of an `emptied` aggregate, each taken exactly once. -/
  slots : List String := []
  /-- `from VALUES`: for a call, the values its result borrows from (design §4.1). -/
  fromVals : List ValId := []
  /-- `lent %G`: for a lend (a `box_make` with `flags.lent_box`, design §10), the group the box
  is lent to.  The lend reads the lender first and the group second, and consumes nothing. -/
  lent : Option ValId := none
  /-- `noloans`: for a take, the result's type cannot hold a view, so the take carries none of the loans
  of the aggregate it comes out of (see `Inst.dropsLoans`). -/
  noLoans : Bool := false
  /-- `views VALUES` (format v2): for a constructor with an owned or `emptied` result, the borrowed operands it reads into
  a slot whose type its destruction does not destroy (a span, a list view, a borrowed overlay). Only these may be a loan the
  aggregate holds (J6 `construct-read`, condition 2). -/
  views : List ValId := []
  /-- `imm N`: the instruction's `data` for `iconst` (the constant), `cmp` and `fcmp` (the
  predicate): what lets two tests be compared by value (design §5, guarded takes). -/
  imm : Option Nat := none
  /-- The arguments of a `call` in parameter order, each with whether it is passed owned
  (it is then in `consumes`) or read (it is then in `reads`). Only the whole-program
  corollary uses it; the export has `reads` and `consumes` split by mode. -/
  callArgs : List (ValId × Bool) := []
  /-- The line states a class other than the one the file's class table gives its operation: the
  reader keeps the stated class and the checker rejects the function (J1) instead of the file
  being refused as malformed. -/
  misclassified : Bool := false
  deriving DecidableEq, Repr

/-- The arguments of a call in parameter order, each with whether it is consumed (taken by the callee, so it is in
`consumes`) or read (it is in `reads`): walk the entry's parameters; a taking parameter takes the next value of `consumes`,
any other the next of `reads`.  The walk stops early when the lists run out (the arity check catches that). -/
def walkArgs : List ParamTok → List ValId → List ValId → List (ValId × Bool)
  | [], _, _ => []
  | t :: ts, rs, cs =>
    if t.takes then
      match cs with
      | c :: cs' => (c, true) :: walkArgs ts rs cs'
      | [] => []
    else
      match rs with
      | r :: rs' => (r, false) :: walkArgs ts rs' cs
      | [] => []

/-- The arguments of a call line, given the entry it names: the first read of an indirect call is the function value. -/
def Inst.argsOf (i : Inst) (e : CalleeEntry) : List (ValId × Bool) :=
  walkArgs e.params (if e.kind == .indirect then i.reads.drop 1 else i.reads) i.consumes

/-- Whether the instruction drops the loans of what it consumes instead of handing them on to its owned
result (**A13**, AXIOMS.md): a take whose result the exporter says cannot hold a view (`noloans`: the
`None` arm of the lowering of `copy` of a `T?`).  Every other instruction with an owned result, a take
included, hands them on. -/
def Inst.dropsLoans (i : Inst) : Bool := i.cls == .take && i.noLoans

/-- `phi %N … edges bM:%V,…`: the value flowing in from each predecessor. -/
structure Phi where
  dst : ValId
  edges : List (BlockId × ValId)
  deriving DecidableEq, Repr

/-- Block terminators (`term …`).  `ret none` is a return of no value. -/
inductive Term where
  | jump (b : BlockId)
  | branch (c : ValId) (t f : BlockId)
  | ret (v : Option ValId)
  | unreachable
  deriving DecidableEq, Repr

/-- A basic block: predecessors, phis, instructions in order, terminator.  `abandons` are the
`abandon bP %V,…` lines (C9.1, design entry 55): for the edge from the predecessor `bP`, the owned values
the path leaks because the process ends at a trap further on.  An abandon changes the abstract state
(the values leave `L`, `P` and `G` forget them) and leaves memory alone. -/
structure Block where
  preds : List BlockId
  phis : List Phi
  insts : List Inst
  term : Term
  abandons : List (BlockId × List ValId) := []
  deriving DecidableEq, Repr

/-- The values the edge from `p` into the block abandons (none when it has no line). -/
def Block.abandonFrom (blk : Block) (p : BlockId) : List ValId :=
  match blk.abandons.find? (·.1 == p) with
  | some a => a.2
  | none => []

/-- A function instance: signature (`function … result … from …`, `param I …`), the
pseudo-block `b-` (parameters and constants, defined outside every block) and the blocks.
Parameter `i` is the value `paramVals[i]`, named by its `param <I> %N <state>` line. -/
structure Function where
  name : String
  /-- State of each parameter from the signature: `scalar`, `owned` or `borrowed`. -/
  params : List St
  /-- State of the result: `scalar`, `owned` or `borrowed`. -/
  result : St
  /-- Parameter indices the borrowed result is `from` (the `BorrowContract`). -/
  from_ : List Nat
  /-- The value of parameter `i` (`param <I> %N <state>`). -/
  paramVals : List ValId
  pre : List Inst
  blocks : List Block
  /-- The callee table (C9.2): one entry per distinct callee, numbered from 0. -/
  callees : List CalleeEntry := []
  /-- The same blocks as an array: a constant-time lookup by block id for the checker. -/
  blockArr : Array Block := blocks.toArray
  blockArr_eq : blockArr = blocks.toArray := by rfl
  deriving DecidableEq, Repr

/-- The claims of a certificate (design §4): the state of every value and the parents of
every borrowed value.  Total functions; a value no line defines has state `none`. -/
structure Certificate where
  state : ValId → St
  parents : ValId → List Root

/-- Functional update of a map indexed by `Nat`. -/
def upd {α : Type} (g : Nat → α) (k : Nat) (v : α) : Nat → α :=
  fun n => if n = k then v else g n

/-! ## Accessors -/

/-- The block with id `b`. -/
def Function.block? (f : Function) (b : BlockId) : Option Block := f.blockArr[b]?

/-- The lookup by block id is the list lookup. -/
theorem Function.block?_eq (f : Function) (b : BlockId) : f.block? b = f.blocks[b]? := by
  unfold Function.block?
  rw [f.blockArr_eq]
  simp

theorem Function.block?_mem {f : Function} {b : BlockId} {blk : Block}
    (h : f.block? b = some blk) : blk ∈ f.blocks := by
  rw [Function.block?_eq] at h
  exact List.mem_of_getElem? h

theorem Function.block?_lt {f : Function} {b : BlockId} {blk : Block}
    (h : f.block? b = some blk) : b < f.blocks.length := by
  rw [Function.block?_eq] at h
  exact (List.getElem?_eq_some_iff.1 h).1

/-- The entry of its function's callee table a call line names. -/
def Function.entryOf (f : Function) (i : Inst) : Option CalleeEntry :=
  i.entry.bind fun n => f.callees[n]?

/-- The `k`-th instruction of block `b`. -/
def Function.instAt (f : Function) (b : BlockId) (k : Nat) : Option Inst :=
  (f.block? b).bind fun blk => blk.insts[k]?

/-- Every instruction of the function, pseudo-block included. -/
def Function.allInsts (f : Function) : List Inst :=
  f.pre ++ f.blocks.flatMap (·.insts)

/-- Position of `d` in a list of ids. -/
def idxOf? (l : List ValId) (d : ValId) : Option Nat :=
  match l with
  | [] => none
  | x :: xs => if x == d then some 0 else (idxOf? xs d).map (· + 1)

/-- Which parameter `d` is, when it is a parameter value. -/
def Function.paramIdx (f : Function) (d : ValId) : Option Nat := idxOf? f.paramVals d

/-- An upper bound on the value ids of the function (closure iterations of the checker). -/
def Function.nvals (f : Function) : Nat :=
  let ids : List Nat :=
    f.paramVals ++ (f.allInsts.filterMap (·.dst)) ++ (f.blocks.flatMap fun b => b.phis.map (·.dst))
  ids.foldl (fun m n => max m (n + 1)) 0

/-! ## Tests (design §5: guarded takes)

Two branch conditions are *the same test* when they are the same value, or the same pure
`cmp`/`fcmp` (same predicate) of the same operands, constants being compared by value.  The
canonical form is a `Key`; the checker and the semantics both use `keyOfWith`. -/

/-- An operand of a compared test: a value, or an integer constant compared by value. -/
inductive Opd where
  | v (n : ValId)
  | k (c : Nat)
  deriving DecidableEq, Repr

/-- The canonical form of a test. -/
inductive Key where
  /-- the value itself -/
  | val (v : ValId)
  /-- a pure comparison (`cmp` or `fcmp`) with its predicate and operands -/
  | cmp (op : String) (pred : Nat) (a b : Opd)
  deriving DecidableEq, Repr

/-- Whether the operand is the value `d`. -/
def Opd.mentions : Opd → ValId → Bool
  | .v n, d => n == d
  | .k _, _ => false

/-- Whether the test depends on the value `d`: redefining `d` changes what the test means. -/
def Key.mentions : Key → ValId → Bool
  | .val v, d => v == d
  | .cmp _ _ a b, d => a.mentions d || b.mentions d

/-- The operand `x` of a comparison, canonical: an `iconst` becomes its value. -/
def opdOfWith (look : ValId → Option Inst) (x : ValId) : Opd :=
  match look x with
  | some t =>
    match t.op, t.imm with
    | "iconst", some c => .k c
    | _, _ => .v x
  | none => .v x

/-- The test the value `v` stands for, given the instruction that defines each value. -/
def keyOfWith (look : ValId → Option Inst) (v : ValId) : Key :=
  match look v with
  | some t =>
    if (t.op == "cmp" || t.op == "fcmp") && t.cls == .pure then
      match t.imm, t.reads with
      | some p, [a, b] => .cmp t.op p (opdOfWith look a) (opdOfWith look b)
      | _, _ => .val v
    else .val v
  | none => .val v

/-- A take of the container the instruction `i` reads (or a view of it), defined as `n`: the
owner that takes the place of the view (design §3, Project).  Used for the parent of a borrowed
result that is written before its take; only a `Project` is a forward reader (the Zig validator's
`laterSibling`). -/
def forwardTakeWith (look : ValId → Option Inst) (c : Certificate) (i : Inst) (n : ValId) : Bool :=
  i.cls == .project &&
  match look n with
  | some t => t.cls == .project && t.slot.isSome && c.state n == .owned &&
      match t.reads.head? with
      | some k => i.reads.head? == some k ||
          i.reads.any fun a => (c.parents a).contains (.val k)
      | none => false
  | none => false

/-- The instruction that defines the value `v` (a phi is not an instruction). -/
def Function.defOf? (f : Function) (v : ValId) : Option Inst :=
  f.allInsts.find? fun i => i.dst == some v

/-! ## Operation sets the model needs by name

The model is uniform in the operation (design §3 reduced to reads, consumes and the result
state), except where the take protocol (design §3, slots; §5 J8) needs to recognise one. -/

/-- The updates that close a take (design §3, slots): the stores into a slot, `list_pop`
and `dict_remove`. -/
def closingOps : List String :=
  ["record_set", "array_set", "list_set", "list_set_field", "dict_set_value",
   "list_pop", "dict_remove"]

/-- The stores that take a `slot KEY` and a `released` mark (the others close without one). -/
def storeOps : List String :=
  ["record_set", "array_set", "list_set", "list_set_field", "dict_set_value"]

/-- The projections that take a slot when their result is `owned` or `emptied`. -/
def takeOps : List String :=
  ["record_get", "array_get", "list_get", "list_get_field", "dict_entry_key", "dict_entry_value"]

/-- An update that closes the take it names, or any update that may (J8). -/
def Inst.isClosing (i : Inst) : Bool := i.cls == .update && closingOps.contains i.op

/-- Whether `taken` names the part. -/
def takenPart (i : Inst) (part : String) : Bool :=
  match i.taken with
  | some r => (r.splitOn ",").contains part
  | none => false

/-- The slots the agreement of an update with its container looks at (`closeAgrees`): a store
its `slot`, `list_pop` the slot it names (`tail` none), `dict_remove` the key and value slots of
the entry it reads. -/
def queriedKeys (i : Inst) : List String :=
  match i.op with
  | "dict_remove" =>
    match i.reads.head? with
    | some e => [s!"k%{e}", s!"v%{e}"]
    | none => []
  | "list_pop" =>
    match i.slot with
    | some k => if k == "tail" then [] else [k]
    | none => []
  | _ =>
    if storeOps.contains i.op then i.slot.toList else []

/-- The slots an update closes, in its container (the first value it consumes): a store its
`slot`, `list_pop` the slot it names (`tail` closes none), `dict_remove` the key and value
slots of the entry it reads that its `taken` names (both, when the export says nothing). -/
def closedKeys (i : Inst) : List String :=
  match i.op with
  | "dict_remove" =>
    match i.reads.head? with
    | some e =>
      (if i.taken.isNone || takenPart i "key" then [s!"k%{e}"] else []) ++
      (if i.taken.isNone || takenPart i "value" then [s!"v%{e}"] else [])
    | none => []
  | "list_pop" =>
    match i.slot with
    | some k => if k == "tail" then [] else [k]
    | none => []
  | _ =>
    if storeOps.contains i.op then i.slot.toList else []

/-- Whether the store releases `part` of the old content, as written in `released`. -/
def releasesPart (i : Inst) (part : String) : Bool :=
  match i.released with
  | some r => (r.splitOn ",").contains part
  | none => false

/-- J8, closing: whether a closing update agrees with the takes that are open in its container
(`pend k`: the slot `k` was taken and not yet written back).  A store into a slot needs the slot
open when it says `released -` (it destroys nothing: the old content was moved out) and not open
when it says `released old` (it destroys the old content); `record_set` and `array_set` close an
open slot; `list_pop` closes the slot it names; `dict_remove` takes only open slots (`taken`)
and releases a part only when that part's slot is not open. Every other instruction agrees. -/
def closeAgrees (pend : String → Bool) (i : Inst) : Bool :=
  if !i.isClosing then true
  else
    match i.op with
    | "record_set" => match i.slot with | some k => pend k | none => true
    | "array_set" => match i.slot with | some k => pend k | none => true
    | "list_pop" => match i.slot with
      | some k => k == "tail" || pend k
      | none => true
    | "dict_remove" =>
      match i.reads.head? with
      | some e =>
        (i.taken.isNone ||
          ((!takenPart i "key" || pend s!"k%{e}") && (!takenPart i "value" || pend s!"v%{e}"))) &&
        (!releasesPart i "key" || !pend s!"k%{e}") && (!releasesPart i "value" || !pend s!"v%{e}")
      | none => false
    | _ =>
      match i.slot with
      | some k =>
        if i.released == some "-" then pend k
        else if i.released == some "old" then !pend k
        else false
      | none => true

/-- A phi that carries a value: a dead phi (state `none`) is skipped (design §3, Phis). -/
def Phi.live (c : Certificate) (φ : Phi) : Bool := c.state φ.dst != .none

/-! ## The export file (design §4.1) -/

/-- One function of a certificate file, with the reason it is `unchecked`, if any. -/
structure Entry where
  fn : Function
  cert : Certificate
  unchecked : Option String

end Own
