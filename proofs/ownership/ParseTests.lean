import CheckerTests
import Render
import Certcheck

/-!
# Tests of the reader and of `certcheck` (C3.5)

* every example of `CheckerTests.lean` survives `render` then `parse`, with the same verdict;
* other version strings, malformed files and inconsistent files are refused;
* `certcheck` on `fixtures/` prints exactly `fixtures/expected.txt`.
-/

namespace Own
namespace ParseTests

open Own.Tests

def examples : List (String × (Function × Certificate)) :=
  [ ("okAllocDrop", okAllocDrop), ("okView", okView), ("okOwnedReturn", okOwnedReturn),
    ("okBorrowedReturn", okBorrowedReturn), ("okLoop", okLoop), ("okJoin", okJoin),
    ("okTrapJoin", okTrapJoin), ("okCursor", okCursor), ("okStack", okStack),
    ("okStackPhi", okStackPhi), ("okUndefPhi", okUndefPhi), ("okVoidCall", okVoidCall),
    ("okVoidUndef", okVoidUndef), ("okScalarResults", okScalarResults), ("okCallProjection", okCallProjection),
    ("badCallProjection", badCallProjection), ("okSelectionPhi", okSelectionPhi), ("badSelectionPhi", badSelectionPhi),
    ("okDeadPhi", okDeadPhi), ("okOwnerThroughPhi", okOwnerThroughPhi), ("badOwnerThroughPhi", badOwnerThroughPhi),
    ("okConstructLoan", okConstructLoan), ("badConstructLoan", badConstructLoan), ("okRecordTake", okRecordTake),
    ("okTwoSlots", okTwoSlots), ("badTakeTwice", badTakeTwice), ("badStoreNotPending", badStoreNotPending),
    ("badPendingAtRet", badPendingAtRet), ("badDropPending", badDropPending), ("okListSetReleasedNone", okListSetReleasedNone),
    ("badReleasedNoneNotPending", badReleasedNoneNotPending), ("okListSetReleasedOld", okListSetReleasedOld), ("badReleasedOldPending", badReleasedOldPending),
    ("okListPop", okListPop), ("okListPopTail", okListPopTail), ("badListPop", badListPop),
    ("okDictRemove", okDictRemove), ("badDictRemoveValue", badDictRemoveValue), ("badPhiPending", badPhiPending),
    ("okEmptied", okEmptied), ("badEmptiedOwnerDropped", badEmptiedOwnerDropped), ("badEmptiedConsumed", badEmptiedConsumed),
    ("badEmptiedTakenTwice", badEmptiedTakenTwice), ("badEmptiedNeverTaken", badEmptiedNeverTaken), ("okGuardedTake", okGuardedTake),
    ("badGuardedConstant", badGuardedConstant), ("badGuardedPredicate", badGuardedPredicate), ("okGuardedValue", okGuardedValue),
    ("okPrunedEdge", okPrunedEdge), ("okSlotView", okSlotView), ("badSlotViewAfterTake", badSlotViewAfterTake),
    ("okSlotViewOtherSlot", okSlotViewOtherSlot), ("okLoanHolder", okLoanHolder), ("badLoanHolderOwner", badLoanHolderOwner),
    ("badLoanHolderTake", badLoanHolderTake), ("okLoanHolderOtherSlot", okLoanHolderOtherSlot), ("badLoanHolderPhi", badLoanHolderPhi),
    ("okNamedUnit", okNamedUnit), ("badReadNamedUnit", badReadNamedUnit), ("okDictRemoveTaken", okDictRemoveTaken),
    ("badDictRemoveTakenNotPending", badDictRemoveTakenNotPending), ("badDictRemoveReleasesTaken", badDictRemoveReleasesTaken), ("badJ1", badJ1),
    ("badJ1Parent", badJ1Parent), ("badJ2Leak", badJ2Leak), ("badJ2Double", badJ2Double),
    ("badJ2Join", badJ2Join), ("badUndefEdgeLive", badUndefEdgeLive), ("badJ3", badJ3),
    ("badJ4", badJ4), ("badStale", badStale), ("badJ5", badJ5),
    ("badJ5Ret", badJ5Ret), ("badJ5From", badJ5From), ("badJ6", badJ6),
    ("badJ6Same", badJ6Same), ("badJ7", badJ7), ("badJ7Store", badJ7Store),
    ("badJ7Drop", badJ7Drop), ("badJ8", badJ8),
    ("okGroup", okGroup), ("okGroupBorrowed", okGroupBorrowed), ("okGroupSlot", okGroupSlot),
    ("okGroupTwoLends", okGroupTwoLends), ("okGroupBranch", okGroupBranch),
    ("okGroupBranchTrap", okGroupBranchTrap), ("okGroupPhi", okGroupPhi), ("okTrapGroup", okTrapGroup),
    ("okLendBeforeTrap", okLendBeforeTrap), ("badLenderDropped", badLenderDropped),
    ("badLenderPushed", badLenderPushed), ("badLenderSlotTaken", badLenderSlotTaken),
    ("badEmptiedLender", badEmptiedLender), ("badLenderAggregateDropped", badLenderAggregateDropped),
    ("badGroupNotEnded", badGroupNotEnded), ("badGroupBranchRet", badGroupBranchRet),
    ("badSubmitAfterEnd", badSubmitAfterEnd), ("badGroupDropped", badGroupDropped),
    ("badGroupJoinResult", badGroupJoinResult), ("badGroupStored", badGroupStored),
    ("badLendNotOwned", badLendNotOwned), ("badLendThreeReads", badLendThreeReads),
    ("badLendOrder", badLendOrder), ("badLendConsumes", badLendConsumes),
    ("badLentOnFresh", badLentOnFresh), ("badTrapGroup", badTrapGroup),
    ("badHolderReadAfterEmptied", badHolderReadAfterEmptied),
    ("badLoanLostThroughUpdate", badLoanLostThroughUpdate), ("okLoanThroughUpdate", okLoanThroughUpdate),
    ("badLoanLostThroughCall", badLoanLostThroughCall), ("badHolderWithItsRoot", badHolderWithItsRoot),
    ("badTakeHoldsView", badTakeHoldsView), ("okTakeOfAbsentPayload", okTakeOfAbsentPayload),
    ("okTakeHoldsViewDroppedFirst", okTakeHoldsViewDroppedFirst), ("okTrapParam", okTrapParam),
    ("badTrapHolder", badTrapHolder), ("okEmptiedFromView", okEmptiedFromView),
    ("badEmptiedFromViewParent", badEmptiedFromViewParent),
    ("badTrapJoinUnlisted", badTrapJoinUnlisted), ("okTrapTakeAbandoned", okTrapTakeAbandoned),
    ("badTrapGroupAbandoned", badTrapGroupAbandoned), ("okTrapHolderAbandoned", okTrapHolderAbandoned),
    ("okTrapRootDroppedAfter", okTrapRootDroppedAfter), ("badAbandonedViewRead", badAbandonedViewRead),
    ("badTrapMeetTakeLaterListed", badTrapMeetTakeLaterListed), ("badAbandonNotPred", badAbandonNotPred),
    ("badAbandonRepeated", badAbandonRepeated), ("badAbandonUnsorted", badAbandonUnsorted),
    ("badAbandonOutsideRegion", badAbandonOutsideRegion), ("badAbandonNotLive", badAbandonNotLive),
    ("badAbandonScalar", badAbandonScalar), ("badAbandonPhiOperand", badAbandonPhiOperand),
    ("okAbandonBranchChain", okAbandonBranchChain), ("okProgramCall", okProgramCall),
    ("badCallEntry", badCallEntry), ("badCallKind", badCallKind), ("badCallArity", badCallArity),
    ("badCallScalar", badCallScalar), ("okCallTakeScalar", okCallTakeScalar),
    ("badCallResultOwned", badCallResultOwned), ("badCallVoidOwner", badCallVoidOwner),
    ("okCallVoid", okCallVoid), ("okCallFrom", okCallFrom), ("badCallFrom", badCallFrom),
    ("badCalleeTableIds", badCalleeTableIds), ("badCalleeTableName", badCalleeTableName),
    ("badCalleeTableFrom", badCalleeTableFrom), ("okIndirectCall", okIndirectCall) ]

