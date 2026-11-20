import Arith.Isa

/-!
# LLVM semantics of the instructions on `BitVec n`

`Exec α` is the outcome of running straight-line code:

* `ok a`: it finished with `a`;
* `trap k`: control reached the cold trap block of kind `k` (defined behaviour, the program
  stops with a located diagnostic);
* `ub`: immediate undefined behaviour (LLVM LangRef: division by zero, `sdiv`/`srem` overflow);
* `poison`: an instruction produced a poison value. LLVM lets a poison value live until it is
  used by a branch, a division or a store. The model is stricter and stops at the instruction
  that creates it, so "the sequence never reaches `poison` or `ub`" implies no instruction of
  the sequence produces poison, used or not.

Register values are never poison in this model: a poison-creating instruction ends the run.
-/

namespace Arith

/-- Outcome of running straight-line LLVM code. -/
inductive Exec (α : Type) where
  | ok (a : α)
  | trap (k : Trap)
  | ub
  | poison
  deriving DecidableEq, Repr

namespace Exec

/-- Sequencing: stops at the first non-`ok` outcome. -/
protected def bind {α β : Type} (x : Exec α) (f : α → Exec β) : Exec β :=
  match x with
  | .ok a => f a
  | .trap k => .trap k
  | .ub => .ub
  | .poison => .poison

instance : Monad Exec where
  pure := .ok
  bind := Exec.bind

@[simp] theorem pure_def {α : Type} (a : α) : (pure a : Exec α) = .ok a := rfl
@[simp] theorem bind_ok {α β : Type} (a : α) (f : α → Exec β) : (Exec.ok a >>= f) = f a := rfl
@[simp] theorem bind_trap {α β : Type} (k : Trap) (f : α → Exec β) :
    (Exec.trap k >>= f) = Exec.trap k := rfl
@[simp] theorem bind_ub {α β : Type} (f : α → Exec β) : (Exec.ub >>= f) = Exec.ub := rfl
@[simp] theorem bind_poison {α β : Type} (f : α → Exec β) : (Exec.poison >>= f) = Exec.poison := rfl

end Exec

/-- The value of a register: `i1` is a `Bool`, `iN` a bit vector, `double` an `F64`. -/
@[reducible] def Ty.interp : Ty → Type
  | .i1 => Bool
  | .int n => BitVec n
  | .double => F64

/-- `icmp` on bit vectors. -/
def Pred.eval {n : Nat} : Pred → BitVec n → BitVec n → Bool
  | .eq, x, y => decide (x = y)
  | .ne, x, y => decide (x ≠ y)
  | .ult, x, y => x.ult y
  | .ule, x, y => x.ule y
  | .ugt, x, y => y.ult x
  | .uge, x, y => y.ule x
  | .slt, x, y => x.slt y
  | .sle, x, y => x.sle y
  | .sgt, x, y => y.slt x
  | .sge, x, y => y.sle x

/-- `fcmp` on the float model. -/
def FPred.eval : FPred → F64 → F64 → Bool
  | .ogt, x, y => F64.ogt x y
  | .oge, x, y => F64.oge x y
  | .olt, x, y => F64.olt x y

/-- `nsw`/`nuw` overflow of `x + y` makes the result poison when the flag is present. -/
def addPoison {n : Nat} (nsw nuw : Bool) (x y : BitVec n) : Bool :=
  (nsw && !decide (inRange true n (x.toInt + y.toInt))) ||
  (nuw && decide (2 ^ n ≤ x.toNat + y.toNat))

/-- `nsw`/`nuw` overflow of `x - y`. -/
def subPoison {n : Nat} (nsw nuw : Bool) (x y : BitVec n) : Bool :=
  (nsw && !decide (inRange true n (x.toInt - y.toInt))) ||
  (nuw && decide (x.toNat < y.toNat))

/-- `nsw`/`nuw` overflow of `x * y`. -/
def mulPoison {n : Nat} (nsw nuw : Bool) (x y : BitVec n) : Bool :=
  (nsw && !decide (inRange true n (x.toInt * y.toInt))) ||
  (nuw && decide (2 ^ n ≤ x.toNat * y.toNat))

@[simp] theorem addPoison_plain {n : Nat} (x y : BitVec n) : addPoison false false x y = false := by
  simp [addPoison]
