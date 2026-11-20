import Checker

/-!
# Executable examples for the checker (C3.3b)

Small hand-built functions on the revised model (design `docs/design/ownership-certificates.md`
as of C1): accepted ones for every shape the real corpus shows, and rejections for each check
J1-J8.  Each `#guard` fails the build when the verdict is not the stated one.

Notation: values `%0`, `%1`, ... are numbers; `list_new` is a `Fresh` instruction, `list_view_of`
a `View`, `print` an `Output`, `drop` a `Drop`.  A rejection is stated by judgment, block,
position and the tag of the failing sub-check (`certcheck --explain` prints the same tag).
-/

namespace Own
namespace Tests

/-- An instruction with the optional export extras. -/
def inst (cls : Class) (op : String) (dst : Option Nat) (reads consumes : List Nat)
    (slot : Option String := none) (released : Option String := none)
    (slots : List String := []) (imm : Option Nat := none) (taken : Option String := none)
    (lent : Option Nat := none) (noLoans : Bool := false) (fromVals : List Nat := [])
    (entry : Option Nat := none) (views : List Nat := []) : Inst :=
  { dst := dst, op := op, cls := cls, reads := reads, consumes := consumes,
    slot := slot, released := released, slots := slots, imm := imm, taken := taken, lent := lent,
    noLoans := noLoans, fromVals := fromVals, entry := entry, views := views }

def blk (preds : List Nat) (phis : List Phi) (insts : List Inst) (term : Term)
    (abandons : List (Nat × List Nat) := []) : Block :=
  { preds := preds, phis := phis, insts := insts, term := term, abandons := abandons }

/-- A certificate from `(value, state, parents)` rows; anything else has state `none`. -/
def cert (rows : List (Nat × St × List Root)) : Certificate :=
  { state := fun n => match rows.find? (·.1 == n) with
      | some r => r.2.1
      | none => .none,
    parents := fun n => match rows.find? (·.1 == n) with
      | some r => r.2.2
      | none => [] }

/-- A runtime entry for a call line: its arity only (A5 judges the rest of a runtime function, C9.2). -/
def runtimeEntry (n : Nat) (i : Inst) : CalleeEntry :=
  { id := n, name := i.op, kind := .runtime,
    params := i.consumes.map (fun _ => ParamTok.take) ++ i.reads.map (fun _ => ParamTok.read),
    result := .scalar, from_ := [] }

/-- Give every call line that names no entry a runtime entry of its own, in order. -/
def attachCallees (f : Function) : Function :=
  let r := f.blocks.foldl
    (fun (acc : List CalleeEntry × List Block) blk =>
      let (es, bs) := acc
      let (es', insts) := blk.insts.foldl
        (fun (a : List CalleeEntry × List Inst) i =>
          if i.cls == .call && i.entry.isNone then
            (a.1 ++ [runtimeEntry a.1.length i], a.2 ++ [{ i with entry := some a.1.length }])
          else (a.1, a.2 ++ [i]))
        (es, [])
      (es', bs ++ [{ blk with insts := insts }]))
    (f.callees, [])
  { name := f.name, params := f.params, result := f.result, from_ := f.from_, paramVals := f.paramVals,
    pre := f.pre, blocks := r.2, callees := r.1 }

/-- A function with parameters `(value, state)`; `pre` gets one `Parameter` instruction
per parameter.  Its callee table is the one given. -/
def fnRaw (params : List (Nat × St)) (result : St) (from_ : List Nat) (blocks : List Block)
    (extraPre : List Inst := []) (callees : List CalleeEntry := []) : Function :=
  { name := "t", params := params.map (·.2), result := result, from_ := from_,
    paramVals := params.map (·.1),
    pre := params.map (fun p => inst .parameter "param" (some p.1) [] []) ++ extraPre,
    blocks := blocks, callees := callees }

/-- `fnRaw`, and its call lines get runtime entries (`attachCallees`) unless they name one. -/
def fn (params : List (Nat × St)) (result : St) (from_ : List Nat) (blocks : List Block)
    (extraPre : List Inst := []) (callees : List CalleeEntry := []) : Function :=
  attachCallees (fnRaw params result from_ blocks extraPre callees)

/-- the constant `%9` that branches test -/
def c9 : List Inst := [inst .constant "iconst" (some 9) [] []]

/-- the verdict is an acceptance -/
def acc (p : Function × Certificate) : Bool := verdict p.1 p.2 == .accept

/-- the verdict is a rejection by judgment `j` at block `b`, position `k`, for the stated sub-check -/
def rej (p : Function × Certificate) (j : J) (b k : Nat) (why : String) : Bool :=
  verdict p.1 p.2 == .reject { j := j, blk := some b, idx := some k, why := why }

/-- the verdict is a function-wide rejection (no block) -/
def rejFn (p : Function × Certificate) (j : J) (why : String) : Bool :=
  verdict p.1 p.2 == .reject { j := j, blk := none, idx := none, why := why }

/-! ## Accepted: the basics -/

/-- allocate a list and drop it -/
def okAllocDrop : Function × Certificate :=
  (fn [] .scalar [] [blk [] [] [inst .fresh "list_new" (some 0) [] [], inst .drop "drop" none [] [0]] (.ret none)],
   cert [(0, .owned, [])])
#guard acc okAllocDrop

/-- a view used while its owner is live -/
def okView : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard acc okView

/-- an owned parameter is returned (the `ret` consumes it) -/
def okOwnedReturn : Function × Certificate :=
  (fn [(0, .owned)] .owned [] [blk [] [] [] (.ret (some 0))], cert [(0, .owned, [])])
#guard acc okOwnedReturn

/-- a borrowed return reaches only the parameter named by `from` -/
def okBorrowedReturn : Function × Certificate :=
  (fn [(0, .borrowed)] .borrowed [0]
    [blk [] [] [inst .project "record_get" (some 1) [0] []] (.ret (some 1))],
   cert [(0, .borrowed, [.caller 0]), (1, .borrowed, [.val 0])])
#guard acc okBorrowedReturn

/-- a loop: an owned phi carries a list around the back edge -/
def okLoop : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0, 2] [{ dst := 1, edges := [(0, 0), (2, 2)] }] [] (.branch 9 2 3),
      blk [1] [] [inst .update "list_push" (some 2) [9] [1]] (.jump 1),
      blk [1] [] [inst .drop "drop" none [] [1]] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard acc okLoop

/-- the decisions known when a loop is entered are forgotten at its head (they need not hold on
the back edges): the branch at the head `b2` repeats the test `b0` decided, but the edge to `b5`
is still live, and `%0` leaks there -/
def badLoopHeadForgets : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 4),
      blk [0] [] [] (.jump 2),
      blk [1, 3] [] [] (.branch 9 3 5),
      blk [2] [] [] (.jump 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.ret none),
      blk [2] [] [] (.ret none) ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badLoopHeadForgets .j2 5 0 "ret-live"

/-- ... whereas outside a loop the same repeated test prunes the edge (the decision stands) -/
def okRepeatedTest : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 4),
      blk [0] [] [] (.jump 2),
      blk [1] [] [] (.branch 9 3 5),
      blk [2] [] [inst .drop "drop" none [] [0]] (.ret none),
      blk [0] [] [inst .drop "drop" none [] [0]] (.ret none),
      blk [2] [] [] (.ret none) ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okRepeatedTest

/-- both arms of a branch consume the list, so the join sees the same live set -/
def okJoin : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [1, 2] [] [] (.ret none) ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okJoin

/-- a trap block (ends in `unreachable`) is an ordinary block, but a path that leaks says so: the edge from `b2`
abandons `%0`, which the edge from `b1` dropped, so the live owners agree (C9.1) -/
def okTrapJoin : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable (abandons := [(2, [0])]) ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okTrapJoin

/-- ... and without the list the edges disagree about the live owners, as at any join -/
def badTrapJoinUnlisted : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badTrapJoinUnlisted .j2 1 1 "join-live b3"

/-- a trap block that reads an owner both edges have live (`%0` live on both, `%1` consumed on one and abandoned on
the other) -/
def okTrapMeet : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [1]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .output "print" none [0] []] .unreachable (abandons := [(2, [1])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (9, .scalar, [])])
#guard acc okTrapMeet

/-- a chain of blocks that only jumps to the trap block is in the region too: the abandon line is on the first
block of the chain -/
def okTrapChain : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.jump 4) (abandons := [(2, [0])]),
      blk [3] [] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okTrapChain

/-- ... but what the chain reads must be usable: an abandoned owner is not -/
def badTrapChain : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .output "print" none [0] []] (.jump 4) (abandons := [(2, [0])]),
      blk [3] [] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badTrapChain .j3 3 0 "read-usable"

/-- ... and may consume an owner that is live on every edge -/
def okTrapConsume : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [1]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .drop "drop" none [] [0]] .unreachable (abandons := [(2, [1])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (9, .scalar, [])])
#guard acc okTrapConsume

/-- ... but an owner the path abandoned is not usable -/
def badTrapMeet : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [1]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .output "print" none [1] []] .unreachable (abandons := [(2, [1])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (9, .scalar, [])])
#guard rej badTrapMeet .j3 3 0 "read-usable"

/-- ... and consuming it twice is refused as anywhere else -/
def badTrapTwice : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [ inst .drop "drop" none [] [0], inst .drop "drop" none [] [0] ] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badTrapTwice .j2 3 1 "consume-live"

/-- the edges must agree about the live owners like everything else, even into a trap block: the value a take
defines is live on one edge only -/
def badTrapTake : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [inst .project "list_get" (some 1) [0] [] (slot := some "e#0")] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .project "list_get" (some 2) [0] [] (slot := some "e#0")] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badTrapTake .j2 1 1 "join-live b3"

