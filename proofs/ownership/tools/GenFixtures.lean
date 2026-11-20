import CheckerTests
import Render

/-!
Generates `fixtures/*.cert` and `fixtures/expected.txt` from the examples of
`CheckerTests.lean`.  The expected verdicts are the ones that file asserts with `#guard`; they
are written here by hand, not computed by the checker.

    lake env lean --run tools/GenFixtures.lean
-/

open Own Own.Tests

/-- A fixture function: a name, the example, and the expected verdict text. -/
structure Fx where
  name : String
  ex : Function × Certificate
  expect : String

def fx (name : String) (ex : Function × Certificate) (expect : String) : Fx :=
  { name := name, ex := ex, expect := expect }

def toEntry (f : Fx) (unchecked : Option String := none) : Entry :=
  { fn := { f.ex.1 with name := f.name }, cert := f.ex.2, unchecked := unchecked }

def files : List (String × List Fx) :=
  [ ("accepted", [
      fx "ok_alloc_drop" okAllocDrop "accept",
      fx "ok_view" okView "accept",
      fx "ok_owned_return" okOwnedReturn "accept",
      fx "ok_borrowed_return" okBorrowedReturn "accept",
      fx "ok_loop" okLoop "accept",
      fx "ok_join" okJoin "accept",
      fx "ok_trap_join" okTrapJoin "accept",
      fx "ok_trap_meet" okTrapMeet "accept",
      fx "ok_trap_consume" okTrapConsume "accept",
      fx "ok_trap_chain" okTrapChain "accept",
      fx "ok_emptied_construct" okEmptiedConstruct "accept",
      fx "ok_repeated_test" okRepeatedTest "accept",
      fx "ok_cursor" okCursor "accept",
      fx "ok_stack" okStack "accept",
      fx "ok_stack_scalar" okStackScalar "accept",
      fx "ok_stack_phi" okStackPhi "accept",
      fx "ok_undef_phi" okUndefPhi "accept",
      fx "ok_void_call" okVoidCall "accept",
      fx "ok_void_undef" okVoidUndef "accept",
      fx "ok_scalar_results" okScalarResults "accept",
      fx "ok_call_projection" okCallProjection "accept",
      fx "ok_selection_phi" okSelectionPhi "accept",
      fx "ok_dead_phi" okDeadPhi "accept",
      fx "ok_owner_through_phi" okOwnerThroughPhi "accept",
      fx "ok_construct_loan" okConstructLoan "accept",
      fx "ok_construct_read_slot" okConstructReadSlot "accept",
      fx "ok_construct_read_listed" okConstructReadListed "accept",
      fx "ok_record_take" okRecordTake "accept",
      fx "ok_two_slots" okTwoSlots "accept",
      fx "ok_list_set_released_none" okListSetReleasedNone "accept",
      fx "ok_list_set_released_old" okListSetReleasedOld "accept",
      fx "ok_list_pop" okListPop "accept",
      fx "ok_list_pop_tail" okListPopTail "accept",
      fx "ok_dict_remove" okDictRemove "accept",
      fx "ok_emptied" okEmptied "accept",
      fx "ok_guarded_take" okGuardedTake "accept",
      fx "ok_guarded_value" okGuardedValue "accept",
      fx "ok_pruned_edge" okPrunedEdge "accept",
      fx "ok_slot_view" okSlotView "accept",
      fx "ok_slot_view_other_slot" okSlotViewOtherSlot "accept",
      fx "ok_loan_holder" okLoanHolder "accept",
      fx "ok_loan_holder_other_slot" okLoanHolderOtherSlot "accept",
      fx "ok_named_unit" okNamedUnit "accept",
      fx "ok_dict_remove_taken" okDictRemoveTaken "accept",
      fx "ok_group" okGroup "accept",
      fx "ok_group_borrowed" okGroupBorrowed "accept",
      fx "ok_group_slot" okGroupSlot "accept",
      fx "ok_group_two_lends" okGroupTwoLends "accept",
      fx "ok_group_branch" okGroupBranch "accept",
      fx "ok_group_branch_trap" okGroupBranchTrap "accept",
      fx "ok_group_phi" okGroupPhi "accept",
      fx "ok_trap_group" okTrapGroup "accept",
      fx "ok_lend_before_trap" okLendBeforeTrap "accept",
      fx "ok_trap_param" okTrapParam "accept",
      fx "ok_trap_take_abandoned" okTrapTakeAbandoned "accept",
      fx "ok_trap_holder_abandoned" okTrapHolderAbandoned "accept",
      fx "ok_trap_root_dropped_after" okTrapRootDroppedAfter "accept",
      fx "ok_abandon_branch_chain" okAbandonBranchChain "accept",
      fx "ok_program_call" okProgramCall "accept",
      fx "ok_call_take_scalar" okCallTakeScalar "accept",
      fx "ok_call_void" okCallVoid "accept",
      fx "ok_call_from" okCallFrom "accept",
      fx "ok_indirect_call" okIndirectCall "accept" ]),
    ("j1", [
      fx "bad_j1" badJ1 "reject J1 b0 0",
      fx "bad_j1_parent" badJ1Parent "reject J1 b0 1",
      fx "bad_views_not_read" badViewsNotRead "reject J1 b0 2",
      fx "bad_views_not_construct" badViewsNotConstruct "reject J1 b0 1",
      fx "bad_lend_not_owned" badLendNotOwned "reject J1 b0 1",
      fx "bad_lend_three_reads" badLendThreeReads "reject J1 b0 2",
      fx "bad_lend_order" badLendOrder "reject J1 b0 2",
      fx "bad_lend_consumes" badLendConsumes "reject J1 b0 2",
      fx "bad_lent_on_fresh" badLentOnFresh "reject J1 b0 1",
      fx "bad_abandon_not_pred" badAbandonNotPred "reject J1 b1 -",
      fx "bad_abandon_repeated" badAbandonRepeated "reject J1 b1 -",
      fx "bad_abandon_unsorted" badAbandonUnsorted "reject J1 b1 -",
      fx "bad_call_entry" badCallEntry "reject J1 b0 1",
      fx "bad_call_kind" badCallKind "reject J1 b0 1",
      fx "bad_call_arity" badCallArity "reject J1 b0 1",
      fx "bad_call_scalar" badCallScalar "reject J1 b0 1",
      fx "bad_call_result_owned" badCallResultOwned "reject J1 b0 0",
      fx "bad_call_void_owner" badCallVoidOwner "reject J1 b0 0",
      fx "bad_call_from" badCallFrom "reject J1 b0 1",
      fx "bad_callee_table_ids" badCalleeTableIds "reject J1 b- -",
      fx "bad_callee_table_name" badCalleeTableName "reject J1 b- -",
      fx "bad_callee_table_from" badCalleeTableFrom "reject J1 b- -" ]),
    ("j2", [
      fx "bad_j2_leak" badJ2Leak "reject J2 b0 1",
      fx "bad_j2_double" badJ2Double "reject J2 b0 2",
      fx "bad_j2_join" badJ2Join "reject J2 b1 1",
      fx "bad_undef_edge_live" badUndefEdgeLive "reject J2 b1 0",
      fx "bad_trap_twice" badTrapTwice "reject J2 b3 1",
      fx "bad_loop_head_forgets" badLoopHeadForgets "reject J2 b5 0",
      fx "bad_group_not_ended" badGroupNotEnded "reject J2 b0 5",
      fx "bad_group_dropped" badGroupDropped "reject J2 b0 5",
      fx "bad_group_join_result" badGroupJoinResult "reject J2 b0 5",
      fx "bad_group_stored" badGroupStored "reject J2 b0 5",
      fx "bad_trap_group" badTrapGroup "reject J2 b1 0",
      fx "bad_trap_holder" badTrapHolder "reject J2 b1 0",
      fx "bad_trap_take" badTrapTake "reject J2 b1 1",
      fx "bad_trap_join_unlisted" badTrapJoinUnlisted "reject J2 b1 1",
      fx "bad_trap_group_abandoned" badTrapGroupAbandoned "reject J2 b1 0",
      fx "bad_abandon_outside_region" badAbandonOutsideRegion "reject J2 b0 1",
      fx "bad_abandon_not_live" badAbandonNotLive "reject J2 b0 2",
      fx "bad_abandon_scalar" badAbandonScalar "reject J2 b0 0",
      fx "bad_abandon_phi_operand" badAbandonPhiOperand "reject J2 b0 1" ]),
    ("j3", [
      fx "bad_read_named_unit" badReadNamedUnit "reject J3 b0 1",
            fx "bad_j3" badJ3 "reject J3 b0 2",
      fx "bad_trap_meet" badTrapMeet "reject J3 b3 0",
      fx "bad_trap_chain" badTrapChain "reject J3 b3 0" ]),
    ("j4", [
      fx "bad_call_projection" badCallProjection "reject J4 b0 4",
      fx "bad_selection_phi" badSelectionPhi "reject J4 b3 1",
      fx "bad_owner_through_phi" badOwnerThroughPhi "reject J4 b1 1",
      fx "bad_construct_loan" badConstructLoan "reject J4 b0 4",
      fx "bad_emptied_owner_dropped" badEmptiedOwnerDropped "reject J4 b0 5",
      fx "bad_emptied_construct_view" badEmptiedConstructView "reject J4 b0 4",
      fx "bad_abandoned_view_read" badAbandonedViewRead "reject J4 b1 0",
      fx "bad_slot_view_after_take" badSlotViewAfterTake "reject J4 b0 3",
      fx "bad_loan_holder_owner" badLoanHolderOwner "reject J4 b0 3",
      fx "bad_loan_holder_take" badLoanHolderTake "reject J4 b0 3",
      fx "bad_loan_holder_phi" badLoanHolderPhi "reject J4 b1 0",
      fx "bad_holder_read_after_emptied" badHolderReadAfterEmptied "reject J4 b0 3",
      fx "bad_lender_dropped" badLenderDropped "reject J4 b0 5",
      fx "bad_lender_pushed" badLenderPushed "reject J4 b0 5",
      fx "bad_lender_slot_taken" badLenderSlotTaken "reject J4 b0 6",
      fx "bad_lender_aggregate_dropped" badLenderAggregateDropped "reject J4 b0 6",
      fx "bad_group_branch_ret" badGroupBranchRet "reject J4 b2 0",
      fx "bad_emptied_lender" badEmptiedLender "reject J4 b0 5",
      fx "bad_j4" badJ4 "reject J4 b0 3",
      fx "bad_stale" badStale "reject J4 b1 0" ]),
    ("j5", [
      fx "bad_j5" badJ5 "reject J5 b0 0",
      fx "bad_j5_ret" badJ5Ret "reject J5 b0 0",
      fx "bad_j5_from" badJ5From "reject J5 b0 1" ]),
    ("j6", [
      fx "bad_j6" badJ6 "reject J6 b0 2",
      fx "bad_j6_same" badJ6Same "reject J6 b0 1",
      fx "bad_construct_read_emptied" badConstructReadEmptied "reject J6 b0 2",
      fx "bad_construct_read_caller" badConstructReadCaller "reject J6 b0 0",
      fx "bad_construct_read_owned" badConstructReadOwned "reject J6 b0 2",
      fx "bad_construct_read_two_owners" badConstructReadTwoOwners "reject J6 b0 4",
      fx "bad_construct_read_listed_not_view" badConstructReadListedNotView "reject J6 b0 2" ]),
    ("j7", [
      fx "bad_j7" badJ7 "reject J7 b0 1",
      fx "bad_j7_store" badJ7Store "reject J7 b0 1",
      fx "bad_j7_drop" badJ7Drop "reject J7 b0 1",
      fx "bad_j7_element" badJ7Element "reject J7 b0 2" ]),
    ("j8", [
      fx "bad_pending_at_ret" badPendingAtRet "reject J8 b0 2",
      fx "bad_take_twice" badTakeTwice "reject J8 b0 2",
      fx "bad_store_not_pending" badStoreNotPending "reject J8 b0 3",
      fx "bad_drop_pending" badDropPending "reject J8 b0 2",
      fx "bad_released_none_not_pending" badReleasedNoneNotPending "reject J8 b0 2",
      fx "bad_released_old_pending" badReleasedOldPending "reject J8 b0 2",
      fx "bad_list_pop" badListPop "reject J8 b0 1",
      fx "bad_dict_remove_value" badDictRemoveValue "reject J8 b0 2",
      fx "bad_phi_pending" badPhiPending "reject J8 b0 2",
      fx "bad_emptied_consumed" badEmptiedConsumed "reject J8 b0 3",
      fx "bad_emptied_taken_twice" badEmptiedTakenTwice "reject J8 b0 3",
      fx "bad_emptied_never_taken" badEmptiedNeverTaken "reject J8 b- -",
      fx "bad_guards_differ" badGuardsDiffer "reject J8 b5 0",
      fx "bad_guarded_constant" badGuardedConstant "reject J8 b3 1",
      fx "bad_guarded_predicate" badGuardedPredicate "reject J8 b3 1",
      fx "bad_dict_remove_taken_not_pending" badDictRemoveTakenNotPending "reject J8 b0 1",
      fx "bad_dict_remove_releases_taken" badDictRemoveReleasesTaken "reject J8 b0 2",
      fx "bad_trap_meet_take_later_listed" badTrapMeetTakeLaterListed "reject J8 b3 0",
      fx "bad_j8" badJ8 "reject J8 b0 2" ]) ]