@[simp] theorem subPoison_plain {n : Nat} (x y : BitVec n) : subPoison false false x y = false := by
  simp [subPoison]
@[simp] theorem mulPoison_plain {n : Nat} (x y : BitVec n) : mulPoison false false x y = false := by
  simp [mulPoison]

/-- `@llvm.uadd.sat` as hardware computes it: add, and saturate to the maximum when the sum wrapped
(the wrapped sum is below an operand exactly when the addition carried out). -/
def uaddSatBV {n : Nat} (x y : BitVec n) : BitVec n :=
  if (x + y).ult x then BitVec.allOnes n else x + y

/-- `@llvm.sadd.sat` as hardware computes it: add, and saturate to the minimum (operands negative)
or the maximum (operands non-negative) when the operands have the same sign and the sum's sign
differs. -/
def saddSatBV {n : Nat} (x y : BitVec n) : BitVec n :=
  if x.msb = y.msb ∧ (x + y).msb ≠ x.msb then
    (if x.msb then BitVec.intMin n else BitVec.intMax n)
  else x + y

/-- `fptosi`/`fptoui` to `iM`: poison unless the operand is finite and its truncation toward zero
fits, as LangRef says ("if the value cannot fit in the destination type, the result is poison"). -/
def fpToInt (signed : Bool) (m : Nat) (x : F64) : Exec (BitVec m) :=
  match x.trunc with
  | some t => if inRange signed m t then .ok (BitVec.ofInt m t) else .poison
  | none => .poison

