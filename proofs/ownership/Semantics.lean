import Syntax

/-!
# Semantics of the ownership model (design §6, "Model")

A heap of allocations with owner trees, small-step execution of a function body, and a
`fault` configuration for every way an ownership bug shows at run time.

## The heap

An allocation is an address `Addr`.  A cell is `unused` (never allocated), `live t`
(allocated, in the owner tree whose root is `t`) or `dead` (destroyed; never reused, so a
stale pointer is always detected).  A tree is the set of cells with one label, and its root
is the cell whose address is the label.  `drop` destroys a whole tree (A2); an update or a
construction moves the trees it consumes into one result tree, destroying whatever the
runtime destroys (`Xform`).

## Values

A run-time value is `imm` (a scalar or an immortal: no heap effect, A4), `own t` (the owner
of tree `t`) or `bor fp` (a borrowed value: a pointer set `fp` into someone else's trees).

## Instructions

Every instruction is executed by one uniform rule (`Step.inst`), read off the export:
* it reads `reads` and consumes `consumes`, and what it consumes is destroyed or moved into
  the result tree (`Xform`);
* its result is as the certificate states: `scalar`/`immortal`/`none` → `imm`;
  `owned`/`stack` → the root of the result tree (or `imm`); `borrowed` → pointers into the
  trees of its `parents`.

The operation classes (design §3) act through the exporter (A1): they decide what is read,
what is consumed and which state the result has.  The model needs the class only for the take
protocol (J8): a take is a `Project` whose result is `owned` and that names a `slot`; a closing
update is `Inst.isClosing`.

## What changed with the revision of 26 October (C3.3b)

* `stack`, `emptied`, `immortal`, `none` and `scalar` values are all `imm`: they own nothing
  that must be destroyed.  A managed `undef` is the null owner, `imm`, and a phi edge from it is
  live.
* The pending transfers are per slot: `pend t k` says the container tree `t` has the slot `k`
  taken out and not yet written back.  The closing update (`record_set`, `array_set`,
  `list_set`, `list_set_field`, `dict_set_value`, `list_pop`, `dict_remove`) closes the slots
  it names and passes the others on to the tree it returns (`pendAfter`); its `released` mark
  must agree with the slot (`closeAgrees`, shared with the checker).
* An `Parameter` instruction inside a block re-reads an argument and changes nothing.
* A dead phi (state `none`) carries nothing.

## Task groups (C6.2, design §10)

A lend (`lent %G`) records in `DState.lent` the cells its lender gives access to as lent to the
group `%G`; a task of the group may read them until the group ends.  The model does not run the
tasks.  It makes destroying a lent cell while the group is live a fault, `Fault.lentGone`
(`LentSafe`): an instruction that consumes the tree of a lent cell must consume the group's tree
too (the join) or be a constructor that keeps what it consumes.

## Trap regions (C9.1, design entry 55)

An edge into a block of the trap region may name owners the path leaks (`abandon` lines).  The step records the roots of
their trees in the ghost set `DState.abandoned` (`abandonNext`) and changes no memory; the loans held by or on an
abandoned tree end (`held`, `lent`).  The checker no longer lists the owners, so nothing reads or consumes the trees
again, and only the trap region is entered with an abandoned tree, which cannot reach a `ret`.

## Calls

A call is the same rule.  What a callee may do to the heap is exactly `Xform`: it destroys
or hands back the trees it was given (the consumed arguments), allocates fresh cells, and
leaves every other cell untouched, the borrowed arguments' trees included.  This *is* the
callee contract of design §6 (assume-guarantee); `Post` states the same contract for a
whole function body, and `Soundness.lean` proves that a checked function satisfies it, which
discharges the assumption for the whole-program corollary.
-/

namespace Own

/-- An allocation. -/
abbrev Addr := Nat

/-- The state of one heap cell. -/
inductive Cell where
  /-- never allocated -/
  | unused
  /-- allocated, in the owner tree with root `t` -/
  | live (t : Addr)
  /-- destroyed; the address is never reused -/
  | dead
  deriving DecidableEq, Repr

/-- The heap. -/
abbrev Heap := Addr → Cell

/-- A run-time value. -/
inductive Val where
  /-- a scalar or an immortal (`str_const`, `text_sentinel`): no heap effect (A4) -/
  | imm
  /-- a stack list of this activation: an allocation in its frame, with no heap cell and no
  destruction, gone when the activation ends.  It must not outlive the activation nor reach the
  allocator (`Fault.escape`, design J7). -/
  | stk
  /-- the owner of the tree rooted at `t` -/
  | own (t : Addr)
  /-- a borrowed value: pointers into trees owned elsewhere -/
  | bor (fp : List Addr)
  deriving DecidableEq, Repr

/-- The value can be read: every allocation it points at is live. -/
def Val.alive (h : Heap) : Val → Prop
  | .imm => True
  | .stk => True
  | .own t => ∃ l, h t = .live l
  | .bor fp => ∀ x ∈ fp, ∃ l, h x = .live l

/-- The live cells the value gives access to: the tree it owns, or the trees containing
the cells it points at. -/
def Val.cells (h : Heap) : Val → Addr → Prop
  | .imm, _ => False
  | .stk, _ => False
  | .own t, x => h x = .live t
  | .bor fp, x => ∃ y ∈ fp, ∃ l, h y = .live l ∧ h x = .live l

/-- A machine state of one activation: the heap, the transfers still pending (design J8:
`pend t k` says the container tree `t` has the slot `k` whose owner was taken out and not yet
written back), the value of every SSA name and the tests already decided on this path (design
§5, guarded takes: `facts k = some b` says the test `k` came out `b` and its operands have not
been redefined since). -/
structure DState where
  heap : Heap
  pend : Addr → String → Bool
  env : ValId → Val
  facts : Key → Option Bool
  /-- `lent g x`: the cell `x` was lent to the group whose tree has the root cell `g` (design §10.6):
  a task of the group may read it until the group ends.  Nothing lends at entry. -/
  lent : Addr → Addr → Prop := fun _ _ => False
  /-- `held g x`: the cell `g` of an owned tree holds a loan on the cell `x` outside its own tree (design
  §3, Construct, and assumption A12): the contents of the tree point at `x`.  An owned result adds the
  cells of the values it lists as parents (A12); a constructor keeps what the trees it consumes held (the
  cells stay where they are, and so does their key); any other instruction that consumes a tree forgets
  what its cells held (**A13**: its result points only into its own listed parents). -/
  held : Addr → Addr → Prop := fun _ _ => False
  /-- `abandoned t`: the tree rooted at the cell `t` was abandoned (C9.1, design entry 55): the path leaks it because
  the process ends at a trap further on.  Memory is untouched; the checker no longer lists the owner of such a tree,
  so nothing reads or consumes it again.  Nothing is abandoned at entry, and a `ret` is reached only with nothing
  abandoned (`Good` in `Soundness.lean`: only an edge into a trap region abandons, and a trap region never returns). -/
  abandoned : Addr → Prop := fun _ => False

/-- The tests that remain decided after the values `ds` are redefined. -/
def clearFacts (facts : Key → Option Bool) (ds : List ValId) : Key → Option Bool :=
  fun k => if ds.any (fun d => k.mentions d) then none else facts k

/-- The tests after a branch decided `key` to be `b`. -/
def setFact (facts : Key → Option Bool) (key : Key) (b : Bool) : Key → Option Bool :=
  fun k => if k = key then some b else facts k

/-- What is fixed during one activation of a function: its body, its certificate and the
values of its parameters at entry (the allocations behind `caller(i)`). -/
structure Ctx where
  fn : Function
  cert : Certificate
  callerVals : Nat → Val

/-- The test a value stands for (see `keyOfWith`). -/
def Ctx.key (ctx : Ctx) (v : ValId) : Key := keyOfWith ctx.fn.defOf? v

/-- The values the live phis of a block define. -/
def phiDsts (c : Certificate) (phis : List Phi) : List ValId :=
  (phis.filter (Phi.live c)).map (·.dst)

/-! ## What an instruction may do to the heap -/

/-- The heap effect of an instruction (A2).  `cs` are the roots of the trees it consumes,
`res` the root of the tree its owned result owns, if any.
* a cell outside the consumed trees is untouched (`keep`, `stay`);
* a cell of a consumed tree is destroyed or moved into the result tree (`gone`);
* an unused cell stays unused, is allocated and destroyed within the instruction, or joins
  the result tree (`fresh`);
* the result root is a live cell that is either fresh or was in a consumed tree (`root`). -/
structure Xform (h h' : Heap) (cs : List Addr) (res : Option Addr) : Prop where
  keep : ∀ x t, h x = .live t → t ∉ cs → h' x = .live t
  stay : ∀ x, h x = .dead → h' x = .dead
  gone : ∀ x t, h x = .live t → t ∈ cs → h' x = .dead ∨ ∃ r, res = some r ∧ h' x = .live r
  fresh : ∀ x, h x = .unused →
    h' x = .unused ∨ h' x = .dead ∨ ∃ r, res = some r ∧ h' x = .live r
  root : ∀ r, res = some r → h' r = .live r ∧ (h r = .unused ∨ ∃ t, h r = .live t ∧ t ∈ cs)

/-- A constructor with an owned result keeps what it consumes: every cell of a consumed tree is in
the result tree
(the aggregate holds the trees it was given, and a view of one of them stays valid, which is
what lets a constructor take an owner it also reads a view of; J6 and design §3, Construct). -/
def Retains (h h' : Heap) (cs : List Addr) (res : Option Addr) : Prop :=
  ∀ x t, h x = .live t → t ∈ cs → ∃ r, res = some r ∧ h' x = .live r

/-- The cells of a root: a value of this function, or the caller's allocation. -/
def rootCells (ctx : Ctx) (ds : DState) : Root → Addr → Prop
  | .val n, x => (ds.env n).cells ds.heap x
  | .slot n _, x => (ds.env n).cells ds.heap x
  | .fwd _, _ => False
  | .caller i, x => (ctx.callerVals i).cells ds.heap x

/-- The state the certificate claims for the value `i` defines. -/
def Inst.res (ctx : Ctx) (i : Inst) : St :=
  match i.dst with
  | some d => ctx.cert.state d
  | none => .none

/-- The root of a value that owns a tree. -/
def ownedRoot : Val → Option Addr
  | .own t => some t
  | _ => none

/-- The roots of the trees owned by the values an edge abandons. -/
def abandonedRoots (ds : DState) (A : List ValId) : List Addr :=
  A.filterMap fun a => ownedRoot (ds.env a)

/-- The machine state after an edge abandons the owners `A` (C9.1, design entry 55).  Memory is untouched, and so are
the environment and the pending takes.  The trees of the abandoned owners are recorded (`abandoned`), and the loans
that involve them end: an abandoned holder never reads what it holds again, and what an abandoned owner owns is never
destroyed, so no loan held by or on an abandoned tree can be violated (`held`, `lent`).  A drop ends them the same way,
by destroying the cells. -/
def abandonNext (ds : DState) (A : List ValId) : DState :=
  { ds with
    abandoned := fun t => ds.abandoned t ∨ t ∈ abandonedRoots ds A
    held := fun g x => ds.held g x ∧
      ¬ ∃ t ∈ abandonedRoots ds A, ds.heap g = .live t ∨ ds.heap x = .live t
    lent := fun g x => ds.lent g x ∧ ¬ ∃ t ∈ abandonedRoots ds A, ds.heap x = .live t }

/-- The cells lent to groups after the instruction: a lend (`lent %G`) adds the cells its lender
(the first operand it reads) gives access to to the group it names, whose tree has the root the
second operand owns.  Every other instruction lends nothing. -/
def lentAfter (ds : DState) (i : Inst) : Addr → Addr → Prop :=
  fun g x => ds.lent g x ∨ ∃ gv a, i.lent = some gv ∧ i.reads.head? = some a ∧
    ownedRoot (ds.env gv) = some g ∧ (ds.env a).cells ds.heap x

/-- The roots of the trees the instruction consumes (immortals consume nothing, A4). -/
def consumedRoots (ds : DState) (i : Inst) : List Addr :=
  i.consumes.filterMap fun c => ownedRoot (ds.env c)

/-- The loans held after the instruction (see `DState.held`): what was held stays, except that
* an instruction that drops loans (`Inst.dropsLoans`: a take) that consumes the tree of a holder forgets
  what the cells of that tree held (**A13**), and
* an instruction other than a constructor that consumes a tree forgets the loans its cells held on cells
  of the same tree (a view into itself: the instruction may destroy or move the cells it points at).
An owned result with root `t` holds a loan on every cell of every value its certificate lists as a parent
(**A12**). -/
def heldAfter (ctx : Ctx) (ds : DState) (i : Inst) (r : Option Addr) : Addr → Addr → Prop :=
  fun g x =>
    (ds.held g x ∧
      ¬ ((i.dropsLoans = true ∧ ∃ t ∈ consumedRoots ds i, ds.heap g = .live t) ∨
         (i.cls ≠ .construct ∧ ∃ t ∈ consumedRoots ds i, ds.heap g = .live t ∧ ds.heap x = .live t))) ∨
    (∃ d t, i.dst = some d ∧ ctx.cert.state d = .owned ∧ r = some t ∧ g = t ∧
      ∃ n, Root.val n ∈ ctx.cert.parents d ∧ (ds.env n).cells ds.heap x)

/-- A take (design J8, slots): a `Project` instruction that names a `slot` and whose result is
`owned` (or `emptied`, an aggregate all of whose parts the take moves out).  It hands the element's ownership to the result tree while the container still holds
the slot.  A take out of an `emptied` aggregate (state `emptied`, value `imm`) is a complete
move: nothing is left pending. -/
def isTransfer (ctx : Ctx) (i : Inst) : Bool :=
  i.cls == .project && (i.res ctx == .owned || i.res ctx == .emptied) && i.slot.isSome

/-- The container tree a take reads from: the root its first operand owns. -/
def transferTarget (ds : DState) (i : Inst) : Option Addr :=
  match i.reads.head? with
  | some a => ownedRoot (ds.env a)
  | none => none

/-- The tree a closing update closes slots of: the root of its first consumed operand. -/
def closeTarget (ds : DState) (i : Inst) : Option Addr :=
  i.consumes.head?.bind fun c => ownedRoot (ds.env c)

/-- The slot `k` is open in the tree a closing update closes slots of, and the update does not
close it: it stays open in the update's result. -/
def closePend (ds : DState) (i : Inst) (k : String) : Bool :=
  match closeTarget ds i with
  | some c => ds.pend c k && !(closedKeys i).contains k
  | none => false

/-- The pending takes after the instruction: consuming a container ends its pending takes (when
the instruction is the closing update that names them; otherwise it faults); the closing update
passes the slots it does not close on to the tree it returns; a take opens its slot. -/
def pendAfter (ctx : Ctx) (ds : DState) (i : Inst) (r : Option Addr) : Addr → String → Bool :=
  fun t k =>
    if i.isClosing && r == some t && closePend ds i k then true
    else if (consumedRoots ds i).contains t || r == some t then false
    else if isTransfer ctx i && transferTarget ds i == some t && i.slot == some k then true
    else ds.pend t k

/-- The new value of the destination, given the result root `r` of the heap effect. -/
def ResultOk (ctx : Ctx) (ds : DState) (i : Inst) (ds' : DState) (r : Option Addr) : Prop :=
  match i.dst with
  | none => ds'.env = ds.env ∧ r = none
  | some d =>
    ∃ v, ds'.env = upd ds.env d v ∧
      match ctx.cert.state d with
      | .owned =>
          ((v = .imm ∧ r = none) ∨ ∃ t, r = some t ∧ v = .own t) ∧
          -- (A10) updating through an immediate (a null owner) yields an immediate
          (i.isClosing = true → closeTarget ds i = none → v = .imm ∧ r = none)
      | .borrowed =>
          r = none ∧ (v = .imm ∨ ∃ fp, v = .bor fp ∧ ∀ x ∈ fp,
            (∃ p ∈ ctx.cert.parents d,
              (∀ n, p = .val n → forwardTakeWith ctx.fn.defOf? ctx.cert i n = false) ∧
              rootCells ctx ds p x) ∧ ∃ l, ds'.heap x = .live l)
      | .stack => v = .stk ∧ r = none
      | _ => v = .imm ∧ r = none

/-- A successful instruction: the heap changes by `Xform`, the destination gets a value
that agrees with the certificate's state, and the pending transfers move.  A `Parameter`
instruction in a block re-reads an argument and changes nothing. -/
def Effect (ctx : Ctx) (ds : DState) (i : Inst) (ds' : DState) : Prop :=
  (i.cls = .parameter ∧ ds' = ds) ∨
  (i.cls ≠ .parameter ∧ ∃ r : Option Addr,
    Xform ds.heap ds'.heap (consumedRoots ds i) r ∧
    (i.cls = .construct → i.res ctx = .owned → Retains ds.heap ds'.heap (consumedRoots ds i) r) ∧
    ResultOk ctx ds i ds' r ∧
    ds'.pend = pendAfter ctx ds i r ∧
    ds'.facts = clearFacts ds.facts i.dst.toList ∧
    ds'.lent = lentAfter ds i ∧
    ds'.held = heldAfter ctx ds i r ∧
    ds'.abandoned = ds.abandoned)

/-! ## Faults (design §6) -/

/-- The ways an execution faults. -/
inductive Fault where
  /-- reading an allocation that is not live (use after destruction) -/
  | readDead
  /-- consuming an allocation that is not a live tree root -/
  | consumeDead
  /-- one instruction destroys the same tree twice -/
  | destroyTwice
  /-- consuming or destroying a borrowed value, hence an allocation reachable only from a
  `caller(i)` root (or from another owner's tree) -/
  | takeBorrowed
  /-- an instruction consumes a tree another of its operands still reads into (J6) -/
  | overlap
  /-- consuming a container whose taken slot is still pending, other than by the closing
  update, taking a slot that is already taken, a closing update that disagrees with its
  slot, or taking out of a container that is not an owned live tree (J8) -/
  | stranded
  /-- a stack allocation outlives the activation or reaches the allocator: it is consumed other
  than as the first operand of a filling push, a push into it stores a value that owns a tree
  (a stack list holds no managed elements, so the tree would never be destroyed), or it is
  returned (design J7) -/
  | escape
  /-- an owned value that holds a loan is read after the allocation the loan is on is gone: one of
  the loan operands the certificate lists as its parents is not live (design J4) -/
  | dangling
  /-- a cell lent to a live group is destroyed before the group ends (design §10.6): a task may
  still read it -/
  | lentGone
  /-- a fault inside a callee, seen from the caller (whole-program semantics only) -/
  | calleeFault
  deriving DecidableEq, Repr

/-- Every operand the instruction reads is live. -/
def ReadsAlive (ds : DState) (i : Inst) : Prop :=
  ∀ r ∈ i.reads, (ds.env r).alive ds.heap

/-- Every consumed tree root is live. -/
def ConsumeLive (ds : DState) (i : Inst) : Prop :=
  ∀ t ∈ consumedRoots ds i, ds.heap t = .live t

/-- No tree is consumed twice by one instruction. -/
def ConsumeOnce (ds : DState) (i : Inst) : Prop :=
  (consumedRoots ds i).Nodup

/-- No consumed operand is a borrowed value. -/
def NotBorrowed (ds : DState) (i : Inst) : Prop :=
  ∀ c ∈ i.consumes, ∀ fp, ds.env c ≠ .bor fp

/-- No operand read by the instruction points into a tree it consumes (a constructor with an
owned result is exempt: it retains the trees it consumes, `Retains`; one with an `emptied`
result is exempt too: the storage moves into the parts that are taken out at once, and the
checker allows no later use of a view of what it consumed). -/
def Separate (ds : DState) (i : Inst) : Prop :=
  ∀ r ∈ i.reads, ∀ x, (ds.env r).cells ds.heap x →
    ∀ t ∈ consumedRoots ds i, ds.heap x ≠ .live t

/-- A container with a pending take is consumed only by the closing update, as its first
consumed operand. -/
def NoStale (ds : DState) (i : Inst) : Prop :=
  ∀ c ∈ i.consumes, ∀ t, ds.env c = .own t → (∃ k, ds.pend t k = true) →
    i.isClosing = true ∧ i.consumes.head? = some c

/-- A take reads a live owned container whose slot is not already taken (or an `imm`: an
`emptied` aggregate or a null owner, which has nothing to take). -/
def TransferOk (ctx : Ctx) (ds : DState) (i : Inst) : Prop :=
  isTransfer ctx i = true →
    match i.reads.head? with
    | none => True
    | some a =>
      match ds.env a with
      | .imm => True
      | .stk => True
      | .own t => ds.heap t = .live t ∧ ∀ k, i.slot = some k → ds.pend t k = false
      | .bor _ => False

/-- The closing update agrees with the slots that are open in its container (`closeAgrees`). -/
def CloseOk (ds : DState) (i : Inst) : Prop :=
  match closeTarget ds i with
  | some t => closeAgrees (ds.pend t) i = true
  | none => True

/-- No stack allocation escapes (design J7): a `stk` value is consumed only as the first operand
of an update whose result is a stack list (a filling push), and the values stored into it own no
tree. -/
def NoEscape (ctx : Ctx) (ds : DState) (i : Inst) : Prop :=
  (∀ k ∈ i.consumes, ds.env k = .stk →
      i.cls = .update ∧ i.consumes.head? = some k ∧ i.res ctx = .stack) ∧
  (∀ c, i.consumes.head? = some c → ds.env c = .stk →
      ∀ k ∈ i.consumes.tail, ∀ t, ds.env k ≠ .own t)

/-- The loans of the owned values an instruction reads are on live allocations (design J4): the
certificate lists, as the parents of an owned value, what its contents point into (assumption A12),
and each of them is live. -/
def LoansLive (ctx : Ctx) (ds : DState) (i : Inst) : Prop :=
  ∀ r ∈ i.reads, ctx.cert.state r = .owned → ∀ n, Root.val n ∈ ctx.cert.parents r →
    (ds.env n).alive ds.heap

/-- No cell lent to a live group, or held by a live owned tree, is destroyed (design §10.6, rule K1,
and J4): when an instruction consumes the tree of such a cell, the holder's tree is consumed with it
(the join, or a drop of both), or the instruction is a constructor with an owned result, which keeps
what it consumes (`Retains`). -/
def LentSafe (ctx : Ctx) (ds : DState) (i : Inst) : Prop :=
  ∀ g x t, (ds.lent g x ∨ ds.held g x) → (∃ l, ds.heap g = .live l ∧ l ∉ consumedRoots ds i) →
    ds.heap x = .live t → t ∈ consumedRoots ds i →
    i.cls = .construct ∧ i.res ctx = .owned

/-- The instruction would fault in state `ds` with fault `f`. -/
def Violates (ctx : Ctx) (ds : DState) (i : Inst) : Fault → Prop
  | .readDead => ¬ ReadsAlive ds i
  | .consumeDead => ¬ ConsumeLive ds i
  | .destroyTwice => ¬ ConsumeOnce ds i
  | .takeBorrowed => ¬ NotBorrowed ds i
  | .overlap => ¬ (i.cls = .construct ∧ (i.res ctx = .owned ∨ i.res ctx = .emptied)) ∧
      ¬ Separate ds i
  | .stranded => ¬ NoStale ds i ∨ ¬ TransferOk ctx ds i ∨ ¬ CloseOk ds i
  | .escape => ¬ NoEscape ctx ds i
  | .dangling => ¬ LoansLive ctx ds i
  | .lentGone => ¬ LentSafe ctx ds i
  | .calleeFault => False

/-! ## Small-step execution -/

/-- A borrowed phi that selects an owned value reads it: it holds a pointer to its tree. -/
def Val.toBorrowed : Val → Val
  | .own t => .bor [t]
  | v => v

/-- Phi values on entering a block along the edge from `p`: all live phis read the old
environment (a phi may use another phi of the same block); a dead phi (state `none`) is
skipped; a borrowed phi holds a pointer to an owned operand's tree. -/
def applyPhis (c : Certificate) (phis : List Phi) (p : BlockId) (env : ValId → Val) :
    ValId → Val :=
  fun n =>
    match phis.find? (fun φ => φ.dst == n && Phi.live c φ) with
    | some φ => match φ.edges.lookup p with
      | some o => if c.state n == .borrowed then (env o).toBorrowed else env o
      | none => env n
    | none => env n

/-- The values flowing into the live phis of a block along the edge from `p`. -/
def incoming (c : Certificate) (phis : List Phi) (p : BlockId) : List ValId :=
  (phis.filter (Phi.live c)).filterMap fun φ => φ.edges.lookup p

/-- Every live phi has an operand along the edge from `p` (the checker's `phi-operand`). -/
def EdgeDefined (c : Certificate) (phis : List Phi) (p : BlockId) : Prop :=
  ∀ φ ∈ phis, Phi.live c φ = true → ∃ o, φ.edges.lookup p = some o

/-- A machine configuration of one activation. -/
inductive Config where
  /-- about to execute instruction `k` of block `b` (`k` = length: the terminator) -/
  | run (b : BlockId) (k : Nat) (ds : DState)
  /-- returned normally with a value -/
  | ret (ds : DState) (v : Val)
  /-- trapped: the process ends, no destruction runs (RC-TRAP-TEARDOWN-1) -/
  | trap
  /-- an ownership fault -/
  | fault (k : Fault)

/-- One step of the function body.  The value of a call is whatever `Effect` allows
(assume-guarantee); a trap may end any instruction. -/
inductive Step (ctx : Ctx) : Config → Config → Prop
  /-- an instruction whose operands are all in order -/
  | inst {b k : Nat} {i : Inst} {ds ds' : DState} :
      ctx.fn.instAt b k = some i → (∀ f, ¬ Violates ctx ds i f) → Effect ctx ds i ds' →
      Step ctx (.run b k ds) (.run b (k + 1) ds')
  /-- an instruction with a bad operand faults -/
  | instFault {b k : Nat} {i : Inst} {ds : DState} (f : Fault) :
      ctx.fn.instAt b k = some i → Violates ctx ds i f → Step ctx (.run b k ds) (.fault f)
  /-- any instruction may trap (arithmetic, bounds, calls) -/
  | instTrap {b k : Nat} {i : Inst} {ds : DState} :
      ctx.fn.instAt b k = some i → Step ctx (.run b k ds) .trap
  /-- `jump b'`: the live phis of `b'` take their values along the edge.  An edge whose phi
  operand is an `undef` is live (the null owner, `imm`).  The phis redefine values, which
  forgets the tests that depend on them. -/
  | jump {b : BlockId} {blk blk' : Block} {b' : BlockId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .jump b' → ctx.fn.block? b' = some blk' →
      EdgeDefined ctx.cert blk'.phis b →
      (∀ o ∈ incoming ctx.cert blk'.phis b, (ds.env o).alive ds.heap) →
      Step ctx (.run b blk.insts.length ds)
        (.run b' 0 { abandonNext ds (blk'.abandonFrom b) with
                       env := applyPhis ctx.cert blk'.phis b ds.env,
                       facts := clearFacts ds.facts (phiDsts ctx.cert blk'.phis) })
  /-- a phi operand that cannot be read faults -/
  | jumpFault {b : BlockId} {blk blk' : Block} {b' : BlockId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .jump b' → ctx.fn.block? b' = some blk' →
      EdgeDefined ctx.cert blk'.phis b →
      (∃ o ∈ incoming ctx.cert blk'.phis b, ¬ (ds.env o).alive ds.heap) →
      Step ctx (.run b blk.insts.length ds) (.fault .readDead)
  /-- `branch c t f`: the condition is read; either successor may be taken, except that a test
  already decided keeps its outcome (**A8**: a pure `cmp` or `fcmp` of the same predicate on
  operands that were not redefined gives the same answer, constants being compared by value).
  The branch decides its test (unless both targets are one block). -/
  | branch {b : BlockId} {blk blk' : Block} {c : ValId} {t f b' : BlockId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .branch c t f → (b' = t ∨ b' = f) →
      ctx.fn.block? b' = some blk' →
      (t ≠ f → ds.facts (ctx.key c) = none ∨ ds.facts (ctx.key c) = some (decide (b' = t))) →
      EdgeDefined ctx.cert blk'.phis b →
      (ds.env c).alive ds.heap → (∀ o ∈ incoming ctx.cert blk'.phis b, (ds.env o).alive ds.heap) →
      Step ctx (.run b blk.insts.length ds)
        (.run b' 0 { abandonNext ds (blk'.abandonFrom b) with
                       env := applyPhis ctx.cert blk'.phis b ds.env,
                       facts := clearFacts
                         (if t = f then ds.facts else setFact ds.facts (ctx.key c) (decide (b' = t)))
                         (phiDsts ctx.cert blk'.phis) })
  | branchFault {b : BlockId} {blk : Block} {c : ValId} {t f : BlockId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .branch c t f → ¬ (ds.env c).alive ds.heap →
      Step ctx (.run b blk.insts.length ds) (.fault .readDead)
  | branchPhiFault {b : BlockId} {blk blk' : Block} {c : ValId} {t f b' : BlockId}
      {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .branch c t f → (b' = t ∨ b' = f) →
      ctx.fn.block? b' = some blk' →
      (t ≠ f → ds.facts (ctx.key c) = none ∨ ds.facts (ctx.key c) = some (decide (b' = t))) →
      EdgeDefined ctx.cert blk'.phis b →
      (∃ o ∈ incoming ctx.cert blk'.phis b, ¬ (ds.env o).alive ds.heap) →
      Step ctx (.run b blk.insts.length ds) (.fault .readDead)
  /-- `ret`: the returned value is read (an owned result is consumed, which only moves it) -/
  | retNone {b : BlockId} {blk : Block} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .ret none →
      Step ctx (.run b blk.insts.length ds) (.ret ds .imm)
  | retVal {b : BlockId} {blk : Block} {v : ValId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .ret (some v) → (ds.env v).alive ds.heap →
      ds.env v ≠ .stk →
      Step ctx (.run b blk.insts.length ds) (.ret ds (ds.env v))
  /-- returning a stack list lets it outlive the activation -/
  | retEscape {b : BlockId} {blk : Block} {v : ValId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .ret (some v) → ds.env v = .stk →
      Step ctx (.run b blk.insts.length ds) (.fault .escape)
  | retFault {b : BlockId} {blk : Block} {v : ValId} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .ret (some v) → ¬ (ds.env v).alive ds.heap →
      Step ctx (.run b blk.insts.length ds) (.fault .readDead)
  /-- `unreachable` traps -/
  | unreachable {b : BlockId} {blk : Block} {ds : DState} :
      ctx.fn.block? b = some blk → blk.term = .unreachable →
      Step ctx (.run b blk.insts.length ds) .trap

/-- Zero or more steps. -/
inductive Star (ctx : Ctx) : Config → Config → Prop
  | refl (c : Config) : Star ctx c c
  | step {c₁ c₂ c₃ : Config} : Step ctx c₁ c₂ → Star ctx c₂ c₃ → Star ctx c₁ c₃

/-- Whether a configuration is a fault. -/
def Config.isFault : Config → Prop
  | .fault _ => True
  | _ => False

/-! ## The contract of a function (design §6) -/

/-- The value parameter `i` has at entry for the SSA name `d` of a parameter instruction;
every other name starts as an immediate (constants, not-yet-defined names). -/
def Function.initEnv (f : Function) (args : Nat → Val) : ValId → Val :=
  fun d => match f.paramIdx d with
    | some k => args k
    | none => .imm

/-- Before the call: the heap is well formed (the root of every live cell's tree is a live
cell labelled by itself, an invariant `Xform` preserves); owned arguments are live, own
disjoint trees and have nothing pending; borrowed arguments are live and lie outside the
owned trees (the caller keeps them alive for the whole call; call-site rule J6 / M5). -/
structure Pre (f : Function) (args : Nat → Val) (h : Heap) (pend : Addr → String → Bool) : Prop where
  wf : ∀ x t, h x = .live t → h t = .live t
  scalar : ∀ i, f.params[i]? = some .scalar → args i = .imm
  owned : ∀ i, f.params[i]? = some .owned →
    args i = .imm ∨ ∃ t, args i = .own t ∧ h t = .live t ∧ ∀ k, pend t k = false
  ownedDisjoint : ∀ i j t, f.params[i]? = some .owned → f.params[j]? = some .owned →
    args i = .own t → args j = .own t → i = j
  borrowed : ∀ i, f.params[i]? = some .borrowed →
    (args i = .imm ∨ ∃ fp, args i = .bor fp) ∧ (args i).alive h
  apart : ∀ i j t, f.params[i]? = some .owned → args i = .own t →
    f.params[j]? = some .borrowed → ∀ x, (args j).cells h x → h x ≠ .live t

/-- `t` is the tree of an owned argument. -/
def OwnedArg (f : Function) (args : Nat → Val) (t : Addr) : Prop :=
  ∃ i, f.params[i]? = some .owned ∧ args i = .own t

/-- The result has the shape the signature promises. -/
def ResultShape (f : Function) (args : Nat → Val) (ds0 ds : DState) (v : Val) : Prop :=
  match f.result with
  | .owned => v = .imm ∨ ∃ r, v = .own r ∧ ds.heap r = .live r ∧ ∀ k, ds.pend r k = false
  | .borrowed => v = .imm ∨ ∃ fp, v = .bor fp ∧ v.alive ds.heap ∧
      ∀ x ∈ fp, ∃ i ∈ f.from_, (args i).cells ds0.heap x
  | _ => v = .imm

/-- After a normal return (`ds0` is the state at the call, `ds` the state at the `ret`):
* every cell outside the owned arguments' trees, the borrowed arguments' trees included, is
  unchanged and live;
* every cell of an owned argument's tree has been destroyed or lies in the tree of the owned
  result;
* every cell allocated during the call is destroyed or lies in the tree of the owned result;
* an owned result's tree is fresh: it contains no cell of the caller's other trees;
* the result has the signature's shape: an owned result is a root with nothing pending, a
  borrowed result lies inside the trees of the arguments its `from` set names. -/
structure Post (f : Function) (args : Nat → Val) (ds0 ds : DState) (v : Val) : Prop where
  frame : ∀ x t, ds0.heap x = .live t → ¬ OwnedArg f args t → ds.heap x = .live t
  deadStays : ∀ x, ds0.heap x = .dead → ds.heap x = .dead
  consumed : ∀ x t, ds0.heap x = .live t → OwnedArg f args t →
    ds.heap x = .dead ∨ ∃ r, v = .own r ∧ ds.heap x = .live r
  created : ∀ x, ds0.heap x = .unused →
    ds.heap x = .unused ∨ ds.heap x = .dead ∨ ∃ r, v = .own r ∧ ds.heap x = .live r
  fresh : ∀ r x, v = .own r → ds.heap x = .live r → ds0.heap x ≠ .dead ∧
    ¬ ∃ t, ds0.heap x = .live t ∧ ¬ OwnedArg f args t
  shape : ResultShape f args ds0 ds v

/-- The context of an activation entered with `args`. -/
def Ctx.entering (f : Function) (cert : Certificate) (args : Nat → Val) : Ctx :=
  { fn := f, cert := cert, callerVals := args }

/-- The configuration at entry. -/
def Function.entry (f : Function) (args : Nat → Val) (h : Heap) (pend : Addr → String → Bool) :
    Config :=
  .run 0 0 { heap := h, pend := pend, env := f.initEnv args, facts := fun _ => none }

/-- **Safety of a function** (design §6): from a state meeting the before-the-call
condition, no execution faults, and every normal return meets the after-return condition. -/
def Safe (f : Function) (cert : Certificate) (args : Nat → Val) (h : Heap)
    (pend : Addr → String → Bool) : Prop :=
  ∀ c, Star (Ctx.entering f cert args) (f.entry args h pend) c →
    ¬ c.isFault ∧
    ∀ ds v, c = .ret ds v →
      Post f args { heap := h, pend := pend, env := f.initEnv args, facts := fun _ => none } ds v

end Own