/-- Render then parse gives the same function and the same verdict. -/
def roundTrips (ex : Function × Certificate) : Bool :=
  let e : Entry := { fn := ex.1, cert := ex.2, unchecked := none }
  match parseFile (renderFile [e]) with
  | .ok [e'] => decide (e'.fn = ex.1) && decide (verdict e'.fn e'.cert = verdict ex.1 ex.2)
  | _ => false

#guard examples.all fun p => roundTrips p.2

/-- Whether reading the text is refused. -/
def refused (text : String) : Bool :=
  match parseFile text with
  | .error _ => true
  | .ok _ => false

-- the version string is checked exactly; the format before the `views` extra (v1) is refused by name
#guard !refused "ownership-certificate-v2\n"
#guard refused "ownership-certificate-v1\n"
#guard refused "ownership-certificate-v3\n"
#guard refused "ownership-certificate-v0\n"
#guard refused "ownership-certificate-v20\n"
#guard refused "ownership-certificate-v2 \n"
#guard refused "Ownership-certificate-v2\n"
#guard (match parseFile "ownership-certificate-v1\n" with
  | .error e => e.endsWith "unsupported format version 'ownership-certificate-v1' (this reader accepts ownership-certificate-v2)"
  | .ok _ => false)
#guard refused "ownership-certificate\n"
#guard refused ""
#guard refused "function f result scalar from - unchecked -\nend\n"

