import Std.Data.HashMap
import Checker

/-!
# Reading `ownership-certificate-v2` (design §4.1)

The grammar, one item per line, fields separated by single spaces:

```text
ownership-certificate-v2
class <op> <Class>                                   one per ir.Op, in enum order
function <name> result <scalar|owned|borrowed> from <I,…|-> unchecked <-|reason>
param <I> %N <state>                                 one per parameter
block bN preds <bM,…|->                              blocks in index order
phi %N <state> parents <%P,…|^I,…|-> edges <bM:%V,…>
inst %N <op> <Class> reads <%V,…|-> consumes <%V,…|-> state <state> parents <%P,…|^I,…|->
inst - <op> <Class> reads <…> consumes <…> state none parents -
term jump bN | term branch %V bT bF | term ret <%V|-> | term unreachable
end
```

`%N` is value `N`, `^I` is `caller(I)`, `bN` is block `N`, `-` is the empty list.  Constants and
parameters are `inst` lines of the pseudo-block `b-`: either every `inst` line before the first
`block b0` line, or the lines after an explicit `block b- preds -` header.  A file holds the
`class` table once and any number of `function … end` groups.

The first line must be exactly `ownership-certificate-v2`; any other version is refused, `ownership-certificate-v1` (the
format before the `views` extra) included.
A malformed file is an error, never a verdict.
-/

namespace Own

/-- The only format version this reader accepts. -/
def formatVersion : String := "ownership-certificate-v2"

/-! ## Tokens -/

def parseNat (s : String) : Except String Nat :=
  match s.toNat? with
  | some n => pure n
  | none => throw s!"expected a number, found '{s}'"

/-- `%N`. -/
def parseVal (s : String) : Except String ValId :=
  if s.startsWith "%" then parseNat (s.drop 1).toString else throw s!"expected a value %N, found '{s}'"

/-- `bN`. -/
def parseBlockId (s : String) : Except String BlockId :=
  if s.startsWith "b" then parseNat (s.drop 1).toString else throw s!"expected a block bN, found '{s}'"

/-- `%N` or `^I`. -/
def parseRoot (s : String) : Except String Root :=
  if s.startsWith "%" then (Root.val <$> parseNat (s.drop 1).toString)
  else if s.startsWith "^" then (Root.caller <$> parseNat (s.drop 1).toString)
  else throw s!"expected %N or ^I, found '{s}'"

/-- A comma-separated list, or `-` for the empty list. -/
def parseList {α : Type} (f : String → Except String α) (s : String) :
    Except String (List α) :=
  if s == "-" then pure [] else (s.splitOn ",").mapM f

def parseSt (s : String) : Except String St :=
  match s with
  | "scalar" => pure .scalar
  | "immortal" => pure .immortal
  | "owned" => pure .owned
  | "stack" => pure .stack
  | "borrowed" => pure .borrowed
  | "emptied" => pure .emptied
  | "none" => pure .none
  | _ => throw s!"unknown state '{s}'"

def St.render : St → String
  | .scalar => "scalar" | .immortal => "immortal" | .owned => "owned"
  | .stack => "stack" | .borrowed => "borrowed" | .emptied => "emptied" | .none => "none"

/-- The class names of the export (design §3 table). -/
def parseClass (s : String) : Except String Class :=
  match s with
  | "Parameter" => pure .parameter | "Constant" => pure .constant | "Pure" => pure .pure
  | "Inspect" => pure .inspect | "Fresh" => pure .fresh | "Copy" => pure .copy
  | "Project" => pure .project | "View" => pure .view | "Character" => pure .character
  | "TextFrame" => pure .textFrame | "Borrow" => pure .borrow | "Update" => pure .update
  | "Construct" => pure .construct | "Take" => pure .take | "Drop" => pure .drop
  | "Call" => pure .call | "Output" => pure .output | "Trace" => pure .trace
  | "Join" => pure .join | "Forward" => pure .forward | "Jump" => pure .jump | "Branch" => pure .branch
  | "Return" => pure .ret | "Trap" => pure .trap
  | _ => throw s!"unknown class '{s}'"

def Class.render : Class → String
  | .parameter => "Parameter" | .constant => "Constant" | .pure => "Pure"
  | .inspect => "Inspect" | .fresh => "Fresh" | .copy => "Copy" | .project => "Project"
  | .view => "View" | .character => "Character" | .textFrame => "TextFrame"
  | .borrow => "Borrow" | .update => "Update" | .construct => "Construct" | .take => "Take"
  | .drop => "Drop" | .call => "Call" | .output => "Output" | .trace => "Trace"
  | .join => "Join" | .forward => "Forward" | .jump => "Jump" | .branch => "Branch" | .ret => "Return"
  | .trap => "Trap"

