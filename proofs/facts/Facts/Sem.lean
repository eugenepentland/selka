import Facts.Run
import Arith.Basic

/-!
# What executions do

A small-step machine over the certificate's IR (design §7, "Model"): mathematical integers, lists, and
opaque values; blocks with phis, instructions and a terminator; direct calls with a call stack.

* An integer operation has the three forms of §4: `none` wraps, `exact` traps when the exact result is
  outside the type, `proven` is undefined behaviour then (`Res.ub`). A shift count outside the width, a zero
  divisor and an out-of-bounds access fail the same way by their form.
* An operation the checker has no exact model of returns any value its type allows (a *choice* the step
  relation quantifies over); `Allowed` says what the model grants of it. The stated intervals of such results
  are the checker's assumptions A6, which the soundness theorem's `Adm` asks executions to honour.
* The machine knows nothing of facts: the soundness theorem is about what every such execution does.
* A step is *typed*: the value an instruction produces has the instruction's declared type (`ValTy`). The IR
  verifier checks the signature of every operation and the runtime is type safe; the model takes it as given
  (`NOTES.md`, assumption TY).
-/

namespace Facts

/-- A run-time value: an integer or boolean, a list (also a list view and a fixed array), anything else. -/
inductive Val where
  | int (n : Int)
  | list (l : List Val)
  | other
  deriving Inhabited

/-- The register file of a frame. -/
abbrev Regs := Nat → Option Val

/-- Write register `u`. -/
def Regs.set (r : Regs) (u : Nat) (v : Val) : Regs := fun w => if w = u then some v else r w

theorem Regs.set_same (R : Regs) (u : Nat) (v : Val) : (R.set u v) u = some v := by simp [Regs.set]

theorem Regs.set_ne (R : Regs) {u w : Nat} (v : Val) (h : w ≠ u) : (R.set u v) w = R w := by simp [Regs.set, h]

/-- The register an optional operand names. -/
def Regs.read (r : Regs) (o : Option Nat) : Option Val := o.bind r

/-- The integer a value is, if it is one. -/
def Val.int? : Val → Option Int
  | .int n => some n
  | _ => none

/-- The list a value is, if it is one. -/
def Val.list? : Val → Option (List Val)
  | .list l => some l
  | _ => none

/-- `x` reduced into the range of type `t` by wrapping modulo `2^bits`. -/
def wrapTo (t : Ty) (x : Int) : Int :=
  match t.range with
  | none => x
  | some r => r.lo + (x - r.lo) % (r.hi - r.lo + 1)

/-- The values of an instruction's operands, read from a register file. -/
structure Ops where
  a : Option Val := none
  b : Option Val := none
  x : List (Option Val) := []
  /-- The argument a `param` instruction reads. -/
  arg : Option Val := none

/-- Read the operands of `i`, in a frame called with `args`. -/
def readOps (r : Regs) (args : List Val) (i : Inst) : Ops :=
  { a := if i.op == .call then none else r.read i.operands.a, b := r.read i.operands.b,
    x := i.operands.x.map r.read, arg := args[i.imm]? }

/-- The outcome of evaluating one instruction. -/
inductive Res where
  | val (v : Val)
  | trap
  | ub
  | stuck

/-- The result `r` of an arithmetic operation, by the instruction's form. -/
def Res.ofInt (t : Ty) (ck : Check) (r : Int) : Res :=
  match t.range with
  | some lim =>
    if lim.lo ≤ r ∧ r ≤ lim.hi then .val (.int r)
    else
      match ck with
      | .none => .val (.int (wrapTo t r))
      | .exact => .trap
      | .proven => .ub
  | none => .val (.int r)

/-- What an operation does when its precondition fails (a zero divisor, a count outside the width, an access out of
bounds): a checked one traps, any other is undefined behaviour. -/
def failWith (ck : Check) : Res :=
  match ck with
  | .exact => .trap
  | _ => .ub

/-- The value a parameter of type `t` takes when the argument `a` is passed: the same bits at the parameter's
type. -/
def paramVal (t : Ty) : Val → Val
  | .int n => .int (wrapTo t n)
  | v => v