def hdr : String := "ownership-certificate-v2\nclass drop Drop\nclass list_new Fresh\n"

-- malformed content is an error, never a verdict
#guard refused (hdr ++ "function f result scalar from - unchecked -\n")                -- no end
#guard refused (hdr ++ "end\n")                                                          -- end outside a function
#guard refused (hdr ++ "function f result weird from - unchecked -\nend\n")              -- bad state
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b1 preds -\nterm ret -\nblock b0 preds -\nterm ret -\nend\n")  -- block numbers must increase
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\nend\n")             -- block without term
#guard refused (hdr ++ "function f result scalar from - unchecked -\nparam 1 %0 owned\nend\n")            -- parameter numbering
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\ninst %0 mystery Fresh reads - consumes - state owned parents -\nterm ret -\nend\n")  -- op not in the table
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\ninst %0 list_new Fresh reads - consumes - state owned parents -\ninst %0 list_new Fresh reads - consumes - state owned parents -\nterm ret -\nend\n")  -- value defined twice
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\ninst %0 list_new Fresh reads %x consumes - state owned parents -\nterm ret -\nend\n")  -- bad value
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\nterm jump b1 b2\nend\n")  -- malformed term
#guard refused (hdr ++ "garbage line\n")

-- a small well-formed function, written out by hand
def hand : String :=
  hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\n" ++
    "inst %0 list_new Fresh reads - consumes - state owned parents -\n" ++
    "inst - drop Drop reads - consumes %0 state none parents -\nterm ret -\nend\n"

#guard (match parseFile hand with
  | .ok [e] => verdict e.fn e.cert == .accept
  | _ => false)

-- a class that differs from the table is read, and the function is rejected (J1)
#guard (match parseFile (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\ninst %0 list_new Drop reads - consumes - state owned parents -\nterm ret -\nend\n") with
  | .ok [e] => verdict e.fn e.cert == .reject { j := .j1, blk := some 0, idx := some 0, why := "classOk" }
  | _ => false)

-- the pseudo-block may be introduced by an explicit header
#guard (match parseFile (hdr ++ "function f result scalar from - unchecked -\nblock b- preds -\nblock b0 preds -\nterm ret -\nend\n") with
  | .ok [e] => verdict e.fn e.cert == .accept
  | _ => false)


-- the extras of the real export: an `emptied` aggregate with its `slots`, a take with its `slot`,
-- the `from` list of a call, a `Forward` class line, an escaped name (kept as the file spells it)
def handEmptied : String :=
  "ownership-certificate-v2\nclass call Call\nclass record_get Project\nclass list_new Fresh\n" ++
    "class drop Drop\nclass copy Forward\n" ++
    "function a\\x20b result scalar from - unchecked -\ncallee 0 rt runtime take scalar -\nblock b0 preds -\n" ++
    "inst %0 list_new Fresh reads - consumes - state owned parents -\n" ++
    "inst %1 call Call reads - consumes %0 state emptied parents - slots f1 from - callee 0\n" ++
    "inst %2 record_get Project reads %1 consumes - state owned parents - slot f1\n" ++
    "inst - drop Drop reads - consumes %2 state none parents -\nterm ret -\nend\n"

