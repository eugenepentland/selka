import Cache.Build

/-!
# The theorem: a warm build equals the clean build

`build_correct` is the induction on fuel. `warm_eq_clean` is the statement for a user: with a store whose records are
all faithful, building any step against a world of the history returns the step's output in the clean build of that
world, and the store stays faithful. `cold_eq_clean` is the special case of the empty store.

The assumptions, each a hypothesis of the theorem and none a Lean axiom (`AXIOMS.md`):

* `hcol` (D0): the digest separates the contents the history shows;
* `hst` (E2): an unchanged settled stat tuple stands for unchanged bytes;
* the steps are `Task`s (D1 and D2, true of the model by construction): a step reads only through the handle and is
  a function of what it read.
-/

set_option linter.unusedSectionVars false

namespace Cache

variable {I K C D S : Type} [DecidableEq K] [DecidableEq D] [DecidableEq S]
variable {sys : Sys I K C D S}

/-- A builder that, for steps of rank below `n`, returns the clean output and keeps the store faithful. -/
def BSpec (H : World I C S → Prop) (o : K → C) (n : Nat) (b : Builder I K C D S) : Prop :=
  ∀ k, sys.rank k < n → ∀ σ, Faithful sys H σ →
    ∃ v σ', b k σ = some (v, σ') ∧ v = o k ∧ Faithful sys H σ'

/-- Running a task against the live world with a good builder gives the task's run, and a faithful store. -/
theorem exec_spec {H : World I C S → Prop} {w : World I C S} {o : K → C} {n : Nat} {b : Builder I K C D S}
    (hb : BSpec (sys := sys) H o n b) :
    ∀ t : Task I K C, t.Below sys.rank n → ∀ σ, Faithful sys H σ →
      ∃ σ', Sys.exec sys w b t σ =
          some ((t.run w.val o).1, (t.run w.val o).2.map (sys.depOf w), σ') ∧ Faithful sys H σ' := by
  intro t
  induction t with
  | done c =>
    intro _ σ hσ
    exact ⟨σ, by simp [Sys.exec, Task.run], hσ⟩
  | input i f ih =>
    intro hbel σ hσ
    cases hbel with
    | input _ _ hf =>
      obtain ⟨σ', he, hσ'⟩ := ih (w.val i) (hf _) σ hσ
      refine ⟨σ', ?_, hσ'⟩
      simp only [Sys.exec, he, Task.run, List.map_cons]
  | step k f ih =>
    intro hbel σ hσ
    cases hbel with
    | step _ _ hk hf =>
      obtain ⟨v, σ1, hbk, hv, hσ1⟩ := hb k hk σ hσ
      subst hv
      obtain ⟨σ2, he, hσ2⟩ := ih (o k) (hf _) σ1 hσ1
      refine ⟨σ2, ?_, hσ2⟩
      simp only [Sys.exec, hbk, he, Task.run, List.map_cons]

/-- Verifying a record made in `w₀` against the live world `w`: if it verifies, every sighting of the recorded run
holds in the live world and the live clean outputs. -/
theorem check_spec {H : World I C S → Prop} {w₀ w : World I C S} {o₀ o : K → C} {n : Nat}
    {b : Builder I K C D S} (hb : BSpec (sys := sys) H o n b) (hcol : CollisionFree sys H)
    (hw : H w) (ho : IsClean sys.task w.val o) (h₀ : H w₀) (ho₀ : IsClean sys.task w₀.val o₀)
    (hst : Stable w₀ w) :
    ∀ tr : List (Seen I K C), (∀ e ∈ tr, e.holds w₀.val o₀) →
      (∀ e ∈ tr, ∀ k v, e = .stp k v → sys.rank k < n) → ∀ σ, Faithful sys H σ →
      ∃ ok σ', Sys.check sys w b (tr.map (sys.depOf w₀)) σ = some (ok, σ') ∧
        (ok = true → ∀ e ∈ tr, e.holds w.val o) ∧ Faithful sys H σ' := by
  intro tr
  induction tr with
  | nil =>
    intro _ _ σ hσ
    exact ⟨true, σ, by simp [Sys.check], by simp, hσ⟩
  | cons e rest ih =>
    intro hh hr σ hσ
    have hh' : ∀ e' ∈ rest, e'.holds w₀.val o₀ := fun e' he' => hh e' (List.mem_cons_of_mem _ he')
    have hr' : ∀ e' ∈ rest, ∀ k v, e' = .stp k v → sys.rank k < n :=
      fun e' he' => hr e' (List.mem_cons_of_mem _ he')
    have hhe : e.holds w₀.val o₀ := hh e (List.mem_cons_self ..)
    cases e with
    | inp i v =>
      have hv : w₀.val i = v := hhe
      subst hv
      by_cases hok : sys.inpOk w i (sys.dig (w₀.val i)) (if w₀.settled i then some (w₀.stat i) else none) = true
      · have hwi := inpOk_sound hcol h₀ hw hst i hok
        obtain ⟨ok, σ', hc, hholds, hσ'⟩ := ih hh' hr' σ hσ
        refine ⟨ok, σ', ?_, ?_, hσ'⟩
        · simp only [List.map_cons, Sys.depOf, Sys.check, hok, ite_true]
          exact hc
        · intro hok' e' he'
          rcases List.mem_cons.mp he' with rfl | he''
          · exact hwi
          · exact hholds hok' e' he''
      · refine ⟨false, σ, ?_, by simp, hσ⟩
        simp only [List.map_cons, Sys.depOf, Sys.check]
        simp only [Bool.not_eq_true] at hok
        simp [hok]
    | stp k v =>
      have hv : o₀ k = v := hhe
      have hrk : sys.rank k < n := hr (.stp k v) (List.mem_cons_self ..) k v rfl
      obtain ⟨v', σ1, hbk, hv', hσ1⟩ := hb k hrk σ hσ
      subst hv'
      by_cases hd : sys.dig (some (o k)) = sys.dig (some v)
      · have heq : some (o k) = some v :=
          hcol _ _ (Or.inr ⟨w, o, hw, ho, k, rfl⟩) (Or.inr ⟨w₀, o₀, h₀, ho₀, k, by rw [hv]⟩) hd
        have hok : o k = v := Option.some.inj heq
        obtain ⟨ok, σ', hc, hholds, hσ'⟩ := ih hh' hr' σ1 hσ1
        refine ⟨ok, σ', ?_, ?_, hσ'⟩
        · simp only [List.map_cons, Sys.depOf, Sys.check, hbk, hd, ite_true]
          exact hc
        · intro hok' e' he'
          rcases List.mem_cons.mp he' with rfl | he''
          · exact hok
          · exact hholds hok' e' he''
      · refine ⟨false, σ1, ?_, by simp, hσ1⟩
        simp only [List.map_cons, Sys.depOf, Sys.check, hbk, hd, ite_false]

