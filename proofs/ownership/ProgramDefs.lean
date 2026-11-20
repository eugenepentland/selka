import Soundness
import Link

/-!
# Whole-program semantics (for the corollary of design §6)

The per-function theorem (`Soundness.lean`) is about one activation in which a call may do
anything its contract allows.  Here a call to a function of the program *runs it*:

* a `Program` is a list of functions with their certificates; a call line names an entry of its
  function's callee table (`Inst.entry`), the entry names the callee and gives the passing mode of each
  parameter, and the arguments in parameter order are read off the entry (`Inst.argsOf`);
* `PStep` is `Step`, except that at a call to a function of the program the callee's own
  execution decides the outcome (`R`), with the callee's arguments built from the caller's
  environment: an owned argument is passed as is, any other is lent (`lend`);
* `RunsAt prog d` is the outcome of a complete run of a function that nests calls at most `d`
  deep.  Every finite execution has a finite call depth, and a recursive call is a run at
  smaller depth, so an induction on `d` covers all finite executions, recursion included.

Calls to other functions (`extern func`, `myl_core_*`) are still resolved by the contract
(`Step.inst`): that is design assumption A5.

**A call whose result is an `emptied` record** (the write-back record of a function with `mut`
parameters, which the caller takes apart at once; C9.4) is run like any other, but the caller's model
does not keep the record: `callNext` binds the destination to an immediate and destroys the callee's
result tree (`dissolve`), because the parts the caller then takes out are modelled as fresh trees, the way
the per-function semantics already treats an `emptied` constructor, `record_get` and `union_take`.  That the
storage of the returned record is exactly the storage of those parts is assumption A16 (`AXIOMS.md`).
-/

namespace Own

/-- A value lent to a callee for a read argument: the callee can reach the owned tree
without owning it. -/
def lend : Val → Val
  | .imm => .imm
  | .stk => .imm
  | .own t => .bor [t]
  | .bor fp => .bor fp

/-- The callee's arguments, from the caller's environment and the call's argument list. -/
def argOf (A : List (ValId × Bool)) (env : ValId → Val) : Nat → Val := fun I =>
  match A[I]? with
  | some (n, true) => env n
  | some (n, false) => lend (env n)
  | none => .imm

/-- The outcome of a run. -/
inductive Out where
  | ret (ds : DState) (v : Val)
  | trap
  | fault

/-- Runs of the callees: `R g args heap pend out` says the function `g` run with `args` in
the given heap ends with `out`. -/
abbrev CallRes := Nat → (Nat → Val) → Heap → (Addr → String → Bool) → Out → Prop

/-- The root of a returned owned tree. -/
def resRoot : Val → Option Addr
  | .own t => some t
  | _ => none

/-- The cells of the tree rooted at `r` are destroyed (assumption A16: the parts of an `emptied` call result
are modelled as fresh trees by the takes that follow, as for an `emptied` constructor, whose consumed trees
`Xform` destroys). -/
def dissolve (h : Heap) (r : Addr) : Heap := fun x => if h x = .live r then .dead else h x

/-- The value a call binds to its destination: an `emptied` record owns nothing (`imm`). -/
def callVal (ctx : Ctx) (i : Inst) (v : Val) : Val :=
  if i.res ctx = .emptied then .imm else v

/-- The heap of the caller after a call returns `v` in the heap `h`: the callee's heap, except that the tree
of an `emptied` record is dissolved. -/
def callHeap (ctx : Ctx) (i : Inst) (h : Heap) : Val → Heap
  | .own r => if i.res ctx = .emptied then dissolve h r else h
  | _ => h

/-- The configuration of the caller after a call. -/
def callNext (ctx : Ctx) (b k : Nat) (ds : DState) (i : Inst) : Out → Config
  | .ret dsr v => .run b (k + 1)
      { ds with
        heap := callHeap ctx i dsr.heap v
        pend := pendAfter ctx ds i (resRoot (callVal ctx i v))
        env := match i.dst with
          | some d => upd ds.env d (callVal ctx i v)
          | none => ds.env
        facts := clearFacts ds.facts i.dst.toList
        held := heldAfter ctx ds i (resRoot (callVal ctx i v)) }
  | .trap => .trap
  | .fault => .fault .calleeFault

/-- The index of the function of the program a name denotes (the first of that name). -/
def Program.indexOf (prog : Program) (name : String) : Option Nat := prog.findIdx? fun fc => fc.1.name == name

/-- The call instruction at a position, with its table entry and its callee, when it calls a function of the
program: a call line whose entry is of kind `program` and names a function of the program. -/
def Program.callAt (prog : Program) (ctx : Ctx) (b k : Nat) : Option (Inst × CalleeEntry × Nat) :=
  match ctx.fn.instAt b k with
  | some i =>
    match ctx.fn.entryOf i with
    | some e =>
      if i.cls == .call && e.kind == .program then (prog.indexOf e.name).map fun g => (i, e, g) else none
    | none => none
  | none => none

