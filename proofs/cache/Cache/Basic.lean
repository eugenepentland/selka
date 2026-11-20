/-!
# Steps, what they read, and the clean build

A *step* is a deterministic function of what it reads. What it reads comes through the inputs handle
(`src/core/inputs.zig`): an input (a file, a directory listing, a variable, ...) or the output of another step.
The model makes this structural: a step is a `Task`, a tree whose only effects are `input i` (read input `i`, continue
with what was seen) and `step k` (demand step `k`, continue with its output). A task is a Lean function, so it
is deterministic and reads nothing but through those two nodes **by construction**. That the Zig steps are
refinements of such tasks is an assumption about the Zig code (`AXIOMS.md`, D1 and D2); the model cannot state it.

The *clean build* of a world is the outputs `o : K → C` that satisfy every step's equation: `o k` is the result of
running step `k` against the world and against `o`. Steps are acyclic, which `Task.Below` states with a rank.
-/

namespace Cache

/-- One thing a run of a task read: an input and the value it showed (`none` for an absent file), or a step and
its output. This is what the handle writes down. -/
inductive Seen (I K C : Type) where
  | inp : I → Option C → Seen I K C
  | stp : K → C → Seen I K C

/-- A step: a tree of reads. `input i f` reads input `i` and continues with `f` of what it showed; `step k f` demands
step `k` and continues with `f` of its output; `done c` is the step's output. -/
inductive Task (I K C : Type) where
  | done : C → Task I K C
  | input : I → (Option C → Task I K C) → Task I K C
  | step : K → (C → Task I K C) → Task I K C

variable {I K C : Type}

/-- Whether a sighting is what the world `w` and the step outputs `o` say. -/
def Seen.holds (w : I → Option C) (o : K → C) : Seen I K C → Prop
  | .inp i v => w i = v
  | .stp k v => o k = v

/-- Run a task against a static world and the outputs of the steps it demands: its output, and everything it read
in order. -/
def Task.run (w : I → Option C) (o : K → C) : Task I K C → C × List (Seen I K C)
  | .done c => (c, [])
  | .input i f =>
    let r := (f (w i)).run w o
    (r.1, .inp i (w i) :: r.2)
  | .step k f =>
    let r := (f (o k)).run w o
    (r.1, .stp k (o k) :: r.2)

/-- A run's own sightings hold in the world it ran against. -/
theorem Task.run_holds (w : I → Option C) (o : K → C) :
    ∀ t : Task I K C, ∀ e ∈ (t.run w o).2, e.holds w o := by
  intro t
  induction t with
  | done c => intro e he; simp [Task.run] at he
  | input i f ih =>
    intro e he
    simp only [Task.run, List.mem_cons] at he
    rcases he with rfl | he
    · rfl
    · exact ih _ e he
  | step k f ih =>
    intro e he
    simp only [Task.run, List.mem_cons] at he
    rcases he with rfl | he
    · rfl
    · exact ih _ e he

/-- **A step is a function of what it read.** If a second world and second outputs show everything the run in the
first showed, the run in the second is the same run: same output, same reads. -/
theorem Task.run_congr (w : I → Option C) (o : K → C) (w' : I → Option C) (o' : K → C) :
    ∀ t : Task I K C, (∀ e ∈ (t.run w o).2, e.holds w' o') → t.run w' o' = t.run w o := by
  intro t
  induction t with
  | done c => intro _; rfl
  | input i f ih =>
    intro h
    have hi : w' i = w i := h (.inp i (w i)) (by simp [Task.run])
    have h2 : ∀ e ∈ ((f (w i)).run w o).2, e.holds w' o' :=
      fun e he => h e (by simp [Task.run, he])
    simp only [Task.run, hi]
    rw [ih (w i) h2]
  | step k f ih =>
    intro h
    have hk : o' k = o k := h (.stp k (o k)) (by simp [Task.run])
    have h2 : ∀ e ∈ ((f (o k)).run w o).2, e.holds w' o' :=
      fun e he => h e (by simp [Task.run, he])
    simp only [Task.run, hk]
    rw [ih (o k) h2]

/-- A task whose every demand is of a step of rank below `r`, whatever the values it has seen. -/
inductive Task.Below (rank : K → Nat) (r : Nat) : Task I K C → Prop where
  | done (c : C) : Task.Below rank r (.done c)
  | input (i : I) (f : Option C → Task I K C) :
      (∀ v, Task.Below rank r (f v)) → Task.Below rank r (.input i f)
  | step (k : K) (f : C → Task I K C) :
      rank k < r → (∀ c, Task.Below rank r (f c)) → Task.Below rank r (.step k f)

/-- A rank bound is a bound for every larger rank. -/
theorem Task.Below.mono {rank : K → Nat} {r r' : Nat} (h : r ≤ r') {t : Task I K C}
    (b : Task.Below rank r t) : Task.Below rank r' t := by
  induction b with
  | done c => exact .done c
  | input i f _ ih => exact .input i f ih
  | step k f hk _ ih => exact .step k f (Nat.lt_of_lt_of_le hk h) ih