/-- Running a step afresh against the live world gives its clean output and a faithful store with the new record. -/
theorem rebuild_spec {H : World I C S → Prop} {w : World I C S} {o : K → C} {n : Nat}
    {b : Builder I K C D S} (hb : BSpec (sys := sys) H o n b) (hw : H w) (ho : IsClean sys.task w.val o)
    (k : K) (hk : sys.rank k < n + 1) (σ : Store I K C D S) (hσ : Faithful sys H σ) :
    ∃ σ', sys.rebuild w b k σ = some (o k, σ') ∧ Faithful sys H σ' := by
  have hbel : (sys.task k).Below sys.rank n := (sys.below k).mono (Nat.le_of_lt_succ hk)
  obtain ⟨σ1, he, hσ1⟩ := exec_spec (w := w) hb (sys.task k) hbel σ hσ
  have hrec : (⟨((sys.task k).run w.val o).2.map (sys.depOf w), o k⟩ : Rec I K C D S) = sys.recordOf w o k := by
    show _ = ({ deps := ((sys.task k).run w.val o).2.map (sys.depOf w), out := ((sys.task k).run w.val o).1 } : Rec I K C D S)
    rw [← ho k]
  refine ⟨σ1.set k (sys.recordOf w o k), ?_, ?_⟩
  · simp only [Sys.rebuild, he]
    rw [← ho k, hrec]
  · intro k' r hr
    by_cases hkk : k' = k
    · subst hkk
      rw [Store.set_same] at hr
      cases hr
      exact ⟨w, o, hw, ho, rfl⟩
    · rw [Store.set_other _ _ hkk] at hr
      exact hσ1 k' r hr