#guard (match parseFile handEmptied with
  | .ok [e] => e.fn.name == "a\\x20b" && verdict e.fn e.cert == .accept
  | _ => false)

-- a block header with `-` predecessors and a gap in the block numbers (the exporter drops
-- blocks without predecessors): the missing block is a placeholder that nothing reaches
#guard (match parseFile (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\nterm jump b2\nblock b2 preds b0\nterm ret -\nend\n") with
  | .ok [e] => e.fn.blocks.length == 3 && verdict e.fn e.cert == .accept
  | _ => false)

-- an edge to a block the file does not contain is refused
#guard refused (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\nterm jump b5\nend\n")

-- `released` and `slot` on a store are read back
#guard (match parseFile (hdr ++ "class list_set Update\nfunction f result scalar from - unchecked -\nblock b0 preds -\n" ++
    "inst %0 list_new Fresh reads - consumes - state owned parents -\n" ++
    "inst %1 list_set Update reads - consumes %0 state owned parents - slot e#0 released old\n" ++
    "inst - drop Drop reads - consumes %1 state none parents -\nterm ret -\nend\n") with
  | .ok [e] => e.fn.blocks.head?.map (fun b => b.insts.map (fun i => (i.slot, i.released))) ==
      some [(none, none), (some "e#0", some "old"), (none, none)]
  | _ => false)

-- the `lent %G` extra of a lend is read back; twice, or without a value, the line is refused
def handLend (extra : String) : String :=
  hdr ++ "class box_make Construct\nclass call Call\nclass list_new Fresh\nclass drop Drop\n" ++
    "function f result scalar from - unchecked -\ncallee 0 rt runtime - scalar -\ncallee 1 rt runtime take scalar -\nblock b0 preds -\n" ++
    "inst %0 call Call reads - consumes - state owned parents - from - callee 0\n" ++
    "inst %1 list_new Fresh reads - consumes - state owned parents -\n" ++
    s!"inst %2 box_make Construct reads %1,%0 consumes - state owned parents - {extra}\n" ++
    "inst - drop Drop reads - consumes %2 state none parents -\n" ++
    "inst - call Call reads - consumes %0 state none parents - from - callee 1\n" ++
    "inst - drop Drop reads - consumes %1 state none parents -\nterm ret -\nend\n"

#guard (match parseFile (handLend "lent %0") with
  | .ok [e] => e.fn.blocks.head?.map (fun b => b.insts.map (·.lent)) ==
      some [none, none, some 0, none, none, none] && verdict e.fn e.cert == .accept
  | _ => false)
#guard refused (handLend "lent %0 lent %0")
-- the `noloans` extra of a take is read back
#guard (match parseFile (hdr ++ "class record_take Take\nclass list_new Fresh\nclass drop Drop\nfunction f result scalar from - unchecked -\nblock b0 preds -\n" ++
    "inst %0 list_new Fresh reads - consumes - state owned parents -\n" ++
    "inst %1 record_take Take reads - consumes %0 state owned parents - noloans\n" ++
    "inst - drop Drop reads - consumes %1 state none parents -\nterm ret -\nend\n") with
  | .ok [e] => e.fn.blocks.head?.map (fun b => b.insts.map (·.noLoans)) == some [false, true, false]
  | _ => false)
#guard refused (handLend "lent")
#guard refused (handLend "lent group")

-- the callee table (C9.2): a table line and the `callee N` extra of a call line are read back
def handCallee : String :=
  "ownership-certificate-v2\nclass call Call\nclass list_new Fresh\nclass drop Drop\n" ++
    "function f result scalar from - unchecked -\n" ++
    "callee 0 g::h program take,read-scalar owned 1\n" ++
    "callee 1 - indirect take scalar -\n" ++
    "block b0 preds -\n" ++
    "inst %0 list_new Fresh reads - consumes - state owned parents -\n" ++
    "inst %1 call Call reads %0 consumes - state owned parents - from - callee 0\n" ++
    "inst - drop Drop reads - consumes %1 state none parents -\nterm ret -\nend\n"