/-- The comparison `x p y`. -/
def predEval : Pred → Int → Int → Bool
  | .eq, x, y => decide (x = y)
  | .ne, x, y => decide (x ≠ y)
  | .lt, x, y => decide (x < y)
  | .le, x, y => decide (x ≤ y)
  | .gt, x, y => decide (x > y)
  | .ge, x, y => decide (x ≥ y)

/-- `bit_xor` of two values of type `t`: the bitwise exclusive or of their two's complement bits. -/
def xorVal (t : Ty) (x y : Int) : Int :=
  Arith.ival t.signed (BitVec.ofInt t.bits x ^^^ BitVec.ofInt t.bits y)

/-- Evaluate one instruction on its operand values; `ch` is the value a free operation returns. -/
def evalOps (i : Inst) (o : Ops) (ch : Val) : Res :=
  let t := i.ty
  let ck := i.check
  let x? := o.a.bind Val.int?
  let y? := o.b.bind Val.int?
  match i.op with
  | .iconst => .val (.int (constVal t i.imm))
  | .param => match o.arg with | some a => .val (paramVal t a) | none => .stuck
  | .add => match x?, y? with | some x, some y => Res.ofInt t ck (x + y) | _, _ => .stuck
  | .sub => match x?, y? with | some x, some y => Res.ofInt t ck (x - y) | _, _ => .stuck
  | .mul => match x?, y? with | some x, some y => Res.ofInt t ck (x * y) | _, _ => .stuck
  | .saturatingAdd =>
    match x?, y?, t.range with
    | some x, some y, some lim => .val (.int (max lim.lo (min lim.hi (x + y))))
    | _, _, _ => .stuck
  | .shiftLeft =>
    match x?, y? with
    | some x, some y =>
      if 0 ≤ y ∧ y < (t.bits : Int) then .val (.int (wrapTo t (x * 2 ^ y.toNat))) else failWith ck
    | _, _ => .stuck
  | .shiftRight =>
    match x?, y? with
    | some x, some y =>
      if 0 ≤ y ∧ y < (t.bits : Int) then .val (.int (x >>> y.toNat)) else failWith ck
    | _, _ => .stuck
  | .floorDiv =>
    match x?, y? with
    | some x, some y => if y = 0 then failWith ck else Res.ofInt t ck (Int.fdiv x y)
    | _, _ => .stuck
  | .div =>
    match x?, y? with
    | some x, some y => if y = 0 then failWith ck else Res.ofInt t ck (Int.tdiv x y)
    | _, _ => .stuck
  | .floorRem =>
    match x?, y? with
    | some x, some y => if y = 0 then failWith ck else .val (.int (Int.fmod x y))
    | _, _ => .stuck
  | .rem =>
    match x?, y? with
    | some x, some y => if y = 0 then failWith ck else .val (.int (Int.tmod x y))
    | _, _ => .stuck
  | .neg => match x? with | some x => Res.ofInt t ck (-x) | none => .stuck
  | .bitXor => match x?, y? with | some x, some y => .val (.int (xorVal t x y)) | _, _ => .stuck
  | .convert => match x? with | some x => Res.ofInt t ck x | none => .stuck
  | .cmp =>
    match Pred.ofImm i.imm, x?, y? with
    | some p, some x, some y => .val (.int (if predEval p x y then 1 else 0))
    | _, _, _ => .stuck
  | .not => match x? with | some x => .val (.int (1 - x)) | none => .stuck
  | .listLen => match o.a.bind Val.list? with | some l => .val (.int l.length) | none => .stuck
  | .listGet | .arrayGet =>
    match o.a.bind Val.list?, y? with
    | some l, some k => if 0 ≤ k ∧ k < (l.length : Int) then .val (l[k.toNat]!) else failWith ck
    | _, _ => .stuck
  | .listSet | .arraySet =>
    match o.a.bind Val.list?, y?, o.x with
    | some l, some k, some e :: _ =>
      if 0 ≤ k ∧ k < (l.length : Int) then .val (.list (l.set k.toNat e)) else failWith ck
    | _, _, _ => .stuck
  | .listPop =>
    match o.a.bind Val.list? with
    | some l => if l.isEmpty then failWith ck else .val (.list l.dropLast)
    | none => .stuck
  | .listPush =>
    match o.a.bind Val.list?, o.b with
    | some l, some e => if (l.length : Int) + 1 > maxListLength then .trap else .val (.list (l ++ [e]))
    | _, _ => .stuck
  | .listNew => .val (.list [])
  | .listCopy | .listViewOf | .borrow =>
    match o.a.bind Val.list? with
    | some l => .val (.list l)
    | none => .stuck
  | .recordMake => if t = .list then .val (.list (o.x.map fun e => e.getD .other)) else .val ch
  | _ => .val ch