/-- ... unless the container with the open take is abandoned on the edge that has it (and on the other) -/
def okTrapTakeAbandoned : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [inst .project "list_get" (some 1) [0] [] (slot := some "e#0")] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable (abandons := [(1, [0, 1]), (2, [0])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (9, .scalar, [])])
#guard acc okTrapTakeAbandoned

/-- a cursor loop: the borrowed phi `%1` is its own parent (cyclic roots) -/
def okCursor : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 5) [0] [] ] (.jump 1),
      blk [0, 2] [{ dst := 1, edges := [(0, 5), (2, 2)] }] [] (.branch 9 2 3),
      blk [1] [] [inst .project "list_get" (some 2) [1] []] (.jump 1),
      blk [1] [] [ inst .output "print" none [1] [], inst .drop "drop" none [] [0] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (5, .borrowed, [.val 0]), (1, .borrowed, [.val 0, .val 1]),
         (2, .borrowed, [.val 1]), (9, .scalar, [])])
#guard acc okCursor

/-! ## Accepted: the shapes of the real compiler (C3.3b) -/

/-- `stack` is never in `L`: a stack list is filled in place and simply goes out of scope
(the pass schedules no `drop` for it) -/
def okStack : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .update "list_push" (some 1) [] [0] ] (.ret none)],
   cert [(0, .stack, []), (1, .stack, [])])
#guard acc okStack

/-- a scalar may be pushed into a stack list (it owns nothing) -/
def okStackScalar : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .update "list_push" (some 1) [] [0, 9] ] (.ret none)]
    c9,
   cert [(0, .stack, []), (1, .stack, []), (9, .scalar, [])])
#guard acc okStackScalar

/-- a stack phi joins two stack lists and neither is in `L` -/
def okStackPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [] (.branch 9 1 2),
      blk [0] [] [inst .fresh "list_new" (some 0) [] []] (.jump 3),
      blk [0] [] [inst .fresh "list_new" (some 1) [] []] (.jump 3),
      blk [1, 2] [{ dst := 2, edges := [(1, 0), (2, 1)] }] [] (.ret none) ]
    c9,
   cert [(0, .stack, []), (1, .stack, []), (2, .stack, []), (9, .scalar, [])])
#guard acc okStackPhi

/-- an owned phi whose second edge carries an `undef` (the null owner): the edge is live,
consuming the `undef` is a no-op and the first edge consumes the list -/
def okUndefPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [1, 2] [{ dst := 3, edges := [(1, 0), (2, 7)] }] [inst .drop "drop" none [] [3]] (.ret none) ]
    (c9 ++ [inst .constant "undef" (some 7) [] []]),
   cert [(0, .owned, []), (9, .scalar, []), (7, .immortal, []), (3, .owned, [])])
#guard acc okUndefPhi

/-- ... but an operation that reads the null owner is J3 (lane FX12: a `match mut` binding lowered to one) -/
def badNullOwnerRead : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [inst .inspect "str_len" (some 1) [7] []] (.ret none)]
    (c9 ++ [inst .constant "undef" (some 7) [] []]),
   cert [(9, .scalar, []), (7, .immortal, []), (1, .scalar, [])])
#guard rej badNullOwnerRead .j3 0 0 "read-null-owner"

/-- a void call (`inst - call`) and a marker call define nothing -/
def okVoidCall : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [], inst .call "call" none [9] [] ] (.ret none)]
    c9,
   cert [(9, .scalar, [])])
#guard acc okVoidCall

/-- a void-typed `undef` (state `none`) consumed by an update is a no-op -/
def okVoidUndef : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "set_new" (some 0) [] [],
                 inst .update "set_add" (some 1) [] [0, 7],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    [inst .constant "undef" none [] []],
   cert [(0, .owned, []), (1, .owned, [])])
-- `%7` is the unnamed operand: it has no state
#guard acc okVoidUndef

/-- a `Take` and an `Update` whose result is a scalar (a flag, a count) -/
def okScalarResults : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .update "list_push" (some 1) [] [0],
                 inst .take "union_take" (some 2) [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .scalar, [])])
#guard acc okScalarResults

/-- a call result that holds a loan on the view it was given, and a projection of it: the
projection borrows from the view's owner, which the call result's parents name -/
def okCallProjection : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .call "call" (some 2) [1] [],
                 inst .project "record_get" (some 3) [2] [],
                 inst .output "print" none [3] [],
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]),
         (3, .borrowed, [.val 1])])
#guard acc okCallProjection

/-- ... but the call result's loan ends when its root, the owner of the view, is dropped
(J4, loans on owned aggregates are enforced) -/
def badCallProjection : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .call "call" (some 2) [1] [],
                 inst .project "record_get" (some 3) [2] [],
                 inst .drop "drop" none [] [0],
                 inst .output "print" none [3] [],
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]),
         (3, .borrowed, [.val 1])])
#guard rej badCallProjection .j4 0 4 "loan-outlives-root"

/-- a borrowed selection phi: one arm a view, the other the owned fallback; it consumes
nothing, and its roots are the view's owner and the fallback -/
def okSelectionPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .fresh "list_new" (some 2) [] [],
                  inst .view "list_view_of" (some 1) [0] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [{ dst := 3, edges := [(1, 1), (2, 2)] }]
        [ inst .output "print" none [3] [],
          inst .drop "drop" none [] [0], inst .drop "drop" none [] [2] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (2, .owned, []), (1, .borrowed, [.val 0]),
         (3, .borrowed, [.val 0, .val 2]), (9, .scalar, [])])
#guard acc okSelectionPhi

/-- ... and it is not usable once the fallback is gone -/
def badSelectionPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .fresh "list_new" (some 2) [] [],
                  inst .view "list_view_of" (some 1) [0] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [{ dst := 3, edges := [(1, 1), (2, 2)] }]
        [ inst .drop "drop" none [] [2], inst .output "print" none [3] [],
          inst .drop "drop" none [] [0] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (2, .owned, []), (1, .borrowed, [.val 0]),
         (3, .borrowed, [.val 0, .val 2]), (9, .scalar, [])])
#guard rej badSelectionPhi .j4 3 1 "read-borrowed-usable"

/-- a dead phi (state `none`) carries nothing: its edges are not looked at -/
def okDeadPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [{ dst := 4, edges := [(1, 5)] }] [] (.ret none) ]
    c9,
   cert [(9, .scalar, [])])
#guard acc okDeadPhi

/-- the owner of a view moves into an owned phi: the storage stays put, so the view is still
usable after the phi and ends with the phi's value -/
def okOwnerThroughPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [] ] (.jump 1),
      blk [0] [{ dst := 2, edges := [(0, 0)] }]
        [ inst .output "print" none [1] [], inst .drop "drop" none [] [2] ] (.ret none) ]
    [],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [])])
#guard acc okOwnerThroughPhi

/-- ... and not after the phi's value was dropped -/
def badOwnerThroughPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [] ] (.jump 1),
      blk [0] [{ dst := 2, edges := [(0, 0)] }]
        [ inst .drop "drop" none [] [2], inst .output "print" none [1] [] ] (.ret none) ]
    [],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [])])
#guard rej badOwnerThroughPhi .j4 1 1 "read-borrowed-usable"

/-- a constructor takes the owner of a view it also reads (a loan): the aggregate holds the
view's storage afterwards -/
def okConstructLoan : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [0],
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard acc okConstructLoan

/-- ... and the view does not outlive the aggregate -/
def badConstructLoan : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [0],
                 inst .drop "drop" none [] [2],
                 inst .output "print" none [1] [] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard rej badConstructLoan .j4 0 4 "read-borrowed-usable"

/-! ## Accepted and rejected: the take protocol, per slot (design §3, §5 J8) -/

/-- a take of one slot, an update, the store that closes it (`released -`: the old content
was taken, the store destroys nothing) -/
def okRecordTake : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .update "list_push" (some 2) [] [1],
                 inst .update "record_set" (some 3) [] [0, 2] (slot := some "f1"),
                 inst .drop "drop" none [] [3] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, [])])
#guard acc okRecordTake

/-- a record with two managed fields: both taken, closed one at a time in either order;
the store passes the other pending slot on to the record it returns -/
def okTwoSlots : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .project "record_get" (some 2) [0] [] (slot := some "f2"),
                 inst .update "record_set" (some 3) [] [0, 2] (slot := some "f2"),
                 inst .update "record_set" (some 4) [] [3, 1] (slot := some "f1"),
                 inst .drop "drop" none [] [4] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .owned, [])])
#guard acc okTwoSlots

/-- the same slot cannot be taken twice -/
def badTakeTwice : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .project "record_get" (some 2) [0] [] (slot := some "f1") ] .unreachable],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, [])])
#guard rej badTakeTwice .j8 0 2 "take"

/-- a record store into a slot that was not taken -/
def badStoreNotPending : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .project "record_get" (some 2) [0] [] (slot := some "f1"),
                 inst .update "record_set" (some 3) [] [0, 1] (slot := some "f2") ] .unreachable],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, [])])
#guard rej badStoreNotPending .j8 0 3 "close"

/-- a take still open at `ret` (the container it leaves live is what the checker reports first) -/
def badPendingAtRet : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1") ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rej badPendingAtRet .j8 0 2 "ret-pending"

/-- the container of an open take is dropped instead of being updated -/
def badDropPending : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .drop "drop" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rej badDropPending .j8 0 2 "pending"

