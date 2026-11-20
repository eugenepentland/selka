import Certcheck

/-- `lake exe certcheck DIR_OR_FILE`: see `Certcheck.lean`. -/
def main (args : List String) : IO UInt32 := do
  if args.head? == some "--link" then
    match args.tail with
    | [path] =>
      let out ← IO.getStdout
      let counts ← Own.runLink path (fun l => do out.putStrLn l; out.flush)
      IO.println (Own.linkSummaryLine counts)
      return if counts.errors > 0 then 2 else if counts.reject > 0 then 1 else 0
    | _ =>
      IO.eprintln "usage: certcheck --link DIR_OR_FILE"
      return 2
  let explain := args.contains "--explain"
  let dump := match args.dropWhile (· != "--dump") with
    | _ :: name :: _ => some name
    | _ => none
  let rest := match args.dropWhile (· != "--dump") with
    | _ :: _ :: tail => (args.takeWhile (· != "--dump")) ++ tail
    | _ => args
  match rest.filter (· != "--explain") with
  | [path] =>
    let out ← IO.getStdout
    let counts ← Own.runPath path (fun l => do out.putStrLn l; out.flush) explain dump
    IO.println (Own.summaryLine counts)
    IO.println (Own.corollaryLine counts)
    IO.println (Own.callsLine counts)
    if counts.skipped > 0 then
      IO.eprintln s!"certcheck: skipped {counts.skipped} file(s) that are not ownership certificates"
    if counts.errors > 0 then return 2
    else if counts.reject > 0 then return 1
    else return 0
  | _ =>
    IO.eprintln "usage: certcheck [--explain] [--dump FUNCTION] DIR_OR_FILE"
    return 2
