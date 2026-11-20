import Arith.Formulas
import Arith.Print
import Arith.FloatToInt

/-!
# The templates

Every sequence the emitter produces for an operation, a type and a check mode, rendered from the
formulas of `Formulas.lean` by `Isa.print`. `lake exe arith-templates` prints them; the committed
file `templates.txt` must equal that output (the gate checks it), and the Zig test
`src/core/arith_lowering_test.zig` compares `emit_llvm.zig`'s output with it.

Case ids are `OP.TYPE.MODE`, with `OP` one of `div rem floor_div floor_rem shift_left shift_right
saturating_add convert float_to_int`; `convert` has `SRC.DST` in place of `TYPE`. Modes:

* `exact`: `check = exact`, a variable operand (division also has `const` and `const-1` for the
  constant divisors `7` and `-1`, which skip tests that cannot fire);
* `none`: no check, no fact (only `convert`);
* `proven`: the facts removed the check;
* `proven-verify`: a `proven` check emitted under `--verify-facts`, trapping with kind `fact`;
* `narrow`, `narrow-const`, `proven-narrow`: the `u32` operand forms (division) and the `i32`
  result form (`float_to_int` to `i64`) that need the facts' ranges.
-/

namespace Arith

/-- One rendered case. -/
structure Case where
  id : String
  lines : List String

/-- The eight integer types of the language: (signed, width). -/
def types : List (Bool × Nat) :=
  [(true, 8), (true, 16), (true, 32), (true, 64), (false, 8), (false, 16), (false, 32), (false, 64)]

/-- The language's name of a type. -/
def typeName (s : Bool) (n : Nat) : String := (if s then "i" else "u") ++ toString n

/-- The division operations and their Core names. -/
def divKinds : List (DivKind × String) :=
  [(.div, "div"), (.rem, "rem"), (.floorDiv, "floor_div"), (.floorRem, "floor_rem")]

private def mk (id : String) (retTy : String) (body : P String) : Case :=
  { id := id, lines := render retTy body }

/-- The division cases of one operation and type. -/
def divCases (k : DivKind) (name : String) (s : Bool) (n : Nat) : List Case :=
  let ty := typeName s n
  let t := tyName n
  let id (mode : String) := s!"{name}.{ty}.{mode}"
  let general :=
    if s then
      [ mk (id "exact") t (divSigned Isa.print n k true true "a" "b"),
        mk (id "const") t (divSigned Isa.print n k false false "a" "7"),
        mk (id "const-1") t (divSigned Isa.print n k false true "a" "-1") ]
    else
      [ mk (id "exact") t (divU Isa.print n k.isRem true "a" "b"),
        mk (id "const") t (divU Isa.print n k.isRem false "a" "7") ]
  let proven :=
    [ mk (id "proven") t (divProven Isa.print n k.isRem "a" "b"),
      mk (id "proven-verify") t (divProvenVerified Isa.print n s k.isRem "a" "b") ]
  let narrow :=
    if n = 64 then
      (if s then [] else
        [ mk (id "narrow") t (divUNarrow Isa.print k.isRem true "a" "b"),
          mk (id "narrow-const") t (divUNarrow Isa.print k.isRem false "a" "7") ]) ++
      [ mk (id "proven-narrow") t (divUNarrow Isa.print k.isRem false "a" "b") ]
    else []
  general ++ proven ++ narrow

/-- The shift cases of one direction and type. -/
def shiftCases (left : Bool) (s : Bool) (n : Nat) : List Case :=
  let name := if left then "shift_left" else "shift_right"
  let id (mode : String) := s!"{name}.{typeName s n}.{mode}"
  let t := tyName n
  [ mk (id "exact") t (shift Isa.print n left s true .invalidShift "a" "b"),
    mk (id "proven") t (shift Isa.print n left s false .invalidShift "a" "b"),
    mk (id "proven-verify") t (shift Isa.print n left s true .fact "a" "b") ]

/-- The `convert` cases from one type to another (they differ in width or signedness). -/
def convertCases (sf : Bool) (wf : Nat) (st : Bool) (wt : Nat) : List Case :=
  let id (mode : String) := s!"convert.{typeName sf wf}.{typeName st wt}.{mode}"
  let t := tyName wt
  [ mk (id "exact") t (convert Isa.print sf st wf wt true .cast "a"),
    mk (id "none") t (convert Isa.print sf st wf wt false .cast "a"),
    mk (id "proven-verify") t (convert Isa.print sf st wf wt true .fact "a") ]

/-- The `float_to_int` cases of one target type. -/
def floatCases (s : Bool) (m : Nat) : List Case :=
  let id (mode : String) := s!"float_to_int.{typeName s m}.{mode}"
  let t := tyName m
  let (above, hi, inclusive) := f2iConsts s m
  [ mk (id "exact") t (floatToInt Isa.print .floatConversion s inclusive m above hi "a"),
    mk (id "proven") t (floatToIntProven Isa.print s m "a"),
    mk (id "proven-verify") t (floatToInt Isa.print .fact s inclusive m above hi "a") ] ++
  (if s && m = 64 then [mk (id "proven-narrow") t (floatToInt64Narrow Isa.print "a")] else [])

/-- Every case, in a fixed order. -/
def allCases : List Case :=
  (types.flatMap fun (s, n) =>
    divKinds.flatMap fun (k, name) => divCases k name s n) ++
  (types.flatMap fun (s, n) =>
    shiftCases true s n ++ shiftCases false s n) ++
  (types.map fun (s, n) =>
    mk s!"saturating_add.{typeName s n}" (tyName n) (saturatingAdd Isa.print n s "a" "b")) ++
  (types.flatMap fun (sf, wf) =>
    types.flatMap fun (st, wt) =>
      if sf == st && wf == wt then [] else convertCases sf wf st wt) ++
  (types.flatMap fun (s, m) => floatCases s m)

/-- A case as text. -/
def Case.text (c : Case) : String :=
  "case " ++ c.id ++ "\n" ++ String.intercalate "\n" c.lines ++ "\nend\n"

/-- The whole `templates.txt`. -/
def templatesText : String :=
  "# Generated by `lake exe arith-templates` from proofs/arith/Arith/Formulas.lean; do not edit.\n" ++
  String.intercalate "" (allCases.map Case.text)

end Arith