/-- Evaluate one instruction in register file `r` of a frame called with `args`. -/
def evalInst (r : Regs) (args : List Val) (i : Inst) (ch : Val) : Res := evalOps i (readOps r args i) ch

/-- The values of a type: an integer in the type's range, a list of at most `M` elements, or (for every other type)
an opaque value. -/
def ValTy (t : Ty) (v : Val) : Prop :=
  match t.range with
  | some r => ∃ n, v = .int n ∧ r.lo ≤ n ∧ n ≤ r.hi
  | none =>
    match t with
    | .list => ∃ l, v = .list l ∧ (l.length : Int) ≤ maxListLength
    | _ => v = .other

/-- What the model grants of a freely chosen result beyond its type: a length is in `[0, M]`. -/
def Allowed (i : Inst) (v : Val) : Prop :=
  match i.op with
  | .strLen | .dictEntries => ∃ n, v = .int n ∧ 0 ≤ n ∧ n ≤ maxListLength
  | _ => True

/-- A frame: a function activation at instruction `pc` of block `blk`. -/
structure Frame where
  fn : Nat
  args : List Val
  regs : Regs
  blk : Nat
  pc : Nat

/-- A call stack, the running frame first. -/
abbrev Config := List Frame

/-- The value phi `p` takes when its block is entered from `from_`, read in the old registers. -/
def phiNew (r : Regs) (from_ : Nat) (p : Phi) : Option Val :=
  match p.edges.find? (·.block == from_) with
  | some e => r e.value
  | none => none

/-- One step of the phi copy. -/
def phiStep (r : Regs) (from_ : Nat) (acc : Regs) (p : Phi) : Regs :=
  match phiNew r from_ p with
  | some v => acc.set p.value v
  | none => acc

/-- The registers after entering block `t` from block `from_`: each phi takes the operand of its edge from `from_`
(the old register file is read, so the phis are a parallel copy). -/
def enterRegs (r : Regs) (t : Block) (from_ : Nat) : Regs := t.phis.foldl (phiStep r from_) r

/-- The registers of a fresh activation of `f` called with `args`: each constant, parameter and other `pre` value takes
the value its operation gives (a free choice for an operation the checker does not model, within what its type
allows); nothing else is defined. -/
def InitRegs (f : Function) (args : List Val) (r : Regs) : Prop :=
  (∀ i ∈ f.pre, ∃ ch v, evalInst (fun _ => none) args i ch = .val v ∧ ValTy i.ty v ∧ Allowed i v ∧
    r i.value = some v) ∧
  (∀ u, (∀ i ∈ f.pre, i.value ≠ u) → r u = none)

/-- The function a call instruction names, when it has a body. -/
def callee? (m : Module) (i : Inst) : Option (Nat × Function) :=
  match i.operands.a with
  | some g =>
    match m.functions[g]? with
    | some h => if h.blocks.size > 0 then some (g, h) else none
    | none => none
  | none => none

/-- The arguments of a call: the registers of its argument list (an absent one is an opaque unit). -/
def callArgs (r : Regs) (i : Inst) : List Val := i.operands.x.map fun o => (r.read o).getD .other

