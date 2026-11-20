import Cache.Basic

/-!
# A torn handle writes no record

The handle writes a step's record as the step reads (`Handle.record` in `src/core/inputs.zig`). The world can change
while a step runs: the step may read one path twice and see different bytes. The handle notices (`torn`) and
`seal` returns nothing, so no record is stored.

`Task.runT` runs a task against a world that changes between reads: the `n`-th input read shows `ws n`. A trace is
*consistent* when no input is seen with two values (no tear). `consistent_run` says a consistent run is a run in a
single static world: the world that shows each input what the step saw. Hence the record of a consistent run is a
record `recordOf` of some static world, which is what `Faithful` asks of a record, and a torn run's record is never
stored, so a build under concurrent edits can only fail to cache, never cache a state that never existed.
-/

namespace Cache

variable {I K C : Type}

/-- Run a task against a world that changes between reads: the `n`-th input read shows `ws n`. The step outputs `o`
do not change. -/
def Task.runT (ws : Nat → I → Option C) (o : K → C) : Task I K C → Nat → C × List (Seen I K C)
  | .done c, _ => (c, [])
  | .input i f, n =>
    let r := (f (ws n i)).runT ws o (n + 1)
    (r.1, .inp i (ws n i) :: r.2)
  | .step k f, n =>
    let r := (f (o k)).runT ws o n
    (r.1, .stp k (o k) :: r.2)

/-- A trace with no tear: no input is seen with two values. -/
def Consistent (tr : List (Seen I K C)) : Prop :=
  ∀ i v₁ v₂, Seen.inp (K := K) i v₁ ∈ tr → Seen.inp (K := K) i v₂ ∈ tr → v₁ = v₂

theorem Consistent.tail {e : Seen I K C} {tr : List (Seen I K C)} (h : Consistent (e :: tr)) : Consistent tr :=
  fun i v₁ v₂ h1 h2 => h i v₁ v₂ (List.mem_cons_of_mem _ h1) (List.mem_cons_of_mem _ h2)

/-- **A consistent run in a changing world is a run in one static world.** -/
theorem consistent_run [DecidableEq I] (ws : Nat → I → Option C) (o : K → C) :
    ∀ (t : Task I K C) (n : Nat), Consistent (t.runT ws o n).2 → ∃ w : I → Option C, t.run w o = t.runT ws o n := by
  intro t
  induction t with
  | done c => intro n _; exact ⟨fun _ => none, rfl⟩
  | step k f ih =>
    intro n hc
    obtain ⟨w, hw⟩ := ih (o k) n hc.tail
    exact ⟨w, by simp only [Task.run, Task.runT, hw]⟩
  | input i f ih =>
    intro n hc
    obtain ⟨w', hw'⟩ := ih (ws n i) (n + 1) hc.tail
    refine ⟨fun j => if j = i then ws n i else w' j, ?_⟩
    have hrun : (f (ws n i)).run (fun j => if j = i then ws n i else w' j) o = (f (ws n i)).run w' o := by
      apply Task.run_congr
      intro e he
      have hh := Task.run_holds w' o (f (ws n i)) e he
      cases e with
      | stp k v => exact hh
      | inp j v =>
        show (if j = i then ws n i else w' j) = v
        by_cases hji : j = i
        · subst hji
          simp only [ite_true]
          have hmem : Seen.inp (K := K) j v ∈ ((f (ws n j)).runT ws o (n + 1)).2 := by
            rw [← hw']; exact he
          exact hc j _ _ (by simp [Task.runT]) (by simp [Task.runT, hmem])
        · simp only [hji, ite_false]
          exact hh
    simp only [Task.run, Task.runT, ite_true, hrun, hw']

end Cache