/-- The task-group examples whose operations are real IR operations, for the Zig validator
(`selka validate-certificates fixtures-zig`): the invented names of the Lean examples are replaced
(`group_open`, `submit`, `group_end` and `take` are calls, `record_new` is a `list_new`). `bad_lend_order`
and `bad_lent_on_fresh` are not among them: the Zig reader refuses a lend whose second read is not its group
and a `lent` extra on another operation (a refused file, not a verdict), where the Lean reader reads them
and rejects J1. -/
def realOp (op : String) : String :=
  if op == "group_open" || op == "submit" || op == "group_end" || op == "take" then "call"
  else if op == "record_new" then "list_new"
  else op

def realInst (i : Inst) : Inst := { i with op := realOp i.op }

def realFn (f : Function) : Function :=
  { name := f.name, params := f.params, result := f.result, from_ := f.from_,
    paramVals := f.paramVals, pre := f.pre.map realInst, callees := f.callees,
    blocks := f.blocks.map fun b => { b with insts := b.insts.map realInst } }

def zigFiles : List Fx :=
  [ fx "ok_group" okGroup "accept",
    fx "ok_group_borrowed" okGroupBorrowed "accept",
    fx "ok_group_slot" okGroupSlot "accept",
    fx "ok_group_two_lends" okGroupTwoLends "accept",
    fx "ok_group_branch" okGroupBranch "accept",
    fx "ok_group_branch_trap" okGroupBranchTrap "accept",
    fx "ok_group_phi" okGroupPhi "accept",
    fx "ok_trap_group" okTrapGroup "accept",
    fx "ok_lend_before_trap" okLendBeforeTrap "accept",
    fx "bad_lend_not_owned" badLendNotOwned "reject J1 b0 1",
    fx "bad_lend_three_reads" badLendThreeReads "reject J1 b0 2",
    fx "bad_lend_consumes" badLendConsumes "reject J1 b0 2",
    fx "bad_group_not_ended" badGroupNotEnded "reject J2 b0 5",
    fx "bad_group_dropped" badGroupDropped "reject J2 b0 5",
    fx "bad_group_join_result" badGroupJoinResult "reject J2 b0 5",
    fx "bad_group_stored" badGroupStored "reject J2 b0 5",
    fx "bad_trap_group" badTrapGroup "reject J2 b1 0",
    fx "bad_submit_after_end" badSubmitAfterEnd "reject J3 b0 6",
    fx "bad_lender_dropped" badLenderDropped "reject J4 b0 5",
    fx "bad_lender_pushed" badLenderPushed "reject J4 b0 5",
    fx "bad_lender_slot_taken" badLenderSlotTaken "reject J4 b0 6",
    fx "bad_lender_aggregate_dropped" badLenderAggregateDropped "reject J4 b0 6",
    fx "bad_group_branch_ret" badGroupBranchRet "reject J4 b2 0",
    fx "bad_emptied_lender" badEmptiedLender "reject J4 b0 5",
    fx "bad_holder_read_after_emptied" badHolderReadAfterEmptied "reject J4 b0 3" ]