/-- a list store whose old content was taken says `released -`: the take must be open -/
def okListSetReleasedNone : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0"),
                 inst .update "list_set" (some 2) [9] [0, 1] (slot := some "e#0") (released := some "-"),
                 inst .drop "drop" none [] [2] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard acc okListSetReleasedNone

/-- `released -` with no take open: the store would leak the old content -/
def badReleasedNoneNotPending : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .update "list_set" (some 2) [9] [0, 1] (slot := some "e#0") (released := some "-") ] .unreachable]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badReleasedNoneNotPending .j8 0 2 "close"

/-- `released old` with no take open: the store destroys the old content -/
def okListSetReleasedOld : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .update "list_set" (some 2) [9] [0, 1] (slot := some "e#0") (released := some "old"),
                 inst .drop "drop" none [] [2] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard acc okListSetReleasedOld

/-- `released old` while the take is open: the store would destroy content that was moved out -/
def badReleasedOldPending : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0"),
                 inst .update "list_set" (some 2) [9] [0, 1] (slot := some "e#0") (released := some "old") ] .unreachable]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badReleasedOldPending .j8 0 2 "close"

/-- `list_pop` closes the slot it names -/
def okListPop : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0"),
                 inst .update "list_pop" (some 2) [] [0] (slot := some "e#0"),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard acc okListPop

/-- `list_pop` of the `tail` closes nothing, so with no take open it is fine -/
def okListPopTail : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .update "list_pop" (some 1) [] [0] (slot := some "tail"),
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, [])])
#guard acc okListPopTail

/-- `list_pop` of a slot that is not open -/
def badListPop : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .update "list_pop" (some 1) [] [0] (slot := some "e#0") ] .unreachable],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rej badListPop .j8 0 1 "close"

/-- `dict_remove` closes the key and value slots of the entry it reads; the value was taken, so
the removal releases only the key -/
def okDictRemove : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .project "dict_entry_value" (some 1) [0, 7] [] (slot := some "v%7"),
                 inst .update "dict_remove" (some 2) [7] [0] (released := some "key"),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    [inst .constant "iconst" (some 7) [] []],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (7, .scalar, [])])
#guard acc okDictRemove

/-- ... releasing the value too would destroy what the take moved out -/
def badDictRemoveValue : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .project "dict_entry_value" (some 1) [0, 7] [] (slot := some "v%7"),
                 inst .update "dict_remove" (some 2) [7] [0] (released := some "key,value") ] .unreachable]
    [inst .constant "iconst" (some 7) [] []],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (7, .scalar, [])])
#guard rej badDictRemoveValue .j8 0 2 "close"

/-- a phi may not consume a container with an open take -/
def badPhiPending : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                  inst .project "record_get" (some 1) [0] [] (slot := some "f1") ] (.jump 1),
      blk [0] [{ dst := 2, edges := [(0, 0)] }] [] .unreachable ]
    [],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, [])])
#guard rej badPhiPending .j8 0 2 "phi-pending"

/-! ## Emptied aggregates (design §3, slots) -/

/-- a call consumes a list and returns a record `emptied`: its managed field `f1` is taken
exactly once (by `%3`); the record owns nothing and is never consumed.  The view `%2` of that
field is written before the take and is rooted at the owner that takes its place. -/
def okEmptied : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 2) [1] [],
                 inst .project "record_get" (some 3) [1] [] (slot := some "f1"),
                 inst .project "union_payload" (some 4) [2] [],
                 inst .output "print" none [4] [],
                 inst .drop "drop" none [] [3] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .borrowed, [.val 3]), (3, .owned, []),
         (4, .borrowed, [.val 3])])
#guard acc okEmptied

/-- the write-back record of a call that took `%0` and read the view `%6` returns, besides the owner, a
borrowed leaf of that view: the projection lists the call's `from` value `%6` as its parent (design §3,
Project; `eval_design_block::parse_board` of the EDA corpus) -/
def okEmptiedFromView : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 5) [] [],
                 inst .view "list_view_of" (some 6) [5] [],
                 inst .call "call" (some 1) [6] [0] (slots := ["f1"]) (fromVals := [6]),
                 inst .project "record_get" (some 2) [1] [],
                 inst .project "record_get" (some 3) [1] [] (slot := some "f1"),
                 inst .output "print" none [2] [],
                 inst .drop "drop" none [] [3],
                 inst .drop "drop" none [] [5] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .borrowed, [.val 6]), (3, .owned, []),
         (5, .owned, []), (6, .borrowed, [.val 5])])
#guard acc okEmptiedFromView

/-- ... but a parent the call does not list is not an operand of the projection (J1) -/
def badEmptiedFromViewParent : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 5) [] [],
                 inst .view "list_view_of" (some 6) [5] [],
                 inst .call "call" (some 1) [6] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 2) [1] [],
                 inst .project "record_get" (some 3) [1] [] (slot := some "f1"),
                 inst .output "print" none [2] [],
                 inst .drop "drop" none [] [3],
                 inst .drop "drop" none [] [5] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .borrowed, [.val 6]), (3, .owned, []),
         (5, .owned, []), (6, .borrowed, [.val 5])])
#guard rej badEmptiedFromViewParent .j1 0 4 "parentsOk"

/-- a constructor whose result is `emptied` (a record built only to have its field taken straight
out) consumes an owner and reads a view of it, like an owned aggregate that records the view as a
loan: the storage moves into the field the take returns (`borrowed_signatures`) -/
def okEmptiedConstruct : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 3) [2] [],
                 inst .project "record_get" (some 4) [2] [] (slot := some "f1"),
                 inst .output "print" none [3] [],
                 inst .drop "drop" none [] [4] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .emptied, []),
         (3, .borrowed, [.val 2, .val 4]), (4, .owned, [])])
#guard acc okEmptiedConstruct

/-- ... but the view written before the construction does not survive it -/
def badEmptiedConstructView : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 3) [2] [] (slot := some "f1"),
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [3] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .emptied, []), (3, .owned, [])])
#guard rej badEmptiedConstructView .j4 0 4 "read-borrowed-usable"

/-- ... a projection of the view lasts only as long as the owner that took its place -/
def badEmptiedOwnerDropped : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 2) [1] [],
                 inst .project "record_get" (some 3) [1] [] (slot := some "f1"),
                 inst .drop "drop" none [] [3],
                 inst .output "print" none [2] [] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .borrowed, [.val 3]), (3, .owned, [])])
#guard rej badEmptiedOwnerDropped .j4 0 5 "read-borrowed-usable"

/-- an emptied record is never consumed (the structural check refuses any use but a first read
of a projection) -/
def badEmptiedConsumed : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                 inst .drop "drop" none [] [1],
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .owned, [])])
#guard rej badEmptiedConsumed .j8 0 3 "emptied"

/-- each slot of an emptied record is taken exactly once: twice is refused ... -/
def badEmptiedTakenTwice : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                 inst .project "record_get" (some 3) [1] [] (slot := some "f1"),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [3] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .owned, []), (3, .owned, [])])
#guard rej badEmptiedTakenTwice .j8 0 3 "emptied"

/-- ... and so is a slot that is never taken -/
def badEmptiedNeverTaken : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [] [0] (slots := ["f1", "f2"]),
                 inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .owned, []), (1, .emptied, []), (2, .owned, [])])
#guard rejFn badEmptiedNeverTaken .j8 "emptied"

/-- a live owned value that holds a loan keeps what it borrows from: an emptied constructor
destroys the owner the holder borrows from (only a constructor with an owned result moves the loans
with the storage, design §9 entry 41), which is `loan-outlives-root` at the constructor -/
def badHolderReadAfterEmptied : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .call "call" (some 2) [1] [],
                 inst .construct "record_make" (some 3) [] [0] (slots := ["f1"]),
                 inst .project "record_get" (some 4) [3] [] (slot := some "f1"),
                 inst .output "print" none [2] [],
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [4] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .emptied, []),
         (4, .owned, [])])
#guard rej badHolderReadAfterEmptied .j4 0 3 "loan-outlives-root"

/-! ## Constructors that read a borrow (J6 `construct-read`, lane VAL)

A constructor whose result is owned or `emptied` reads a borrowed operand only when the operand lives in owners it
consumes (a slot of one included), or when the result is owned and lists the operand as a loan.  Lane FX6 found a plan
that broke it: an `emptied` item record read a dictionary's key as a borrow of the dictionary, and the take out of it
handed the key out as an owner that was destroyed every iteration.  The accepted neighbours of entries 19 and 28 are
`okConstructLoan` and `okEmptiedConstruct` above. -/

/-- entry 28 through a slot: an emptied record takes an owned record and reads a view of one of its slots -/
def okConstructReadSlot : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 1) [] [],
                 inst .construct "record_make" (some 2) [] [1],
                 inst .project "record_get" (some 3) [2] [] (slot := some "f0"),
                 inst .construct "record_make" (some 4) [3] [2] (slots := ["f0"]),
                 inst .project "record_get" (some 5) [4] [] (slot := some "f0"),
                 inst .drop "drop" none [] [5] ] (.ret none)],
   cert [(1, .owned, []), (2, .owned, []), (3, .borrowed, [.val 2]), (4, .emptied, []),
         (5, .owned, [])])
#guard acc okConstructReadSlot

/-- an owned record that holds a view of an owner it does not take, as a loan it lists, and is dropped before the owner -/
def okConstructReadListed : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [] (views := [1]),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard acc okConstructReadListed

