import Facts.Types

/-!
# Reading `fact-certificate-v1`

The reader of design §10, line for line the one in `src/core/fact_text.zig`: the same lines are
accepted, in the same state machine, and a malformed file is reported at the same line number.
-/

namespace Facts

/-- Every operation name of `ir.Op` (`src/core/ir.zig`), so an unknown name is refused as the Zig reader refuses it. -/
def irOpNames : List String :=
  ["param", "iconst", "fconst", "undef", "str_const", "copy", "borrow", "phi", "add", "sub", "mul", "div", "rem",
   "floor_div", "floor_rem", "neg", "bit_and", "bit_or", "bit_xor", "not", "cmp", "fadd", "fsub", "fmul", "fdiv",
   "fneg", "fcmp", "int_to_float", "float_to_int", "convert", "list_new", "list_len", "list_get", "list_view_of",
   "list_slice_view", "list_push", "list_copy", "str_len", "str_parse_int", "union_make", "union_tag",
   "union_payload", "record_make", "record_get", "record_set", "list_set", "list_pop", "list_get_field", "dict_new",
   "dict_len", "dict_find", "dict_entry_key", "dict_entry_value", "dict_set_value", "dict_insert", "dict_remove",
   "dict_entries", "dict_entry_live", "dict_copy", "dict_clear", "str_char", "str_width", "str_code", "str_append",
   "str_append_char", "str_slice", "str_view_of", "str_from_view", "text_sentinel", "text_frame", "list_sort",
   "array_get", "array_set", "array_from_bytes", "func_ref", "call_indirect", "box_make", "box_get", "box_frame", "block_frame",
   "drop",
   "err_trace", "call", "print", "jump", "branch", "ret", "buffer_new", "buffer_copy", "buffer_set", "buffer_push",
   "buffer_pop", "shift_left", "shift_right", "saturating_add", "float_unary", "list_set_field", "buffer_append",
   "str_slice_view", "str_slice_bytes_view", "union_take", "box_take", "float_convert", "bitcast", "float_fma",
   "vector_select", "byte_load", "record_take"]

/-- Where and why the text was malformed. -/
structure Problem where
  line : Nat
  reason : String
  deriving Repr

/-- A function being read. -/
structure Draft where
  header : Header := ⟨"", false, false, [], .void⟩
  params : Array (Option Interval) := #[]
  returns : Option Interval := none
  pre : Array Inst := #[]
  blocks : Array Block := #[]
  loops : Array Loop := #[]
  lists : Array ListFact := #[]
  bounds : Array Bound := #[]
  sites : Array Site := #[]

/-- The block being read. -/
structure Current where
  id : Nat := 0
  dead : Bool := false
  preds : List Nat := []
  phis : Array Phi := #[]
  insts : Array Inst := #[]

/-- The reader's state. -/
structure Reader where
  line : Nat := 0
  seenHeader : Bool := false
  functions : Array Function := #[]
  open_ : Bool := false
  draft : Draft := {}
  inPre : Bool := true
  inBlock : Bool := false
  current : Current := {}

abbrev Parser := Except Problem

/-- Fail at the reader's current line. -/
def Reader.fail {α : Type} (r : Reader) (reason : String) : Parser α :=
  .error ⟨r.line, reason⟩

/-- A signed decimal number with an optional sign, in the range `[lo, hi]`. -/
def parseNumber (s : String) (lo hi : Int) : Option Int :=
  let (neg, digits) : Bool × String :=
    if s.startsWith "-" then (true, (s.drop 1).toString)
    else if s.startsWith "+" then (false, (s.drop 1).toString) else (false, s)
  if digits.isEmpty || !digits.all Char.isDigit then none
  else
    let n : Int := (digits.foldl (fun (acc : Nat) c => acc * 10 + (c.toNat - '0'.toNat)) 0 : Nat)
    let v := if neg then -n else n
    if lo ≤ v ∧ v ≤ hi then some v else none

/-- A `u32`. -/
def parseU32 (s : String) : Option Nat := (parseNumber s 0 (2 ^ 32 - 1)).map Int.toNat

/-- A `u64`. -/
def parseU64 (s : String) : Option Nat := (parseNumber s 0 (2 ^ 64 - 1)).map Int.toNat

/-- An `i128`. -/
def parseI128 (s : String) : Option Int := parseNumber s (-(2 ^ 127)) (2 ^ 127 - 1)

/-- `%N`. -/
def parseValue (s : String) : Option Nat :=
  if s.length < 2 || !s.startsWith "%" then none else parseU32 (s.drop 1).toString

