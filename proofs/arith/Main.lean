import Arith.Templates

/-! `lake exe arith-templates`: the rendered templates and the tools that keep the committed files
equal to them.

* no argument: print `templates.txt`;
* `--check FILE`: exit 1 unless FILE is exactly that text;
* `--md FILE`: exit 1 unless every `<!-- case ID -->` block of FILE (a fenced `text` block right
  after the marker) holds the lines Lean renders for case ID;
* `--update-md FILE`: rewrite those blocks in place.
-/

open Arith in
/-- The lines of the case with id `id`, without the `case`/`end` lines. -/
def caseLines (id : String) : Option (List String) :=
  (allCases.find? (·.id == id)).map (·.lines)

/-- Rewrite every marked block of `content`; returns the new text and the ids that were stale or
unknown. A block is the marker line, a line starting with three backticks, the body, and a line of
three backticks. -/
def rewriteBlocks (content : String) : String × List String := Id.run do
  let lines := content.splitOn "\n"
  let mut out : Array String := #[]
  let mut bad : Array String := #[]
  let mut i := 0
  let arr := lines.toArray
  while i < arr.size do
    let line := arr[i]!
    if line.startsWith "<!-- case " && line.endsWith " -->" then
      let id := ((line.drop "<!-- case ".length).dropEnd " -->".length).toString
      out := out.push line
      -- the opening fence
      i := i + 1
      out := out.push arr[i]!
      -- the old body, up to the closing fence
      let mut j := i + 1
      let mut old : Array String := #[]
      while j < arr.size && arr[j]! != "```" do
        old := old.push arr[j]!
        j := j + 1
      match caseLines id with
      | some body =>
        if old.toList != body then bad := bad.push id
        out := out ++ body.toArray
      | none =>
        bad := bad.push s!"{id} (no such case)"
        out := out ++ old
      out := out.push "```"
      i := j + 1
    else
      out := out.push line
      i := i + 1
  return (String.intercalate "\n" out.toList, bad.toList)

def main (args : List String) : IO UInt32 := do
  match args with
  | [] =>
    IO.print Arith.templatesText
    pure 0
  | ["--check", path] =>
    let have_ ← IO.FS.readFile path
    if have_ == Arith.templatesText then
      pure 0
    else
      IO.eprintln s!"{path} is not what Arith.Formulas renders; run `lake exe arith-templates > {path}`"
      pure 1
  | ["--md", path] =>
    let (_, bad) := rewriteBlocks (← IO.FS.readFile path)
    if bad.isEmpty then
      pure 0
    else
      IO.eprintln s!"{path}: these blocks differ from what Arith.Formulas renders: {bad}; run `lake exe arith-templates --update-md {path}`"
      pure 1
  | ["--update-md", path] =>
    let (text, bad) := rewriteBlocks (← IO.FS.readFile path)
    if bad.any (·.endsWith "(no such case)") then
      IO.eprintln s!"{path}: unknown case ids in {bad}"
      pure 1
    else
      IO.FS.writeFile path text
      pure 0
  | _ =>
    IO.eprintln "usage: arith-templates [--check FILE | --md FILE | --update-md FILE]"
    pure 2
