import Facts

/-!
# `lake exe factcheck DIR_OR_FILE`

Reads `fact-certificate-v1` files and prints one verdict per function, in the format of
`selka validate-fact-certificates` (docs/design/fact-certificates.md §10):

    FILE NAME accept
    FILE NAME reject F2 b3 %17        (the check, the block or `b-`, the value or `-`)
    FILE error line N: REASON         (a malformed file)

then a `summary` line. Exit 0 when every function is accepted, 1 when one is rejected, 2 for a usage
error or a malformed file.
-/

open Facts

/-- The `.fact-certificate` files under a directory, sorted by path. -/
def collect (root : System.FilePath) : IO (Array System.FilePath) := do
  let all ← root.walkDir
  let files := all.filter fun p => p.toString.endsWith ".fact-certificate"
  return files.qsort fun a b => a.toString < b.toString

/-- The verdict line text of one function. -/
def verdictLine (path : String) (name : String) : Verdict → String
  | .accepted _ => s!"{path} {escapeName name} accept"
  | .rejected f =>
    s!"{path} {escapeName name} reject {f.check.label} " ++
      (match f.block with | some b => s!"b{b} " | none => "b- ") ++
      (match f.value with | some v => s!"%{v}" | none => "-")

/-- Running totals. -/
structure Totals where
  files : Nat := 0
  functions : Nat := 0
  accept : Nat := 0
  reject : Nat := 0
  errors : Nat := 0
  stats : Stats := {}

/-- `factcheck --census TARGET`: how much of the corpus rests on each kind of acceptance. -/
def census (target : String) : IO UInt32 := do
  let path : System.FilePath := target
  let single ← do
    if ← path.isDir then pure false else pure true
  let files ← if single then pure #[path] else collect path
  let mut t : Census := {}
  let mut n := 0
  let mut chain := 0
  for file in files do
    let bytes ← IO.FS.readFile file
    if !bytes.startsWith "fact-certificate-v1" then continue
    match parseModule bytes with
    | .error _ => pure ()
    | .ok m =>
      for f in m.functions do
        match censusFunction m f with
        | some c => t := t.add c; n := n + 1
        | none => pure ()
      for f in m.functions do
        match prepare m f with
        | .ok c => if (c.firstFault).isNone then chain := chain + c.chainCount
        | .error _ => pure ()
  IO.println s!"census functions={n} phi_hull={t.phiHull} phi_counter={t.phiCounter} phi_reduction={t.phiReduction} phi_reduction_multi_loop={t.phiReductionNested} inst_derived={t.instDerived} inst_assumed={t.instAssumed} list_derived={t.listDerived} list_assumed={t.listAssumed} fill_caps={t.caps} empty_stated={t.emptyStated} edge_checked={t.edgeChecked} reductions_proved_by_chain={chain}"
  return 0

/-- `factcheck --reductions TARGET`: every reduction phi the checker accepts, with what its derivation needs. -/
def reductions (target : String) : IO UInt32 := do
  let path : System.FilePath := target
  let single ← do
    if ← path.isDir then pure false else pure true
  let files ← if single then pure #[path] else collect path
  let stdout ← IO.getStdout
  for file in files do
    let bytes ← IO.FS.readFile file
    if !bytes.startsWith "fact-certificate-v1" then continue
    match parseModule bytes with
    | .error _ => pure ()
    | .ok m =>
      for f in m.functions do
        match prepare m f with
        | .error _ => pure ()
        | .ok c =>
          if (c.firstFault).isNone then
            for line in c.reductionLines file.toString (escapeName f.header.name) do
              stdout.putStrLn line
  return 0

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--census", target] => census target
  | ["--reductions", target] => reductions target
  | [target] =>
    let path : System.FilePath := target
    let single ← do
      if ← path.isDir then pure false else pure true
    let files ← if single then pure #[path] else collect path
    let mut t : Totals := {}
    let stdout ← IO.getStdout
    for file in files do
      let bytes ← IO.FS.readFile file
      if !single && !bytes.startsWith "fact-certificate-v1" then continue
      t := { t with files := t.files + 1 }
      match parseModule bytes with
      | .error p =>
        t := { t with errors := t.errors + 1 }
        stdout.putStrLn s!"{file} error line {p.line}: {p.reason}"
      | .ok m =>
        let verdicts := checkModule m
        for (f, v) in m.functions.toList.zip verdicts do
          t := { t with functions := t.functions + 1 }
          stdout.putStrLn (verdictLine file.toString f.header.name v)
          match v with
          | .accepted s =>
            t := { t with accept := t.accept + 1,
                          stats := { t.stats with derived := t.stats.derived + s.derived,
                                                  assumed := t.stats.assumed + s.assumed,
                                                  proven := t.stats.proven + s.proven,
                                                  unchecked := (t.stats.unchecked.zip s.unchecked).map fun (a, b) => a + b } }
          | .rejected _ => t := { t with reject := t.reject + 1 }
    let unchecked := t.stats.unchecked.foldl (· + ·) 0
    stdout.putStrLn s!"summary files={t.files} functions={t.functions} accept={t.accept} reject={t.reject} errors={t.errors} derived={t.stats.derived} assumed={t.stats.assumed} proven={t.stats.proven} unchecked={unchecked}"
    return if t.errors != 0 then 2 else if t.reject != 0 then 1 else 0
  | _ =>
    IO.eprintln "usage: factcheck DIR_OR_FILE"
    return 2
