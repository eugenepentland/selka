/-!
# The Core IR as the verifier reads it

The Lean image of the tables of `src/core/ir.zig` that `src/core/verify_ir.zig` reads, as `core-ir-v1` writes them
(`src/core/ir_text.zig`): the compound types in interning order, and per function its name, signature, instruction
table, packed operand list and blocks. Nothing is interpreted here: an instruction's `data` is the raw 64-bit number,
and the rules (`Rules.lean`) decode it per operation.

A type is its number. The leaves below 16 are the scalars and blocks of `ir.Type`; the five named leaves above
`0xfffffff0` are `byte_buffer`, `capability`, `resource`, `bytes_view` and the two task types; every other number
from 16 on names entry `n - 16` of the module's compound table (`Ty.isCompound`), and is a type of the module only when
that entry exists (`Module.valid`).
-/

namespace VerifyIr

/-- A Core IR type, by its number. -/
abbrev Ty := Nat

namespace Ty
def void : Ty := 0
def bool : Ty := 1
def i8 : Ty := 2
def i16 : Ty := 3
def i32 : Ty := 4
def i64 : Ty := 5
def u8 : Ty := 6
def u16 : Ty := 7
def u32 : Ty := 8
def u64 : Ty := 9
def f64 : Ty := 10
def cap : Ty := 11
def str : Ty := 12
def bytes : Ty := 13
def strView : Ty := 14
def f32 : Ty := 15
def byteBuffer : Ty := 0xfffffff0
def capability : Ty := 0xfffffff1
def resource : Ty := 0xfffffff2
def bytesView : Ty := 0xfffffff3
def taskGroup : Ty := 0xfffffff4
def taskHandle : Ty := 0xfffffff5

/-- The first number that names a compound type. -/
def firstCompound : Nat := 16

/-- Whether the number names an entry of the compound table: from 16 on, except the named leaves that are blocks or spans
(the two task types are not among them, so they name compound entries no module has). -/
def isCompound (t : Ty) : Bool :=
  decide (t ≥ firstCompound) && t != byteBuffer && t != capability && t != resource && t != bytesView

/-- Width in bits and signedness of a fixed-width integer type. -/
def integer? (t : Ty) : Option (Nat × Bool) :=
  if t = i8 then some (8, true) else if t = i16 then some (16, true)
  else if t = i32 then some (32, true) else if t = i64 then some (64, true)
  else if t = u8 then some (8, false) else if t = u16 then some (16, false)
  else if t = u32 then some (32, false) else if t = u64 then some (64, false) else none

/-- A fixed-width integer type (not `bool`). -/
def isInteger (t : Ty) : Bool := (integer? t).isSome

/-- A borrowed text or bytes span. -/
def isSpan (t : Ty) : Bool := t == strView || t == bytesView

/-- A binary64 or binary32 scalar. -/
def isFloat (t : Ty) : Bool := t == f64 || t == f32
end Ty

/-- How a function is reached (`ir.Linkage`); `externAddress` is an `@address` extern, called through the address its
first passed argument holds. -/
inductive Linkage where
  | internal | externC | runtimeC | externAddress
  deriving DecidableEq, Repr, Inhabited

/-- One step of a borrow projection (`ir.BorrowProjection`). -/
inductive Proj where
  | field (k : Nat)
  | payload (k : Nat)
  deriving DecidableEq, Repr, Inhabited

/-- An owner source of a borrowed result (`ir.BorrowSource`). -/
inductive Source where
  | argument (k : Nat)
  | result (path : List Proj)
  deriving DecidableEq, Repr, Inhabited

/-- The physical parameter conventions (`ir.ParameterPassing`): three 64-bit masks and their tails above 63. -/
structure Passing where
  owned : Nat := 0
  consumes : Nat := 0
  views : Nat := 0
  extraOwned : List Nat := []
  extraConsumes : List Nat := []
  extraViews : List Nat := []
  deriving DecidableEq, Repr, Inhabited

