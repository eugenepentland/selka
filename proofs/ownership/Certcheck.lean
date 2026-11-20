import Parse
import Link
import Std.Data.HashMap

/-!
# The `certcheck` driver

`lake exe certcheck DIR_OR_FILE` reads `ownership-certificate-v2` files and prints one line per
function:

```text
<file> <function> accept
<file> <function> reject <J1..J8> <block> <inst>
<file> <function> unchecked <reason>
<file> error <message>                         (a malformed file; not a verdict)
```

`<block>` is `bN`, or `b-` for the signature and the pseudo-block; `<inst>` is the instruction's
index in the block (the number of instructions for the terminator and the edges leaving it), or
`-`.  The last line is `summary files=… functions=… accept=… reject=… unchecked=… errors=…`.
In a directory, a file that does not start with `ownership-certificate-` is skipped (noted on
standard error).

The verdict is `Own.check`'s: the function Soundness.lean proves sound.  Exit status: 0 when
every function is accepted or unchecked, 1 when one is rejected, 2 for a usage error or a
malformed file.

**The census of the whole-program corollary** (C9.4, C9.2).  After the `summary` line come two lines, the census
`summary corollary: programs meeting every checked hypothesis of the corollary: N of M (…)` and
`summary calls: …`.  A *program* is the set of units of one build: a file whose name starts with `module-`,
`helper-` or `generic-` belongs to the program of its directory (the debug export writes the units of one program side by
side); any other file is a program of its own (the release export and the `dump-ir` wrappers write one `program.certificate`
or `NAME.certificate` each).  A program is counted when every function of it is accepted (`ProgWf.checked`: none rejected,
none `unchecked`, no malformed file) **and** the program-level link passes (`ProgWf.link`: every callee table entry of kind
`program` names a function of the program and describes its header, `Link.lean`).  Nothing else is assumed about the
program: the call-site agreement is derived from the two (`callWf_of_site`).  What remains are the numbered assumptions of
`AXIOMS.md` (the contracts of the runtime functions, A5, and the types of function values, A17), which the census does
not count against a program.  The parenthesis says how many covered programs the corollary used to exclude: a program
with a call to a program function that returns nothing (`CallWf.dst`, a hypothesis that call does not meet, before C9.2),
and one with a call whose value is `emptied` (`CallWf.noEmptied`, before C9.4).

`certcheck --link PATH` is the program-level link alone, in the format of the Zig `selka link-certificates`: a program is a
directory that holds certificate files (PATH itself, given a file), one line `DIR CALLER link-reject ENTRY TAG` per `program`
entry that does not match the function it names (the first of `callee-missing`, `callee-arity`, `callee-param`,
`callee-result`, `callee-from`), then `summary programs=P functions=F entries=E reject=R errors=X`; exit 0, 1 or 2.
-/

namespace Own

/-- The verdict line for one function. -/
def verdictLine (file name : String) (v : Verdict) (explain : Bool := false) : String :=
  match v with
  | .accept => s!"{file} {name} accept"
  | .reject fl =>
    let blk := match fl.blk with
      | some b => s!"b{b}"
      | none => "b-"
    let idx := match fl.idx with
      | some k => s!"{k}"
      | none => "-"
    s!"{file} {name} reject {fl.j.label} {blk} {idx}" ++ (if explain then s!" ({fl.why})" else "")

/-- The proposed entry state of every block, for `certcheck --dump NAME`. -/
def dumpStates (e : Entry) : List String :=
  let cc := mkCC e.fn e.cert
  let inn := solve cc
  (List.range e.fn.blocks.length).filterMap fun b =>
    match inn b with
    | some σ => some s!"  b{b}: L={σ.L} P={σ.P} G={σ.G.length} F={σ.F.length} D={σ.D.length}"
    | none => none

