import Checker

/-!
# The program-level link (C9.2, design entry 57)

A callee table entry of kind `program` names a function of the program.  The checker has checked the call sites against
the entry (J1 `call-entry`, `call-arity`, `call-scalar`, `call-result`, `call-from`); the link checks the entry against
the function it names: that function is among the functions of the program, and its header (the `param` lines, the
`result` and the `from` of its `function` line) is what the entry says.  Together they establish `CallWf` for every call to
a function of the program (`ProgramSite.lean`), so the whole-program corollary no longer assumes it.

A *program* is the set of functions of one build (all the units of a debug build, the single file of a release build).
The link needs only the headers and the callee tables, so `certcheck` reads them out of each file and keeps nothing else.
-/

namespace Own

/-- A program: functions with their certificates. -/
abbrev Program := List (Function × Certificate)

/-- What the link needs of a function: its header, and the state its certificate gives the value of each parameter. -/
structure Header where
  name : String
  params : List St
  states : List St
  result : St
  from_ : List Nat
  deriving DecidableEq, Repr

/-- The header of a function. -/
def Header.of (fc : Function × Certificate) : Header :=
  { name := fc.1.name, params := fc.1.params, states := fc.1.paramVals.map fc.2.state, result := fc.1.result,
    from_ := fc.1.from_ }

/-- A function as the link sees it: its header and its callee table. -/
structure LinkFn where
  hd : Header
  callees : List CalleeEntry
  deriving DecidableEq, Repr

def LinkFn.of (fc : Function × Certificate) : LinkFn := { hd := Header.of fc, callees := fc.1.callees }

/-- Why the entry does not describe the function whose header is `h` (the first thing that differs): the number of
parameters, a parameter (the state half of its word is the state of the `param` line, and the value of the parameter has
that state), the result, the borrow contract. -/
def entryTag (e : CalleeEntry) (h : Header) : Option String :=
  if e.params.length != h.params.length || h.states.length != h.params.length then some "callee-arity"
  else if !((e.params.zip (h.params.zip h.states)).all fun (t, k, s) => t.state == k && s == k) then
    some "callee-param"
  else if e.result.state != h.result then some "callee-result"
  else if e.from_ != h.from_ then some "callee-from"
  else none

/-- The index of the function a name denotes (the first of that name). -/
def indexOfName (fs : List LinkFn) (name : String) : Option Nat := fs.findIdx? fun f => f.hd.name == name

/-- The entries of a program that do not match the function they name: caller, entry, tag.  Only entries of kind
`program` are linked: a runtime function, an extern function and a marker are judged by A5, and an indirect entry names no
function (the certificate has no type to look at). -/
def linkRejects (fs : List LinkFn) : List (String × Nat × String) :=
  fs.flatMap fun f => f.callees.filterMap fun e =>
    if e.kind == .program then
      match indexOfName fs e.name with
      | none => some (f.hd.name, e.id, "callee-missing")
      | some g =>
        match fs[g]? with
        | some callee => (entryTag e callee.hd).map fun t => (f.hd.name, e.id, t)
        | none => some (f.hd.name, e.id, "callee-missing")
    else none

/-- The program links: every `program` entry names a function of the program and matches its header. -/
def linkOk (fs : List LinkFn) : Bool := (linkRejects fs).isEmpty

/-- Function names are unique in a program (the linker would refuse two). -/
def namesUnique (fs : List LinkFn) : Bool := nodupB (fs.map (·.hd.name))

end Own
