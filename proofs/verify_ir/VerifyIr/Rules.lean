import VerifyIr.TypeOps

/-!
# What each operation asks of its operands

The typing rules of the IR, one per operation: given the instruction, the types of its operands (after following
forwarding copies) and the module, whether the instruction is well typed. `Shape` is the instruction with the types
the rules read; `sigOk` is the rule. The view rules (`viewDefOk`, `viewUseOk`) say where a borrowed span or list view
may be made and where it may be read: never stored, printed as bytes, or returned as an owned value.
-/

namespace VerifyIr

/-- Flags of `src/core/flags.zig` the rules read. -/
def textTrapFlag : Nat := 2 ^ 58
def placeCopyFlag : Nat := 2 ^ 60

/-- A type no module has: the type of an operand that does not exist. -/
def noTy : Ty := 2 ^ 33

/-- What the rules of one function read: the module and the function. -/
structure Fn where
  m : Module
  f : Function

namespace Fn
variable (c : Fn)

/-- The instruction behind a reference that exists. -/
def inst? (r : Nat) : Option Inst := c.f.insts[r]?

/-- Follow forwarding copies (`ir.Function.resolve`). A copy chain that leaves the table or comes back to itself
resolves to nothing. -/
def resolve (r : Option Nat) : Option Nat :=
  let rec go : Nat → Nat → Option Nat
    | 0, _ => none
    | n + 1, x => match c.f.insts[x]? with
      | some i => if i.op == .copy then (match i.a with | some y => go n y | none => none) else some x
      | none => none
  match r with
  | none => none
  | some x => go (c.f.insts.size + 1) x

/-- The type of the value a reference stands for. -/
def typeOf (r : Nat) : Ty :=
  match c.resolve (some r) with
  | some x => (c.f.insts[x]?.map (·.ty)).getD noTy
  | none => noTy

/-- The packed extra operands of `data`, when the slice lies inside the function's list. -/
def extraOf? (data : Nat) : Option (List (Option Nat)) :=
  let (start, len) := extraSlice data
  if start ≤ c.f.extra.size && len ≤ c.f.extra.size - start then some (c.f.extra.extract start (start + len)).toList
  else none

/-- The extra operands (empty when the slice is out of range, which `extra-range` refuses first). -/
def extraOf (data : Nat) : List (Option Nat) := (c.extraOf? data).getD []

/-- Every value an instruction reads, in order: `a` and `b` where they are values (not for a jump, nor for the
operations that read their extra list only), then the extra list. -/
def valueOperands (i : Inst) : List (Option Nat) :=
  if i.op == .jump then [] else
  let direct := if i.op.extraOnly then [] else ([i.a, i.b].filter (·.isSome))
  direct ++ (if i.op.hasExtra then c.extraOf i.data else [])

/-- The compound structure of `t`'s storage when it is of kind `k`. -/
def compoundOf (t : Ty) : Option Compound := c.m.compound? (c.m.storageType t)

def listOf (t : Ty) : Option Ty := match c.compoundOf t with | some (.list e) => some e | _ => none
def listViewOf (t : Ty) : Option Ty := match c.compoundOf t with | some (.listView e) => some e | _ => none
def dictOf (t : Ty) : Option (Ty × Ty) := match c.compoundOf t with | some (.dict k v) => some (k, v) | _ => none
def arrayOf (t : Ty) : Option (Ty × Nat × Bool) :=
  match c.compoundOf t with | some (.array e n v) => some (e, n, v) | _ => none
def recordOf (t : Ty) : Option (List Ty) := match c.compoundOf t with | some (.record fs) => some fs | _ => none
def unionOf (t : Ty) : Option (List Ty) := match c.compoundOf t with | some (.union cs) => some cs | _ => none
def boxOf (t : Ty) : Option Ty := match c.compoundOf t with | some (.box e) => some e | _ => none
def fnOf (t : Ty) : Option Signature := match c.compoundOf t with | some (.fn s) => some s | _ => none

