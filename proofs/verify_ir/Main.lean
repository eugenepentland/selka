import VerifyIr

/-!
# `lake exe irverify DIR_OR_FILE`

Reads `core-ir-v1` texts and prints the verdicts in the format of `selka verify-ir`:

    FILE types accept | FILE types reject RULE
    FILE NAME accept | FILE NAME reject RULE bB %I      (b- and %- when the failure names none)
    FILE error line N: REASON

then a `summary` line. `--strict` adds the candidate rules (`Strict`) the Zig verifier does not have. Exit 0 when everything is accepted, 1 when something is rejected, 2 for a usage error or a
text that does not parse.
-/

open VerifyIr

/-- The `.core-ir` files under a directory, sorted by path. -/
def collect (root : System.FilePath) : IO (Array System.FilePath) := do
  let all ← root.walkDir
  let files := all.filter fun p => p.toString.endsWith ".core-ir"
  return files.qsort fun a b => a.toString < b.toString

structure Totals where
  justified : Nat := 0
  shapeM : Nat := 0
  byField : Nat := 0
  byPhi : Nat := 0
  files : Nat := 0
  functions : Nat := 0
  accept : Nat := 0
  reject : Nat := 0
  errors : Nat := 0

def failureText (f : Failure) : String :=
  s!"{f.rule.label} " ++ (match f.block with | some b => s!"b{b} " | none => "b- ") ++
    (match f.inst with | some i => s!"%{i}" | none => "%-")

def checkFile (strict : Bool) (path : String) (text : String) (t : Totals) : Array String × Totals := Id.run do
  let mut t := { t with files := t.files + 1 }
  match parseModule text with
  | .error p => return (#[s!"{path} error line {p.line}: {p.reason}"], { t with errors := t.errors + 1 })
  | .ok m =>
    let mut out : Array String := #[]
    match m.checkTypes with
    | .ok _ => out := out.push s!"{path} types accept"
    | .error f =>
      -- the function rules read the table, so a refused table gets no function lines
      return (out.push s!"{path} types reject {f.rule.label}", { t with reject := t.reject + 1 })
    let fr := m.freeTable
    for g in m.functions do
      t := { t with functions := t.functions + 1 }
      if g.sig.linkage == .internal then
        let c := Fn.mk m g
        match c.structure_ with
        | .ok gr =>
          let (j, r, p, mm) := c.payloadCounts gr.reachable
          t := { t with justified := t.justified + j + r + p, byField := t.byField + r, byPhi := t.byPhi + p,
                        shapeM := t.shapeM + mm }
        | .error _ => pure ()
      let strictFailure : Option String :=
        if !strict then none else
        match m.strictHeader g with
        | some s => some s!"{s.label} b- %-"
        | none =>
        if g.sig.linkage != .internal then none else
        match (Fn.mk m g).strictBody with
        | .ok _ => none
        | .error (s, r) => some (s!"{s.label} b- " ++ (match r with | some i => s!"%{i}" | none => "%-"))
      match verdict m fr g, strictFailure with
      | .ok _, some why =>
        t := { t with reject := t.reject + 1 }
        out := out.push s!"{path} {g.name} reject {why}"
      | .ok _, none =>
        t := { t with accept := t.accept + 1 }
        out := out.push s!"{path} {g.name} accept"
      | .error f, _ =>
        t := { t with reject := t.reject + 1 }
        out := out.push s!"{path} {g.name} reject {failureText f}"
    return (out, t)

/-- `irverify --facts DIR`: for each program with both texts, whether the fact certificate's skeleton of every function is
the translation of its IR (`translatesB`); one line per mismatched function, then a summary. -/
def factsCheck (target : String) : IO UInt32 := do
  let files ← collect target
  let stdout ← IO.getStdout
  let mut programs := 0
  let mut functions := 0
  let mut bad := 0
  let mut missing := 0
  for file in files do
    let certPath := (file.parent.getD ".") / "program.fact-certificate"
    if !(← certPath.pathExists) then
      missing := missing + 1
      continue
    let irText ← IO.FS.readFile file
    let certText ← IO.FS.readFile certPath
    match parseModule irText, Facts.parseModule certText with
    | .ok mI, .ok mF =>
      programs := programs + 1
      if mF.functions.size != mI.functions.size then
        bad := bad + 1
        stdout.putStrLn s!"{file} function-count {mI.functions.size} {mF.functions.size}"
        continue
      for (gI, k) in mI.functions.toList.zipIdx do
        functions := functions + 1
        match mF.functions[k]? with
        | some fF =>
          if skelOf fF != (Fn.mk mI gI).translate then
            bad := bad + 1
            stdout.putStrLn s!"{file} {gI.name} translate-mismatch"
        | none => pure ()
    | _, _ =>
      bad := bad + 1
      stdout.putStrLn s!"{file} parse-error"
  stdout.putStrLn s!"facts programs={programs} functions={functions} mismatches={bad} without-certificate={missing}"
  return if bad != 0 then 1 else 0

def main (args : List String) : IO UInt32 := do
  if let ["--facts", target] := args then return ← factsCheck target
  let strict := args.contains "--strict"
  match args.filter (· != "--strict") with
  | [target] =>
    let path : System.FilePath := target
    let single := !(← path.isDir)
    let files ← if single then pure #[path] else collect path
    let stdout ← IO.getStdout
    let mut t : Totals := {}
    for file in files do
      let text ← IO.FS.readFile file
      let (lines, t') := checkFile strict file.toString text t
      t := t'
      for l in lines do stdout.putStrLn l
    stdout.putStrLn s!"summary files={t.files} functions={t.functions} accept={t.accept} reject={t.reject} errors={t.errors}"
    stdout.putStrLn s!"summary union-tags justified={t.justified} shape-m={t.shapeM} by-field={t.byField} by-phi={t.byPhi}"
    return if t.errors != 0 then 2 else if t.reject != 0 then 1 else 0
  | _ =>
    IO.eprintln "usage: irverify DIR_OR_FILE"
    return 2