/-- A fixed array has the length its type declares (`aux` of the access): the machine takes it as given
(`NOTES.md`, assumption TY). -/
def ArrayTy (r : Regs) (args : List Val) (i : Inst) : Prop :=
  (i.op = .arrayGet ∨ i.op = .arraySet) → ∃ l, (readOps r args i).a = some (.list l) ∧ (l.length : Int) = i.aux

/-- One step of the machine. -/
inductive Step (m : Module) : Config → Config → Prop where
  /-- Execute an instruction other than a call to a function with a body. -/
  | inst {fr : Frame} {rest : Config} {f : Function} {blk : Block} {i : Inst} {ch v : Val} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts[fr.pc]? = some i →
      (i.op = .call → callee? m i = none) → ArrayTy fr.regs fr.args i →
      evalInst fr.regs fr.args i ch = .val v → ValTy i.ty v → Allowed i v →
      Step m (fr :: rest) ({ fr with regs := fr.regs.set i.value v, pc := fr.pc + 1 } :: rest)
  /-- Call a function with a body: a new frame. -/
  | call {fr : Frame} {rest : Config} {f : Function} {blk : Block} {i : Inst} {g : Nat} {h : Function}
      {regs : Regs} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts[fr.pc]? = some i →
      i.op = .call → callee? m i = some (g, h) → InitRegs h (callArgs fr.regs i) regs →
      Step m (fr :: rest) ({ fn := g, args := callArgs fr.regs i, regs, blk := 0, pc := 0 } :: fr :: rest)
  /-- Jump to a block, entering its phis. -/
  | jump {fr : Frame} {rest : Config} {f : Function} {blk tb : Block} {t : Nat} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts.length = fr.pc →
      blk.term = .jump t → f.blocks[t]? = some tb →
      Step m (fr :: rest) ({ fr with regs := enterRegs fr.regs tb fr.blk, blk := t, pc := 0 } :: rest)
  /-- Branch on a boolean. -/
  | branch {fr : Frame} {rest : Config} {f : Function} {blk tb : Block} {c t e s : Nat} {k : Int} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts.length = fr.pc →
      blk.term = .branch c t e → fr.regs c = some (.int k) → (k = 1 ∧ s = t ∨ k = 0 ∧ s = e) →
      f.blocks[s]? = some tb →
      Step m (fr :: rest) ({ fr with regs := enterRegs fr.regs tb fr.blk, blk := s, pc := 0 } :: rest)
  /-- Return to the caller, which was at its call instruction. -/
  | ret {fr cr : Frame} {rest : Config} {f cf : Function} {blk cb : Block} {i : Inst} {v : Val} {rv : Option Nat}
      {h : Function} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts.length = fr.pc →
      blk.term = .ret rv → v = (fr.regs.read rv).getD .other →
      m.functions[cr.fn]? = some cf → cf.blocks[cr.blk]? = some cb → cb.insts[cr.pc]? = some i →
      i.op = .call → callee? m i = some (fr.fn, h) → ValTy i.ty v →
      Step m (fr :: cr :: rest) ({ cr with regs := cr.regs.set i.value v, pc := cr.pc + 1 } :: rest)

/-- An instruction whose evaluation is undefined behaviour from this configuration. -/
inductive StepUb (m : Module) : Config → Inst → Prop where
  | inst {fr : Frame} {rest : Config} {f : Function} {blk : Block} {i : Inst} {ch : Val} :
      m.functions[fr.fn]? = some f → f.blocks[fr.blk]? = some blk → blk.insts[fr.pc]? = some i →
      ArrayTy fr.regs fr.args i → evalInst fr.regs fr.args i ch = .ub → StepUb m (fr :: rest) i

/-- The configurations of one external entry: a function called with arguments. -/
def Entry (m : Module) (g : Nat) (args : List Val) (cfg : Config) : Prop :=
  ∃ h regs, m.functions[g]? = some h ∧ h.blocks.size > 0 ∧ InitRegs h args regs ∧
    cfg = [{ fn := g, args, regs, blk := 0, pc := 0 }]

end Facts
