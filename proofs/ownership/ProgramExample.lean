import Program
import CheckerTests

/-!
# The corollary applied to a program with an `emptied` call and a unit call (C9.4, C9.2)

A three-function program.  `callee` takes a list and returns it (the write-back record of a function with a `mut`
parameter, here without any other part); `unit` takes nothing and returns nothing; `main` calls `callee`, takes the
returned list out of the `emptied` call result at once and drops it, and calls `unit`, whose call line has no value.

Before C9.4 the first call was outside the corollary (`CallWf.noEmptied`); before C9.2 the second was too (`CallWf.dst`,
a destination, was an unstated hypothesis that a unit call does not meet), and `CallWf` was assumed for every call.  Now
`ProgWf` is `check` for every function and the link of the callee tables to the functions they name, and `runs_sound` and
`main_no_leak` apply.
-/

namespace Own
namespace Ex

open Own.Tests

/-- The call of `callee`: `%0` is consumed, the result `%1` is an `emptied` record whose field `f1` is taken. -/
def emptiedCall : Inst := inst .call "call" (some 1) [] [0] (slots := ["f1"]) (entry := some 0)

/-- The call of `unit`: no value. -/
def unitCall : Inst := inst .call "call" none [] [] (entry := some 1)

/-- `main`: build a list, pass it to `callee`, take it back out of the returned record, drop it, call `unit`. -/
def mainEmptied : Function × Certificate :=
  ({ fnRaw [] .scalar []
      [blk [] [] [ inst .fresh "list_new" (some 0) [] [],
                   emptiedCall,
                   inst .project "record_get" (some 2) [1] [] (slot := some "f1"),
                   inst .drop "drop" none [] [2],
                   unitCall ] (.ret none)]
      [] [progEntry 0 "callee" [.take] .owned, progEntry 1 "unit" [] .scalar] with name := "main" },
   cert [(0, .owned, []), (1, .emptied, []), (2, .owned, [])])

/-- `callee` returns its parameter. -/
def calleeOwned : Function × Certificate := ({ okOwnedReturn.1 with name := "callee" }, okOwnedReturn.2)

/-- `unit` does nothing. -/
def unitFn : Function × Certificate :=
  ({ (fnRaw [] .scalar [] [blk [] [] [] (.ret none)]) with name := "unit" }, cert [])

/-- The program. -/
def emptiedProg : Program := [mainEmptied, calleeOwned, unitFn]

-- All three functions pass `check` (by evaluation: the kernel cannot reduce the checker's hash maps).
#guard emptiedProg.all fun fc => check fc.1 fc.2

/-- The callee tables link: `callee` and `unit` are functions of the program, and their headers are what the entries say. -/
theorem emptiedProg_link : linkOk (emptiedProg.map LinkFn.of) = true := by decide +kernel

/-- The program is well formed, given that its functions check (`#guard` above). -/
theorem emptiedProg_wf (hchk : ∀ fc ∈ emptiedProg, check fc.1 fc.2 = true) : ProgWf emptiedProg :=
  ⟨hchk, emptiedProg_link⟩

/-- So every run of `main` is safe, whatever the callees do with the `emptied` result. -/
theorem emptiedProg_sound (hchk : ∀ fc ∈ emptiedProg, check fc.1 fc.2 = true) :
    ∀ d : Nat, CalleesOk emptiedProg d :=
  runs_sound (emptiedProg_wf hchk)

/-- ... and `main`, started on an empty heap, leaks nothing when it returns. -/
theorem emptiedProg_main_no_leak (hchk : ∀ fc ∈ emptiedProg, check fc.1 fc.2 = true)
    (args : Nat → Val) (pend : Addr → String → Bool)
    (hpre : Pre mainEmptied.1 args (fun _ => .unused) pend)
    (hsc : ScalarArgs (mkCC mainEmptied.1 mainEmptied.2) args) {d : Nat} {ds : DState} {v : Val}
    (hr : RunsAt emptiedProg d 0 args (fun _ => .unused) pend (.ret ds v)) :
    ∀ x t, ds.heap x ≠ .live t :=
  main_no_leak (emptiedProg_wf hchk) (g := 0) (fc := mainEmptied) rfl args pend hpre hsc rfl hr

end Ex
end Own

#print axioms Own.Ex.emptiedProg_link
#print axioms Own.Ex.emptiedProg_main_no_leak