/-- `bN`. -/
def parseBlock (s : String) : Option Nat :=
  if s.length < 2 || !s.startsWith "b" then none else parseU32 (s.drop 1).toString

/-- The value of a hexadecimal digit. -/
def hexDigit? (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 'A'.toNat + 10)
  else none

/-- The characters of a function name with its `\xHH` escapes decoded; none for a bad escape. -/
def unescapeChars : List Char → List Char → Option (List Char)
  | [], acc => some acc.reverse
  | '\\' :: 'x' :: h :: l :: rest, acc =>
    match hexDigit? h, hexDigit? l with
    | some a, some b => unescapeChars rest (Char.ofNat (a * 16 + b) :: acc)
    | _, _ => none
  | c :: rest, acc => unescapeChars rest (c :: acc)

/-- A function name as the file spells it. -/
def unescapeName (s : String) : Option String := (unescapeChars s.toList []).map String.ofList

/-- A function name is one token: a byte at or below `0x20`, `0x7f` or `\\` is written `\xHH`. -/
def escapeName (s : String) : String :=
  s.foldl (fun (acc : String) c =>
    if c.toNat ≤ 0x20 ∨ c.toNat = 0x7f ∨ c = '\\' then
      let h := c.toNat
      let hex (d : Nat) : Char := if d < 10 then Char.ofNat ('0'.toNat + d) else Char.ofNat ('a'.toNat + d - 10)
      acc ++ "\\x" ++ String.singleton (hex (h / 16)) ++ String.singleton (hex (h % 16))
    else acc.push c) ""

/-- The two-word-or-one-word interval at `w[at]`: the interval and how many words it took. -/
def rangeAt (r : Reader) (w : Array String) (at_ : Nat) : Parser (Option Interval × Nat) := do
  if at_ ≥ w.size then r.fail "a missing interval"
  else if w[at_]! == "-" then pure (none, 1)
  else if at_ + 1 ≥ w.size then r.fail "an interval needs two numbers"
  else
    match parseI128 w[at_]!, parseI128 w[at_ + 1]! with
    | some lo, some hi => pure (some ⟨lo, hi⟩, 2)
    | _, _ => r.fail "a bad number"

/-- The words at the given positions are the given markers. -/
def marked (w : Array String) (marks : List (Nat × String)) : Bool :=
  marks.all fun (i, s) => w[i]? == some s

/-- A flag is `0` or `1`. -/
def flagOf (r : Reader) (s : String) : Parser Bool :=
  if s == "1" then pure true else if s == "0" then pure false else r.fail "a flag is 0 or 1"

/-- Types separated by commas, or `-`. -/
def typesOf (r : Reader) (s : String) : Parser (List Ty) :=
  if s == "-" then pure [] else
    (s.splitOn ",").mapM fun item =>
      match Ty.ofToken? item with
      | some t => pure t
      | none => r.fail "an unknown type"

/-- The operand word `-`, `#N` or `%N`. -/
def operandOf (r : Reader) (s : String) : Parser (Option Nat) :=
  if s == "-" then pure none
  else if s.length ≥ 2 && s.startsWith "#" then
    match parseU32 (s.drop 1).toString with
    | some n => pure (some n)
    | none => r.fail "a bad number"
  else
    match parseValue s with
    | some n => pure (some n)
    | none => r.fail "expected a value like %12"