/-- A function signature (`ir.Signature`) with its borrow contract (`path`, `sources`). Two signatures are the same
signature exactly when they are equal as values (`ir.Signature.eql` compares every field). -/
structure Signature where
  params : List Ty
  ret : Ty
  linkage : Linkage
  passing : Passing
  path : List Proj
  sources : List Source
  deriving DecidableEq, Repr, Inhabited

/-- A compound type (`ir.Compound`). -/
inductive Compound where
  | list (e : Ty)
  | listView (e : Ty)
  | box (e : Ty)
  | borrowed (e : Ty)
  | dict (k v : Ty)
  | array (e : Ty) (n : Nat) (vector : Bool)
  | record (fields : List Ty)
  | union (cases : List Ty)
  | fn (sig : Signature)
  deriving DecidableEq, Repr, Inhabited

/-- The kind of a compound type. -/
inductive Kind where
  | list | listView | box | borrowed | dict | array | record | union | fn
  deriving DecidableEq, Repr, Inhabited

/-- The kind of a compound. -/
def Compound.kind : Compound → Kind
  | .list _ => .list | .listView _ => .listView | .box _ => .box | .borrowed _ => .borrowed
  | .dict _ _ => .dict | .array _ _ _ => .array | .record _ => .record | .union _ => .union | .fn _ => .fn

/-- The operations of `ir.Op`, in its order. -/
inductive Op where
  | param | iconst | fconst | undef | strConst | copy | borrow | phi
  | add | sub | mul | div | rem | floorDiv | floorRem | neg | bitAnd | bitOr | bitXor | not | cmp
  | fadd | fsub | fmul | fdiv | fneg | fcmp | intToFloat | floatToInt | convert
  | listNew | listLen | listGet | listViewOf | listSliceView | listPush | listCopy | strLen | strParseInt
  | unionMake | unionTag | unionPayload | recordMake | recordGet | recordSet | listSet | listPop | listGetField
  | dictNew | dictLen | dictFind | dictEntryKey | dictEntryValue | dictSetValue | dictInsert | dictRemove
  | dictEntries | dictEntryLive | dictCopy | dictClear
  | strChar | strWidth | strCode | strAppend | strAppendChar | strSlice | strViewOf | strFromView
  | textSentinel | textFrame | listSort | arrayGet | arraySet | arrayFromBytes | funcRef | callIndirect
  | boxMake | boxGet | boxFrame | blockFrame | drop | errTrace | call | print | jump | branch | ret | unreachable
  | bufferNew | bufferCopy | bufferSet | bufferPush | bufferPop | shiftLeft | shiftRight | saturatingAdd
  | floatUnary | listSetField | bufferAppend | strSliceView | strSliceBytesView | unionTake | boxTake
  | floatConvert | bitcast | floatFma | vectorSelect | byteLoad | recordTake
  deriving DecidableEq, Repr, Inhabited

namespace Op