/-- One level of the build: a good builder for the steps below gives a good build of the step. -/
theorem buildStep_spec {H : World I C S → Prop} {w : World I C S} {o : K → C} {n : Nat}
    {b : Builder I K C D S} (hb : BSpec (sys := sys) H o n b) (hcol : CollisionFree sys H)
    (hw : H w) (ho : IsClean sys.task w.val o) (hst : ∀ w₀, H w₀ → Stable w₀ w) :
    BSpec (sys := sys) H o (n + 1) (sys.buildStep w b) := by
  intro k hk σ hσ
  have hbel : (sys.task k).Below sys.rank n := (sys.below k).mono (Nat.le_of_lt_succ hk)
  unfold Sys.buildStep
  cases hσk : σ k with
  | none =>
    obtain ⟨σ', hr, hσ'⟩ := rebuild_spec hb hw ho k hk σ hσ
    exact ⟨o k, σ', by simpa using hr, rfl, hσ'⟩
  | some r =>
    obtain ⟨w₀, o₀, h₀, ho₀, hrec⟩ := hσ k r hσk
    subst hrec
    have htr : ∀ e ∈ ((sys.task k).run w₀.val o₀).2, ∀ k' v, e = .stp k' v → sys.rank k' < n :=
      fun e he k' v hev =>
        Nat.lt_of_lt_of_le (((sys.below k).trace w₀.val o₀) e he k' v hev) (Nat.le_of_lt_succ hk)
    obtain ⟨ok, σ', hc, hholds, hσ'⟩ :=
      check_spec hb hcol hw ho h₀ ho₀ (hst w₀ h₀) _ (Task.run_holds w₀.val o₀ (sys.task k)) htr σ hσ
    have hdeps : (sys.recordOf w₀ o₀ k).deps = ((sys.task k).run w₀.val o₀).2.map (sys.depOf w₀) := rfl
    dsimp only
    rw [hdeps, hc]
    cases ok with
    | true =>
      have hcongr := Task.run_congr w₀.val o₀ w.val o (sys.task k) (hholds rfl)
      refine ⟨(sys.recordOf w₀ o₀ k).out, σ', rfl, ?_, hσ'⟩
      show ((sys.task k).run w₀.val o₀).1 = o k
      rw [ho k, hcongr]
    | false =>
      obtain ⟨σ'', hr, hσ''⟩ := rebuild_spec hb hw ho k hk σ' hσ'
      exact ⟨o k, σ'', hr, rfl, hσ''⟩

/-- **The build is correct at every fuel above the rank**, by induction on fuel. -/
theorem build_correct {H : World I C S → Prop} {w : World I C S} {o : K → C}
    (hcol : CollisionFree sys H) (hw : H w) (ho : IsClean sys.task w.val o)
    (hst : ∀ w₀, H w₀ → Stable w₀ w) : ∀ n, BSpec (sys := sys) H o n (sys.buildAt w n) := by
  intro n
  induction n with
  | zero => intro k hk; exact absurd hk (Nat.not_lt_zero _)
  | succ n ih =>
    exact buildStep_spec ih hcol hw ho hst

/-- The build of one step: with the fuel its rank asks for. -/
def Sys.build (sys : Sys I K C D S) (w : World I C S) (k : K) (σ : Store I K C D S) :
    Option (C × Store I K C D S) :=
  sys.buildAt w (sys.rank k + 1) k σ

/-- **Theorem (a warm build equals the clean build).** Let `H` be a history of worlds, `σ` a store whose records are
all faithful to it, `w` a world of the history, and `o` the clean build of `w`. If the digest separates the contents
the history shows (D0) and every earlier recording world is stable against `w` (E2), then building any step `k`
against `w` from `σ` returns `o k`, exactly what the clean build produces, and leaves a store that is again
faithful. Nothing is assumed of what the store holds beyond faithfulness: a stale, partial or empty store is fine. -/
theorem warm_eq_clean {H : World I C S → Prop} {w : World I C S} {o : K → C}
    (hcol : CollisionFree sys H) (hw : H w) (ho : IsClean sys.task w.val o)
    (hst : ∀ w₀, H w₀ → Stable w₀ w) (k : K) (σ : Store I K C D S) (hσ : Faithful sys H σ) :
    ∃ σ', sys.build w k σ = some (o k, σ') ∧ Faithful sys H σ' := by
  obtain ⟨v, σ', hb, hv, hσ'⟩ := build_correct hcol hw ho hst (sys.rank k + 1) k (Nat.lt_succ_self _) σ hσ
  subst hv
  exact ⟨σ', hb, hσ'⟩

/-- The empty store is faithful to any history. -/
theorem faithful_empty (H : World I C S → Prop) : Faithful sys H (fun _ => none) := by
  intro k r hr; simp at hr

/-- **Corollary (a cold build equals the clean build).** The same with the empty store: the algorithm run from
nothing returns the clean build, so the guarantee is the one the compiler gives without any cache. -/
theorem cold_eq_clean {H : World I C S → Prop} {w : World I C S} {o : K → C}
    (hcol : CollisionFree sys H) (hw : H w) (ho : IsClean sys.task w.val o)
    (hst : ∀ w₀, H w₀ → Stable w₀ w) (k : K) :
    ∃ σ', sys.build w k (fun _ => none) = some (o k, σ') ∧ Faithful sys H σ' :=
  warm_eq_clean hcol hw ho hst k _ (faithful_empty H)