/-- A scalar float or a vector of floats. -/
def floatLanes (t : Ty) : Bool :=
  Ty.isFloat t || (match c.arrayOf t with | some (e, _, v) => v && Ty.isFloat e | none => false)
/-- A vector of Booleans. -/
def maskOf (t : Ty) : Bool := match c.arrayOf t with | some (e, _, v) => v && e == Ty.bool | none => false
/-- A vector of fixed-width integers. -/
def integerLanes (t : Ty) : Bool := match c.arrayOf t with | some (e, _, v) => v && Ty.isInteger e | none => false
/-- Vectors of one length whose lanes convert between binary32 and binary64. -/
def convertsLanes (to from_ : Ty) : Bool :=
  match c.arrayOf to, c.arrayOf from_ with
  | some (te, tn, tv), some (fe, fn_, fv) =>
    tv && fv && tn == fn_ && ((te == Ty.f64 && fe == Ty.f32) || (te == Ty.f32 && fe == Ty.f64))
  | _, _ => false
/-- A Boolean vector as long as the vector `operand`. -/
def maskOver (mask operand : Ty) : Bool :=
  match c.arrayOf operand, c.arrayOf mask with
  | some (_, n, _), some (e, k, v) => v && e == Ty.bool && k == n
  | _, _ => false

/-- Reading a `t` out of `source` is the element read it declares: a list's or list view's element, or one octet of a
raw-octet value. -/
def elementRead (source t : Ty) : Bool :=
  match c.listOf source with
  | some e => e == t
  | none => match c.listViewOf source with
    | some e => e == t
    | none => (source == Ty.bytes || source == Ty.byteBuffer || source == Ty.strView || source == Ty.bytesView) && t == Ty.u8

/-- A list, a list view, or a raw-octet value whose length is a block length. -/
def listOrView (t : Ty) : Bool :=
  t == Ty.bytes || t == Ty.byteBuffer || Ty.isSpan t || (c.listOf t).isSome || (c.listViewOf t).isSome

/-- The values have exactly these types, in order. -/
def typesMatch (vs : List (Option Nat)) (ts : List Ty) : Bool :=
  vs.length == ts.length && (vs.zip ts).all fun (v, t) => match v with | some r => c.typeOf r == t | none => false

/-- A collection of overlays read as a whole is the overlay of the owned collection whose layout it shares. -/
def lentWhole (result source : Ty) : Bool :=
  match c.m.lentElement source with
  | none => false
  | some element =>
    if !c.m.isBorrowed result then false else
    let stored := c.m.storageType result
    if !c.m.valid stored then false else
    match c.m.compound? source with
    | some (.dict k _) => match c.m.dictShape stored with
      | some (sk, sv) => sk == k && sv == c.m.storageType element
      | none => false
    | _ => match c.m.compound? stored with
      | some (.list e) => e == c.m.storageType element
      | _ => false

end Fn

/-- A parameter of `sig` at `index` takes a borrowed span: an internal function's span or list-view parameter, or an
external function's text, bytes or list-view parameter it declares as a view and does not take. -/
def admittedView (m : Module) (sig : Signature) (index : Nat) : Bool :=
  let p := sig.params[index]?
  let listView := match p with | some t => m.kind? t == some .listView | none => false
  if sig.linkage == .internal && (match p with | some t => Ty.isSpan t || listView | none => false) then true else
  let textOrBytes := match p with | some t => t == Ty.str || t == Ty.bytes || listView | none => false
  sig.linkage != .internal && textOrBytes && Passing.viewAt sig.passing index && !Passing.takes sig.passing index

/-- An instruction with the types its rule reads: `a` and `b` are the types of its operands (`void` when absent, and for
a call, whose `a` is the callee), `extra` its extra operands. -/
structure Shape where
  i : Inst
  a : Ty
  b : Ty
  extra : List (Option Nat)

