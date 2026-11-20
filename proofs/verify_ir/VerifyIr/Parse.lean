import VerifyIr.Types

/-!
# Reading `core-ir-v1`

The reader of the format `src/core/ir_text.zig` writes and reads: the same texts parse, and a malformed one is
reported at the same line. Names stay escaped (the verdict lines print them as the text spells them).
-/

namespace VerifyIr

/-- Where and why a text was malformed. -/
structure Problem where
  line : Nat
  reason : String
  deriving Repr

/-- The words of one line, and the line's number. -/
structure Line where
  number : Nat
  words : Array String

/-- The reader: the lines and the next one to read. -/
abbrev Reader := StateT Nat (Except Problem)

/-- The text's lines, split into words. -/
def splitLines (text : String) : Array Line := Id.run do
  let mut out : Array Line := #[]
  let mut n := 0
  for line in text.splitOn "\n" do
    n := n + 1
    out := out.push ⟨n, ((line.splitOn " ").filter (· ≠ "")).toArray⟩
  return out

section
variable (ls : Array Line)

/-- Fail at line `n`. -/
def failAt {α : Type} (n : Nat) (reason : String) : Reader α := throw ⟨n, reason⟩

/-- The next line. -/
def nextLine : Reader Line := do
  let i ← get
  match ls[i]? with
  | some l => set (i + 1); pure l
  | none => failAt ls.size "the text ends early"

end

/-- Words of one line being read, with a cursor. -/
structure Words where
  line : Nat
  words : Array String
  at_ : Nat := 0

/-- A reader of one line's words. -/
abbrev WReader := StateT Words (Except Problem)

def wfail {α : Type} (reason : String) : WReader α := do
  let w ← get
  throw ⟨w.line, reason⟩

def word : WReader String := do
  let w ← get
  match w.words[w.at_]? with
  | some s => set { w with at_ := w.at_ + 1 }; pure s
  | none => wfail "a line ends early"

def lineEnd : WReader Unit := do
  let w ← get
  if w.at_ != w.words.size then wfail "a line has extra words"

/-- A decimal number of digits only. -/
def decimal? (s : String) : Option Nat :=
  if s.isEmpty || !s.all Char.isDigit then none else s.toNat?

def num : WReader Nat := do
  match decimal? (← word) with
  | some n => pure n
  | none => wfail "expected a number"

/-- A number below `2 ^ bits` (the Zig reader parses each field at its width). -/
def numBelow (bits : Nat) : WReader Nat := do
  let n ← num
  if n < 2 ^ bits then pure n else wfail "expected a number"

def ty : WReader Ty := numBelow 32

/-- An instruction reference: `-` or a number other than `2^32 - 1` (which is `none`). -/
def ref : WReader (Option Nat) := do
  let s ← word
  if s == "-" then pure none
  else match decimal? s with
    | some n => if n < 2 ^ 32 - 1 then pure (some n) else if n = 2 ^ 32 - 1 then wfail "an instruction number out of range" else wfail "expected an instruction number or -"
    | none => wfail "expected an instruction number or -"

def countOf {α : Type} (n : Nat) (item : WReader α) : WReader (List α) := do
  let mut out : Array α := #[]
  for _ in [0:n] do out := out.push (← item)
  pure out.toList

def tys : WReader (List Ty) := do countOf (← num) ty
def nums32 : WReader (List Nat) := do countOf (← num) (numBelow 32)

def step : WReader Proj := do
  let s ← word
  let rest := (s.drop 1).toString
  match s.front, decimal? rest with
  | 'f', some k => if k < 2 ^ 32 then pure (.field k) else wfail "a bad projection step"
  | 'p', some k => if k < 2 ^ 32 then pure (.payload k) else wfail "a bad projection step"
  | _, _ => wfail (if s.length < 2 then "expected a projection step" else "a bad projection step")

def source : WReader Source := do
  let s ← word
  let rest := (s.drop 1).toString
  if s.length < 2 then wfail "expected a borrow source" else
  match s.front, decimal? rest with
  | 'a', some k => if k < 2 ^ 32 then pure (.argument k) else wfail "a bad borrow source"
  | 'r', some k => if k < 2 ^ 32 then pure (.result (← countOf k step)) else wfail "a bad borrow source"
  | _, _ => wfail "a bad borrow source"

def linkage : WReader Linkage := do
  match ← word with
  | "internal" => pure .internal
  | "extern_c" => pure .externC
  | "runtime_c" => pure .runtimeC
  | "extern_address" => pure .externAddress
  | _ => wfail "an unknown linkage"