/-- The trap-region cases of C3.8 that carry no `abandon` line (`fixtures-zig/trap-region.cert`): without a line the
edges into a trap block must agree like any other. -/
def trapFiles : List Fx :=
  [ fx "bad_trap_meet_take_later" badTrapMeetTakeLater "reject J2 b1 0",
    fx "bad_trap_meet_take_first" badTrapMeetTakeFirst "reject J2 b1 1",
    fx "bad_trap_meet_roots" badTrapMeetRoots "reject J4 b3 1",
    fx "bad_trap_meet_roots_swapped" badTrapMeetRootsSwapped "reject J4 b3 1",
    fx "bad_trap_holder" badTrapHolder "reject J2 b1 0",
    fx "bad_trap_closing" badTrapClosing "reject J8 b3 0",
    fx "bad_trap_branch_chain" badTrapBranchChain "reject J2 b1 1",
    fx "bad_trap_chain_phi" badTrapChainPhi "reject J2 b1 1" ]

/-- Loans carried through the consumer of a holder (C3.8): the cases for the Zig lane (`fixtures-zig/loans.cert`). -/
def loanFiles : List Fx :=
  [ fx "bad_loan_lost_through_update" badLoanLostThroughUpdate "reject J4 b0 4",
    fx "ok_loan_through_update" okLoanThroughUpdate "accept",
    fx "bad_loan_lost_through_call" badLoanLostThroughCall "reject J4 b0 4",
    fx "bad_holder_with_its_root" badHolderWithItsRoot "reject J4 b0 3" ]