namespace Fn
variable (c : Fn)

/-- `a` and `b` are typed where they are value operands: not for a jump, nor for the operations that read only their
extra list (a call's `a` is its callee). -/
def shape (i : Inst) : Shape :=
  let direct := i.op != .jump && !i.op.extraOnly
  { i, a := (match i.a with | some r => if direct then c.typeOf r else Ty.void | none => Ty.void),
    b := (match i.b with | some r => if direct then c.typeOf r else Ty.void | none => Ty.void),
    extra := if i.op.hasExtra then c.extraOf i.data else [] }

/-- A view may be made only at the boundary (a parameter, a call result), as an undefined constant, or by a view operation, a copy, a phi, a field
read or a payload read. -/
def viewDefOk (s : Shape) : Bool :=
  !c.m.isView s.i.ty ||
  match s.i.op with
  | .param | .call | .undef | .strViewOf | .strSliceView | .strSliceBytesView | .listViewOf | .listSliceView | .copy | .phi
  | .recordGet | .unionPayload => true
  | _ => false

/-- A view operand at position `k` is read in place: by its own family's operations, a phi of its kind, a return, a
constructor of a type that holds borrows, or a parameter that takes a view. -/
def viewUseOk (s : Shape) (k : Nat) (t : Ty) : Bool :=
  let o := s.i.op
  let callAdmits := match s.i.a with
    | some f => match c.m.functions[f]? with
      | some g => admittedView c.m g.sig k
      | none => false
    | none => false
  let indirectParam (ok : Ty → Bool) := k ≥ 1 && (match c.fnOf s.a with
    | some sig => match sig.params[k - 1]? with | some p => ok p | none => false
    | none => false)
  let borrowCtor := (o == .unionMake || o == .recordMake) && c.m.containsBorrow s.i.ty
  if t == Ty.strView then
    match o with
    | .strFromView | .strLen | .listLen | .strParseInt | .strViewOf | .copy => k == 0
    | .textFrame => k == 1
    | .blockFrame => k == 0
    | .listGet => k == 0 && s.i.ty == Ty.u8
    | .bufferAppend => k == 1
    | .strCode | .strWidth | .byteLoad => k == 0
    | .strAppendChar => k == 1
    | .phi => s.i.ty == Ty.strView
    | .ret | .print => true
    | .unionMake | .recordMake => borrowCtor
    | .dictFind => k == 1 && (match c.dictOf s.a with | some (key, _) => key == Ty.str | none => false)
    | .call => callAdmits
    | .callIndirect => indirectParam (· == Ty.strView)
    | _ => false
  else if t == Ty.bytesView then
    match o with
    | .blockFrame => k == 0
    | .strLen | .listLen | .listGet | .strViewOf | .copy => k == 0
    | .ret => true
    | .unionMake | .recordMake => borrowCtor
    | .byteLoad => k == 0
    | .bufferAppend => k == 1
    | .dictFind => k == 1 && (match c.dictOf s.a with | some (key, _) => key == Ty.bytes | none => false)
    | .phi => Ty.isSpan s.i.ty
    | .call => callAdmits
    | .callIndirect => indirectParam (· == Ty.bytesView)
    | _ => false
  else
    match o with
    | .blockFrame => k == 0
    | .listLen | .listGet | .listGetField | .listSliceView | .copy | .listCopy => k == 0
    | .ret => true
    | .unionMake | .recordMake => borrowCtor
    | .phi => (c.listViewOf s.i.ty).isSome
    | .call => callAdmits
    | .callIndirect => indirectParam (fun p => c.m.kind? p == some .listView)
    | _ => false

/-- The probe of a `dict_insert` is a `dict_find` of the same dictionary and key (or of the span its key was made of). -/
def insertProbe (s : Shape) : Bool :=
  match s.i.b, s.extra with
  | some pb, [key, _] =>
    match c.resolve (some pb) >>= c.inst? with
    | some probe =>
      if probe.op != .dictFind || c.resolve probe.a != c.resolve s.i.a then false else
      let lookedUp := c.resolve probe.b
      let k := c.resolve key
      if lookedUp == k then true else
      match k >>= c.inst? with
      | some mat => mat.op == .strFromView && c.resolve mat.a == lookedUp
      | none => false
    | none => false
  | _, _ => false

/-- The comparison rule: lanes give a mask as long as the operands; a scalar comparison gives a Boolean; function values
compare for equality only. -/
def cmpOk (s : Shape) : Bool :=
  if s.a == s.b && c.integerLanes s.a then decide (s.i.data < 6) && c.maskOver s.i.ty s.a else
  if s.i.ty != Ty.bool || s.a != s.b then false else
  if (c.fnOf s.a).isSome then s.i.data == 0 || s.i.data == 1 else
  (Ty.isInteger s.a || s.a == Ty.bool) && decide (s.i.data < 6)

/-- The path an element-field store writes: the field path in the `u64` constant that is its second extra operand. -/
def setPath (i : Inst) : Option (List Nat) :=
  match c.extraOf i.data with
  | [_, p] => match c.resolve p >>= c.inst? with
    | some k => if k.op == .iconst && k.ty == Ty.u64 then some (fieldPath k.data) else none
    | none => none
  | _ => none

/-- The rule of a direct call: the callee exists, its result is the instruction's, each argument has the parameter's
type or is a span the parameter admits. -/
def callOk (s : Shape) : Bool :=
  match s.i.a with
  | none => false
  | some fi => match c.m.functions[fi]? with
    | none => false
    | some g =>
      s.i.ty == g.sig.ret && s.extra.length == g.sig.params.length &&
      ((s.extra.zip g.sig.params).zipIdx.all fun ((arg, p), k) =>
        let t := match arg with | some r => c.typeOf r | none => noTy
        t == p || ((Ty.isSpan t || t == Ty.bytes) && admittedView c.m g.sig k && !Ty.isCompound p))

/-- The signature of every operation. -/
def sigOk (s : Shape) : Bool :=
  let i := s.i
  let m := c.m
  let t := i.ty
  let int := Ty.isInteger
  match i.op with
  -- buffers, shifts, float extras, selects
  | .bufferNew => t == Ty.byteBuffer && s.a == Ty.u64
  | .bufferCopy | .bufferPop => t == Ty.byteBuffer && s.a == Ty.byteBuffer
  | .bufferPush => t == Ty.byteBuffer && s.a == Ty.byteBuffer &&
      (if i.data == 0 then s.b == Ty.u8 else if i.data == 1 then s.b == Ty.i64 else if i.data == 2 then s.b == Ty.f64 else false)
  | .bufferSet => t == Ty.byteBuffer && s.a == Ty.byteBuffer && int s.b && c.typesMatch s.extra [Ty.u8]
  | .shiftLeft | .shiftRight | .saturatingAdd => int t && s.a == t && s.b == t
  | .floatUnary => (Ty.isFloat t || (c.floatLanes t && i.data == 0)) && s.a == t && decide (i.data < 7)
  | .floatFma => c.floatLanes t && s.a == t && s.b == t && c.typesMatch s.extra [t]
  | .vectorSelect => c.maskOf s.a && s.b == t && (c.floatLanes t || c.integerLanes t || c.maskOf t) &&
      c.typesMatch s.extra [t]
  -- dictionaries, text, arrays, function values
  | .dictNew => (c.dictOf t).isSome && s.a == Ty.u64
  | .dictLen | .dictEntries => (c.dictOf s.a).isSome && t == Ty.u64
  | .dictFind => match c.dictOf s.a with
    | some (k, _) => t == Ty.i64 && (s.b == k || (k == Ty.str && s.b == Ty.strView) || (k == Ty.bytes && s.b == Ty.bytesView))
    | none => false
  | .dictEntryKey => match c.dictOf s.a with | some (k, _) => t == k && s.b == Ty.i64 | none => false
  | .dictEntryValue => match c.dictOf s.a with | some (_, v) => t == v && s.b == Ty.i64 | none => false
  | .dictSetValue => match c.dictOf s.a with
    | some (_, v) => t == s.a && s.b == Ty.i64 && c.typesMatch s.extra [v]
    | none => false
  | .dictInsert => match c.dictOf s.a with
    | some (k, v) => t == s.a && s.b == Ty.i64 && c.typesMatch s.extra [k, v]
    | none => false
  | .dictRemove => (c.dictOf s.a).isSome && t == s.a && s.b == Ty.i64
  | .dictEntryLive => (c.dictOf s.a).isSome && t == Ty.bool && s.b == Ty.i64
  | .dictCopy | .dictClear => (c.dictOf s.a).isSome && t == s.a
  | .strChar => s.a == Ty.str && s.b == Ty.u64 && t == Ty.str
  | .strWidth => (s.a == Ty.str || s.a == Ty.strView) && s.b == Ty.u64 && t == Ty.u64
  | .strCode => (s.a == Ty.str || s.a == Ty.strView) && s.b == Ty.u64 && t == Ty.u32
  | .strAppend => t == Ty.str && s.a == Ty.str && s.b == Ty.str
  | .strAppendChar => t == Ty.str && s.a == Ty.str && (s.b == Ty.str || s.b == Ty.strView) && c.typesMatch s.extra [Ty.u64]
  | .strSlice => t == Ty.str && s.a == Ty.str && s.b == Ty.i64 && c.typesMatch s.extra [Ty.i64]
  | .strViewOf =>
    ((t == Ty.strView && (s.a == Ty.str || s.a == Ty.byteBuffer || s.a == Ty.strView)) ||
     (t == Ty.bytesView && (s.a == Ty.bytes || s.a == Ty.bytesView))) && s.b == Ty.u64 && c.typesMatch s.extra [Ty.u64]
  | .strSliceView =>
    ((t == Ty.strView && s.a == Ty.str) || (t == Ty.bytesView && (s.a == Ty.bytes || s.a == Ty.byteBuffer))) &&
      s.b == Ty.i64 && c.typesMatch s.extra [Ty.i64]
  | .strSliceBytesView => t == Ty.strView && s.a == Ty.str && s.b == Ty.i64 && c.typesMatch s.extra [Ty.i64]
  | .strFromView => t == Ty.str && s.a == Ty.strView
  | .byteLoad => s.a == Ty.bytesView && s.b == Ty.u64 && decide (i.data ≤ 1) &&
      ([Ty.u16, Ty.i16, Ty.u32, Ty.i32, Ty.u64, Ty.i64].contains t ||
       ([Ty.u8, Ty.i8, Ty.f32, Ty.f64].contains t && i.data == 0))
  | .textFrame => t == Ty.str && s.a == Ty.str && s.b == Ty.strView
  | .listSort => (c.listOf s.a).isSome && t == s.a && s.b == Ty.bool
  | .arrayGet => match c.arrayOf s.a with | some (e, _, _) => t == e && int s.b | none => false
  | .arrayFromBytes => match c.arrayOf t with | some (e, _, _) => e == Ty.u8 && s.a == Ty.bytes | none => false
  | .arraySet => match c.arrayOf s.a with
    | some (e, _, _) => t == s.a && int s.b && c.typesMatch s.extra [e]
    | none => false
  | .funcRef => match c.fnOf t with
    | some sig => (match m.functions[i.data]? with
      | some g => sig == g.sig && sig.linkage == .internal
      | none => false)
    | none => false
  | .callIndirect => match c.fnOf s.a with
    | some sig => sig.linkage == .internal && t == sig.ret && c.typesMatch s.extra sig.params
    | none => false
  -- constants, arithmetic, comparisons, conversions
  | .copy => true
  -- a parameter reads the argument passed for parameter `data`, at that parameter's type
  | .param => c.f.sig.params[i.data]? == some t
  | .fconst => c.floatLanes t
  | .strConst => t == Ty.str || t == Ty.bytes
  -- a function value is made only by `func_ref` (A17): no undefined value is, or holds, one
  | .undef => !m.holdsFn t
  | .borrow =>
    (m.storageType t == m.storageType s.a && m.managed (m.storageType s.a) && m.isBorrowed t != m.isBorrowed s.a) ||
      c.lentWhole t s.a
  | .textSentinel => t == Ty.str || (c.listOf t).isSome
  | .iconst => int t || t == Ty.bool || t == Ty.cap
  | .phi => (c.extraOf i.data).all fun o => match o with | some r => c.typeOf r == t | none => false
  | .add | .sub | .mul => (int t || c.integerLanes t) && s.a == t && s.b == t
  | .div | .rem | .floorDiv | .floorRem => int t && s.a == t && s.b == t
  | .neg => (int t || c.integerLanes t) && s.a == t
  | .bitAnd | .bitOr | .bitXor => (int t || t == Ty.bool || c.integerLanes t || c.maskOf t) && s.a == t && s.b == t
  | .not => (t == Ty.bool && s.a == Ty.bool) || (c.maskOf t && s.a == t)
  | .cmp => c.cmpOk s
  | .fadd | .fsub | .fmul | .fdiv => c.floatLanes t && s.a == t && s.b == t
  | .fneg => c.floatLanes t && s.a == t
  | .fcmp => (t == Ty.bool || c.maskOf t) && c.floatLanes s.a && s.b == s.a && decide (i.data < 6)
  | .intToFloat => Ty.isFloat t && int s.a
  | .floatToInt => int t && Ty.isFloat s.a
  | .floatConvert => (t == Ty.f64 && s.a == Ty.f32) || (t == Ty.f32 && s.a == Ty.f64) || c.convertsLanes t s.a
  | .bitcast => (t == Ty.f64 && s.a == Ty.u64) || (t == Ty.u64 && s.a == Ty.f64) ||
      (t == Ty.f32 && s.a == Ty.u32) || (t == Ty.u32 && s.a == Ty.f32)
  | .convert => int t && int s.a
  | .strLen => int t && (s.a == Ty.str || s.a == Ty.strView || s.a == Ty.bytesView)
  | .strParseInt => (s.a == Ty.str || s.a == Ty.strView) && (c.unionOf t).isSome
  -- lists, records, unions, boxes, drops
  | .listNew => (c.listOf t).isSome && int s.a
  | .listLen => int t && c.listOrView s.a
  | .listGet => int s.b && c.elementRead s.a t
  | .listViewOf => match c.listViewOf t with | some e => c.listOf s.a == some e | none => false
  | .listSliceView => match c.listViewOf t with
    | some e =>
      let source := match c.listOf s.a with | some x => some x | none => c.listViewOf s.a
      source == some e && s.b == Ty.i64 && c.typesMatch s.extra [Ty.i64]
    | none => false
  | .listPush => match c.listOf s.a with | some e => t == s.a && s.b == e | none => false
  | .listCopy => match c.listOf s.a with
    | some _ => t == s.a
    | none => match c.listViewOf s.a with | some e => c.listOf t == some e | none => false
  | .listPop => (c.listOf s.a).isSome && t == s.a
  | .listSet => match c.listOf s.a with
    | some e => t == s.a && int s.b && c.typesMatch s.extra [e]
    | none => false
  | .listGetField =>
    let element := match c.listOf s.a with | some x => some x | none => c.listViewOf s.a
    match element with
    | some e =>
      let path := fieldPath i.data
      !path.isEmpty && (match m.pathTarget e path with | some (pt, _) => int s.b && pt == t | none => false)
    | none => false
  | .listSetField => match c.listOf s.a with
    | some e =>
      t == s.a && int s.b && s.extra.length == 2 &&
      (match c.setPath i with
       | some path => !path.isEmpty && (match m.pathTarget e path with
         | some (pt, tagOf) => tagOf == Ty.void && (match s.extra with | v :: _ => (match v with | some r => pt == c.typeOf r | none => false) | [] => false)
         | none => false)
       | none => false)
    | none => false
  | .bufferAppend => t == Ty.byteBuffer && s.a == Ty.byteBuffer && s.extra.length == 2 &&
      (s.b == Ty.bytes || s.b == Ty.byteBuffer || Ty.isSpan s.b) && c.typesMatch s.extra [Ty.i64, Ty.i64]
  | .unionTag => t == Ty.u32 && (c.unionOf s.a).isSome
  | .unionMake | .unionPayload | .unionTake =>
    let ut := if i.op == .unionMake then t else s.a
    match c.unionOf ut with
    | none => false
    | some cases => match cases[i.data]? with
      | none => false
      | some payload => match i.op with
        | .unionTake => let inner := (c.boxOf payload).getD payload; inner != Ty.void && inner == t
        | .unionPayload => payload != Ty.void && payload == t
        | _ => if payload == Ty.void then i.a.isNone else i.a.isSome && s.a == payload
  | .recordMake => match c.recordOf t with
    | some fs => c.typesMatch s.extra fs
    | none => match c.arrayOf t with
      | some (e, n, _) => s.extra.length == n && s.extra.all fun v => match v with | some r => c.typeOf r == e | none => false
      | none => false
  | .recordGet => match c.recordOf s.a with | some fs => fs[i.data]? == some t | none => false
  | .recordTake => match c.recordOf s.a with
    | some fs => !m.containsBorrow s.a && m.managed s.a && fs[i.data]? == some t
    | none => false
  | .recordSet => match c.recordOf s.a with | some fs => t == s.a && fs[i.data]? == some s.b | none => false
  | .boxMake => match c.boxOf t with | some inner => s.a == inner | none => false
  | .boxGet | .boxTake => match c.boxOf s.a with | some inner => inner == t | none => false
  | .boxFrame => match c.boxOf t with | some inner => s.a == inner && m.kind? inner == some .record | none => false
  | .blockFrame =>
    if t == Ty.str then s.a == Ty.strView && i.b.isSome && s.b == Ty.str
    else if t == Ty.bytes then s.a == Ty.bytesView && i.b.isNone
    else (match c.listOf t, c.listViewOf s.a with
      | some e, some v => e == v && i.b.isSome && s.b == t
      | _, _ => false)
  | .drop => t == Ty.void && m.managed s.a
  | .errTrace => t == Ty.void && decide (i.data ≤ 4) && (if i.data == 3 then i.a.isSome && s.a == Ty.str else i.a.isNone)
  -- calls, printing, terminators
  | .call => c.callOk s
  | .print => t == Ty.void && (match s.extra with | some r :: _ => c.typeOf r == Ty.cap | _ => false)
  | .jump => decide (i.data < c.f.blocks.size)
  | .branch => s.a == Ty.bool
  | .ret => if c.f.sig.ret == Ty.void then i.a.isNone else i.a.isSome && s.a == c.f.sig.ret
  | .unreachable => t == Ty.void &&
      ((i.a.isNone && i.b.isNone) ||
       (i.data / textTrapFlag % 2 == 1 && i.a.isSome && i.b.isSome && int s.a && int s.b))

/-- A shallow copy of a list or dictionary would duplicate managed children (zero-RC has no shared ownership). -/
def shallowManagedCopy (i : Inst) : Bool :=
  c.m.valid i.ty &&
  match i.op, c.m.compound? i.ty with
  | .listCopy, some (.list e) => c.m.managed e
  | .dictCopy, some (.dict k v) => c.m.managed k || c.m.managed v
  | _, _ => false

end Fn

end VerifyIr