def signature : WReader Signature := do
  let l ← linkage
  let r ← ty
  let ps ← tys
  let owned ← numBelow 64
  let consumes ← numBelow 64
  let views ← numBelow 64
  let xo ← nums32
  let xc ← nums32
  let xv ← nums32
  let path ← countOf (← num) step
  let sources ← countOf (← num) source
  pure { params := ps, ret := r, linkage := l,
         passing := { owned, consumes, views, extraOwned := xo, extraConsumes := xc, extraViews := xv },
         path, sources }

def compound : WReader Compound := do
  match ← word with
  | "list" => pure (.list (← ty))
  | "list_view" => pure (.listView (← ty))
  | "box" => pure (.box (← ty))
  | "borrowed" => pure (.borrowed (← ty))
  | "dict" => let k ← ty; let v ← ty; pure (.dict k v)
  | "array" =>
    let e ← ty
    let n ← numBelow 32
    match ← numBelow 8 with
    | 0 => pure (.array e n false)
    | 1 => pure (.array e n true)
    | _ => wfail "expected 0 or 1"
  | "record" => pure (.record (← tys))
  | "union" => pure (.union (← tys))
  | "fn" => pure (.fn (← signature))
  | _ => wfail "an unknown compound kind"

def checkWord : WReader Unit := do
  match ← word with
  | "none" | "exact" | "proven" => pure ()
  | _ => wfail "an unknown check"

def inst : WReader Inst := do
  let some op := Op.ofName? (← word) | wfail "an unknown operation"
  let t ← ty
  let a ← ref
  let b ← ref
  let d ← numBelow 64
  checkWord
  pure { op, ty := t, a, b, data := d }

/-- Run a word reader over a whole line, which it must consume. -/
def onLine {α : Type} (l : Line) (r : WReader α) (from_ : Nat := 0) : Except Problem α :=
  match (do let x ← r; lineEnd; pure x).run ⟨l.number, l.words, from_⟩ with
  | .ok (x, _) => .ok x
  | .error e => .error e

section
variable (ls : Array Line)

/-- A line that starts with `keyword`, read from its second word. -/
def keyed {α : Type} (keyword : String) (r : WReader α) (reason : String := "an unexpected line") : Reader α := do
  let l ← nextLine ls
  if l.words[0]? != some keyword then failAt l.number reason
  match onLine l r 1 with
  | .ok x => pure x
  | .error e => throw e

/-- `KEYWORD N`. -/
def counted (keyword : String) : Reader Nat := do
  let l ← nextLine ls
  if l.words.size != 2 || l.words[0]? != some keyword then failAt l.number "expected a count line"
  match onLine l num 1 with
  | .ok x => pure x
  | .error e => throw e

def block : Reader Block :=
  keyed ls "block" (do
    let n ← num
    let mut is : Array (Option Nat) := #[]
    for _ in [0:n] do is := is.push (← ref)
    let p ← num
    let mut ps : Array Nat := #[]
    for _ in [0:p] do ps := ps.push (← numBelow 32)
    pure ⟨is, ps⟩)

def function : Reader Function := do
  let (name, span, loops) ← keyed ls "function" (do
    let n ← word
    let s ← numBelow 32
    let l ← num
    pure (n, s, l))
  let sig ← keyed ls "sig" signature
  let n ← counted ls "insts"
  let mut is : Array Inst := #[]
  for _ in [0:n] do
    let l ← nextLine ls
    match onLine l inst with
    | .ok i => is := is.push i
    | .error e => throw e
  let extra ← keyed ls "extra" (do
    let k ← num
    let mut xs : Array (Option Nat) := #[]
    for _ in [0:k] do xs := xs.push (← ref)
    pure xs)
  let nb ← counted ls "blocks"
  let mut bs : Array Block := #[]
  for _ in [0:nb] do bs := bs.push (← block ls)
  keyed ls "end" (pure ())
  pure { name, span, loops, sig, insts := is, extra, blocks := bs }

def moduleReader : Reader Module := do
  let first ← nextLine ls
  if first.words.size != 1 || first.words[0]? != some "core-ir-v1" then failAt first.number "not a core-ir-v1 text"
  let nt ← counted ls "types"
  let mut cs : Array Compound := #[]
  for _ in [0:nt] do
    let l ← nextLine ls
    if l.words[0]? != some "t" || l.words.size < 2 then failAt l.number "expected a type line"
    match onLine l compound 1 with
    | .ok c => cs := cs.push c
    | .error e => throw e
  let nf ← counted ls "functions"
  let mut fs : Array Function := #[]
  for _ in [0:nf] do fs := fs.push (← function ls)
  let rest ← get
  for l in ls.extract rest ls.size do
    if l.words.size != 0 then failAt l.number "text after the last function"
  pure { compounds := cs, functions := fs }

end

/-- The module a `core-ir-v1` text describes. -/
def parseModule (text : String) : Except Problem Module :=
  let ls := splitLines text
  match (moduleReader ls).run 0 with
  | .ok (m, _) => .ok m
  | .error e => .error e

end VerifyIr