/-- Counts for the summary line. -/
structure Counts where
  files : Nat := 0
  functions : Nat := 0
  accept : Nat := 0
  reject : Nat := 0
  unchecked : Nat := 0
  errors : Nat := 0
  skipped : Nat := 0
  /-- the programs of the census (set by `runPath`) -/
  programs : Nat := 0
  /-- the programs all of whose functions are accepted and whose callee tables link -/
  covered : Nat := 0
  /-- the covered programs with no call to a program function that returns nothing: the corollary covered them with a
  `CallWf.dst` hypothesis (before C9.2) -/
  coveredNoVoid : Nat := 0
  /-- the covered programs with neither such a call nor a call whose value is `emptied`: what the corollary covered
  before C9.4 -/
  coveredNoVoidNoEmptied : Nat := 0
  /-- the call lines, those to a function of the program, through a function value, and to a runtime function, an
  extern function or a marker -/
  callLines : Nat := 0
  callProgram : Nat := 0
  callIndirect : Nat := 0
  callRuntime : Nat := 0
  /-- the `program` entries the link examined and the ones it rejected -/
  linkEntries : Nat := 0
  linkRejects : Nat := 0

/-- What the census needs of a file: every function is accepted, some call has an `emptied` value, some call to a program
function has no value, the call lines by kind, and the headers and callee tables the link needs. -/
structure FileCensus where
  allAccepted : Bool := true
  emptiedCall : Bool := false
  voidProgramCall : Bool := false
  callLines : Nat := 0
  callProgram : Nat := 0
  callIndirect : Nat := 0
  callRuntime : Nat := 0
  links : List LinkFn := []

/-- A function has a call whose value is an `emptied` record (the write-back record of a `mut` call). -/
def Entry.hasEmptiedCall (e : Entry) : Bool :=
  e.fn.blocks.any fun blk => blk.insts.any fun i =>
    i.cls == .call && (match i.dst with
      | some d => e.cert.state d == .emptied
      | none => false)

/-- The call lines of a function: all, to a program function, indirect, other; and whether one to a program function has
no value. -/
def Entry.callStats (e : Entry) : Nat × Nat × Nat × Nat × Bool :=
  e.fn.blocks.foldl
    (fun acc blk => blk.insts.foldl
      (fun (a : Nat × Nat × Nat × Nat × Bool) i =>
        if i.cls == .call then
          match e.fn.entryOf i with
          | some en =>
            let (t, p, ind, o, v) := a
            match en.kind with
            | .program => (t + 1, p + 1, ind, o, v || i.dst.isNone)
            | .indirect => (t + 1, p, ind + 1, o, v)
            | _ => (t + 1, p, ind, o + 1, v)
          | none => let (t, p, ind, o, v) := a; (t + 1, p, ind, o + 1, v)
        else a)
      acc)
    (0, 0, 0, 0, false)

/-- The program a certificate file belongs to (see the header). -/
def programKey (f : System.FilePath) : String :=
  let name := f.fileName.getD ""
  if name.startsWith "module-" || name.startsWith "helper-" || name.startsWith "generic-" then (f.parent.map (·.toString)).getD "" else f.toString

/-- Check one file's text. -/
def checkText (file text : String) (c : Counts) (explain : Bool := false)
    (dump : Option String := none) : List String × Counts × FileCensus :=
  match parseFile text with
  | .error msg =>
    ([s!"{file} error {msg}"], { c with files := c.files + 1, errors := c.errors + 1 },
      { allAccepted := false })
  | .ok es =>
    es.foldl
      (fun (acc : List String × Counts × FileCensus) e =>
        let (ls, c, k) := acc
        let (ct, cp, ci, co, cv) := e.callStats
        let k := { k with emptiedCall := k.emptiedCall || e.hasEmptiedCall, voidProgramCall := k.voidProgramCall || cv,
                          callLines := k.callLines + ct, callProgram := k.callProgram + cp,
                          callIndirect := k.callIndirect + ci, callRuntime := k.callRuntime + co,
                          links := k.links ++ [LinkFn.of (e.fn, e.cert)] }
        match e.unchecked with
        | some reason =>
          (ls ++ [s!"{file} {e.fn.name} unchecked {reason}"],
            { c with functions := c.functions + 1, unchecked := c.unchecked + 1 },
            { k with allAccepted := false })
        | none =>
          let extra := if dump == some e.fn.name then dumpStates e else []
          match verdict e.fn e.cert with
          | .accept =>
            (ls ++ [verdictLine file e.fn.name .accept] ++ extra,
              { c with functions := c.functions + 1, accept := c.accept + 1 }, k)
          | v =>
            (ls ++ [verdictLine file e.fn.name v explain] ++ extra,
              { c with functions := c.functions + 1, reject := c.reject + 1 },
              { k with allAccepted := false }))
      ([], { c with files := c.files + 1 }, {})