/-- ... but only a view (format v2, `views`): the same record listing a borrowed operand it does not mark as a view (a
borrowed `str`, which the record's destruction would destroy) is refused -/
def badConstructReadListedNotView : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [],
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard rej badConstructReadListedNotView .j6 0 2 "construct-read"

/-- J1 `views`: a view is an operand the constructor reads -/
def badViewsNotRead : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [] (views := [0]),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard rej badViewsNotRead .j1 0 2 "views"

/-- J1 `views`: only a constructor lists views -/
def badViewsNotConstruct : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [] (views := [0]),
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard rej badViewsNotConstruct .j1 0 1 "views"

/-- the plan of FX6: an emptied record reads a view of an owner it does not consume, and the take out of it is an owner
of that storage; the owner is destroyed too.  Every other check passes it. -/
def badConstructReadEmptied : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [] (slots := ["f0"]),
                 inst .project "record_get" (some 3) [2] [] (slot := some "f0"),
                 inst .drop "drop" none [] [3],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .emptied, []), (3, .owned, [])])
#guard rej badConstructReadEmptied .j6 0 2 "construct-read"

/-- ... the same with the borrow rooted in the caller: a borrowed parameter -/
def badConstructReadCaller : Function × Certificate :=
  (fn [(0, .borrowed)] .scalar []
    [blk [] [] [ inst .construct "record_make" (some 1) [0] [] (slots := ["f0"]),
                 inst .project "record_get" (some 2) [1] [] (slot := some "f0"),
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .borrowed, [.caller 0]), (1, .emptied, []), (2, .owned, [])])
#guard rej badConstructReadCaller .j6 0 0 "construct-read"

/-- an owned record that reads a view of an owner it neither takes nor lists as a loan: the record destroys what the
owner destroys again -/
def badConstructReadOwned : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .construct "record_make" (some 2) [1] [],
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [])])
#guard rej badConstructReadOwned .j6 0 2 "construct-read"

/-- an emptied record that takes one owner and reads views of it and of a second owner it does not take -/
def badConstructReadTwoOwners : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .view "list_view_of" (some 2) [0] [],
                 inst .view "list_view_of" (some 3) [1] [],
                 inst .construct "record_make" (some 4) [2, 3] [0] (slots := ["f0", "f1"]),
                 inst .project "record_get" (some 5) [4] [] (slot := some "f0"),
                 inst .project "record_get" (some 6) [4] [] (slot := some "f1"),
                 inst .drop "drop" none [] [5],
                 inst .drop "drop" none [] [6],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .borrowed, [.val 0]), (3, .borrowed, [.val 1]),
         (4, .emptied, []), (5, .owned, []), (6, .owned, [])])
#guard rej badConstructReadTwoOwners .j6 0 4 "construct-read"

/-! ## Guarded takes (design §5)

The idiom of the real corpus: `i = dict_find(d, k)`; `if i != -1: take d[i]`; later
`if i != -1: dict_remove(d, i)`.  The take is open on one edge into the join and not on the
other; the two tests are the same `cmp` of the same operands with equal constants, so the
second branch decides what the join left open. -/

/-- the constants `%8` and `%15` (both the integer 0), as the export writes them -/
def zeroes : List Inst :=
  [inst .constant "iconst" (some 8) [] [] (imm := some 0),
   inst .constant "iconst" (some 15) [] [] (imm := some 0)]

/-- the shared body: `%1` a dictionary, `%7` the position `dict_find` returns, tests `%9` and
`%16`; `p2`, `c2` are the predicate and the constant the second test uses -/
def guarded (p2 c2 : Nat) (extra : List Inst := []) : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "dict_new" (some 1) [] [],
                  inst .inspect "dict_find" (some 7) [1] [],
                  inst .pure "cmp" (some 9) [7, 8] [] (imm := some 5) ] (.branch 9 1 2),
      blk [0] [] [ inst .project "dict_entry_value" (some 11) [1, 7] [] (slot := some "v%7"),
                   inst .drop "drop" none [] [11] ] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] (extra ++ [inst .pure "cmp" (some 16) [7, 15] [] (imm := some p2)]) (.branch 16 4 5),
      blk [3] [] [inst .update "dict_remove" (some 18) [7] [1] (released := some "key")] (.jump 5),
      blk [3, 4] [{ dst := 19, edges := [(3, 1), (4, 18)] }]
        [inst .drop "drop" none [] [19]] (.ret none) ]
    (zeroes.map (fun i => if c2 == 0 then i else { i with imm := if i.dst == some 15 then some c2 else i.imm })),
   cert [(1, .owned, []), (7, .scalar, []), (8, .scalar, []), (9, .scalar, []), (11, .owned, []),
         (15, .scalar, []), (16, .scalar, []), (18, .owned, []), (19, .owned, [])])

/-- the second test is the same `cmp` of the same operands (`%15` equals `%8` by value): accepted -/
def okGuardedTake : Function × Certificate := guarded 5 0
#guard acc okGuardedTake

/-- ... with a different constant it is another test, and the join cannot be told apart -/
def badGuardedConstant : Function × Certificate := guarded 5 1
#guard rej badGuardedConstant .j8 3 1 "phi-pending"

/-- ... and so is a different predicate -/
def badGuardedPredicate : Function × Certificate := guarded 4 0
#guard rej badGuardedPredicate .j8 3 1 "phi-pending"

/-- one entry, guarded by a different test on each edge of a join (one under `%9`, the other under
`%10`): there is no single decision to carry, so the join is refused -/
def badGuardsDiffer : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "dict_new" (some 1) [] [],
                  inst .inspect "dict_find" (some 7) [1] [],
                  inst .pure "cmp" (some 9) [7, 8] [] (imm := some 5),
                  inst .pure "cmp" (some 10) [7, 8] [] (imm := some 4),
                  inst .pure "cmp" (some 12) [7, 13] [] (imm := some 3) ] (.branch 12 1 2),
      blk [0] [] [] (.branch 9 3 4),
      blk [0] [] [] (.branch 10 6 7),
      blk [1] [] [ inst .project "dict_entry_value" (some 11) [1, 7] [] (slot := some "v%7"),
                   inst .drop "drop" none [] [11] ] (.jump 5),
      blk [1] [] [] (.jump 5),
      blk [3, 4] [] [] (.jump 9),
      blk [2] [] [ inst .project "dict_entry_value" (some 14) [1, 7] [] (slot := some "v%7"),
                   inst .drop "drop" none [] [14] ] (.jump 8),
      blk [2] [] [] (.jump 8),
      blk [6, 7] [] [] (.jump 9),
      blk [5, 8] [] [inst .drop "drop" none [] [1]] (.ret none) ]
    [inst .constant "iconst" (some 8) [] [] (imm := some 0),
     inst .constant "iconst" (some 13) [] [] (imm := some 7)],
   cert [(1, .owned, []), (7, .scalar, []), (8, .scalar, []), (9, .scalar, []), (10, .scalar, []),
         (11, .owned, []), (12, .scalar, []), (13, .scalar, []), (14, .owned, [])])
#guard rej badGuardsDiffer .j8 5 0 "join-pending b9"

/-- a value is defined once (SSA): redefining the operand of a test is refused outright, so a
guard can only lose an operand to a loop, where the entry state of the header does not fit -/
def badDuplicateDef : Function × Certificate :=
  guarded 5 0 [inst .inspect "dict_find" (some 7) [1] []]
#guard rejFn badDuplicateDef .j1 "dst-unique"

/-- the test may also be the same value: a parameter flag decides twice -/
def okGuardedValue : Function × Certificate :=
  (fn [(9, .scalar)] .scalar []
    [ blk [] [] [ inst .fresh "dict_new" (some 1) [] [],
                  inst .inspect "dict_find" (some 7) [1] [] ] (.branch 9 1 2),
      blk [0] [] [ inst .project "dict_entry_value" (some 11) [1, 7] [] (slot := some "v%7"),
                   inst .drop "drop" none [] [11] ] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.branch 9 4 5),
      blk [3] [] [inst .update "dict_remove" (some 18) [7] [1] (released := some "key")] (.jump 5),
      blk [3, 4] [{ dst := 19, edges := [(3, 1), (4, 18)] }]
        [inst .drop "drop" none [] [19]] (.ret none) ]
    [],
   cert [(9, .scalar, []), (1, .owned, []), (7, .scalar, []), (11, .owned, []),
         (18, .owned, []), (19, .owned, [])])
#guard acc okGuardedValue

/-- the second branch on a test already decided prunes the edge it rules out: here the false
edge of the second test cannot be taken, so the take is never left open -/
def okPrunedEdge : Function × Certificate :=
  (fn [(9, .scalar)] .scalar []
    [ blk [] [] [ inst .fresh "dict_new" (some 1) [] [],
                  inst .inspect "dict_find" (some 7) [1] [] ] (.branch 9 1 2),
      blk [0] [] [ inst .project "dict_entry_value" (some 11) [1, 7] [] (slot := some "v%7"),
                   inst .drop "drop" none [] [11] ] (.branch 9 3 4),
      blk [0] [] [inst .drop "drop" none [] [1]] (.ret none),
      blk [1] [] [inst .update "dict_remove" (some 18) [7] [1] (released := some "key"),
                  inst .drop "drop" none [] [18]] (.ret none),
      blk [1] [] [] .unreachable ]
    [],
   cert [(9, .scalar, []), (1, .owned, []), (7, .scalar, []), (11, .owned, []), (18, .owned, [])])
#guard acc okPrunedEdge

/-! ## Loans on slots of owned aggregates (design §3 Project; J4)

A view of one slot of an owned container is rooted at that slot: taking the slot, or consuming
the container, ends it.  An owned aggregate that holds such a view as a loan may not outlive
the loan's root. -/