/-- One step of a function whose calls to functions of the program run those functions. -/
inductive PStep (prog : Program) (R : CallRes) (ctx : Ctx) : Config → Config → Prop
  /-- any step of the contract semantics, except the completion of a call to a function of
  the program -/
  | loc {c c' : Config} : Step ctx c c' →
      (∀ b k ds, c = .run b k ds → prog.callAt ctx b k ≠ none →
        (∃ f, c' = .fault f) ∨ c' = .trap) →
      PStep prog R ctx c c'
  /-- a call to a function of the program: its run decides the outcome -/
  | call {b k : Nat} {i : Inst} {e : CalleeEntry} {g : Nat} {ds : DState} {out : Out} :
      prog.callAt ctx b k = some (i, e, g) → (∀ f, ¬ Violates ctx ds i f) →
      R g (argOf (i.argsOf e) ds.env) ds.heap ds.pend out →
      PStep prog R ctx (.run b k ds) (callNext ctx b k ds i out)

/-- Zero or more program steps. -/
inductive PStar (prog : Program) (R : CallRes) (ctx : Ctx) : Config → Config → Prop
  | refl (c : Config) : PStar prog R ctx c c
  | step {c₁ c₂ c₃ : Config} : PStep prog R ctx c₁ c₂ → PStar prog R ctx c₂ c₃ →
      PStar prog R ctx c₁ c₃

/-- The outcome a terminal configuration stands for. -/
def Config.out? : Config → Option Out
  | .ret ds v => some (.ret ds v)
  | .trap => some .trap
  | .fault _ => some .fault
  | .run .. => none

/-- The complete runs of function `g` whose calls nest at most `d` deep. -/
def RunsAt (prog : Program) : Nat → CallRes
  | 0 => fun _ _ _ _ _ => False
  | d + 1 => fun g args h pend out =>
      ∃ fc, prog[g]? = some fc ∧ ∃ c',
        PStar prog (RunsAt prog d) (Ctx.entering fc.1 fc.2 args) (fc.1.entry args h pend) c' ∧
          c'.out? = some out

/-- A value that holds no tree: a scalar, an immortal or a unit value. -/
def Unmanaged (cert : Certificate) (n : ValId) : Prop :=
  cert.state n = .scalar ∨ cert.state n = .immortal ∨ cert.state n = .none

/-- A call site agrees with its callee's signature and certificate: the arguments `A` are listed in parameter order and
split into the owned ones (`consumes`) and the others (`reads`); scalar parameters receive scalars, and so do the
parameters the callee's own certificate calls `scalar` (A9; a parameter the callee takes whose value is a scalar receives
a scalar in `consumes`); the state of the call's value follows the callee's result, a borrowed result is borrowed from the
arguments its `from` set names, a call without a value returns neither an owner nor a borrow; an `emptied` result is a
record the callee returns as an owner (A16); and the value is not a stack list (J1).

Since C9.2 this is not a hypothesis: the call-site half is checked per function from its callee table (`InstOk`:
J1 `call-entry`, `call-arity`, `call-scalar`, `call-result`, `call-from`), the entry half by the program-level link
(`Link.lean`), and `callWf_of_site` (`ProgramSite.lean`) derives it. -/
structure CallWf (cert : Certificate) (callee : Function × Certificate) (i : Inst)
    (A : List (ValId × Bool)) : Prop where
  cls : i.cls = .call
  len : A.length = callee.1.params.length
  mode : ∀ (I : Nat) (n : ValId) (b : Bool), A[I]? = some (n, b) →
    (callee.1.params[I]? = some .owned → b = true) ∧
    (b = true → callee.1.params[I]? = some .owned ∨ (callee.1.params[I]? = some .scalar ∧ Unmanaged cert n))
  cons : (A.filter (·.2)).map (·.1) = i.consumes
  rds : (A.filter fun a => !a.2).map (·.1) = i.reads
  scalar : ∀ (I : Nat) (n : ValId) (b : Bool), A[I]? = some (n, b) →
    callee.1.params[I]? = some .scalar → Unmanaged cert n
  argScalar : ∀ (I : Nat) (n : ValId) (b : Bool) (v : ValId), A[I]? = some (n, b) →
    callee.1.paramVals[I]? = some v → callee.2.state v = .scalar → Unmanaged cert n
  voidRes : i.dst = none → callee.1.result ≠ .owned ∧ callee.1.result ≠ .borrowed
  resOwned : ∀ d, i.dst = some d → (cert.state d).owning = true → callee.1.result = .owned
  resBor : ∀ d, i.dst = some d → cert.state d = .borrowed → callee.1.result = .borrowed ∧
    ∀ I ∈ callee.1.from_, ∃ n, A[I]? = some (n, false) ∧ (Unmanaged cert n ∨ Root.val n ∈ cert.parents d)
  resImm : ∀ d, i.dst = some d →
    (cert.state d = .scalar ∨ cert.state d = .immortal ∨ cert.state d = .none) →
    callee.1.result ≠ .owned ∧ callee.1.result ≠ .borrowed
  resEmptied : ∀ d, i.dst = some d → cert.state d = .emptied → callee.1.result = .owned
  noStack : ∀ d, i.dst = some d → cert.state d ≠ .stack

/-- A program that is well formed: all its functions check, and its callee tables link to its functions.  The call sites
agree with their callees as a consequence (`ProgWf.callWf`). -/
structure ProgWf (prog : Program) : Prop where
  checked : ∀ fc ∈ prog, check fc.1 fc.2 = true
  link : linkOk (prog.map LinkFn.of) = true

end Own
