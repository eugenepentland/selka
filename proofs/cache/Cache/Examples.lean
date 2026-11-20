import Cache.Theorem

/-!
# Examples: the algorithm runs, and the hypotheses are not decorative

A two-step system. `parse` reads input `a` and returns its tens (`a / 10`); `emit` demands `parse`, reads input `b`
and returns `parse + b`. The digest of a value is the value plus one (absent is 0), so it is injective. Editing `a`
within a decade changes `parse`'s input digest but not its output digest, so `emit`'s record stays valid: early
cutoff.

The last two examples break a hypothesis of `warm_eq_clean` on purpose and the algorithm returns a stale output:
a stat tuple that does not change when the bytes do (E2), and a digest that does not separate contents (D0).
-/

namespace Cache.Examples

open Cache

/-- `parse` is step 0, `emit` is step 1. -/
def steps : Nat → Task String Nat Nat
  | 0 => .input "a" fun v => .done (v.getD 0 / 10)
  | _ => .step 0 fun p => .input "b" fun v => .done (p + v.getD 0)

def sysOf (dig : Option Nat → Nat) : Sys String Nat Nat Nat Nat where
  task := steps
  rank k := min k 1
  below k := by
    cases k with
    | zero => exact .input _ _ fun _ => .done _
    | succ k => exact .step _ _ (by simp) fun _ => .input _ _ fun _ => .done _
  dig := dig

/-- Digest: injective. -/
def good : Sys String Nat Nat Nat Nat := sysOf fun | none => 0 | some c => c + 1

/-- A world: values of `a` and `b`, the stat tuple of `a` (any change of bytes changes it), and every tuple settled. -/
def world (a b : Nat) : World String Nat Nat where
  val i := if i = "a" then some a else some b
  stat i := if i = "a" then a else b
  settled _ := true

def empty : Store String Nat Nat Nat Nat := fun _ => none

/-- Build `emit` in the given worlds one after another; the outputs. -/
def session (sys : Sys String Nat Nat Nat Nat) (ws : List (World String Nat Nat)) : List (Option Nat) :=
  (ws.foldl (fun (acc : Store String Nat Nat Nat Nat × List (Option Nat)) w =>
    match sys.build w 1 acc.1 with
    | some (v, σ') => (σ', acc.2 ++ [some v])
    | none => (acc.1, acc.2 ++ [none])) (empty, [])).2

-- clean builds: emit = a/10 + b
#guard session good [world 17 5] == [some 6]
-- warm builds equal the clean ones, in all four ways an input can change (or not)
#guard session good [world 17 5, world 17 5, world 12 5, world 12 6, world 31 6, world 17 5] ==
  [some 6, some 6, some 6, some 7, some 9, some 6]

/-- Stat tuple of `a` constant while its bytes change: the fast path trusts it. -/
def staleWorld (a b : Nat) : World String Nat Nat where
  val i := if i = "a" then some a else some b
  stat _ := 7
  settled _ := true

-- E2 broken: the second world's `a` is 31 but the unchanged stat tuple says 17 still stands: stale (clean is 8)
#guard session good [staleWorld 17 5, staleWorld 31 5] == [some 6, some 6]
#guard session good [world 17 5, world 31 5] == [some 6, some 8]

/-- A digest that does not separate contents. -/
def collide : Sys String Nat Nat Nat Nat := sysOf fun _ => 0

-- D0 broken: with `a` and `a'` sharing a digest the record is served: stale (clean is 8)
#guard session collide [world 17 5, world 31 5] == [some 6, some 6]

end Cache.Examples