/-- a view of a slot, used while the container is live -/
def okSlotView : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard acc okSlotView

/-- taking the slot ends the view -/
def badSlotViewAfterTake : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .project "record_get" (some 2) [0] [] (slot := some "f1"),
                 inst .output "print" none [1] [] ] .unreachable],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [])])
#guard rej badSlotViewAfterTake .j4 0 3 "read-borrowed-usable"

/-- ... but taking another slot does not -/
def okSlotViewOtherSlot : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .project "record_get" (some 2) [0] [] (slot := some "f2"),
                 inst .output "print" none [1] [] ] .unreachable],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [])])
#guard acc okSlotViewOtherSlot

/-- an aggregate holding the view as a loan, consumed before the container -/
def okLoanHolder : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .construct "record_make" (some 2) [1] [] (views := [1]),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard acc okLoanHolder

/-- ... but the container may not be consumed while the holder is live -/
def badLoanHolderOwner : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .construct "record_make" (some 2) [1] [] (views := [1]),
                 inst .drop "drop" none [] [0],
                 inst .drop "drop" none [] [2] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1])])
#guard rej badLoanHolderOwner .j4 0 3 "loan-outlives-root"

/-- ... nor the slot taken -/
def badLoanHolderTake : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .construct "record_make" (some 2) [1] [] (views := [1]),
                 inst .project "record_get" (some 3) [0] [] (slot := some "f1") ] .unreachable],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, [])])
#guard rej badLoanHolderTake .j4 0 3 "loan-outlives-root"

/-- a holder of a loan on one slot does not mind another slot being taken -/
def okLoanHolderOtherSlot : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                 inst .project "record_get" (some 1) [0] [] (slot := some "f1"),
                 inst .construct "record_make" (some 2) [1] [] (views := [1]),
                 inst .project "record_get" (some 3) [0] [] (slot := some "f2") ] .unreachable],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, [])])
#guard acc okLoanHolderOtherSlot

/-- a loan held through a phi follows the phi: the holder moves with its value -/
def badLoanHolderPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "record_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]) ] (.jump 1),
      blk [0] [{ dst := 3, edges := [(0, 2)] }]
        [ inst .drop "drop" none [] [0], inst .drop "drop" none [] [3] ] (.ret none) ]
    [],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, [])])
#guard rej badLoanHolderPhi .j4 1 0 "loan-outlives-root"

/-! ## The v2 export: named unit values and the `taken` parts of `dict_remove` -/

/-- a unit value an instruction names (`inst %3 undef ... state none`) is consumed as a no-op -/
def okNamedUnit : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .constant "undef" (some 3) [] [],
                 inst .update "dict_insert" (some 1) [] [0, 3],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, [])])
#guard acc okNamedUnit

/-- ... but reading it is J3 -/
def badReadNamedUnit : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .constant "undef" (some 3) [] [],
                 inst .output "print" none [3] [] ] (.ret none)],
   cert [])
#guard rej badReadNamedUnit .j3 0 1 "read-usable"

/-- the value of an entry was taken; the removal says so and releases only the key -/
def okDictRemoveTaken : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .project "dict_entry_value" (some 1) [0, 7] [] (slot := some "v%7"),
                 inst .update "dict_remove" (some 2) [7] [0] (slot := some "v%7")
                   (released := some "key") (taken := some "value"),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    [inst .constant "iconst" (some 7) [] []],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (7, .scalar, [])])
#guard acc okDictRemoveTaken

/-- ... a removal that says the value was taken when it was not -/
def badDictRemoveTakenNotPending : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .update "dict_remove" (some 2) [7] [0] (slot := some "v%7")
                   (released := some "key") (taken := some "value") ] .unreachable]
    [inst .constant "iconst" (some 7) [] []],
   cert [(0, .owned, []), (2, .owned, []), (7, .scalar, [])])
#guard rej badDictRemoveTakenNotPending .j8 0 1 "close"

/-- ... and one that releases a part that is still pending -/
def badDictRemoveReleasesTaken : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "dict_new" (some 0) [] [],
                 inst .project "dict_entry_value" (some 1) [0, 7] [] (slot := some "v%7"),
                 inst .update "dict_remove" (some 2) [7] [0] (slot := some "v%7")
                   (released := some "key,value") (taken := some "-") ] .unreachable]
    [inst .constant "iconst" (some 7) [] []],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (7, .scalar, [])])
#guard rej badDictRemoveReleasesTaken .j8 0 2 "close"

/-! ## Rejections, one per judgment -/

/-- J1: a `Fresh` instruction cannot have a borrowed result -/
def badJ1 : Function × Certificate :=
  (fn [] .scalar [] [blk [] [] [inst .fresh "list_new" (some 0) [] []] (.ret none)],
   cert [(0, .borrowed, [])])
#guard rej badJ1 .j1 0 0 "classOk"

/-- J1: a borrowed result names a parent the instruction does not read -/
def badJ1Parent : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [] [],
                 inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard rej badJ1Parent .j1 0 1 "parentsOk"

/-- J2: a list that is never consumed leaks (reported at the `ret`) -/
def badJ2Leak : Function × Certificate :=
  (fn [] .scalar [] [blk [] [] [inst .fresh "list_new" (some 0) [] []] (.ret none)],
   cert [(0, .owned, [])])
#guard rej badJ2Leak .j2 0 1 "ret-live"

/-- J2: a list dropped twice -/
def badJ2Double : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .drop "drop" none [] [0], inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .owned, [])])
#guard rej badJ2Double .j2 0 2 "consume-live"

/-- J2: the two arms of a branch leave different live sets at the join -/
def badJ2Join : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.ret none) ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badJ2Join .j2 1 1 "join-live b3"

/-- J2: an `undef` edge is live (the old model skipped it): the arm that does not pass the
list into the phi still holds it at the join (reported at the other predecessor, which the
forward pass reached second) -/
def badUndefEdgeLive : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [{ dst := 3, edges := [(1, 0), (2, 7)] }] [inst .drop "drop" none [] [3]] (.ret none) ]
    (c9 ++ [inst .constant "undef" (some 7) [] []]),
   cert [(0, .owned, []), (9, .scalar, []), (7, .immortal, []), (3, .owned, [])])
#guard rej badUndefEdgeLive .j2 1 0 "join-live b3"

/-- J3: a list used after it was dropped -/
def badJ3 : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .drop "drop" none [] [0], inst .output "print" none [0] [] ] (.ret none)],
   cert [(0, .owned, [])])
#guard rej badJ3 .j3 0 2 "read-usable"

/-- J4: a view used after its owner was dropped -/
def badJ4 : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .drop "drop" none [] [0],
                 inst .output "print" none [1] [] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard rej badJ4 .j4 0 3 "read-borrowed-usable"

/-- J4: a view made in one loop iteration is not defined on the path that enters the loop -/
def badStale : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0, 1] [] [ inst .output "print" none [2] [],
                      inst .view "list_view_of" (some 2) [0] [] ] (.branch 9 1 2),
      blk [1] [] [inst .drop "drop" none [] [0]] (.ret none) ]
    c9,
   cert [(0, .owned, []), (2, .borrowed, [.val 0]), (9, .scalar, [])])
#guard rej badStale .j4 1 0 "read-borrowed-usable"

/-- J5: a borrowed parameter is dropped -/
def badJ5 : Function × Certificate :=
  (fn [(0, .borrowed)] .scalar [] [blk [] [] [inst .drop "drop" none [] [0]] (.ret none)],
   cert [(0, .borrowed, [.caller 0])])
#guard rej badJ5 .j5 0 0 "consume-borrowed"

/-- J5: a borrowed value is returned where the result is owned -/
def badJ5Ret : Function × Certificate :=
  (fn [(0, .borrowed)] .owned [] [blk [] [] [] (.ret (some 0))], cert [(0, .borrowed, [.caller 0])])
#guard rej badJ5Ret .j5 0 0 "ret-borrowed"

/-- J5: a borrowed result is returned that borrows from a parameter outside `from` -/
def badJ5From : Function × Certificate :=
  (fn [(0, .borrowed), (1, .borrowed)] .borrowed [0]
    [blk [] [] [inst .project "record_get" (some 2) [1] []] (.ret (some 2))],
   cert [(0, .borrowed, [.caller 0]), (1, .borrowed, [.caller 1]), (2, .borrowed, [.val 1])])
#guard rej badJ5From .j5 0 1 "ret-from"

/-- J6: a call takes a list while another argument is a view of it (rule M5) -/
def badJ6 : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .view "list_view_of" (some 1) [0] [],
                 inst .call "call" (some 2) [1] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .scalar, [])])
#guard rej badJ6 .j6 0 2 "consume-root-of-operand"

/-- J6: a value both read and consumed by one instruction -/
def badJ6Same : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [0] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .scalar, [])])
#guard rej badJ6Same .j6 0 1 "consume-and-read"

/-- J7: a stack list is returned -/
def badJ7 : Function × Certificate :=
  (fn [] .owned [] [blk [] [] [inst .fresh "list_new" (some 0) [] []] (.ret (some 0))],
   cert [(0, .stack, [])])
#guard rej badJ7 .j7 0 1 "ret-stack"

/-- J7: a stack list is stored into a constructor -/
def badJ7Store : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .construct "record_make" (some 1) [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .stack, []), (1, .owned, [])])
#guard rej badJ7Store .j7 0 1 "stack"

/-- J7: a stack list holds no managed elements: pushing an owned value would never destroy it -/
def badJ7Element : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .update "list_push" (some 2) [] [0, 1],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .stack, []), (1, .owned, []), (2, .stack, [])])
#guard rej badJ7Element .j7 0 2 "stack"