/-- Take one line of the file. -/
def takeLine (r : Reader) (line : String) : Parser Reader := do
  let w := (line.splitOn " ").toArray
  let w0 := w[0]!
  if w0 == "fact-certificate-v1" then
    return { r with seenHeader := true }
  if w0 == "function" then
    if r.open_ then r.fail "a function starts before the last one ends"
    else if w.size != 10 || !marked w [(2, "linkage"), (4, "addr"), (6, "params"), (8, "ret")] then
      r.fail "a malformed function line"
    else
      let name ← match unescapeName w[1]! with
        | some n => pure n
        | none => r.fail "a bad escape in a name"
      let internal ← if w[3]! == "internal" then pure true else if w[3]! == "other" then pure false
        else r.fail "an unknown linkage"
      let addr ← flagOf r w[5]!
      let params ← typesOf r w[7]!
      let ret ← match Ty.ofToken? w[9]! with
        | some t => pure t
        | none => r.fail "an unknown type"
      return { r with draft := { header := ⟨name, internal, addr, params, ret⟩ }, inPre := true,
                      inBlock := false, current := {}, open_ := true }
  if !r.open_ then r.fail "a line outside a function"
  else if w0 == "param" then
    if w.size < 3 then r.fail "a malformed param line"
    else
      match parseNumber w[1]! 0 (2 ^ 63) with
      | none => r.fail "a bad number"
      | some k =>
        if k.toNat != r.draft.params.size then r.fail "parameters must be numbered 0, 1, … in order"
        else
          let (range, used) ← rangeAt r w 2
          if 2 + used != w.size then r.fail "a malformed param line"
          else return { r with draft := { r.draft with params := r.draft.params.push range } }
  else if w0 == "returns" then
    let (range, used) ← rangeAt r w 1
    if 1 + used != w.size then r.fail "a malformed returns line"
    else return { r with draft := { r.draft with returns := range } }
  else if w0 == "block" then
    if w.size != 5 || !marked w [(3, "preds")] then r.fail "a malformed block line"
    else if w[1]! == "b-" then return { r with inPre := true }
    else if r.inBlock then r.fail "a block starts before the last one ends"
    else
      let id ← match parseBlock w[1]! with
        | some n => pure n
        | none => r.fail "expected a block like b3"
      let dead ← if w[2]! == "dead" then pure true else if w[2]! == "reach" then pure false
        else r.fail "a block is reach or dead"
      let preds ← if w[4]! == "-" then pure [] else
        (w[4]!.splitOn ",").mapM fun item =>
          match parseBlock item with
          | some n => pure n
          | none => r.fail "expected a block like b3"
      return { r with inPre := false, inBlock := true, current := { id, dead, preds } }
  else if w0 == "phi" then
    if r.inPre || w.size < 7 || !marked w [(3, "edges"), (5, "range")] then r.fail "a malformed phi line"
    else
      let edges ← (w[4]!.splitOn ",").mapM fun item =>
        match item.splitOn ":" with
        | [b, v] =>
          match parseBlock b, parseValue v with
          | some bb, some vv => pure (⟨bb, vv⟩ : PhiEdge)
          | _, _ => r.fail "a phi edge needs bN:%V"
        | _ => r.fail "a phi edge needs bN:%V"
      let (range, used) ← rangeAt r w 6
      if 6 + used != w.size then r.fail "a malformed phi line"
      else
        let value ← match parseValue w[1]! with
          | some n => pure n
          | none => r.fail "expected a value like %12"
        let ty ← match Ty.ofToken? w[2]! with
          | some t => pure t
          | none => r.fail "an unknown type"
        return { r with current := { r.current with phis := r.current.phis.push ⟨value, ty, edges, range⟩ } }
  else if w0 == "inst" then
    if w.size < 17 || !marked w [(5, "a"), (7, "b"), (9, "x"), (11, "imm"), (13, "aux"), (15, "range")] then
      r.fail "a malformed inst line"
    else
      let (range, used) ← rangeAt r w 16
      if 16 + used != w.size then r.fail "a malformed inst line"
      else
        let extra ← if w[10]! == "-" then pure [] else
          (w[10]!.splitOn ",").mapM fun item =>
            if item == "-" then pure none
            else match parseValue item with
              | some n => pure (some n)
              | none => r.fail "expected a value like %12"
        let value ← match parseValue w[1]! with
          | some n => pure n
          | none => r.fail "expected a value like %12"
        let opName := w[2]!
        if !irOpNames.contains opName then r.fail "an unknown operation"
        else
          let ty ← match Ty.ofToken? w[3]! with
            | some t => pure t
            | none => r.fail "an unknown type"
          let check ← if w[4]! == "none" then pure Check.none else if w[4]! == "exact" then pure Check.exact
            else if w[4]! == "proven" then pure Check.proven else r.fail "an unknown check"
          let a ← operandOf r w[6]!
          let b ← operandOf r w[8]!
          let imm ← match parseU64 w[12]! with
            | some n => pure n
            | none => r.fail "a bad number"
          let aux ← match parseU64 w[14]! with
            | some n => pure n
            | none => r.fail "a bad number"
          let inst : Inst := { value, op := Op.ofName opName, name := opName, ty, check,
                               operands := { a, b, x := extra }, imm, aux, range }
          if r.inPre then return { r with draft := { r.draft with pre := r.draft.pre.push inst } }
          else return { r with current := { r.current with insts := r.current.insts.push inst } }
  else if w0 == "term" then
    if r.inPre || !r.inBlock then r.fail "a terminator outside a block"
    else
      let t : Term ← if w[1]! == "jump" && w.size == 3 then
          match parseBlock w[2]! with
          | some n => pure (Term.jump n)
          | none => r.fail "expected a block like b3"
        else if w[1]! == "branch" && w.size == 5 then
          match parseValue w[2]!, parseBlock w[3]!, parseBlock w[4]! with
          | some c, some t, some e => pure (Term.branch c t e)
          | _, _, _ => r.fail "a malformed terminator"
        else if w[1]! == "ret" && w.size == 3 then
          if w[2]! == "-" then pure (Term.ret none)
          else match parseValue w[2]! with
            | some v => pure (Term.ret (some v))
            | none => r.fail "expected a value like %12"
        else if w[1]! == "unreachable" && w.size == 2 then pure Term.unreachable
        else r.fail "a malformed terminator"
      let c := r.current
      let blk : Block := ⟨c.id, c.dead, c.preds, c.phis.toList, c.insts.toList, t⟩
      return { r with inBlock := false, current := {}, draft := { r.draft with blocks := r.draft.blocks.push blk } }
  else if w0 == "loop" then
    if w.size != 9 || !marked w [(1, "header"), (3, "body"), (5, "latch"), (7, "exit")] then
      r.fail "a malformed loop line"
    else
      match parseBlock w[2]!, parseBlock w[4]!, parseBlock w[6]!, parseBlock w[8]! with
      | some h, some b, some l, some e =>
        return { r with draft := { r.draft with loops := r.draft.loops.push ⟨h, b, l, e⟩ } }
      | _, _, _, _ => r.fail "expected a block like b3"
  else if w0 == "list" then
    if w.size < 9 || !marked w [(2, "len")] then r.fail "a malformed list line"
    else
      let (len, lused) ← rangeAt r w 3
      let at_ := 3 + lused
      if at_ + 1 ≥ w.size || w[at_]! != "elems" then r.fail "a malformed list line"
      else
        let (elems, eused) ← rangeAt r w (at_ + 1)
        let rest := at_ + 1 + eused
        if rest + 4 != w.size then r.fail "a malformed list line"
        else if w[rest]! != "length" || w[rest + 2]! != "pattern" then r.fail "a malformed list line"
        else
          let value ← match parseValue w[1]! with
            | some n => pure n
            | none => r.fail "expected a value like %12"
          let length ← if w[rest + 1]! == "-" then pure none
            else match parseValue w[rest + 1]! with
              | some n => pure (some n)
              | none => r.fail "expected a value like %12"
          let pattern ← flagOf r w[rest + 3]!
          return { r with draft := { r.draft with lists := r.draft.lists.push ⟨value, len, elems, length, pattern⟩ } }
  else if w0 == "bound" then
    if w.size != 4 then r.fail "a malformed bound line"
    else
      let strict ← if w[3]! == "strict" then pure true else if w[3]! == "loose" then pure false
        else r.fail "a bound is strict or loose"
      match parseValue w[1]!, parseValue w[2]! with
      | some v, some l => return { r with draft := { r.draft with bounds := r.draft.bounds.push ⟨v, l, strict⟩ } }
      | _, _ => r.fail "expected a value like %12"
  else if w0 == "site" then
    if w.size < 2 then r.fail "a malformed site line"
    else
      let parts ← (w.toList.drop 2).mapM fun word =>
        if word == "-" then pure none
        else match word.splitOn ":" with
          | [lo, hi] =>
            match parseI128 lo, parseI128 hi with
            | some l, some h => pure (some (⟨l, h⟩ : Interval))
            | _, _ => r.fail "a bad number"
          | _ => r.fail "a site interval needs lo:hi"
      match parseValue w[1]! with
      | some v => return { r with draft := { r.draft with sites := r.draft.sites.push ⟨v, parts⟩ } }
      | none => r.fail "expected a value like %12"
  else if w0 == "end" then
    if r.inBlock then r.fail "the function ends inside a block"
    else
      let d := r.draft
      let f : Function :=
        { header := d.header, boundary := { params := d.params.toList, returns := d.returns }, pre := d.pre.toList,
          blocks := d.blocks, aux := { loops := d.loops.toList, lists := d.lists.toList, bounds := d.bounds.toList,
                                       sites := d.sites.toList } }
      return { r with functions := r.functions.push f, open_ := false }
  else r.fail "an unknown line"

/-- Read a certificate file. -/
def parseModule (text : String) : Parser Module := do
  let mut r : Reader := {}
  for line in text.splitOn "\n" do
    r := { r with line := r.line + 1 }
    if line.isEmpty then continue
    r ← takeLine r line
  if r.open_ then r.fail "the file ends inside a function"
  else if !r.seenHeader then r.fail "the file does not start with the format line"
  else return ⟨r.functions⟩

end Facts
