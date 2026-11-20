import Facts.Run
import Facts.Parse

/-!
# Tests of the checker

`#guard` runs at build time: `lake build` fails if the checker's verdict on a fixture changes. The fixtures are the
files under `fixtures/` (`fixtures/check.sh` runs the same comparison through the `factcheck` executable).
-/

namespace Facts

/-- The text of the verdict on one function, as `factcheck` prints it after the name. -/
def verdictText : Verdict → String
  | .accepted _ => "accept"
  | .rejected f =>
    "reject " ++ f.check.label ++ " " ++
      (match f.block with | some b => s!"b{b}" | none => "b-") ++ " " ++
      (match f.value with | some v => s!"%{v}" | none => "-")

/-- The verdict lines of a certificate text. -/
def verdictsOf (text : String) : List String :=
  match parseModule text with
  | .error p => [s!"error line {p.line}"]
  | .ok m => (m.functions.toList.zip (checkModule m)).map fun (f, v) => s!"{escapeName f.header.name} {verdictText v}"

#guard verdictsOf (include_str "../fixtures/add_narrow_f2.fact-certificate") == ["f reject F2 b0 %2"]
#guard verdictsOf (include_str "../fixtures/add_narrowsite_f7.fact-certificate") == ["f reject F7 b0 %2"]
#guard verdictsOf (include_str "../fixtures/add_nosite_f7.fact-certificate") == ["f reject F7 b0 %2"]
#guard verdictsOf (include_str "../fixtures/add_proven_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/add_wide_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/add_widesite_f7.fact-certificate") == ["f reject F7 b0 %2"]
#guard verdictsOf (include_str "../fixtures/dead_live_f5.fact-certificate") == ["f reject F5 b2 -"]
#guard verdictsOf (include_str "../fixtures/dead_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/edge_refines_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/edge_toonarrow_f7.fact-certificate") == ["f reject F7 b1 %5"]
#guard verdictsOf (include_str "../fixtures/param_inside.fact-certificate") == ["g accept", "f accept"]
#guard verdictsOf (include_str "../fixtures/param_outside_f6.fact-certificate") == ["g accept", "f reject F6 b0 %1"]

-- design change 15: an empty interval says the value is never produced
#guard verdictsOf (include_str "../fixtures/empty_never_produced_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/empty_alt_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/empty_false_f2.fact-certificate") == ["f reject F2 b0 %2"]
-- design change 16: a subtraction proven by the checks on every edge into its phi's block is counted, not validated
#guard verdictsOf (include_str "../fixtures/edge_checked_ok.fact-certificate") == ["f accept"]
#guard verdictsOf (include_str "../fixtures/edge_unchecked_f7.fact-certificate") == ["f reject F7 b1 %5"]

-- a text that is not a certificate is an error, not a verdict
#guard (verdictsOf "not a certificate").length == 1 && (verdictsOf "not a certificate").head! == "error line 1"

end Facts
