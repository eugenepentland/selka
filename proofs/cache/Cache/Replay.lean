import Lean.Data.Json
import Cache.Blake3

/-!
# A replay record, checked against the disk

`src/core/build_replay.zig` keeps, for each identical build, a record of every input the build read (the handle of
`src/core/inputs.zig`): files by digest, probes for existence, directory listings by digest, environment variables
by value. A replay serves the recorded program iff `unchanged` finds every input as it was.

This file parses such a record and decides, input by input, with two rules:

* `truth`: the specification. A file is unchanged iff its bytes hash to the recorded digest (absent iff the digest is
  null). Nothing else is trusted.
* `zig`: the Zig rule (`unit_cache.checkDependency`): stat first; an absent file is unchanged iff the recorded digest is
  null; a recorded digest of null with the file present is changed; a recorded stat tuple equal to the live one is
  unchanged *without reading the file* (decision E2); otherwise the digest decides.

They agree except where the stat fast path says "unchanged" and the bytes differ: that input is reported as
`STALE`, a counterexample to E2 on the real file system.
-/

namespace Cache.Replay

open Lean

/-- A stat tuple: size, inode, modification and change time in nanoseconds. -/
structure Stamp where
  size : Nat
  inode : Nat
  mtime : Int
  ctime : Int
  deriving BEq, Repr

inductive Filter | all | standardModules
  deriving BEq, Repr

/-- One recorded input, as `inputs.Wire` stores it. -/
inductive Input where
  | file (path : String) (digest : Option String) (stamp : Option Stamp)
  | exists_ (path : String) (present : Bool)
  | listing (path : String) (filter : Filter) (digest : Option String)
  | variable (name : String) (value : Option String)

/-- A parsed replay record. -/
structure Record where
  key : String
  inputs : Array Input
  program : String
  programDigest : String
  programStamp : Stamp

def stampOf (j : Json) : Except String Stamp := do
  let size ← j.getObjValAs? Nat "size"
  let inode ← j.getObjValAs? Nat "inode"
  let mtime ← j.getObjValAs? Int "mtime"
  let ctime ← j.getObjValAs? Int "ctime"
  pure { size, inode, mtime, ctime }

def optStr (j : Json) (k : String) : Option String :=
  match j.getObjVal? k with
  | .ok .null => none
  | .ok v => v.getStr?.toOption
  | .error _ => none

def inputOf (j : Json) : Except String Input := do
  let kind ← j.getObjValAs? String "kind"
  let name ← j.getObjValAs? String "name"
  match kind with
  | "file" =>
    let stamp ← match j.getObjVal? "stamp" with
      | .ok .null => pure none
      | .ok v => some <$> stampOf v
      | .error _ => pure none
    pure (.file name (optStr j "digest") stamp)
  | "exists" => pure (.exists_ name (← j.getObjValAs? Bool "present"))
  | "listing" =>
    let f ← j.getObjValAs? String "filter"
    let filter ← match f with
      | "all" => pure Filter.all
      | "standard_modules" => pure Filter.standardModules
      | other => throw s!"filter {other}"
    pure (.listing name filter (optStr j "digest"))
  | "variable" => pure (.variable name (optStr j "value"))
  | other => throw s!"input kind {other}"

/-- Parse the text of a file under `replay-v1/`: the envelope, then the payload it carries. -/
def parseRecord (text : String) : Except String Record := do
  let env ← Json.parse text
  let payload ← env.getObjValAs? String "payload"
  let p ← Json.parse payload
  let key ← p.getObjValAs? String "key"
  let inputs ← (← p.getObjValAs? (Array Json) "inputs").mapM inputOf
  let program ← p.getObjValAs? String "program"
  let programDigest ← p.getObjValAs? String "digest"
  let programStamp ← stampOf (← p.getObjVal? "stamp")
  pure { key, inputs, program, programDigest, programStamp }

/-! ## Observing the disk -/

/-- `field` of `unit_cache.zig`: an eight-byte little-endian length, then the bytes. -/
def field (out : ByteArray) (b : ByteArray) : ByteArray := Id.run do
  let mut out := out
  let n := b.size
  for k in [0:8] do
    out := out.push ((n >>> (8 * k)) &&& 0xFF).toUInt8
  return out ++ b

/-- The digest of a listing: the kept names in byte order, each length-delimited, after a domain tag. -/
def namesDigest (names : Array String) : String :=
  let sorted := names.qsort (fun a b => a.toUTF8.data.toList < b.toUTF8.data.toList)
  let bytes := sorted.foldl (fun acc n => field acc n.toUTF8) (field ByteArray.empty "core-inputs-listing-v1".toUTF8)
  Blake3.hex (Blake3.hash bytes)

/-- The names a filter keeps in a directory, or `none` when it cannot be opened. `std` lists the embedded standard
modules (`standard_library.paths`). -/
def listNames (std : Array String) (dir : String) (f : Filter) : IO (Option (Array String)) := do
  try
    let entries ← System.FilePath.readDir dir
    let names := entries.map (·.fileName)
    let kept := match f with
      | .all => names
      | .standardModules => names.filter fun n => n.endsWith ".selka" && std.contains n
    pure (some kept)
  catch _ => pure none

/-- The BLAKE3 digest (hex) of a file, `none` when it is absent or unreadable. -/
def fileDigest (path : String) : IO (Option String) := do
  try
    let bytes ← IO.FS.readBinFile path
    pure (some (Blake3.hex (Blake3.hash bytes)))
  catch _ => pure none