/-- Each operation with its name in the text (`@tagName` of `ir.Op`). -/
def table : List (String × Op) :=
  [("param", .param), ("iconst", .iconst), ("fconst", .fconst), ("undef", .undef), ("str_const", .strConst),
   ("copy", .copy), ("borrow", .borrow), ("phi", .phi), ("add", .add), ("sub", .sub), ("mul", .mul), ("div", .div),
   ("rem", .rem), ("floor_div", .floorDiv), ("floor_rem", .floorRem), ("neg", .neg), ("bit_and", .bitAnd),
   ("bit_or", .bitOr), ("bit_xor", .bitXor), ("not", .not), ("cmp", .cmp), ("fadd", .fadd), ("fsub", .fsub),
   ("fmul", .fmul), ("fdiv", .fdiv), ("fneg", .fneg), ("fcmp", .fcmp), ("int_to_float", .intToFloat),
   ("float_to_int", .floatToInt), ("convert", .convert), ("list_new", .listNew), ("list_len", .listLen),
   ("list_get", .listGet), ("list_view_of", .listViewOf), ("list_slice_view", .listSliceView),
   ("list_push", .listPush), ("list_copy", .listCopy), ("str_len", .strLen), ("str_parse_int", .strParseInt),
   ("union_make", .unionMake), ("union_tag", .unionTag), ("union_payload", .unionPayload),
   ("record_make", .recordMake), ("record_get", .recordGet), ("record_set", .recordSet), ("list_set", .listSet),
   ("list_pop", .listPop), ("list_get_field", .listGetField), ("dict_new", .dictNew), ("dict_len", .dictLen),
   ("dict_find", .dictFind), ("dict_entry_key", .dictEntryKey), ("dict_entry_value", .dictEntryValue),
   ("dict_set_value", .dictSetValue), ("dict_insert", .dictInsert), ("dict_remove", .dictRemove),
   ("dict_entries", .dictEntries), ("dict_entry_live", .dictEntryLive), ("dict_copy", .dictCopy),
   ("dict_clear", .dictClear), ("str_char", .strChar), ("str_width", .strWidth), ("str_code", .strCode),
   ("str_append", .strAppend), ("str_append_char", .strAppendChar), ("str_slice", .strSlice),
   ("str_view_of", .strViewOf), ("str_from_view", .strFromView), ("text_sentinel", .textSentinel),
   ("text_frame", .textFrame), ("list_sort", .listSort), ("array_get", .arrayGet), ("array_set", .arraySet),
   ("array_from_bytes", .arrayFromBytes), ("func_ref", .funcRef), ("call_indirect", .callIndirect),
   ("box_make", .boxMake), ("box_get", .boxGet), ("box_frame", .boxFrame), ("block_frame", .blockFrame),
   ("drop", .drop), ("err_trace", .errTrace), ("call", .call), ("print", .print), ("jump", .jump),
   ("branch", .branch), ("ret", .ret), ("unreachable", .unreachable), ("buffer_new", .bufferNew),
   ("buffer_copy", .bufferCopy), ("buffer_set", .bufferSet), ("buffer_push", .bufferPush),
   ("buffer_pop", .bufferPop), ("shift_left", .shiftLeft), ("shift_right", .shiftRight),
   ("saturating_add", .saturatingAdd), ("float_unary", .floatUnary), ("list_set_field", .listSetField),
   ("buffer_append", .bufferAppend), ("str_slice_view", .strSliceView),
   ("str_slice_bytes_view", .strSliceBytesView), ("union_take", .unionTake), ("box_take", .boxTake),
   ("float_convert", .floatConvert), ("bitcast", .bitcast), ("float_fma", .floatFma),
   ("vector_select", .vectorSelect), ("byte_load", .byteLoad), ("record_take", .recordTake)]

/-- The operation a name denotes. -/
def ofName? (s : String) : Option Op := (table.find? (·.1 == s)).map (·.2)

/-- The name of an operation. -/
def name (o : Op) : String := ((table.find? (·.2 == o)).map (·.1)).getD "?"

/-- Ends a block. -/
def terminates : Op → Bool
  | .jump | .branch | .ret | .unreachable => true
  | _ => false

/-- `data` packs an extra operand list. -/
def hasExtra : Op → Bool
  | .phi | .call | .callIndirect | .print | .recordMake | .listSet | .listSetField | .bufferAppend
  | .dictSetValue | .dictInsert | .strAppendChar | .strSlice | .strViewOf | .strSliceView | .strSliceBytesView
  | .floatFma | .vectorSelect | .arraySet | .listSliceView | .bufferSet => true
  | _ => false

/-- Defined outside every block and materialized at each use, so it dominates every use. -/
def isConstant : Op → Bool
  | .param | .iconst | .fconst | .undef | .strConst | .textSentinel | .funcRef => true
  | _ => false

