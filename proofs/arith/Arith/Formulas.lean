import Arith.Isa

/-!
# The lowering formulas

One definition per emitted LLVM sequence, in the order the emitter prints it, written against the
abstract instruction set (`Isa`). Each says in its doc comment which function of
`src/core/emit_llvm.zig` (or `emit_number.zig`) it transcribes. `FORMULAS.md` lists the same
sequences with line references; `templates.txt` is what `Isa.print` renders from these
definitions, and the Zig test `src/core/arith_lowering_test.zig` pins the emitter to it.

Conventions: `n` is the integer width, `a`/`b` the operands, `zc` ("zero check") and `mc`
("minus-one check") say whether the emitter emits the zero test and the `b = -1` handling, which it
skips for a constant divisor that rules the case out.
-/

namespace Arith

/-- The four division-like operations of Core: `div`/`rem` truncate, `floor_div`/`floor_rem` round
toward negative infinity (Python's `//` and `%`). -/
inductive DivKind where
  | div | rem | floorDiv | floorRem
  deriving DecidableEq, Repr

/-- Whether the operation computes a remainder. -/
def DivKind.isRem : DivKind → Bool
  | .rem | .floorRem => true
  | .div | .floorDiv => false

/-- Whether the operation rounds toward negative infinity. -/
def DivKind.isFloor : DivKind → Bool
  | .floorDiv | .floorRem => true
  | .div | .rem => false

variable {M : Type → Type} {R : Ty → Type} [Monad M]

/-- `division`, unsigned operands and `check = exact`: a zero test (omitted for a nonzero constant
divisor, `zc = false`), then `udiv`/`urem`. -/
def divU (I : Isa M R) (n : Nat) (isRem zc : Bool) (a b : R (.int n)) : M (R (.int n)) := do
  if zc then
    let z ← I.icmp .eq n b (I.iconst n 0)
    I.trapIf .divisionByZero z
  if isRem then I.urem n a b else I.udiv n a b

/-- `division`, `u64` operands the facts put in `u32` (`narrowDivision`): the zero test, each
operand masked to its low 32 bits, then `udiv`/`urem` on the masked values. -/
def divUNarrow (I : Isa M R) (isRem zc : Bool) (a b : R (.int 64)) : M (R (.int 64)) := do
  if zc then
    let z ← I.icmp .eq 64 b (I.iconst 64 0)
    I.trapIf .divisionByZero z
  let l ← I.and 64 a (I.iconst 64 4294967295)
  let r ← I.and 64 b (I.iconst 64 4294967295)
  if isRem then I.urem 64 l r else I.udiv 64 l r

/-- `division`, `check = proven` without `--verify-facts`: `udiv`/`urem` of operands the facts show
non-negative with a positive divisor, whatever the signedness of the type. -/
def divProven (I : Isa M R) (n : Nat) (isRem : Bool) (a b : R (.int n)) : M (R (.int n)) :=
  if isRem then I.urem n a b else I.udiv n a b

/-- `division`, `check = proven` with `--verify-facts`: the fact (operands non-negative, divisor
positive) is tested first and a violation traps with kind `fact`. `signed` is the signedness of the
type: an unsigned operand is never negative, so only the zero divisor is tested. -/
def divProvenVerified (I : Isa M R) (n : Nat) (signed isRem : Bool) (a b : R (.int n)) :
    M (R (.int n)) := do
  if signed then
    let negative ← I.icmp .slt n a (I.iconst n 0)
    let nonpositive ← I.icmp .sle n b (I.iconst n 0)
    let either ← I.or1 negative nonpositive
    I.trapIf .fact either
  else
    let zero ← I.icmp .eq n b (I.iconst n 0)
    I.trapIf .fact zero
  divProven I n isRem a b

/-- `floorAdjust`: Python floor semantics from the truncating `sdiv`/`srem` by adjusting when the
remainder is nonzero and its sign differs from the divisor's. `safe` is the divisor the
truncating instructions use (`b`, or `1` where `b = -1`). -/
def floorAdjust (I : Isa M R) (n : Nat) (isRem : Bool) (a b safe : R (.int n)) :
    M (R (.int n)) := do
  let q ← I.sdiv n a safe
  let r ← I.srem n a safe
  let nonzero ← I.icmp .ne n r (I.iconst n 0)
  let mixed ← I.xor n r b
  let negative ← I.icmp .slt n mixed (I.iconst n 0)
  let fix ← I.and1 nonzero negative
  if isRem then
    let add ← I.select n fix b (I.iconst n 0)
    I.add n false false r add
  else
    let sub ← I.zext1 n fix
    I.sub n false false q sub

/-- The quotient or remainder as computed with `safe` as the divisor: `sdiv`/`srem` for the
truncating operations, `floorAdjust` for the flooring ones. -/
def divSignedCore (I : Isa M R) (n : Nat) (k : DivKind) (a b safe : R (.int n)) :
    M (R (.int n)) :=
  match k with
  | .div => I.sdiv n a safe
  | .rem => I.srem n a safe
  | .floorDiv => floorAdjust I n false a b safe
  | .floorRem => floorAdjust I n true a b safe

/-- `division`, signed operands, `check` not `proven`. `zc` says the zero test is emitted, `mc`
that the `b = -1` handling is (a divisor that is not a constant, or the constant `-1`). With `mc`,
the quotient first checks `MIN / -1` (the one signed overflow), the division then runs by `1`
instead of `-1` (so `sdiv`/`srem` never see the overflowing pair), and the quotient is replaced by
`-a`; the remainder needs no replacement because it is `0` either way. -/
def divSigned (I : Isa M R) (n : Nat) (k : DivKind) (zc mc : Bool) (a b : R (.int n)) :
    M (R (.int n)) := do
  if zc then
    let z ← I.icmp .eq n b (I.iconst n 0)
    I.trapIf .divisionByZero z
  if mc then
    let m ← I.icmp .eq n b (I.iconst n (-1))
    if k.isRem then
      let safe ← I.select n m (I.iconst n 1) b
      divSignedCore I n k a b safe
    else
      let mn ← I.icmp .eq n a (I.iconst n (-((2 : Int) ^ (n - 1))))
      let ov ← I.and1 mn m
      I.trapIf .overflow ov
      let safe ← I.select n m (I.iconst n 1) b
      let qd ← divSignedCore I n k a b safe
      let qn ← I.sub n false false (I.iconst n 0) a
      I.select n m qn qd
  else
    divSignedCore I n k a b b

/-- `shift_left` and `shift_right` (`emit_number.instruction`). With `guard` (check `exact`, or
`proven` under `--verify-facts`, then `kind = fact`) the count is compared as unsigned with the
width, which rejects a negative signed count as well as a count `>= n`; `shl` is `shl`, and a right
shift is `ashr` for a signed type and `lshr` for an unsigned one. -/
def shift (I : Isa M R) (n : Nat) (left signed guard : Bool) (kind : Trap) (a b : R (.int n)) :
    M (R (.int n)) := do
  if guard then
    let bad ← I.icmp .uge n b (I.iconst n n)
    I.trapIf kind bad
  if left then I.shl n a b else if signed then I.ashr n a b else I.lshr n a b

/-- `saturating_add` (`emit_number.instruction`): the LLVM intrinsic of the type's signedness. -/
def saturatingAdd (I : Isa M R) (n : Nat) (signed : Bool) (a b : R (.int n)) : M (R (.int n)) :=
  if signed then I.saddSat n a b else I.uaddSat n a b

/-- The range test of `convert` with `check = exact` (`convert`): trap with `kind` when the source
value is below the target's minimum (only when it can be: the target minimum is above the source's)
or above its maximum. `sf`/`st` are the source/target signedness, `wf`/`wt` their widths. -/
def convertGuard (I : Isa M R) (sf st : Bool) (wf wt : Nat) (kind : Trap) (x : R (.int wf)) :
    M Unit := do
  if lo sf wf < lo st wt then
    let below ← I.icmp (if sf then .slt else .ult) wf x (I.iconst wf (lo st wt))
    if hi st wt < hi sf wf then
      let above ← I.icmp (if sf then .sgt else .ugt) wf x (I.iconst wf (hi st wt))
      let either ← I.or1 below above
      I.trapIf kind either
    else I.trapIf kind below
  else if hi st wt < hi sf wf then
    let above ← I.icmp (if sf then .sgt else .ugt) wf x (I.iconst wf (hi st wt))
    I.trapIf kind above