/-- J7: a stack list is never dropped (the pass schedules no `drop` for it) -/
def badJ7Drop : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .drop "drop" none [] [0] ] (.ret none)],
   cert [(0, .stack, [])])
#guard rej badJ7Drop .j7 0 1 "stack"

/-- J8: the container of a transferred read is dropped instead of being updated -/
def badJ8 : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0"),
                 inst .drop "drop" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (9, .scalar, [])])
#guard rej badJ8 .j8 0 2 "pending"


/-! ## Task groups (design §10, package C6)

A group is an owned value (`group_open`, a call without operands).  A lend (`box_make` with
`lent %G`) reads the lender and the group and consumes nothing: the group then holds the roots of
the lender as loans, and records itself as lent-to.  The environment (`record_make`) carries the box
and the submit (a call) consumes it.  The join is a call that consumes the group and returns
nothing.  Until the join the lender is neither consumed nor changed (rule K1), the group is
consumed exactly once (K2), and only by the join. -/

/-- a group, a list lent to it, a task submitted, the join, and only then the lender dropped -/
def okGroup : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, [])])
#guard acc okGroup

/-- the lender may be a borrowed parameter: the caller keeps it for the whole call -/
def okGroupBorrowed : Function × Certificate :=
  (fn [(5, .borrowed)] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .construct "box_make" (some 2) [5, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .call "group_end" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .borrowed, [.caller 0])])
#guard acc okGroupBorrowed

/-- the lender may be a view of one slot of an owned record; the record outlives the join -/
def okGroupSlot : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "record_new" (some 1) [] [],
                 inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                 inst .construct "box_make" (some 3) [2, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 4) [] [3],
                 inst .call "submit" (some 5) [0] [4],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .borrowed, [.val 1]), (3, .owned, []),
         (4, .owned, []), (5, .scalar, [])])
#guard acc okGroupSlot

/-- two lends to one group, and a lender that is the read of another group's owner -/
def okGroupTwoLends : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .fresh "list_new" (some 2) [] [],
                 inst .construct "box_make" (some 3) [1, 0] [] (lent := some 0),
                 inst .construct "box_make" (some 4) [2, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 5) [] [3, 4],
                 inst .call "submit" (some 6) [0] [5],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .owned, []),
         (5, .owned, []), (6, .scalar, [])])
#guard acc okGroupTwoLends

/-- the join on both arms of a branch (a `return` or `break` ends the group on every exit edge) -/
def okGroupBranch : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.ret none),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard acc okGroupBranch

/-- the group moves through an owned phi (a loop that keeps it); the lender's roots and the mark
move with it -/
def okGroupPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.jump 1),
      blk [0] [{ dst := 5, edges := [(0, 0)] }]
        [ inst .call "group_end" none [] [5], inst .drop "drop" none [] [1] ] (.ret none) ]
    [],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .owned, [])])
#guard acc okGroupPhi

/-- a trap block reached with the group live on every edge: the meet checks its loans -/
def okTrapGroup : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard acc okTrapGroup

/-- K1: the lender is dropped before the join -/
def badLenderDropped : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .drop "drop" none [] [1],
                 inst .call "group_end" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, [])])
#guard rej badLenderDropped .j4 0 5 "loan-outlives-root"

/-- K1: the lender is changed (a push consumes it and may move its storage) before the join -/
def badLenderPushed : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .update "list_push" (some 5) [] [1, 9],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [5] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .owned, []), (9, .scalar, [])])
#guard rej badLenderPushed .j4 0 5 "loan-outlives-root"

/-- K1: the slot a lent view lives in is taken before the join -/
def badLenderSlotTaken : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "record_new" (some 1) [] [],
                 inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                 inst .construct "box_make" (some 3) [2, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 4) [] [3],
                 inst .call "submit" (some 5) [0] [4],
                 inst .project "record_get" (some 6) [1] [] (slot := some "f1"),
                 inst .call "group_end" none [] [0] ] .unreachable],
   cert [(0, .owned, []), (1, .owned, []), (2, .borrowed, [.val 1]), (3, .owned, []),
         (4, .owned, []), (5, .scalar, []), (6, .owned, [])])
#guard rej badLenderSlotTaken .j4 0 6 "loan-outlives-root"

/-- entry 41: an emptied constructor destroys what it consumes, so it may not consume a lender -/
def badEmptiedLender : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .construct "record_make" (some 5) [] [1] (slots := ["f0"]),
                 inst .project "record_get" (some 6) [5] [] (slot := some "f0"),
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [6] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .emptied, []), (6, .owned, [])])
#guard rej badEmptiedLender .j4 0 5 "loan-outlives-root"

/-- ... whereas a constructor with an owned result moves the lender, and the loans, into the
aggregate; the aggregate may not be dropped before the join either -/
def badLenderAggregateDropped : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .construct "record_make" (some 5) [] [1],
                 inst .drop "drop" none [] [5],
                 inst .call "group_end" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .owned, [])])
#guard rej badLenderAggregateDropped .j4 0 6 "loan-outlives-root"

/-- K2: a group that is never joined -/
def badGroupNotEnded : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, [])])
#guard rej badGroupNotEnded .j2 0 5 "ret-live"

/-- K2: a path that traps needs no join (`unreachable` ends the process, RC-TRAP-TEARDOWN-1) -/
def okGroupBranchTrap : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.ret none),
      blk [0] [] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard acc okGroupBranchTrap

/-- ... but a path that returns must join: the second arm drops the lender without it -/
def badGroupBranchRet : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.ret none),
      blk [0] [] [ inst .drop "drop" none [] [1] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard rej badGroupBranchRet .j4 2 0 "loan-outlives-root"

/-- K2: a handle (here: the group) is read after the join -/
def badSubmitAfterEnd : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .call "group_end" none [] [0],
                 inst .call "take" (some 5) [0, 4] [],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .owned, [])])
#guard rej badSubmitAfterEnd .j3 0 6 "read-usable"

/-- the join is a call that returns nothing: a drop does not wait for the tasks -/
def badGroupDropped : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .drop "drop" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, [])])
#guard rej badGroupDropped .j2 0 5 "group-join"

/-- ... nor does a call that returns a value, which may hand the group back -/
def badGroupJoinResult : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .call "group_end" (some 5) [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .scalar, [])])
#guard rej badGroupJoinResult .j2 0 5 "group-join"

/-- ... nor does a constructor that stores the group in an aggregate -/
def badGroupStored : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                 inst .construct "record_make" (some 3) [] [2],
                 inst .call "submit" (some 4) [0] [3],
                 inst .construct "record_make" (some 5) [] [0],
                 inst .drop "drop" none [] [5],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (5, .owned, [])])
#guard rej badGroupStored .j2 0 5 "group-join"

/-- J1: the group of a lend is owned -/
def badLendNotOwned : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 9] [] (lent := some 9),
                 inst .drop "drop" none [] [2],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    c9,
   cert [(1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badLendNotOwned .j1 0 1 "lend"

/-- J1: a lend reads exactly the lender and the group -/
def badLendThreeReads : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0, 9] [] (lent := some 0),
                 inst .drop "drop" none [] [2],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badLendThreeReads .j1 0 2 "lend"

/-- J1: the group is the second operand -/
def badLendOrder : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [0, 1] [] (lent := some 0),
                 inst .drop "drop" none [] [2],
                 inst .call "group_end" none [] [0],
                 inst .drop "drop" none [] [1] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, [])])
#guard rej badLendOrder .j1 0 2 "lend"

/-- J1: a lend consumes nothing -/
def badLendConsumes : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .construct "box_make" (some 2) [1, 0] [1] (lent := some 0),
                 inst .drop "drop" none [] [2],
                 inst .call "group_end" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, [])])
#guard rej badLendConsumes .j1 0 2 "lend"

/-- J1: `lent` appears only on a constructor -/
def badLentOnFresh : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "group_open" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [] (lent := some 0),
                 inst .drop "drop" none [] [1],
                 inst .call "group_end" none [] [0] ] (.ret none)],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rej badLentOnFresh .j1 0 1 "lend"

/-- a trap block reached with the group live on one edge only: the groups are never abandoned (its tasks read the
lent cells until the process ends), so the edges cannot be made to agree -/
def badTrapGroup : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard rej badTrapGroup .j2 1 0 "join-live b3"

/-- ... and listing the group is refused -/
def badTrapGroupAbandoned : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [],
                  inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0),
                  inst .construct "record_make" (some 3) [] [2],
                  inst .call "submit" (some 4) [0] [3] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [ inst .call "group_end" none [] [0], inst .drop "drop" none [] [1] ] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable (abandons := [(1, [0, 1])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (3, .owned, []), (4, .scalar, []),
         (9, .scalar, [])])
#guard rej badTrapGroupAbandoned .j2 1 0 "abandon-group"

/-- any owner that holds a loan (here an aggregate that holds a view of `%0`) is live on one edge only: the edges
disagree -/
def badTrapHolder : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]) ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .drop "drop" none [] [2]] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (9, .scalar, [])])
#guard rej badTrapHolder .j2 1 0 "join-live b3"

/-- ... unless the path that has it says it leaks it: the holder is abandoned, and its loan ends with it -/
def okTrapHolderAbandoned : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]) ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .drop "drop" none [] [2]] (.jump 3),
      blk [1, 2] [] [inst .call "call" none [9] []] .unreachable (abandons := [(1, [2])]) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (9, .scalar, [])])
#guard acc okTrapHolderAbandoned