/-- The operations whose `a` and `b` are not value operands: a phi, a call (its `a` is the callee), a print and a
record constructor read their `extra` list only. -/
def extraOnly : Op → Bool
  | .phi | .call | .print | .recordMake => true
  | _ => false

end Op

/-- One instruction (`ir.Inst`): `a` and `b` are `none` when absent, `data` is raw. -/
structure Inst where
  op : Op
  ty : Ty
  a : Option Nat
  b : Option Nat
  data : Nat
  deriving DecidableEq, Repr, Inhabited

/-- One block: its listed instructions (an entry may be `none`, which the verifier refuses) and its predecessors. -/
structure Block where
  insts : Array (Option Nat)
  preds : Array Nat
  deriving Repr, Inhabited

/-- One function. `span` and `loops` are the declaration's span start and its number of recorded loops. -/
structure Function where
  name : String
  span : Nat
  loops : Nat
  sig : Signature
  insts : Array Inst
  extra : Array (Option Nat)
  blocks : Array Block
  deriving Repr, Inhabited

/-- A module: the compound table and the functions. -/
structure Module where
  compounds : Array Compound
  functions : Array Function
  deriving Repr, Inhabited

/-- `data` of an instruction with an extra list: the start in the low 32 bits, the length in bits 32 to 62
(`ir.ExtraSlice.unpack`; bit 63 is a flag). -/
def extraSlice (data : Nat) : Nat × Nat := (data % 2 ^ 32, (data / 2 ^ 32) % 2 ^ 31)

/-- The two targets of a `branch` (`ir.unpackTargets`). -/
def branchTargets (data : Nat) : Nat × Nat := (data % 2 ^ 32, (data / 2 ^ 32) % 2 ^ 32)

/-- A field path (`ir.FieldPath.unpack`): the length in the low 4 bits (at most 5), then 12 bits per step. -/
def fieldPath (data : Nat) : List Nat :=
  let len := min (data % 16) 5
  (List.range len).map fun i => (data / 2 ^ (4 + 12 * i)) % 2 ^ 12

/-! ## Passing conventions -/

namespace Passing

/-- Position `k` is in a compact mask (below 64) or in its tail. -/
def at_ (mask : Nat) (extra : List Nat) (k : Nat) : Bool :=
  if k < 64 then mask.testBit k else k < 2 ^ 32 && extra.contains k

def viewAt (p : Passing) (k : Nat) : Bool := at_ p.views p.extraViews k
def ownedAt (p : Passing) (k : Nat) : Bool := at_ p.owned p.extraOwned k
def consumesAt (p : Passing) (k : Nat) : Bool := at_ p.consumes p.extraConsumes k
def takes (p : Passing) (k : Nat) : Bool := p.ownedAt k || p.consumesAt k
def hasViews (p : Passing) : Bool := p.views != 0 || !p.extraViews.isEmpty

/-- A mask and tail name only positions below `count`, the tail sorted, unique and above 63. -/
def validSet (mask : Nat) (extra : List Nat) (count : Nat) : Bool :=
  (count ≥ 64 || mask >>> count == 0) &&
  (extra.all fun k => decide (k ≥ 64) && decide (k < count)) &&
  (extra.zip (extra.drop 1)).all fun (x, y) => decide (x < y)

/-- The three conventions are in range and no position has two. -/
def valid (p : Passing) (count : Nat) : Bool :=
  validSet p.owned p.extraOwned count && validSet p.consumes p.extraConsumes count &&
  validSet p.views p.extraViews count &&
  p.owned &&& p.consumes == 0 && (p.owned ||| p.consumes) &&& p.views == 0 &&
  p.extraOwned.all (fun k => !p.consumesAt k && !p.viewAt k) &&
  p.extraConsumes.all (fun k => !p.viewAt k)

end Passing

end VerifyIr