/-- A take carries the loans of the aggregate it comes out of unless it is marked `noloans`
(`fixtures-zig/take.cert`). -/
def takeFiles : List Fx :=
  [ fx "bad_take_holds_view" badTakeHoldsView "reject J4 b0 4",
    fx "ok_take_none_arm" okTakeOfAbsentPayload "accept",
    fx "ok_take_holds_view_dropped_first" okTakeHoldsViewDroppedFirst "accept" ]

/-- The construct-read rule (J6, lane VAL) and its accepted neighbours (entries 19 and 28), for the Zig validator
(`fixtures-zig/construct-read.cert`). -/
def constructReadFiles : List Fx :=
  [ fx "ok_construct_loan" okConstructLoan "accept",
    fx "ok_emptied_construct" okEmptiedConstruct "accept",
    fx "ok_construct_read_slot" okConstructReadSlot "accept",
    fx "ok_construct_read_listed" okConstructReadListed "accept",
    fx "bad_construct_read_listed_not_view" badConstructReadListedNotView "reject J6 b0 2",
    fx "bad_views_not_read" badViewsNotRead "reject J1 b0 2",
    fx "bad_views_not_construct" badViewsNotConstruct "reject J1 b0 1",
    fx "bad_construct_read_emptied" badConstructReadEmptied "reject J6 b0 2",
    fx "bad_construct_read_caller" badConstructReadCaller "reject J6 b0 0",
    fx "bad_construct_read_owned" badConstructReadOwned "reject J6 b0 2",
    fx "bad_construct_read_two_owners" badConstructReadTwoOwners "reject J6 b0 4" ]