/-- The words of a callee table entry (design entry 57); an unknown word is a malformed file. -/
def parseKind (s : String) : Except String CalleeKind :=
  match s with
  | "program" => pure .program | "runtime" => pure .runtime | "extern" => pure .extern
  | "marker" => pure .marker | "indirect" => pure .indirect
  | _ => throw s!"unknown callee kind '{s}'"

def CalleeKind.render : CalleeKind → String
  | .program => "program" | .runtime => "runtime" | .extern => "extern" | .marker => "marker"
  | .indirect => "indirect"

def parseParamTok (s : String) : Except String ParamTok :=
  match s with
  | "take" => pure .take | "take-scalar" => pure .takeScalar | "read" => pure .read
  | "read-scalar" => pure .readScalar
  | _ => throw s!"unknown callee parameter '{s}'"

def ParamTok.render : ParamTok → String
  | .take => "take" | .takeScalar => "take-scalar" | .read => "read" | .readScalar => "read-scalar"

def parseResTok (s : String) : Except String ResTok :=
  match s with
  | "scalar" => pure .scalar | "owned" => pure .owned | "borrowed" => pure .borrowed
  | _ => throw s!"unknown callee result '{s}'"

def ResTok.render : ResTok → String
  | .scalar => "scalar" | .owned => "owned" | .borrowed => "borrowed"

/-- The optional fields after `parents`, in the order `slot`, `released`, `slots`, `from`. -/
structure Extras where
  slot : Option String := none
  released : Option String := none
  taken : Option String := none
  slots : List String := []
  fromVals : List ValId := []
  lent : Option ValId := none
  noLoans : Bool := false
  views : Option (List ValId) := none
  imm : Option Nat := none
  entry : Option Nat := none

/-- Read `[slot KEY] [released PARTS] [taken PARTS] [slots KEYS] [from VALUES] [lent %G] [noloans] [views VALUES] [imm N]`. -/
def parseExtras : List String → Except String Extras
  | [] => pure {}
  | "slot" :: k :: rest => do
    let e ← parseExtras rest
    if e.slot.isSome then throw "slot twice"
    pure { e with slot := some k }
  | "released" :: r :: rest => do
    let e ← parseExtras rest
    pure { e with released := some r }
  | "taken" :: r :: rest => do
    let e ← parseExtras rest
    pure { e with taken := some r }
  | "slots" :: ks :: rest => do
    let e ← parseExtras rest
    pure { e with slots := if ks == "-" then [] else ks.splitOn "," }
  | "from" :: vs :: rest => do
    let e ← parseExtras rest
    pure { e with fromVals := ← parseList parseVal vs }
  | "noloans" :: rest => do
    let e ← parseExtras rest
    pure { e with noLoans := true }
  | "callee" :: n :: rest => do
    let e ← parseExtras rest
    if e.entry.isSome then throw "callee twice"
    pure { e with entry := some (← parseNat n) }
  | "lent" :: g :: rest => do
    let e ← parseExtras rest
    if e.lent.isSome then throw "lent twice"
    pure { e with lent := some (← parseVal g) }
  | "views" :: vs :: rest => do
    let e ← parseExtras rest
    if e.views.isSome then throw "views twice"
    pure { e with views := some (← parseList parseVal vs) }
  | "imm" :: n :: rest => do
    let e ← parseExtras rest
    if e.imm.isSome then throw "imm twice"
    pure { e with imm := some (← parseNat n) }
  | t :: _ => throw s!"unexpected field '{t}' after parents"

/-- `bM:%V`. -/
def parseEdge (s : String) : Except String (BlockId × ValId) :=
  match s.splitOn ":" with
  | [b, v] => do pure (← parseBlockId b, ← parseVal v)
  | _ => throw s!"expected bM:%V, found '{s}'"

/-! ## The function being read -/

structure BlockB where
  id : Nat
  preds : List BlockId
  phis : List Phi
  insts : List Inst
  term : Option Term
  abandons : List (BlockId × List ValId) := []

structure FnB where
  name : String
  result : St
  from_ : List Nat
  unchecked : Option String
  /-- `(I, value, kind)`, most recent first -/
  params : List (Nat × ValId × St)
  pre : List Inst
  /-- the callee table read so far, in order -/
  callees : List CalleeEntry := []
  /-- the blocks read so far, in order, with their ids (ids may skip blocks the exporter dropped) -/
  blocks : List (Nat × Block)
  cur : Option BlockB
  seenBlock : Bool
  states : Std.HashMap ValId St
  parents : Std.HashMap ValId (List Root)