/-- The files under a path, sorted. -/
def collectFiles (path : System.FilePath) : IO (Array System.FilePath) := do
  if ← path.isDir then
    let all ← path.walkDir
    let mut files := #[]
    for p in all do
      if !(← p.isDir) then files := files.push p
    pure (files.qsort fun a b => a.toString < b.toString)
  else pure #[path]

/-- The sum of two counts. -/
def Counts.add (a b : Counts) : Counts :=
  { files := a.files + b.files, functions := a.functions + b.functions,
    accept := a.accept + b.accept, reject := a.reject + b.reject,
    unchecked := a.unchecked + b.unchecked, errors := a.errors + b.errors,
    skipped := a.skipped + b.skipped, programs := a.programs + b.programs,
    covered := a.covered + b.covered, coveredNoVoid := a.coveredNoVoid + b.coveredNoVoid,
    coveredNoVoidNoEmptied := a.coveredNoVoidNoEmptied + b.coveredNoVoidNoEmptied,
    callLines := a.callLines + b.callLines, callProgram := a.callProgram + b.callProgram,
    callIndirect := a.callIndirect + b.callIndirect, callRuntime := a.callRuntime + b.callRuntime,
    linkEntries := a.linkEntries + b.linkEntries, linkRejects := a.linkRejects + b.linkRejects }

/-- Check one file: its output lines and its counts (`skipped` when it is not a certificate
file in a directory run). -/
def checkFile (single : Bool) (f : System.FilePath) (explain : Bool) (dump : Option String) :
    IO (List String × Counts × Option FileCensus) := do
  let text ← IO.FS.readFile f
  if !single && !text.startsWith "ownership-certificate-" then
    pure ([], { skipped := 1 }, none)
  else
    let (ls, c, k) := checkText f.toString text {} explain dump
    pure (ls, c, some k)

/-- Check every certificate file under a path, handing each output line to `emit` in file order
as soon as it is known.  The files are checked in parallel on the runtime's thread pool, the
biggest first (`LEAN_NUM_THREADS` sets the pool size). -/
def runPath (path : String) (emit : String → IO Unit) (explain : Bool := false)
    (dump : Option String := none) : IO Counts := do
  let p : System.FilePath := path
  let single := !(← p.isDir)
  let files ← collectFiles p
  let mut sized : Array (Nat × Nat) := #[]
  for h : i in [0:files.size] do
    let size := (← files[i].metadata).byteSize.toNat
    sized := sized.push (size, i)
  let schedule := sized.qsort fun a b => a.1 > b.1
  let mut tasks : Array (Option (Task (Except IO.Error (List String × Counts × Option FileCensus)))) :=
    Array.replicate files.size none
  for (_, i) in schedule do
    let t ← IO.asTask (checkFile single files[i]! explain dump)
    tasks := tasks.set! i (some t)
  let mut counts : Counts := {}
  let mut programs : Std.HashMap String FileCensus := {}
  for h : i in [0:tasks.size] do
    match tasks[i] with
    | some t =>
      match ← IO.wait t with
      | .ok (ls, c, k) =>
        for l in ls do emit l
        counts := counts.add c
        if let some k := k then
          let key := programKey files[i]!
          let old := programs.getD key {}
          programs := programs.insert key
            { allAccepted := old.allAccepted && k.allAccepted, emptiedCall := old.emptiedCall || k.emptiedCall,
              voidProgramCall := old.voidProgramCall || k.voidProgramCall,
              callLines := old.callLines + k.callLines, callProgram := old.callProgram + k.callProgram,
              callIndirect := old.callIndirect + k.callIndirect, callRuntime := old.callRuntime + k.callRuntime,
              links := old.links ++ k.links }
      | .error e => throw e
    | none => pure ()
  let mut covered := 0
  let mut noVoid := 0
  let mut noVoidNoEmptied := 0
  let mut lines := 0
  let mut prog := 0
  let mut ind := 0
  let mut other := 0
  let mut entries := 0
  let mut rejects := 0
  for (_, k) in programs.toList do
    let bad := (linkRejects k.links).length
    entries := entries + (k.links.foldl (fun n f => n + (f.callees.filter (·.kind == .program)).length) 0)
    rejects := rejects + bad
    lines := lines + k.callLines
    prog := prog + k.callProgram
    ind := ind + k.callIndirect
    other := other + k.callRuntime
    if k.allAccepted && bad == 0 then
      covered := covered + 1
      if !k.voidProgramCall then
        noVoid := noVoid + 1
        if !k.emptiedCall then noVoidNoEmptied := noVoidNoEmptied + 1
  pure { counts with programs := programs.size, covered := covered, coveredNoVoid := noVoid,
                     coveredNoVoidNoEmptied := noVoidNoEmptied, callLines := lines, callProgram := prog,
                     callIndirect := ind, callRuntime := other, linkEntries := entries, linkRejects := rejects }