/-- The steps a run of a task below `r` demanded are all below `r`. -/
theorem Task.Below.trace {rank : K → Nat} {r : Nat} (w : I → Option C) (o : K → C) {t : Task I K C}
    (b : Task.Below rank r t) : ∀ e ∈ (t.run w o).2, ∀ k v, e = .stp k v → rank k < r := by
  induction b with
  | done c => intro e he; simp [Task.run] at he
  | input i f _ ih =>
    intro e he k v hev
    simp only [Task.run, List.mem_cons] at he
    rcases he with rfl | he
    · cases hev
    · exact ih _ e he k v hev
  | step k' f hk _ ih =>
    intro e he k v hev
    simp only [Task.run, List.mem_cons] at he
    rcases he with rfl | he
    · cases hev; exact hk
    · exact ih _ e he k v hev


/-- `o` is the **clean build** of the world `w`: every step's output is what running the step against `w` and against
`o` gives. -/
def IsClean (task : K → Task I K C) (w : I → Option C) (o : K → C) : Prop :=
  ∀ k, o k = ((task k).run w o).1

/-- The clean build is unique: two solutions of the step equations agree, by induction on rank. -/
theorem IsClean.unique {task : K → Task I K C} {rank : K → Nat} (hb : ∀ k, (task k).Below rank (rank k))
    {w : I → Option C} {o₁ o₂ : K → C} (h₁ : IsClean task w o₁) (h₂ : IsClean task w o₂) : o₁ = o₂ := by
  have key : ∀ n, ∀ k, rank k < n → o₁ k = o₂ k := by
    intro n
    induction n with
    | zero => intro k hk; exact absurd hk (Nat.not_lt_zero _)
    | succ n ih =>
      intro k hk
      have hcongr : (task k).run w o₂ = (task k).run w o₁ := by
        apply Task.run_congr
        intro e he
        have hh := Task.run_holds w o₁ (task k) e he
        cases e with
        | inp i v => exact hh
        | stp k' v =>
          have hr : rank k' < rank k := (hb k).trace w o₁ _ he k' v rfl
          have := ih k' (Nat.lt_of_lt_of_le hr (Nat.le_of_lt_succ hk))
          show o₂ k' = v
          rw [← this]; exact hh
      rw [h₁ k, h₂ k, hcongr]
  funext k
  exact key (rank k + 1) k (Nat.lt_succ_self _)

/-- A clean build exists (the step equations are solvable when steps are acyclic and `C` is inhabited): the
theorem about builds is not vacuous. -/
theorem IsClean.exists [Inhabited C] {task : K → Task I K C} {rank : K → Nat}
    (hb : ∀ k, (task k).Below rank (rank k)) (w : I → Option C) : ∃ o, IsClean task w o := by
  let A : Nat → K → C := fun n => Nat.rec (fun _ => default) (fun _ a k => ((task k).run w a).1) n
  have hA0 : ∀ k, A 0 k = default := fun _ => rfl
  have hAs : ∀ n k, A (n + 1) k = ((task k).run w (A n)).1 := fun _ _ => rfl
  have stable : ∀ n, ∀ k, rank k < n → ∀ m, n ≤ m → A m k = A n k := by
    intro n
    induction n with
    | zero => intro k hk; exact absurd hk (Nat.not_lt_zero _)
    | succ n ih =>
      intro k hk m hm
      obtain ⟨m', rfl⟩ : ∃ m', m = m' + 1 := ⟨m - 1, by omega⟩
      have hcongr : (task k).run w (A n) = (task k).run w (A m') := by
        apply Task.run_congr
        intro e he
        have hh := Task.run_holds w (A m') (task k) e he
        cases e with
        | inp i v => exact hh
        | stp k' v =>
          have hr : rank k' < rank k := (hb k).trace w (A m') _ he k' v rfl
          have := ih k' (Nat.lt_of_lt_of_le hr (Nat.le_of_lt_succ hk)) m' (by omega)
          show A n k' = v
          rw [← this]; exact hh
      rw [hAs, hAs, ← hcongr]
  refine ⟨fun k => A (rank k + 1) k, ?_⟩
  intro k
  show A (rank k + 1) k = _
  rw [hAs]
  apply congrArg
  refine (Task.run_congr w (A (rank k)) w (fun k => A (rank k + 1) k) (task k) ?_).symm
  intro e he
  have hh := Task.run_holds w (A (rank k)) (task k) e he
  cases e with
  | inp i v => exact hh
  | stp k' v =>
    have hr : rank k' < rank k := (hb k).trace w (A (rank k)) _ he k' v rfl
    have := stable (rank k' + 1) k' (Nat.lt_succ_self _) (rank k) hr
    show A (rank k' + 1) k' = v
    rw [← this]; exact hh

end Cache