/-- `convert` of equal widths: the bits are the value; `add 0` names it for later uses. -/
def convertSame (I : Isa M R) (n : Nat) (x : R (.int n)) : M (R (.int n)) :=
  I.add n false false x (I.iconst n 0)

/-- `convert` to a wider type: sign extension from a signed source, zero extension from an
unsigned one. -/
def convertWiden (I : Isa M R) (sf : Bool) (wf wt : Nat) (x : R (.int wf)) : M (R (.int wt)) :=
  if sf then I.sext wf wt x else I.zext wf wt x

/-- `convert` to a narrower type: `trunc`. -/
def convertNarrow (I : Isa M R) (wf wt : Nat) (x : R (.int wf)) : M (R (.int wt)) :=
  I.trunc wf wt x

/-- The bit movement of `convert` (`convert`): `add 0` for equal widths, an extension (by the
source's signedness) to a wider type, `trunc` to a narrower one. -/
def convertMove (I : Isa M R) (sf : Bool) (wf wt : Nat) (x : R (.int wf)) : M (R (.int wt)) :=
  if h : wt = wf then h ▸ convertSame I wf x
  else if wf < wt then convertWiden I sf wf wt x
  else convertNarrow I wf wt x

/-- `convert` (`emit_llvm.zig` `convert`): with `guard` (`check = exact`, or `proven` under
`--verify-facts`, then `kind = fact`) the range test, then the bit movement. -/
def convert (I : Isa M R) (sf st : Bool) (wf wt : Nat) (guard : Bool) (kind : Trap)
    (x : R (.int wf)) : M (R (.int wt)) := do
  if guard then convertGuard I sf st wf wt kind x
  convertMove I sf wf wt x

/-- `float_to_int` with `check = exact` (`floatToInt`): the truncated value must lie in the target
type. `aboveBits` is the lower bound as a double (`lo - 1.0`, exclusive, or `lo` itself,
inclusive, when `lo - 1.0` is not a double: the signed 64-bit case, `inclusive`), `hiBits` the
exclusive upper bound; an unordered operand (NaN) fails both ordered comparisons. `kind` is
`float_conversion`, or `fact` for a `proven` conversion verified under `--verify-facts`. -/
def floatToInt (I : Isa M R) (kind : Trap) (signed inclusive : Bool) (m : Nat)
    (aboveBits hiBits : BitVec 64) (x : R .double) : M (R (.int m)) := do
  let aboveLo ← I.fcmp (if inclusive then .oge else .ogt) x (I.dconst aboveBits)
  let belowHi ← I.fcmp .olt x (I.dconst hiBits)
  let ok ← I.and1 aboveLo belowHi
  let failed ← I.xor1 ok (I.bconst true)
  I.trapIf kind failed
  if signed then I.fptosi m x else I.fptoui m x

/-- `float_to_int` without the range test (`check = proven`, or `none`): the bare conversion. -/
def floatToIntProven (I : Isa M R) (signed : Bool) (m : Nat) (x : R .double) : M (R (.int m)) :=
  if signed then I.fptosi m x else I.fptoui m x

/-- `float_to_int` to `i64` with `check = proven` when the facts put the result in `i32`: convert to
`i32` and sign-extend, which lets LLVM use the 32-bit conversion instruction. -/
def floatToInt64Narrow (I : Isa M R) (x : R .double) : M (R (.int 64)) := do
  let narrow ← I.fptosi 32 x
  I.sext 32 64 narrow

end Arith