structure PState where
  versionSeen : Bool
  classes : Std.HashMap String Class
  fn : Option FnB
  done : List Entry

def PState.empty : PState :=
  { versionSeen := false, classes := {}, fn := none, done := [] }

/-- A function with nothing read yet. -/
def FnB.new (name : String) (result : St) (from_ : List Nat) (unchecked : Option String) : FnB :=
  { name := name, result := result, from_ := from_, unchecked := unchecked, params := [],
    pre := [], blocks := [], cur := none, seenBlock := false, states := {}, parents := {} }

/-- Finish the block being read: it needs its terminator. -/
def FnB.closeBlock (b : FnB) : Except String FnB :=
  match b.cur with
  | none => pure b
  | some blk =>
    match blk.term with
    | none => throw s!"block b{blk.id} has no term line"
    | some t =>
      let done : Block :=
        { preds := blk.preds, phis := blk.phis.reverse, insts := blk.insts.reverse, term := t,
          abandons := blk.abandons }
      pure { b with blocks := b.blocks ++ [(blk.id, done)], cur := none }

/-- The function read so far, as a `Function` with its certificate. -/
def FnB.finish (b : FnB) : Except String Entry := do
  let b ← b.closeBlock
  let ps := b.params.reverse
  let mut i := 0
  for p in ps do
    if p.1 != i then throw s!"parameters must be numbered 0, 1, ... in order (found {p.1} at position {i})"
    i := i + 1
  let st := b.states
  let pa := b.parents
  -- the exporter drops blocks without predecessors: keep the numbering, fill the gaps
  let top := match b.blocks.getLast? with
    | some (n, _) => n + 1
    | none => 0
  let placeholder : Block := { preds := [], phis := [], insts := [], term := .unreachable }
  let filled := (List.range top).map fun n =>
    match b.blocks.find? (·.1 == n) with
    | some (_, blk) => blk
    | none => placeholder
  let present := b.blocks.map (·.1)
  for (_, blk) in b.blocks do
    for t in blk.term.succs do
      if !present.contains t then throw s!"an edge targets b{t}, which the file does not define"
  pure
    { fn := { name := b.name, params := ps.map (·.2.2), result := b.result, from_ := b.from_,
              paramVals := ps.map (·.2.1), pre := b.pre.reverse, blocks := filled,
              callees := b.callees },
      cert := { state := fun n => st.getD n .none, parents := fun n => pa.getD n [] },
      unchecked := b.unchecked }

/-- Record the state and parents of a defined value. -/
def FnB.define (b : FnB) (v : ValId) (s : St) (ps : List Root) : Except String FnB :=
  if b.states.contains v then throw s!"value %{v} is defined twice"
  else pure { b with states := b.states.insert v s, parents := b.parents.insert v ps }