/-- Days since 1970-01-01 of a civil date (the proleptic Gregorian calendar). -/
def daysFromCivil (y m d : Int) : Int :=
  let y := if m ≤ 2 then y - 1 else y
  let era := (if y ≥ 0 then y else y - 399) / 400
  let yoe := y - era * 400
  let mp := (m + 9) % 12
  let doy := (153 * mp + 2) / 5 + d - 1
  let doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

/-- Nanoseconds since the epoch of a `stat -c %y` time: `2026-10-26 19:55:07.276719688 +0000`. (The `%.9Y` form goes
through a floating point number and loses the last digits.) -/
def parseStatTime (t : String) : Option Int := do
  let parts := t.splitOn " "
  guard (parts.length == 3)
  let date := parts[0]!.splitOn "-"
  let clock := parts[1]!.splitOn ":"
  guard (date.length == 3 && clock.length == 3)
  let secFrac := clock[2]!.splitOn "."
  guard (secFrac.length == 2)
  let y ← date[0]!.toInt?
  let mo ← date[1]!.toInt?
  let d ← date[2]!.toInt?
  let h ← clock[0]!.toInt?
  let mi ← clock[1]!.toInt?
  let sec ← secFrac[0]!.toInt?
  let frac ← secFrac[1]!.toInt?
  let zone := parts[2]!
  guard (zone.length == 5)
  let sign : Int := if zone.front == '-' then -1 else 1
  let zh ← (zone.drop 1 |>.take 2).toInt?
  let zm ← (zone.drop 3).toInt?
  let local_ := daysFromCivil y mo d * 86400 + h * 3600 + mi * 60 + sec
  pure ((local_ - sign * (zh * 3600 + zm * 60)) * 1000000000 + frac)

/-- Stat tuples of many paths with `stat(1)`; absent files are left out. -/
def statMany (paths : Array String) : IO (Std.HashMap String Stamp) := do
  let mut result : Std.HashMap String Stamp := {}
  let mut i := 0
  while i < paths.size do
    let chunk := paths.extract i (i + 400)
    i := i + 400
    let out ← IO.Process.output { cmd := "stat", args := #["-c", "%n\x01%s\x01%i\x01%y\x01%z"] ++ chunk }
    for line in out.stdout.splitOn "\n" do
      match line.splitOn "\x01" with
      | [n, s, ino, m, c] =>
        match parseStatTime m, parseStatTime c, s.toNat?, ino.toNat? with
        | some mt, some ct, some sz, some inode => result := result.insert n { size := sz, inode, mtime := mt, ctime := ct }
        | _, _, _, _ => pure ()
      | _ => pure ()
  return result

/-- The verdicts on one input. -/
structure Verdict where
  /-- The specification: the content is as recorded. -/
  truth : Bool
  /-- The Zig rule, with the stat fast path. -/
  zig : Bool
  /-- The Zig rule answered from the stat tuple alone. -/
  fast : Bool
  what : String

/-- Check one recorded input against the live disk and environment. -/
def check (std : Array String) (stats : Std.HashMap String Stamp) (i : Input) : IO Verdict := do
  match i with
  | .file path digest stamp =>
    let live := stats.get? path
    let current ← fileDigest path
    let truth :=
      match digest, current with
      | none, none => true
      | some d, some c => d == c
      | _, _ => false
    let (zig, fast) :=
      match live with
      | none => (digest.isNone, false)
      | some l =>
        match digest with
        | none => (false, false)
        | some d =>
          if stamp == some l then (true, true)
          else (current == some d, false)
    pure { truth, zig, fast, what := s!"file {path}" }
  | .exists_ path present =>
    let now ← System.FilePath.pathExists path
    pure { truth := now == present, zig := now == present, fast := false, what := s!"exists {path}" }
  | .listing path filter digest =>
    let names ← listNames std path filter
    let now := names.map namesDigest
    let same := now == digest
    pure { truth := same, zig := same, fast := false, what := s!"listing {path}" }
  | .variable name value =>
    let now ← IO.getEnv name
    pure { truth := now == value, zig := now == value, fast := false, what := s!"variable {name}" }

/-- Whether the recorded program file is intact: the recorded stat tuple, else the recorded digest. -/
def programIntact (stats : Std.HashMap String Stamp) (r : Record) : IO (Bool × Bool) := do
  let current ← fileDigest r.program
  let truth := current == some r.programDigest
  let zig :=
    match stats.get? r.program with
    | none => false
    | some l => l == r.programStamp || truth
  pure (truth, zig)

/-- Read a record file and check every input. Prints one line per input that differs and a verdict line. Returns
whether the specification says unchanged. -/
def run (std : Array String) (path : String) : IO (Bool × Bool × Nat) := do
  let text ← IO.FS.readFile path
  match parseRecord text with
  | .error e => throw (IO.userError s!"{path}: {e}")
  | .ok r =>
    let files := r.inputs.filterMap fun
      | .file p _ _ => some p
      | _ => none
    let stats ← statMany (files.push r.program)
    let mut truth := true
    let mut zig := true
    let mut stale := 0
    for i in r.inputs do
      let v ← check std stats i
      if !v.truth || !v.zig then
        IO.println s!"input {v.what} truth={v.truth} zig={v.zig}"
      if v.fast && !v.truth then
        stale := stale + 1
        IO.println s!"STALE {v.what}: the stat tuple is unchanged and the bytes are not"
      truth := truth && v.truth
      zig := zig && v.zig
    let (pt, pz) ← programIntact stats r
    IO.println s!"verdict inputs={r.inputs.size} truth={truth} zig={zig} program_truth={pt} program_zig={pz} stale={stale}"
    pure (truth, zig, stale)

end Cache.Replay
