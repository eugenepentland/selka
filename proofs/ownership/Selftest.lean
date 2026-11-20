import Certcheck

/-- `lake exe selftest [DIR]`: run `certcheck` on the fixtures (default `fixtures`) and compare
with `DIR/expected.txt`.  Exit status 0 when identical, 1 when not. -/
def main (args : List String) : IO UInt32 := do
  let dir := args.headD "fixtures"
  let acc ← IO.mkRef ([] : List String)
  let counts ← Own.runPath dir fun l => acc.modify (· ++ [l])
  let lines ← acc.get
  let got := "\n".intercalate (lines ++ [Own.summaryLine counts]) ++ "\n"
  let expected ← IO.FS.readFile s!"{dir}/expected.txt"
  if got == expected then
    IO.println s!"selftest: {counts.functions} functions in {counts.files} files match {dir}/expected.txt"
    return 0
  else
    IO.eprintln s!"selftest: output differs from {dir}/expected.txt:\n{got}"
    return 1