/-- ... and then the loan is not looked at again: the root may be dropped in the region -/
def okTrapRootDroppedAfter : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]) ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .drop "drop" none [] [2]] (.jump 3),
      blk [1, 2] [] [inst .drop "drop" none [] [0]] .unreachable (abandons := [(1, [2])]) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (9, .scalar, [])])
#guard acc okTrapRootDroppedAfter

/-- ... while an owner that is abandoned is not usable, the loans it holds are those of a dead value, and the owner
it borrows from may then be abandoned in its turn: a view of an abandoned owner is not usable -/
def badAbandonedViewRead : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [] ] (.jump 1),
      blk [0] [] [inst .output "print" none [1] []] .unreachable (abandons := [(0, [0])]) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (9, .scalar, [])])
#guard rej badAbandonedViewRead .j4 1 0 "read-borrowed-usable"

/-- a re-read of a parameter in a trap block defines nothing new, so it does not keep the block out of
the region, even for an owned parameter the edges disagree about -/
def okTrapParam : Function × Certificate :=
  ({ (fn [(0, .owned)] .scalar []
      [ blk [] [] [] (.branch 9 1 2),
        blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
        blk [0] [] [] (.jump 3),
        blk [1, 2] [] [inst .parameter "param" (some 0) [] []] .unreachable (abandons := [(2, [0])]) ]
      c9) with pre := c9 },
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okTrapParam

/-- **Loans through an update (C3.8, assumption A13 narrowed to takes).** An instruction with an owned
result carries the loans of the owned values it consumes: the update below builds `%3` from the holder
`%2`, which holds a view of `%0`, so `%3` holds it too and `%0` may not be dropped while `%3` is live. -/
def badLoanLostThroughUpdate : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .update "list_push" (some 3) [] [2, 9],
                  inst .drop "drop" none [] [0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard rej badLoanLostThroughUpdate .j4 0 4 "loan-outlives-root"

/-- ... and the same with the list dropped first -/
def okLoanThroughUpdate : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .update "list_push" (some 3) [] [2, 9],
                  inst .drop "drop" none [] [3],
                  inst .drop "drop" none [] [0] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard acc okLoanThroughUpdate

/-- **An update that lends what it stores (RB2, collections of borrows).** A push into a collection of borrows reads, not
consumes, the borrowed element and lists it as a parent of the owned result, as a constructor that holds a view does: the
collection then holds a loan on the element's owner, so that owner outlives the collection's last use. -/
def okUpdateLendsStoredBorrow : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .fresh "list_new" (some 2) [] [],
                  inst .update "list_push" (some 3) [1] [2],
                  inst .drop "drop" none [] [3],
                  inst .drop "drop" none [] [0] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, []), (3, .owned, [.val 1]), (9, .scalar, [])])
#guard acc okUpdateLendsStoredBorrow

/-- ... and the element's owner dropped while the collection that holds the loan is live -/
def badUpdateLoanOutlivesRoot : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .fresh "list_new" (some 2) [] [],
                  inst .update "list_push" (some 3) [1] [2],
                  inst .drop "drop" none [] [0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, []), (3, .owned, [.val 1]), (9, .scalar, [])])
#guard rej badUpdateLoanOutlivesRoot .j4 0 4 "loan-outlives-root"

/-- A call that consumes a holder and returns an owned value carries the loans too -/
def badLoanLostThroughCall : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .call "call" (some 3) [] [2],
                  inst .drop "drop" none [] [0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard rej badLoanLostThroughCall .j4 0 4 "loan-outlives-root"

/-- ... and a holder consumed together with the owner it borrows from, by an instruction whose result
is owned, would hand a dangling view on: strict -/
def badHolderWithItsRoot : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .call "call" (some 3) [] [2, 0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard rej badHolderWithItsRoot .j4 0 3 "loan-outlives-root"

/-- **A take carries the loans of the aggregate it comes out of**, unless the exporter marks it `noloans`
(assumption A13, AXIOMS.md).  Here the part really does hold a view of `%0`, and `%0` is dropped while
the part is live: rejected. -/
def badTakeHoldsView : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .take "record_take" (some 3) [] [2],
                  inst .drop "drop" none [] [0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard rej badTakeHoldsView .j4 0 4 "loan-outlives-root"

/-- The `None` arm of the `copy` lowering: the take of an absent payload (the exporter says the result
cannot hold a view: `noloans`), then the owner is dropped while the result is live: accepted. -/
def okTakeOfAbsentPayload : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .take "record_take" (some 3) [] [2] (noLoans := true),
                  inst .drop "drop" none [] [0],
                  inst .drop "drop" none [] [3] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard acc okTakeOfAbsentPayload

/-- A take of a part that holds a view, the owner dropped after the part: accepted. -/
def okTakeHoldsViewDroppedFirst : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                  inst .view "list_view_of" (some 1) [0] [],
                  inst .construct "record_make" (some 2) [1] [] (views := [1]),
                  inst .take "record_take" (some 3) [] [2],
                  inst .drop "drop" none [] [3],
                  inst .drop "drop" none [] [0] ] (.ret none) ]
    c9,
   cert [(0, .owned, []), (1, .borrowed, [.val 0]), (2, .owned, [.val 1]), (3, .owned, []),
         (9, .scalar, [])])
#guard acc okTakeHoldsViewDroppedFirst

/-- a block with a lend is not part of the trap-only region (a region that traps submits no task):
it is checked like any other block, against the join of its edges -/
def okLendBeforeTrap : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .call "group_open" (some 0) [] [],
                  inst .fresh "list_new" (some 1) [] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [ inst .construct "box_make" (some 2) [1, 0] [] (lent := some 0) ] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard acc okLendBeforeTrap


/-! ## Trap regions (C9.1)

Every block is an ordinary block: the edges into it must agree about the live owners, the open takes and the
rest.  A path that leaks says so with an `abandon` line.  The examples below are the cases the trap meet of C3.8 was
written for. -/

/-- the value a take defines is live on one edge only: the edges disagree (J2) -/
def badTrapMeetTakeLater : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0")] (.jump 3),
      blk [1, 2] [] [inst .project "list_get" (some 2) [0, 9] [] (slot := some "e#0")] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badTrapMeetTakeLater .j2 1 0 "join-live b3"

/-- ... and when that value is abandoned the slot it took is open on one edge only: the join makes it a take guarded by
the branch test, which the second take in the trap block refuses (J8) -/
def badTrapMeetTakeLaterListed : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0")] (.jump 3),
      blk [1, 2] [] [inst .project "list_get" (some 2) [0, 9] [] (slot := some "e#0")] .unreachable
        (abandons := [(2, [1])]) ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badTrapMeetTakeLaterListed .j8 3 0 "take"

/-- ... whichever edge it is -/
def badTrapMeetTakeFirst : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0")] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [inst .project "list_get" (some 2) [0, 9] [] (slot := some "e#0")] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (9, .scalar, [])])
#guard rej badTrapMeetTakeFirst .j2 1 1 "join-live b3"

/-- the roots of the edges are united: a borrowed phi selecting a view of `%0` on one edge and of
`%1` on the other is rooted at both, so dropping `%1` in the trap block ends it -/
def badTrapMeetRoots : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [inst .view "list_view_of" (some 2) [0] []] (.jump 3),
      blk [0] [] [inst .view "list_view_of" (some 3) [1] []] (.jump 3),
      blk [1, 2] [{ dst := 4, edges := [(1, 2), (2, 3)] }]
        [ inst .drop "drop" none [] [1], inst .output "print" none [4] [] ] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .borrowed, [.val 0]), (3, .borrowed, [.val 1]),
         (4, .borrowed, [.val 0, .val 1]), (9, .scalar, [])])
#guard rej badTrapMeetRoots .j4 3 1 "read-borrowed-usable"

/-- ... whichever edge selects which view -/
def badTrapMeetRootsSwapped : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [inst .view "list_view_of" (some 2) [1] []] (.jump 3),
      blk [0] [] [inst .view "list_view_of" (some 3) [0] []] (.jump 3),
      blk [1, 2] [{ dst := 4, edges := [(1, 2), (2, 3)] }]
        [ inst .drop "drop" none [] [1], inst .output "print" none [4] [] ] .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .borrowed, [.val 1]), (3, .borrowed, [.val 0]),
         (4, .borrowed, [.val 0, .val 1]), (9, .scalar, [])])
#guard rej badTrapMeetRootsSwapped .j4 3 1 "read-borrowed-usable"

/-- a closing update is not part of a trap region: its check compares the open takes with its
`released` mark, and a union of open takes does not say which edge it is checked on.  The take is
open on one edge only, so the block is checked like any other, against the join -/
def badTrapClosing : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 4) [] [] ]
        (.branch 9 1 2),
      blk [0] [] [] (.jump 3),
      blk [0] [] [ inst .project "list_get" (some 1) [0, 9] [] (slot := some "e#0"),
                   inst .drop "drop" none [] [1] ] (.jump 3),
      blk [1, 2] []
        [ inst .update "list_set" (some 2) [9] [0, 4] (slot := some "e#0") (released := some "-") ]
        .unreachable ]
    c9,
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, []), (4, .owned, []), (9, .scalar, [])])
#guard rej badTrapClosing .j8 3 0 "close"

/-- a block that branches to trap blocks only is not part of a trap region here (the region is
chains of jumps): it is checked like any other block, so the edges into it must agree -/
def badTrapBranchChain : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.branch 9 4 5),
      blk [3] [] [] .unreachable,
      blk [3] [] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard rej badTrapBranchChain .j2 1 1 "join-live b3"