/-- Read one line (`toks` are its space-separated fields). -/
def readLine (st : PState) (toks : List String) : Except String PState := do
  match toks with
  | ["class", op, cls] =>
    if st.fn.isSome then throw "class line inside a function"
    let c ← parseClass cls
    pure { st with classes := st.classes.insert op c }
  | "function" :: name :: "result" :: res :: "from" :: fr :: "unchecked" :: reason@(_ :: _) =>
    if st.fn.isSome then throw "function inside a function (missing end)"
    let result ← parseSt res
    let from_ ← parseList parseNat fr
    let unchecked := if reason == ["-"] then none else some (" ".intercalate reason)
    pure { st with fn := some (FnB.new name result from_ unchecked) }
  | ["param", i, v, s] =>
    let some b := st.fn | throw "param line outside a function"
    if b.seenBlock then throw "param line after a block"
    pure { st with fn := some { b with params := (← parseNat i, ← parseVal v, ← parseSt s) :: b.params } }
  | ["callee", n, name, kind, ps, res, fr] =>
    let some b := st.fn | throw "callee line outside a function"
    if b.seenBlock then throw "callee line after a block"
    let entry : CalleeEntry :=
      { id := ← parseNat n, name := name, kind := ← parseKind kind,
        params := ← parseList parseParamTok ps, result := ← parseResTok res, from_ := ← parseList parseNat fr }
    pure { st with fn := some { b with callees := b.callees ++ [entry] } }
  | ["block", "b-", "preds", "-"] =>
    let some b := st.fn | throw "block line outside a function"
    if b.seenBlock then throw "pseudo-block b- must come before b0"
    pure st
  | ["block", bn, "preds", ps] =>
    let some b := st.fn | throw "block line outside a function"
    let b ← b.closeBlock
    let id ← parseBlockId bn
    match b.blocks.getLast? with
    | some (prev, _) => if id <= prev then throw s!"blocks must be numbered in increasing order (b{id} after b{prev})"
    | none => pure ()
    let preds ← parseList parseBlockId ps
    let blk : BlockB := { id := id, preds := preds, phis := [], insts := [], term := none }
    pure { st with fn := some { b with seenBlock := true, cur := some blk } }
  | ["abandon", bp, vs] =>
    let some b := st.fn | throw "abandon line outside a function"
    let some blk := b.cur | throw "abandon line outside a block"
    let pred ← parseBlockId bp
    let vals ← parseList parseVal vs
    pure { st with fn := some { b with cur := some { blk with abandons := blk.abandons ++ [(pred, vals)] } } }
  | ["phi", v, s, "parents", ps, "edges", es] =>
    let some b := st.fn | throw "phi line outside a function"
    let some blk := b.cur | throw "phi line outside a block"
    if !blk.insts.isEmpty then throw "phi line after an inst line"
    let dst ← parseVal v
    let state ← parseSt s
    let parents ← parseList parseRoot ps
    let edges ← parseList parseEdge es
    let b ← b.define dst state parents
    pure { st with fn := some { b with
      cur := some { blk with phis := { dst := dst, edges := edges } :: blk.phis } } }
  | "inst" :: v :: op :: cls :: "reads" :: rs :: "consumes" :: cs :: "state" :: s :: "parents" :: ps :: extra =>
    let some b := st.fn | throw "inst line outside a function"
    let c ← parseClass cls
    let misclassified ← match st.classes[op]? with
      | none => throw s!"operation '{op}' is not in the class table"
      | some c' => pure (c' != c)
    let reads ← parseList parseVal rs
    let consumes ← parseList parseVal cs
    let state ← parseSt s
    let parents ← parseList parseRoot ps
    let (dst, b) ← if v == "-" then
        (if state != .none then throw "inst - must have state none" else pure (none, b))
      else do
        let d ← parseVal v
        pure (some d, ← b.define d state parents)
    let ex ← parseExtras extra
    let inst : Inst :=
      { dst := dst, op := op, cls := c, reads := reads, consumes := consumes, slot := ex.slot,
        released := ex.released, taken := ex.taken, slots := ex.slots, fromVals := ex.fromVals,
        lent := ex.lent, noLoans := ex.noLoans, views := ex.views.getD [], imm := ex.imm, entry := ex.entry, misclassified := misclassified }
    match b.cur with
    | some blk =>
      pure { st with fn := some { b with cur := some { blk with insts := inst :: blk.insts } } }
    | none =>
      if b.seenBlock then throw "inst line outside a block"
      else pure { st with fn := some { b with pre := inst :: b.pre } }
  | "term" :: rest =>
    let some b := st.fn | throw "term line outside a function"
    let some blk := b.cur | throw "term line outside a block"
    if blk.term.isSome then throw s!"block b{blk.id} has two term lines"
    let t ← match rest with
      | ["jump", bn] => Term.jump <$> parseBlockId bn
      | ["branch", c, bt, bf] => do pure (Term.branch (← parseVal c) (← parseBlockId bt) (← parseBlockId bf))
      | ["ret", "-"] => pure (Term.ret none)
      | ["ret", v] => (fun x => Term.ret (some x)) <$> parseVal v
      | ["unreachable"] => pure Term.unreachable
      | _ => throw s!"malformed term line"
    pure { st with fn := some { b with cur := some { blk with term := some t } } }
  | ["end"] =>
    let some b := st.fn | throw "end outside a function"
    let e ← b.finish
    pure { st with fn := none, done := st.done ++ [e] }
  | [] => pure st
  | t :: _ => throw s!"unknown or malformed line starting with '{t}'"

/-- Read a whole file: the class table and the functions in order. -/
def parseFile (text : String) : Except String (List Entry) := do
  let lines := (text.splitOn "\n").map fun l => if l.endsWith "\r" then l.dropEnd 1 |>.toString else l
  match lines with
  | [] => throw "empty file"
  | first :: rest =>
    if first != formatVersion then
      if first.startsWith "ownership-certificate-" then
        throw s!"unsupported format version '{first}' (this reader accepts {formatVersion})"
      else throw s!"not an ownership certificate file (first line '{first}')"
    let mut st := PState.empty
    let mut n := 1
    for l in rest do
      n := n + 1
      if l == "" then continue
      match readLine st (l.splitOn " ") with
      | .ok st' => st := st'
      | .error msg => throw s!"line {n}: {msg}"
    if st.fn.isSome then throw "unexpected end of file inside a function (missing end)"
    pure st.done

end Own