def main : IO Unit := do
  let mut expected : List String := []
  let mut nacc := 0
  let mut nrej := 0
  let mut nfun := 0
  let mut nfile := 0
  for (stem, fs) in files do
    let path := s!"fixtures/{stem}.cert"
    IO.FS.writeFile path (renderFile (fs.map (toEntry ·)))
    nfile := nfile + 1
    for f in fs do
      expected := expected ++ [s!"{path} {f.name} {f.expect}"]
      nfun := nfun + 1
      if f.expect == "accept" then nacc := nacc + 1 else nrej := nrej + 1
  -- the task-group examples with real operations, for the Zig validator (`fixtures-zig`)
  let zig := zigFiles.map fun f => { f with ex := (realFn f.ex.1, f.ex.2) }
  IO.FS.createDirAll "fixtures-zig"
  IO.FS.writeFile "fixtures-zig/taskgroup.cert" (renderFile (zig.map (toEntry ·)))
  let trap := trapFiles.map fun f => { f with ex := (realFn f.ex.1, f.ex.2) }
  IO.FS.writeFile "fixtures-zig/trap-region.cert" (renderFile (trap.map (toEntry ·)))
  let loans := loanFiles.map fun f => { f with ex := (realFn f.ex.1, f.ex.2) }
  IO.FS.writeFile "fixtures-zig/loans.cert" (renderFile (loans.map (toEntry ·)))
  let take := takeFiles.map fun f => { f with ex := (realFn f.ex.1, f.ex.2) }
  IO.FS.writeFile "fixtures-zig/take.cert" (renderFile (take.map (toEntry ·)))
  let reads := constructReadFiles.map fun f => { f with ex := (realFn f.ex.1, f.ex.2) }
  IO.FS.writeFile "fixtures-zig/construct-read.cert" (renderFile (reads.map (toEntry ·)))
  IO.FS.writeFile "fixtures-zig/expected.txt"
    ("\n".intercalate (zig.map (fun f => s!"fixtures-zig/taskgroup.cert {f.name} {f.expect}") ++
      trap.map (fun f => s!"fixtures-zig/trap-region.cert {f.name} {f.expect}") ++
      loans.map (fun f => s!"fixtures-zig/loans.cert {f.name} {f.expect}") ++
      take.map (fun f => s!"fixtures-zig/take.cert {f.name} {f.expect}") ++
      reads.map fun f => s!"fixtures-zig/construct-read.cert {f.name} {f.expect}") ++ "\n")
  -- an unchecked function is counted and never validated
  let u := fx "unchecked_task_group" okAllocDrop "unchecked task-group"
  IO.FS.writeFile "fixtures/unchecked.cert" (renderFile [toEntry u (some "task-group")])
  expected := expected ++ ["fixtures/unchecked.cert unchecked_task_group unchecked task-group"]
  nfile := nfile + 1
  nfun := nfun + 1
  expected := expected ++
    [s!"summary files={nfile} functions={nfun} accept={nacc} reject={nrej} unchecked=1 errors=0"]
  IO.FS.writeFile "fixtures/expected.txt" ("\n".intercalate expected ++ "\n")