#guard (match parseFile handCallee with
  | .ok [e] =>
    e.fn.callees == [ { id := 0, name := "g::h", kind := .program, params := [.take, .readScalar],
                        result := .owned, from_ := [1] },
                      { id := 1, name := "-", kind := .indirect, params := [.take], result := .scalar, from_ := [] } ] &&
    (e.fn.blocks.head?.map fun b => b.insts.map (·.entry)) == some [none, some 0, none]
  | _ => false)
-- an unknown word of a table line is a malformed file; so is a table line after a block
#guard refused (handCallee.replace "program" "progam")
#guard refused (handCallee.replace "take,read-scalar" "take,reed")
#guard refused (handCallee.replace "owned 1" "none 1")
#guard refused (handCallee.replace "callee 1 - indirect take scalar -\nblock b0 preds -" "block b0 preds -\ncallee 1 - indirect take scalar -")
-- a call line without `callee` is J1 `call-entry`; with the table of the file it is read
#guard (match parseFile (handCallee.replace " callee 0" "") with
  | .ok [e] => verdict e.fn e.cert == .reject { j := .j1, blk := some 0, idx := some 1, why := "call-entry" }
  | _ => false)
#guard (match parseFile handCallee with
  | .ok [e] => verdict e.fn e.cert != .accept
  | _ => false)

/-- `certcheck` on the fixtures prints exactly the expected file. -/
def fixturesMatch : IO Unit := do
  let acc ← IO.mkRef ([] : List String)
  let counts ← runPath "fixtures" fun l => acc.modify (· ++ [l])
  let lines ← acc.get
  let got := "\n".intercalate (lines ++ [summaryLine counts]) ++ "\n"
  let expected ← IO.FS.readFile "fixtures/expected.txt"
  if got != expected then
    throw (IO.userError s!"certcheck fixtures differs from fixtures/expected.txt:\n{got}")

#eval fixturesMatch

/-! ### The census of the whole-program corollary (C9.4) -/

-- a call whose value is an `emptied` record is seen; a function without one is not
#guard (match parseFile handEmptied with
  | .ok [e] => e.hasEmptiedCall
  | _ => false)
#guard (match parseFile (hdr ++ "function f result scalar from - unchecked -\nblock b0 preds -\nterm ret -\nend\n") with
  | .ok [e] => !e.hasEmptiedCall
  | _ => false)
-- the units of one debug build share a directory and are one program; any other file is a program
#guard programKey "out/tests/lang/x/module-ab.certificate" == "out/tests/lang/x"
#guard programKey "out/tests/lang/x/helper-cd.certificate" == "out/tests/lang/x"
#guard programKey "out/tests/lang/x/generic-ef.certificate" == "out/tests/lang/x"
#guard programKey "out/tests/lang/x/program.certificate" == "out/tests/lang/x/program.certificate"

/-- The census over `fixtures-census/`: `p1` (two units, both accepted), `p2` (two units, one leaks), `p3` (accepted, a call
with an `emptied` value), `p4` (accepted), `p5` (a call to a program function that returns nothing, and that function) and
`p6` (the same call, to a function the program does not have: the link rejects it).  Four of six programs meet the
hypotheses, three without a unit call to a program function, two without that or an emptied call.  Over `fixtures/`,
which holds one file per program, no file is wholly accepted and linked: the accepted one has examples of calls to a
function `g` that is not in the file. -/
def censusMatches : IO Unit := do
  let census ← runPath "fixtures-census" fun _ => pure ()
  if (census.programs, census.covered, census.coveredNoVoid, census.coveredNoVoidNoEmptied) != (6, 4, 3, 2) then
    throw (IO.userError s!"census of fixtures-census: {census.programs} {census.covered} {census.coveredNoVoid} {census.coveredNoVoidNoEmptied}")
  if (census.linkEntries, census.linkRejects) != (2, 1) then
    throw (IO.userError s!"link of fixtures-census: {census.linkEntries} {census.linkRejects}")
  let fixtures ← runPath "fixtures" fun _ => pure ()
  if (fixtures.programs, fixtures.covered, fixtures.coveredNoVoid, fixtures.coveredNoVoidNoEmptied) != (10, 0, 0, 0) then
    throw (IO.userError s!"census of fixtures: {fixtures.programs} {fixtures.covered} {fixtures.coveredNoVoid} {fixtures.coveredNoVoidNoEmptied}")

#eval censusMatches

end ParseTests
end Own
