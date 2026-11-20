/-!
# The form of a fact certificate

`fact-certificate-v1` (docs/design/fact-certificates.md §10), in memory: the Lean image of
`src/core/fact_function.zig`. A module is the list of its functions; a function states, for its
integer and boolean values, intervals the final fact tables claim, and the checker
(`Checker.lean`) asks whether those intervals are an inductive invariant of the IR.

Everything is a mathematical integer; `Ty.range` bounds each value by its type.
-/

namespace Facts

/-- A closed integer interval `[lo, hi]`. It is empty when `lo > hi`. -/
structure Interval where
  lo : Int
  hi : Int
  deriving DecidableEq, Repr, Inhabited

namespace Interval

/-- The interval holding exactly `v`. -/
def point (v : Int) : Interval := ⟨v, v⟩

/-- The smallest interval holding both. -/
def hull (a b : Interval) : Interval := ⟨min a.lo b.lo, max a.hi b.hi⟩

/-- The values both hold (empty when `lo > hi`). -/
def meet (a b : Interval) : Interval := ⟨max a.lo b.lo, min a.hi b.hi⟩

/-- `a` holds no value. -/
def isEmpty (a : Interval) : Bool := decide (a.lo > a.hi)

/-- Whether every value of `a` lies in `b`; the empty interval lies in every interval (design change 15). -/
def within (a b : Interval) : Bool := a.isEmpty || (decide (a.lo ≥ b.lo) && decide (a.hi ≤ b.hi))

/-- `v` lies in `a`. -/
def contains (a : Interval) (v : Int) : Prop := a.lo ≤ v ∧ v ≤ a.hi

end Interval

/-- The type of a value as the certificate classifies it (design §10). -/
inductive Ty where
  | void | bool | i8 | i16 | i32 | i64 | u8 | u16 | u32 | u64 | f64 | list | other
  deriving DecidableEq, Repr, Inhabited

namespace Ty

/-- The spelling in the format. -/
def token : Ty → String
  | .void => "void" | .bool => "bool" | .i8 => "i8" | .i16 => "i16" | .i32 => "i32" | .i64 => "i64"
  | .u8 => "u8" | .u16 => "u16" | .u32 => "u32" | .u64 => "u64" | .f64 => "f64" | .list => "list"
  | .other => "other"

/-- The type a spelling names. -/
def ofToken? : String → Option Ty
  | "void" => some .void | "bool" => some .bool | "i8" => some .i8 | "i16" => some .i16
  | "i32" => some .i32 | "i64" => some .i64 | "u8" => some .u8 | "u16" => some .u16
  | "u32" => some .u32 | "u64" => some .u64 | "f64" => some .f64 | "list" => some .list
  | "other" => some .other
  | _ => none

/-- Width in bits of an integer type, 1 for `bool`; 0 for any other type. -/
def bits : Ty → Nat
  | .bool => 1
  | .i8 | .u8 => 8
  | .i16 | .u16 => 16
  | .i32 | .u32 => 32
  | .i64 | .u64 => 64
  | _ => 0

/-- Whether the integer type is signed. -/
def signed : Ty → Bool
  | .i8 | .i16 | .i32 | .i64 => true
  | _ => false

/-- Every value the type holds, or none for a non-integer type (design §2.1, `R(t)`). -/
def range (t : Ty) : Option Interval :=
  if t.bits = 0 then none
  else if t = .bool then some ⟨0, 1⟩
  else if t.signed then some ⟨-(2 : Int) ^ (t.bits - 1), (2 : Int) ^ (t.bits - 1) - 1⟩
  else some ⟨0, (2 : Int) ^ t.bits - 1⟩

/-- Whether the type carries intervals. -/
def isInteger (t : Ty) : Bool := t.range.isSome

end Ty

/-- Check forms of an integer operation (`ir.Check`, design §4). -/
inductive Check where
  | none | exact | proven
  deriving DecidableEq, Repr, Inhabited

/-- The operations the checker distinguishes; every other operation of `ir.Op` is `other`
(design §4: "every other op: R"). -/
inductive Op where
  | iconst | param | undef | unionPayload | unionTake | recordTake | boxTake | call
  | add | sub | mul | saturatingAdd | shiftLeft | shiftRight
  | floorDiv | div | floorRem | rem | neg | bitXor | convert | cmp | not
  | listLen | strLen | dictEntries | dictLen | dictEntryKey | dictEntryValue
  | recordGet | listGet | arrayGet | listGetField | listSet | arraySet | listPop
  | listNew | listPush | listCopy | listViewOf | borrow | recordMake
  | floatToInt | other
  deriving DecidableEq, Repr, Inhabited

namespace Op