/-- a chain block may not jump to a block with a live phi: the chain is checked like any other
blocks, so the edges into it must agree -/
def badTrapChainPhi : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [ inst .fresh "list_new" (some 0) [] [] ] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.jump 4),
      blk [3] [{ dst := 5, edges := [(3, 9)] }] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (5, .scalar, []), (9, .scalar, [])])
#guard rej badTrapChainPhi .j2 1 1 "join-live b3"

/-- the verdict is a rejection of the whole block by judgment `j` (no instruction), for the stated sub-check -/
def rejBlk (p : Function × Certificate) (j : J) (b : Nat) (why : String) : Bool :=
  verdict p.1 p.2 == .reject { j := j, blk := some b, idx := none, why := why }

/-- J1 `abandon-shape`: a line names a block that is not a predecessor -/
def badAbandonNotPred : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0] [] [] .unreachable (abandons := [(7, [0])]) ]
    [],
   cert [(0, .owned, [])])
#guard rejBlk badAbandonNotPred .j1 1 "abandon-shape"

/-- ... a predecessor twice -/
def badAbandonRepeated : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0] [] [] .unreachable (abandons := [(0, [0]), (0, [0])]) ]
    [],
   cert [(0, .owned, [])])
#guard rejBlk badAbandonRepeated .j1 1 "abandon-shape"

/-- ... or values that are not strictly ascending -/
def badAbandonUnsorted : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] [], inst .fresh "list_new" (some 1) [] []] (.jump 1),
      blk [0] [] [] .unreachable (abandons := [(0, [1, 0])]) ]
    [],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rejBlk badAbandonUnsorted .j1 1 "abandon-shape"

/-- J2 `abandon-region`: only a block every path from which ends in a trap may be entered with owners abandoned -/
def badAbandonOutsideRegion : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0] [] [] (.ret none) (abandons := [(0, [0])]) ]
    [],
   cert [(0, .owned, [])])
#guard rej badAbandonOutsideRegion .j2 0 1 "abandon-region"

/-- J2 `abandon-live`: the value must be an owner live on the edge -/
def badAbandonNotLive : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] [], inst .drop "drop" none [] [0]] (.jump 1),
      blk [0] [] [] .unreachable (abandons := [(0, [0])]) ]
    [],
   cert [(0, .owned, [])])
#guard rej badAbandonNotLive .j2 0 2 "abandon-live"

/-- ... a scalar is not an owner -/
def badAbandonScalar : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [] (.jump 1),
      blk [0] [] [] .unreachable (abandons := [(0, [9])]) ]
    c9,
   cert [(9, .scalar, [])])
#guard rej badAbandonScalar .j2 0 0 "abandon-live"

/-- the abandon applies before the phis take their operands: a phi that takes an abandoned owner reads a value that
is not live -/
def badAbandonPhiOperand : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.jump 1),
      blk [0] [{ dst := 1, edges := [(0, 0)] }] [] .unreachable (abandons := [(0, [0])]) ]
    [],
   cert [(0, .owned, []), (1, .owned, [])])
#guard rej badAbandonPhiOperand .j2 0 1 "phi-consume-live"

/-- a block that branches to trap blocks only is in the region (the least fixpoint, not chains of jumps): the
edges into it say what they leak, and the trap blocks it reaches then agree -/
def okAbandonBranchChain : Function × Certificate :=
  (fn [] .scalar []
    [ blk [] [] [inst .fresh "list_new" (some 0) [] []] (.branch 9 1 2),
      blk [0] [] [inst .drop "drop" none [] [0]] (.jump 3),
      blk [0] [] [] (.jump 3),
      blk [1, 2] [] [] (.branch 9 4 5) (abandons := [(2, [0])]),
      blk [3] [] [] .unreachable,
      blk [3] [] [] .unreachable ]
    c9,
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okAbandonBranchChain

-- ... and without the line the edges into it disagree (J2, at the join)
#guard rej badTrapBranchChain .j2 1 1 "join-live b3"

/-! ## Calls name their callee (C9.2, design entry 57) -/

/-- A program entry. -/
def progEntry (n : Nat) (name : String) (params : List ParamTok) (result : ResTok) (from_ : List Nat := []) :
    CalleeEntry :=
  { id := n, name := name, kind := .program, params := params, result := result, from_ := from_ }

/-- a call to a program function that takes `%0` and reads `%1` and returns an owner: the entry says so -/
def okProgramCall : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .fresh "list_new" (some 1) [] [],
                 inst .call "call" (some 2) [1] [0] (entry := some 0),
                 inst .drop "drop" none [] [1],
                 inst .drop "drop" none [] [2] ] (.ret none)]
    [] [progEntry 0 "g" [.take, .read] .owned],
   cert [(0, .owned, []), (1, .owned, []), (2, .owned, [])])
#guard acc okProgramCall

/-- J1 `call-entry`: the entry the line names is not in the table -/
def badCallEntry : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" none [] [0] (entry := some 3) ] (.ret none)]
    [] [progEntry 0 "g" [.take] .scalar],
   cert [(0, .owned, [])])
#guard rej badCallEntry .j1 0 1 "call-entry"

/-- ... or a `call` names an indirect entry -/
def badCallKind : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" none [] [0] (entry := some 0) ] (.ret none)]
    [] [{ id := 0, name := "-", kind := .indirect, params := [.take], result := .scalar, from_ := [] }],
   cert [(0, .owned, [])])
#guard rej badCallKind .j1 0 1 "call-entry"

/-- J1 `call-arity`: the call consumes nothing, the callee takes a parameter -/
def badCallArity : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" none [0] [] (entry := some 0),
                 inst .drop "drop" none [] [0] ] (.ret none)]
    [] [progEntry 0 "g" [.take] .scalar],
   cert [(0, .owned, [])])
#guard rej badCallArity .j1 0 1 "call-arity"

/-- J1 `call-scalar`: a parameter whose value is a scalar receives an owner -/
def badCallScalar : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" none [0] [] (entry := some 0),
                 inst .drop "drop" none [] [0] ] (.ret none)]
    [] [progEntry 0 "g" [.readScalar] .scalar],
   cert [(0, .owned, [])])
#guard rej badCallScalar .j1 0 1 "call-scalar"

/-- ... a taking parameter whose value is a scalar takes a scalar: the argument is in `consumes` -/
def okCallTakeScalar : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [9] (entry := some 0) ] (.ret none)]
    c9 [progEntry 0 "g" [.takeScalar] .scalar],
   cert [(9, .scalar, [])])
#guard acc okCallTakeScalar

/-- J1 `call-result`: the value is an owner, the callee returns a scalar -/
def badCallResultOwned : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" (some 0) [] [] (entry := some 0),
                 inst .drop "drop" none [] [0] ] (.ret none)]
    [] [progEntry 0 "g" [] .scalar],
   cert [(0, .owned, [])])
#guard rej badCallResultOwned .j1 0 0 "call-result"

/-- ... a call without a value (a unit call) to a callee that returns an owner would drop it -/
def badCallVoidOwner : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [] (entry := some 0) ] (.ret none)]
    [] [progEntry 0 "g" [] .owned],
   cert [])
#guard rej badCallVoidOwner .j1 0 0 "call-result"

/-- a call without a value to a unit function is fine (the corollary covers it since C9.2) -/
def okCallVoid : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [] (entry := some 0) ] (.ret none)]
    [] [progEntry 0 "g" [] .scalar],
   cert [])
#guard acc okCallVoid

/-- J1 `call-from`: a borrowed value lists as parents the argument at each position of the callee's borrow contract -/
def okCallFrom : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [0] [] (entry := some 0) (fromVals := [0]),
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [0] ] (.ret none)]
    [] [progEntry 0 "g" [.read] .borrowed [0]],
   cert [(0, .owned, []), (1, .borrowed, [.val 0])])
#guard acc okCallFrom

def badCallFrom : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call" (some 1) [0] [] (entry := some 0) (fromVals := [0]),
                 inst .output "print" none [1] [],
                 inst .drop "drop" none [] [0] ] (.ret none)]
    [] [progEntry 0 "g" [.read] .borrowed [0]],
   cert [(0, .owned, []), (1, .borrowed, [])])
#guard rej badCallFrom .j1 0 1 "call-from"

/-- J1 `callee-table`, at the signature: the ids must be 0, 1, 2, ... -/
def badCalleeTableIds : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [] (entry := some 0) ] (.ret none)]
    [] [progEntry 1 "g" [] .scalar],
   cert [])
#guard rejFn badCalleeTableIds .j1 "callee-table"

/-- ... the name is `-` exactly for an indirect entry -/
def badCalleeTableName : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [] (entry := some 0) ] (.ret none)]
    [] [progEntry 0 "-" [] .scalar],
   cert [])
#guard rejFn badCalleeTableName .j1 "callee-table"

/-- ... and a position of the borrow contract is a parameter -/
def badCalleeTableFrom : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .call "call" none [] [] (entry := some 0) ] (.ret none)]
    [] [progEntry 0 "g" [] .scalar [2]],
   cert [])
#guard rejFn badCalleeTableFrom .j1 "callee-table"

/-- a call through a function value: the first read is the function value, the entry is the function type's -/
def okIndirectCall : Function × Certificate :=
  (fn [] .scalar []
    [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                 inst .call "call_indirect" none [9] [0] (entry := some 0) ] (.ret none)]
    c9 [{ id := 0, name := "-", kind := .indirect, params := [.take], result := .scalar, from_ := [] }],
   cert [(0, .owned, []), (9, .scalar, [])])
#guard acc okIndirectCall

end Tests
end Own