/-- Collision-freedom of a larger history is collision-freedom of a smaller one. -/
theorem CollisionFree.mono {H H' : World I C S → Prop} (h : ∀ w, H w → H' w) (c : CollisionFree sys H') :
    CollisionFree sys H := by
  intro a b ha hb hd
  apply c a b _ _ hd
  · rcases ha with ⟨w, hw, i, hi⟩ | ⟨w, o, hw, ho, k, hk⟩
    · exact Or.inl ⟨w, h w hw, i, hi⟩
    · exact Or.inr ⟨w, o, h w hw, ho, k, hk⟩
  · rcases hb with ⟨w, hw, i, hi⟩ | ⟨w, o, hw, ho, k, hk⟩
    · exact Or.inl ⟨w, h w hw, i, hi⟩
    · exact Or.inr ⟨w, o, h w hw, ho, k, hk⟩

/-- A session: builds of given steps against given worlds, one after another, the store threaded through. -/
def Sys.session (sys : Sys I K C D S) : List (World I C S × K) → Store I K C D S → List (Option C)
  | [], _ => []
  | (w, k) :: rest, σ =>
    match sys.build w k σ with
    | none => [none]
    | some (v, σ') => some v :: Sys.session sys rest σ'

/-- The induction behind `session_eq_clean`: `pre` are the worlds already recorded. -/
theorem session_aux {all : World I C S → Prop} (hcol : CollisionFree sys all)
    (clean : World I C S → K → C) :
    ∀ (steps : List (World I C S × K)) (pre : List (World I C S)) (σ : Store I K C D S),
      (∀ s ∈ steps, all s.1) → (∀ w ∈ pre, all w) →
      (∀ s ∈ steps, IsClean sys.task s.1.val (clean s.1)) →
      List.Pairwise (fun a b => Stable a.1 b.1) steps →
      (∀ w ∈ pre, ∀ s ∈ steps, Stable w s.1) →
      Faithful sys (fun w => w ∈ pre) σ →
      sys.session steps σ = steps.map (fun s => some (clean s.1 s.2)) := by
  intro steps
  induction steps with
  | nil => intros; rfl
  | cons s rest ih =>
    intro pre σ hall hpre hclean hpair hcross hσ
    obtain ⟨w, k⟩ := s
    have hH : ∀ w', w' ∈ w :: pre → all w' := by
      intro w' hw'
      rcases List.mem_cons.mp hw' with rfl | h
      · exact hall _ (List.mem_cons_self ..)
      · exact hpre _ h
    have hcol' : CollisionFree sys (fun w' => w' ∈ w :: pre) := hcol.mono hH
    have hst : ∀ w₀, w₀ ∈ w :: pre → Stable w₀ w := by
      intro w₀ hw₀
      rcases List.mem_cons.mp hw₀ with rfl | h
      · exact Stable.refl _
      · exact hcross w₀ h (w, k) (List.mem_cons_self ..)
    have hσ' : Faithful sys (fun w' => w' ∈ w :: pre) σ :=
      Faithful.mono sys (fun w' h => List.mem_cons_of_mem _ h) hσ
    obtain ⟨σ', hb, hσ''⟩ := warm_eq_clean hcol' (List.mem_cons_self ..) (hclean (w, k) (List.mem_cons_self ..)) hst k σ hσ'
    simp only [Sys.session, hb, List.map_cons]
    rw [ih (w :: pre) σ' (fun s' hs' => hall s' (List.mem_cons_of_mem _ hs')) hH
      (fun s' hs' => hclean s' (List.mem_cons_of_mem _ hs')) (List.pairwise_cons.mp hpair).2 ?_ hσ'']
    · intro w₀ hw₀ s' hs'
      rcases List.mem_cons.mp hw₀ with rfl | h
      · exact (List.pairwise_cons.mp hpair).1 s' hs'
      · exact hcross w₀ h s' (List.mem_cons_of_mem _ hs')

/-- **Theorem (any session equals the clean builds).** Build steps one after another, in any order and against any
worlds, with one store threaded through and no store at the start. If the digest separates every content the session
shows (D0) and each world is stable against every later one (E2: a tuple settled at an earlier build and equal now
stands for unchanged bytes), every output is the one the clean build of that build's world gives. -/
theorem session_eq_clean {all : World I C S → Prop} (hcol : CollisionFree sys all)
    (clean : World I C S → K → C) (steps : List (World I C S × K))
    (hall : ∀ s ∈ steps, all s.1)
    (hclean : ∀ s ∈ steps, IsClean sys.task s.1.val (clean s.1))
    (hpair : List.Pairwise (fun a b => Stable a.1 b.1) steps) :
    sys.session steps (fun _ => none) = steps.map (fun s => some (clean s.1 s.2)) :=
  session_aux hcol clean steps [] _ hall (by simp) hclean hpair (by simp) (by intro k r hr; simp at hr)

end Cache
