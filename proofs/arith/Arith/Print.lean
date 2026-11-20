import Arith.Isa

/-!
# Rendering the formulas as LLVM text

`Isa.print` interprets the instruction set as a text generator: each instruction appends the line
the emitter would print (names are `t1`, `t2`, … in order of definition; the parameters are `a`
and `b`), and `trapIf` appends the one pseudo-instruction `trapif c kind` for the emitter's
four-line trap idiom. The Zig test normalises the emitter's output to the same form.
-/

namespace Arith

/-- Printer state: the next register number and the lines so far. -/
structure PSt where
  next : Nat := 1
  lines : Array String := #[]

/-- The printing monad. -/
abbrev P := StateM PSt

/-- The LLVM type name. -/
def tyName (n : Nat) : String := s!"i{n}"

/-- The kind name the emitter's trap site table uses (`TrapKind` in `emit_llvm.zig`). -/
def Trap.name : Trap → String
  | .overflow => "overflow"
  | .divisionByZero => "division_by_zero"
  | .floatConversion => "float_conversion"
  | .cast => "cast"
  | .fact => "fact"
  | .invalidShift => "invalid_shift"

/-- The LLVM spelling of an `icmp` predicate. -/
def Pred.name : Pred → String
  | .eq => "eq" | .ne => "ne" | .ult => "ult" | .ule => "ule" | .ugt => "ugt" | .uge => "uge"
  | .slt => "slt" | .sle => "sle" | .sgt => "sgt" | .sge => "sge"

/-- The LLVM spelling of an `fcmp` predicate. -/
def FPred.name : FPred → String
  | .ogt => "ogt" | .oge => "oge" | .olt => "olt"

/-- Uppercase hexadecimal digits of `v`, padded to 16. -/
def hex16 (v : Nat) : String :=
  let digits := (Nat.toDigits 16 v).map Char.toUpper
  String.ofList (List.replicate (16 - digits.length) '0' ++ digits)

/-- Define a fresh register with the line `f name`; returns the name. -/
def defLine (f : String → String) : P String := do
  let s ← get
  let name := s!"t{s.next}"
  set { s with next := s.next + 1, lines := s.lines.push (f name) }
  pure name

/-- Append a line that defines no register. -/
def plainLine (line : String) : P Unit :=
  modify fun s => { s with lines := s.lines.push line }

/-- `add`/`sub`/`mul` flags in LLVM's order. -/
def flagText (nsw nuw : Bool) : String :=
  (if nuw then "nuw " else "") ++ (if nsw then "nsw " else "")

/-- The instruction set as text. -/
def Isa.print : Isa P (fun _ => String) where
  iconst _ v := toString v
  bconst b := if b then "true" else "false"
  dconst bits := s!"0x{hex16 bits.toNat}"
  icmp p n x y := defLine fun t => s!"{t} = icmp {p.name} {tyName n} {x}, {y}"
  and n x y := defLine fun t => s!"{t} = and {tyName n} {x}, {y}"
  xor n x y := defLine fun t => s!"{t} = xor {tyName n} {x}, {y}"
  and1 x y := defLine fun t => s!"{t} = and i1 {x}, {y}"
  or1 x y := defLine fun t => s!"{t} = or i1 {x}, {y}"
  xor1 x y := defLine fun t => s!"{t} = xor i1 {x}, {y}"
  select n c x y := defLine fun t => s!"{t} = select i1 {c}, {tyName n} {x}, {tyName n} {y}"
  add n nsw nuw x y := defLine fun t => s!"{t} = add {flagText nsw nuw}{tyName n} {x}, {y}"
  sub n nsw nuw x y := defLine fun t => s!"{t} = sub {flagText nsw nuw}{tyName n} {x}, {y}"
  mul n nsw nuw x y := defLine fun t => s!"{t} = mul {flagText nsw nuw}{tyName n} {x}, {y}"
  udiv n x y := defLine fun t => s!"{t} = udiv {tyName n} {x}, {y}"
  sdiv n x y := defLine fun t => s!"{t} = sdiv {tyName n} {x}, {y}"
  urem n x y := defLine fun t => s!"{t} = urem {tyName n} {x}, {y}"
  srem n x y := defLine fun t => s!"{t} = srem {tyName n} {x}, {y}"
  shl n x y := defLine fun t => s!"{t} = shl {tyName n} {x}, {y}"
  lshr n x y := defLine fun t => s!"{t} = lshr {tyName n} {x}, {y}"
  ashr n x y := defLine fun t => s!"{t} = ashr {tyName n} {x}, {y}"
  zext n m x := defLine fun t => s!"{t} = zext {tyName n} {x} to {tyName m}"
  sext n m x := defLine fun t => s!"{t} = sext {tyName n} {x} to {tyName m}"
  trunc n m x := defLine fun t => s!"{t} = trunc {tyName n} {x} to {tyName m}"
  zext1 m c := defLine fun t => s!"{t} = zext i1 {c} to {tyName m}"
  uaddSat n x y := defLine fun t =>
    s!"{t} = call {tyName n} @llvm.uadd.sat.{tyName n}({tyName n} {x}, {tyName n} {y})"
  saddSat n x y := defLine fun t =>
    s!"{t} = call {tyName n} @llvm.sadd.sat.{tyName n}({tyName n} {x}, {tyName n} {y})"
  fcmp p x y := defLine fun t => s!"{t} = fcmp {p.name} double {x}, {y}"
  fptosi m x := defLine fun t => s!"{t} = fptosi double {x} to {tyName m}"
  fptoui m x := defLine fun t => s!"{t} = fptoui double {x} to {tyName m}"
  trapIf k c := plainLine s!"trapif {c} {k.name}"

/-- A rendered case: the instruction lines followed by the `ret` of the result register, given the
types of the operands (`a`, `b`) and of the result. -/
def render (retTy : String) (body : P String) : List String :=
  let (res, st) := body.run {}
  st.lines.toList ++ [s!"ret {retTy} {res}"]

end Arith