/-- The summary line. -/
def summaryLine (c : Counts) : String :=
  s!"summary files={c.files} functions={c.functions} accept={c.accept} reject={c.reject} " ++
    s!"unchecked={c.unchecked} errors={c.errors}"

/-- The census line (see the header): the programs every function of which is accepted and whose callee tables link, and
how many of them the corollary used to exclude: those with a call to a program function that returns nothing (before C9.2),
and those with that or a call whose value is `emptied` (before C9.4). -/
def corollaryLine (c : Counts) : String :=
  s!"summary corollary: programs meeting every checked hypothesis of the corollary: {c.covered} of {c.programs} " ++
    s!"(kept out before C9.2 by a call to a program function that returns nothing: {c.covered - c.coveredNoVoid}; " ++
    s!"kept out before C9.4 by that or an emptied call: {c.covered - c.coveredNoVoidNoEmptied})"

/-- The call census: the call lines, those the callee tables name as program functions (and the entries the link checked
and rejected), through a function value (A17), and to a runtime function, an extern function or a marker (A5). -/
def callsLine (c : Counts) : String :=
  s!"summary calls: {c.callLines} call lines: {c.callProgram} to a program function ({c.linkEntries} entries linked, " ++
    s!"{c.linkRejects} rejected), {c.callIndirect} through a function value, {c.callRuntime} to a runtime function, " ++
    s!"an extern function or a marker"


/-- What a `--link` run counted. -/
structure LinkCounts where
  programs : Nat := 0
  functions : Nat := 0
  entries : Nat := 0
  reject : Nat := 0
  errors : Nat := 0

/-- `certcheck --link PATH`: the program-level link (see the header).  A program is a directory that holds certificate
files directly, and PATH itself when it is a file. -/
def runLink (path : String) (emit : String → IO Unit) : IO LinkCounts := do
  let p : System.FilePath := path
  let single := !(← p.isDir)
  let files ← collectFiles p
  let mut groups : Std.HashMap String (Array System.FilePath) := {}
  for f in files do
    let key := if single then f.toString else (f.parent.map (·.toString)).getD "."
    groups := groups.insert key ((groups.getD key #[]).push f)
  let keys := (groups.toList.map (·.1)).toArray.qsort (· < ·)
  let mut counts : LinkCounts := {}
  for key in keys do
    let mut fns : List LinkFn := []
    let mut seen := false
    for f in groups.getD key #[] do
      let text ← IO.FS.readFile f
      if !text.startsWith "ownership-certificate-" then continue
      seen := true
      match parseFile text with
      | .error msg =>
        counts := { counts with errors := counts.errors + 1 }
        emit s!"{f} error {msg}"
      | .ok es => fns := fns ++ es.map fun e => LinkFn.of (e.fn, e.cert)
    if !seen then continue
    let entryCount := fns.foldl (fun n f => n + (f.callees.filter (·.kind == .program)).length) 0
    counts := { counts with programs := counts.programs + 1 }
    counts := { counts with functions := counts.functions + fns.length }
    counts := { counts with entries := counts.entries + entryCount }
    let rej := linkRejects fns
    counts := { counts with reject := counts.reject + rej.length }
    for (caller, entry, tag) in rej do
      emit s!"{key} {caller} link-reject {entry} {tag}"
  pure counts

/-- The summary line of a `--link` run. -/
def linkSummaryLine (c : LinkCounts) : String :=
  s!"summary programs={c.programs} functions={c.functions} entries={c.entries} reject={c.reject} errors={c.errors}"

end Own