/-- LLVM's semantics of the instruction set. -/
def Isa.exec : Isa Exec Ty.interp where
  iconst n v := BitVec.ofInt n v
  bconst b := b
  dconst bits := F64.ofBits bits
  icmp p _n x y := .ok (p.eval x y)
  and _n x y := .ok (x &&& y)
  xor _n x y := .ok (x ^^^ y)
  and1 x y := .ok (x && y)
  or1 x y := .ok (x || y)
  xor1 x y := .ok (x ^^ y)
  select _n c x y := .ok (if c then x else y)
  add _n nsw nuw x y := if addPoison nsw nuw x y then .poison else .ok (x + y)
  sub _n nsw nuw x y := if subPoison nsw nuw x y then .poison else .ok (x - y)
  mul _n nsw nuw x y := if mulPoison nsw nuw x y then .poison else .ok (x * y)
  udiv n x y := if y = 0#n then .ub else .ok (x.udiv y)
  sdiv n x y := if y = 0#n ∨ (x = BitVec.intMin n ∧ y = -1#n) then .ub else .ok (x.sdiv y)
  urem n x y := if y = 0#n then .ub else .ok (x.umod y)
  srem n x y := if y = 0#n ∨ (x = BitVec.intMin n ∧ y = -1#n) then .ub else .ok (x.srem y)
  shl n x y := if n ≤ y.toNat then .poison else .ok (x <<< y.toNat)
  lshr n x y := if n ≤ y.toNat then .poison else .ok (x >>> y.toNat)
  ashr n x y := if n ≤ y.toNat then .poison else .ok (x.sshiftRight y.toNat)
  zext _n m x := .ok (x.setWidth m)
  sext _n m x := .ok (x.signExtend m)
  trunc _n m x := .ok (x.setWidth m)
  zext1 m c := .ok (if c then 1#m else 0#m)
  uaddSat _n x y := .ok (uaddSatBV x y)
  saddSat _n x y := .ok (saddSatBV x y)
  fcmp p x y := .ok (p.eval x y)
  fptosi m x := fpToInt true m x
  fptoui m x := fpToInt false m x
  trapIf k c := if c then .trap k else .ok ()

/-! The semantics, one equation per instruction, for `simp`. -/

section Fields
variable {n m : Nat}
@[simp] theorem exec_iconst (v : Int) : Isa.exec.iconst n v = BitVec.ofInt n v := rfl
@[simp] theorem exec_bconst (b : Bool) : Isa.exec.bconst b = b := rfl
@[simp] theorem exec_dconst (bits : BitVec 64) : Isa.exec.dconst bits = F64.ofBits bits := rfl
@[simp] theorem exec_icmp (p : Pred) (x y : BitVec n) : Isa.exec.icmp p n x y = .ok (p.eval x y) := rfl
@[simp] theorem exec_and (x y : BitVec n) : Isa.exec.and n x y = .ok (x &&& y) := rfl
@[simp] theorem exec_xor (x y : BitVec n) : Isa.exec.xor n x y = .ok (x ^^^ y) := rfl
@[simp] theorem exec_and1 (x y : Bool) : Isa.exec.and1 x y = .ok (x && y) := rfl
@[simp] theorem exec_or1 (x y : Bool) : Isa.exec.or1 x y = .ok (x || y) := rfl
@[simp] theorem exec_xor1 (x y : Bool) : Isa.exec.xor1 x y = .ok (x ^^ y) := rfl
@[simp] theorem exec_select (c : Bool) (x y : BitVec n) :
    Isa.exec.select n c x y = .ok (if c then x else y) := rfl
@[simp] theorem exec_add (nsw nuw : Bool) (x y : BitVec n) :
    Isa.exec.add n nsw nuw x y = if addPoison nsw nuw x y then .poison else .ok (x + y) := rfl
@[simp] theorem exec_sub (nsw nuw : Bool) (x y : BitVec n) :
    Isa.exec.sub n nsw nuw x y = if subPoison nsw nuw x y then .poison else .ok (x - y) := rfl
@[simp] theorem exec_mul (nsw nuw : Bool) (x y : BitVec n) :
    Isa.exec.mul n nsw nuw x y = if mulPoison nsw nuw x y then .poison else .ok (x * y) := rfl
@[simp] theorem exec_udiv (x y : BitVec n) :
    Isa.exec.udiv n x y = if y = 0#n then .ub else .ok (x.udiv y) := rfl
@[simp] theorem exec_sdiv (x y : BitVec n) :
    Isa.exec.sdiv n x y = if y = 0#n ∨ (x = BitVec.intMin n ∧ y = -1#n) then .ub else .ok (x.sdiv y) := rfl
@[simp] theorem exec_urem (x y : BitVec n) :
    Isa.exec.urem n x y = if y = 0#n then .ub else .ok (x.umod y) := rfl
@[simp] theorem exec_srem (x y : BitVec n) :
    Isa.exec.srem n x y = if y = 0#n ∨ (x = BitVec.intMin n ∧ y = -1#n) then .ub else .ok (x.srem y) := rfl
@[simp] theorem exec_shl (x y : BitVec n) :
    Isa.exec.shl n x y = if n ≤ y.toNat then .poison else .ok (x <<< y.toNat) := rfl
@[simp] theorem exec_lshr (x y : BitVec n) :
    Isa.exec.lshr n x y = if n ≤ y.toNat then .poison else .ok (x >>> y.toNat) := rfl
@[simp] theorem exec_ashr (x y : BitVec n) :
    Isa.exec.ashr n x y = if n ≤ y.toNat then .poison else .ok (x.sshiftRight y.toNat) := rfl
@[simp] theorem exec_zext (x : BitVec n) : Isa.exec.zext n m x = .ok (x.setWidth m) := rfl
@[simp] theorem exec_sext (x : BitVec n) : Isa.exec.sext n m x = .ok (x.signExtend m) := rfl
@[simp] theorem exec_trunc (x : BitVec n) : Isa.exec.trunc n m x = .ok (x.setWidth m) := rfl
@[simp] theorem exec_zext1 (c : Bool) : Isa.exec.zext1 m c = .ok (if c then 1#m else 0#m) := rfl
@[simp] theorem exec_uaddSat (x y : BitVec n) : Isa.exec.uaddSat n x y = .ok (uaddSatBV x y) := rfl
@[simp] theorem exec_saddSat (x y : BitVec n) : Isa.exec.saddSat n x y = .ok (saddSatBV x y) := rfl
@[simp] theorem exec_fcmp (p : FPred) (x y : F64) : Isa.exec.fcmp p x y = .ok (p.eval x y) := rfl
@[simp] theorem exec_fptosi (x : F64) : Isa.exec.fptosi m x = fpToInt true m x := rfl
@[simp] theorem exec_fptoui (x : F64) : Isa.exec.fptoui m x = fpToInt false m x := rfl
@[simp] theorem exec_trapIf (k : Trap) (c : Bool) :
    Isa.exec.trapIf k c = if c then .trap k else .ok () := rfl
end Fields

end Arith
