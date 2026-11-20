import Cache
import Cache.Blake3
import Cache.Replay

/-!
# `lake exe cacheplan`

Runs the cache's decisions on recorded traces.

    cacheplan plan REQUEST [OUT]     the incremental test planner of `src/cache_plan_reference_v2.zig` on a recorded
                                      `SLKCP002` request; writes the reply payload to OUT and prints one summary line
    cacheplan diff REQUEST...        for each REQUEST, plan it and compare with the recorded reply beside it (REQUEST with
                                      `.req` replaced by `.rep`): the decision, batches, groups and reverse index exactly
    cacheplan changed OLD NEW        whether the nodes NEW does not list as changed all have a body digest and callee count
                                      that some node of OLD has (a necessary condition of `Cache.Admit.Complete`)
    cacheplan replay RECORD [--stdlib DIR]
                                      the replay rule of `src/core/build_replay.zig` on a record under `replay-v1/`, against
                                      the disk and environment as they are now
    cacheplan digest FILE            the BLAKE3 digest of a file, as a record stores it
    cacheplan listing DIR [FILTER]   the listing digest of a directory (FILTER: all, standard_modules)
    cacheplan selftest               the BLAKE3 test vectors

See README.md for the other commands and the differential drivers.
-/

open Cache.Plan

/-- The summary line of a plan, as the differential driver reads it. -/
def summary (q : Request) (o : Outcome) : String :=
  let dirty := o.dirty.foldl (fun n d => if d then n + 1 else n) 0
  let prior :=
    match q.prior with
    | none => "absent"
    | some (_, groups, reverse) =>
      if groups == o.groups && reverse == o.reverse then "matches" else "differs"
  let w := o.work
  s!"plan nodes={q.callees.size} tests={q.roots.size} changed={q.changed.size} dirty={dirty} reused={w.reusedTests} " ++
  s!"planned={w.plannedTests} certified={o.certified} prior={prior}"

def planCommand (path : String) (out : Option String) : IO UInt32 := do
  let bytes ← IO.FS.readBinFile path
  match parseRequest bytes with
  | .error e =>
    IO.eprintln s!"{path}: malformed request: {e}"
    return 2
  | .ok q =>
    let o := plan q
    if let some f := out then
      IO.FS.writeBinFile f (replyPayload o)
    IO.println (summary q o)
    return if o.certified then 0 else 1

/-- The names of the embedded standard library's modules: the `.selka` files of `src/stdlib`. -/
def stdlibNames (dir : String) : IO (Array String) := do
  try
    let entries ← System.FilePath.readDir dir
    pure ((entries.map (·.fileName)).filter (·.endsWith ".selka"))
  catch _ => pure #[]

def replayCommand (record : String) (stdlib : String) : IO UInt32 := do
  let std ← stdlibNames stdlib
  let (truth, zig, stale) ← Cache.Replay.run std record
  return if stale > 0 then 3 else if truth == zig then 0 else 1

/-- One request against its recorded reply. -/
def diffOne (path : String) : IO (Bool × Bool × Bool) := do
  let repPath := (String.ofList (path.toList.take (path.length - 4))) ++ ".rep"
  let req ← IO.FS.readBinFile path
  let rep ← IO.FS.readBinFile repPath
  if String.fromUTF8! (req.extract 0 8) == "SLKCP001" then
    -- the version-one protocol: closures of root sets
    match parseRequestV1 req, parseReplyV1 rep with
    | .ok q, .ok z =>
      let o := plan q
      if o.batches != z then
        IO.println s!"DIFF {path}: v1 batches"
      return (o.batches == z, true, true)
    | .error e, _ | _, .error e =>
      IO.println s!"DIFF {path}: v1: {e}"
      return (false, false, false)
  match parseRequest req, parseReply rep with
  | .error e, _ =>
    IO.println s!"DIFF {path}: request: {e}"
    return (false, false, false)
  | _, .error e =>
    IO.println s!"DIFF {path}: reply: {e}"
    return (false, false, false)
  | .ok q, .ok z =>
    let o := plan q
    let d := differences o z
    let priorOk := match q.prior with
      | none => true
      | some (_, groups, reverse) => groups == o.groups && reverse == o.reverse
    if !d.isEmpty then
      IO.println s!"DIFF {path}: {d}"
    return (d.isEmpty, o.certified, priorOk)

def diffCommand (paths : List String) : IO UInt32 := do
  let mut agree := 0
  let mut certified := 0
  let mut priors := 0
  for p in paths do
    let (a, c, pr) ← diffOne p
    if a then agree := agree + 1
    if c then certified := certified + 1
    if pr then priors := priors + 1
  IO.println s!"diff requests={paths.length} agree={agree} differ={paths.length - agree} certified={certified} prior_ok={priors}"
  return if agree == paths.length && certified == paths.length then 0 else 1

def changedCommand (oldPath newPath : String) : IO UInt32 := do
  match parseRequest (← IO.FS.readBinFile oldPath), parseRequest (← IO.FS.readBinFile newPath) with
  | .ok old, .ok new =>
    let bad := uncoveredUnchanged old new
    let listed := new.changed.size
    IO.println s!"changed old_nodes={old.callees.size} new_nodes={new.callees.size} listed={listed} uncovered={bad.size}"
    return if bad.isEmpty then 0 else 1
  | .error e, _ | _, .error e =>
    IO.eprintln s!"malformed request: {e}"
    return 2

def main (args : List String) : IO UInt32 := do
  match args with
  | ["changed", old, new] => changedCommand old new
  | "diff" :: paths@(_ :: _) => diffCommand paths
  | ["plan", request] => planCommand request none
  | ["plan", request, out] => planCommand request (some out)
  | ["replay", record] => replayCommand record "src/stdlib"
  | ["replay", record, "--stdlib", dir] => replayCommand record dir
  | ["digest", file] =>
    match ← Cache.Replay.fileDigest file with
    | some d => IO.println d; return 0
    | none => IO.eprintln s!"{file}: cannot read"; return 2
  | "listing" :: dir :: rest =>
    let filter := if rest == ["standard_modules"] then Cache.Replay.Filter.standardModules else Cache.Replay.Filter.all
    let std ← stdlibNames "src/stdlib"
    match ← Cache.Replay.listNames std dir filter with
    | some names => IO.println (Cache.Replay.namesDigest names); return 0
    | none => IO.eprintln s!"{dir}: cannot list"; return 2
  | ["selftest"] =>
    IO.println s!"blake3 vectors: {Cache.Blake3.selfTest}"
    return if Cache.Blake3.selfTest then 0 else 1
  | _ =>
    IO.eprintln "usage: cacheplan plan REQUEST [OUT] | replay RECORD [--stdlib DIR] | selftest"
    return 2