/-- The operation a name (`ir.Op`'s tag) denotes. -/
def ofName : String → Op
  | "iconst" => .iconst | "param" => .param | "undef" => .undef
  | "union_payload" => .unionPayload | "union_take" => .unionTake | "record_take" => .recordTake
  | "box_take" => .boxTake | "call" => .call
  | "add" => .add | "sub" => .sub | "mul" => .mul | "saturating_add" => .saturatingAdd
  | "shift_left" => .shiftLeft | "shift_right" => .shiftRight
  | "floor_div" => .floorDiv | "div" => .div | "floor_rem" => .floorRem | "rem" => .rem
  | "neg" => .neg | "bit_xor" => .bitXor | "convert" => .convert | "cmp" => .cmp | "not" => .not
  | "list_len" => .listLen | "str_len" => .strLen | "dict_entries" => .dictEntries
  | "dict_len" => .dictLen | "dict_entry_key" => .dictEntryKey | "dict_entry_value" => .dictEntryValue
  | "record_get" => .recordGet | "list_get" => .listGet | "array_get" => .arrayGet
  | "list_get_field" => .listGetField | "list_set" => .listSet | "array_set" => .arraySet
  | "list_pop" => .listPop | "list_new" => .listNew | "list_push" => .listPush
  | "list_copy" => .listCopy | "list_view_of" => .listViewOf | "borrow" => .borrow
  | "record_make" => .recordMake | "float_to_int" => .floatToInt
  | _ => .other

end Op

/-- Whether the operation's result is chosen freely (within what its type allows) because the checker has no
exact model of it (design §4 "every other op", and the stage-2 kinds). -/
def Op.isFree : Op → Bool
  | .undef | .unionPayload | .unionTake | .recordTake | .boxTake | .strLen | .dictEntries | .dictLen
  | .dictEntryKey | .dictEntryValue | .recordGet | .listGetField | .floatToInt | .other => true
  | _ => false

/-- The operands of an instruction line: the IR's two operands and its extra list, after `copy`
resolution. For a `call`, `a` is the callee's function index. An `x` entry of `none` is the
absent operand `-`. -/
structure Operands where
  a : Option Nat := none
  b : Option Nat := none
  x : List (Option Nat) := []
  deriving Repr, Inhabited, DecidableEq

/-- One `inst` line. `imm` is the instruction's `data` (the constant's two's complement bits, the
predicate, a field) and `aux` the array length of `array_get`/`array_set`. -/
structure Inst where
  value : Nat
  op : Op
  name : String
  ty : Ty
  check : Check
  operands : Operands := {}
  imm : Nat := 0
  aux : Nat := 0
  range : Option Interval := none
  deriving Repr, Inhabited, DecidableEq

/-- One incoming edge of a phi. -/
structure PhiEdge where
  block : Nat
  value : Nat
  deriving DecidableEq, Repr, Inhabited

/-- One `phi` line. -/
structure Phi where
  value : Nat
  ty : Ty
  edges : List PhiEdge
  range : Option Interval := none
  deriving Repr, Inhabited, DecidableEq

/-- How a block ends. -/
inductive Term where
  | jump (target : Nat)
  | branch (cond : Nat) (thenB : Nat) (elseB : Nat)
  | ret (v : Option Nat)
  | unreachable
  deriving DecidableEq, Repr, Inhabited

/-- One block: its predecessors in the order the phis list their edges, its phis, its
instructions and its end. -/
structure Block where
  id : Nat
  dead : Bool
  preds : List Nat
  phis : List Phi
  insts : List Inst
  term : Term
  deriving Repr, Inhabited

/-- A builder loop record (`ir.Loop`): the checker recognises counted loops on these. -/
structure Loop where
  header : Nat
  body : Nat
  latch : Nat
  exit : Nat
  deriving DecidableEq, Repr, Inhabited

/-- What the facts state of a list value (design §2.4). -/
structure ListFact where
  value : Nat
  len : Option Interval := none
  elems : Option Interval := none
  length : Option Nat := none
  pattern : Bool := false
  deriving Repr, Inhabited, DecidableEq

/-- `value <= len(list)`, or `<` when strict, for a list parameter. -/
structure Bound where
  value : Nat
  list : Nat
  strict : Bool
  deriving Repr, Inhabited

/-- The viewed operand intervals of one `proven` instruction (design §10, Sites). -/
structure Site where
  value : Nat
  parts : List (Option Interval)
  deriving Repr, Inhabited

/-- The facts a function states beyond its instructions' intervals. -/
structure Aux where
  loops : List Loop := []
  lists : List ListFact := []
  bounds : List Bound := []
  sites : List Site := []
  deriving Repr, Inhabited

/-- The function header. -/
structure Header where
  name : String
  internal : Bool
  addressTaken : Bool
  params : List Ty
  ret : Ty
  deriving Repr, Inhabited

/-- What a function states about its parameters and what it returns (design §2.3). -/
structure Boundary where
  params : List (Option Interval) := []
  returns : Option Interval := none
  deriving Repr, Inhabited

/-- One function. `pre` holds the constants and parameters, defined outside every block. -/
structure Function where
  header : Header
  boundary : Boundary := {}
  pre : List Inst := []
  blocks : Array Block := #[]
  aux : Aux := {}
  deriving Repr, Inhabited

/-- The certificate of one module: every function with a body, in module order. -/
structure Module where
  functions : Array Function
  deriving Repr, Inhabited

/-- The largest list or string the address space holds (design §4, `M = 2^47`). -/
def maxListLength : Int := (2 : Int) ^ 47

end Facts
