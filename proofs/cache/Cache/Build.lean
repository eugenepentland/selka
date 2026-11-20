import Cache.Basic

/-!
# Records, the build algorithm, and the theorem

The build is demand driven. To build step `k` against the live world `w`:

* if the store holds a **record** for `k` (what the step read, each with a digest, and its output), **verify** it:
  every recorded input must still show its recorded digest (or an unchanged settled stat tuple, the fast path of
  decision E2), and every recorded step must, once built, show its recorded output digest. Building a recorded step
  may re-run it; if it produces the digest it had, the record of `k` stays valid. This is **early cutoff**;
* otherwise, or if verification fails, **run** the step against the live world, building the steps it demands on
  the way (**dynamic dependencies**: what it reads depends on what it saw), and store a new record.

The record of a step is exactly what `src/core/inputs.zig` writes (`Handle.seal`) plus the output.

`Faithful` is the invariant: every record in the store is the record that running its step in some world of the
history would have written. The theorem (`build_correct`) says that, under the assumptions of `AXIOMS.md`, a build
against `w` with any faithful store returns what the clean build of `w` returns, and leaves a faithful store.
-/

set_option linter.unusedSectionVars false

namespace Cache

variable {I K C D S : Type}

/-- The parameters of a build: the steps, their acyclicity (a rank), and the digest function of what is read. -/
structure Sys (I K C D S : Type) where
  /-- Each step as a tree of reads. -/
  task : K → Task I K C
  /-- Steps demand only steps of lower rank, so the equations of the clean build have a solution. -/
  rank : K → Nat
  below : ∀ k, (task k).Below rank (rank k)
  /-- The digest of what a read showed (`none` is an absent file), and of a step's output (`some`). -/
  dig : Option C → D

/-- What the live world shows of the inputs: their value, their stat tuple, and whether that tuple was *settled*
when taken (old enough, relative to the clock, that a later write must change it: the age test of decision E2). -/
structure World (I C S : Type) where
  val : I → Option C
  stat : I → S
  settled : I → Bool

/-- One recorded read: an input with the digest of what it showed and, if the stat tuple was settled, the tuple; or a
step with the digest of its output. -/
inductive Dep (I K D S : Type) where
  | inp : I → D → Option S → Dep I K D S
  | stp : K → D → Dep I K D S

/-- A step's record: everything it read, in order, and its output. -/
structure Rec (I K C D S : Type) where
  deps : List (Dep I K D S)
  out : C

/-- The record store. -/
abbrev Store (I K C D S : Type) := K → Option (Rec I K C D S)

/-- The store with the record of `k` replaced. -/
def Store.set [DecidableEq K] (σ : Store I K C D S) (k : K) (r : Rec I K C D S) : Store I K C D S :=
  fun k' => if k' = k then some r else σ k'

theorem Store.set_same [DecidableEq K] (σ : Store I K C D S) (k : K) (r : Rec I K C D S) :
    σ.set k r k = some r := by simp [Store.set]

theorem Store.set_other [DecidableEq K] (σ : Store I K C D S) {k k' : K} (r : Rec I K C D S) (h : k' ≠ k) :
    σ.set k r k' = σ k' := by simp [Store.set, h]

variable (sys : Sys I K C D S)

/-- What the handle writes down for one sighting made in world `w`. -/
def Sys.depOf (w : World I C S) : Seen I K C → Dep I K D S
  | .inp i v => .inp i (sys.dig v) (if w.settled i then some (w.stat i) else none)
  | .stp k v => .stp k (sys.dig (some v))

/-- The record that running step `k` in world `w`, against the step outputs `o`, writes. -/
def Sys.recordOf (w : World I C S) (o : K → C) (k : K) : Rec I K C D S :=
  let r := (sys.task k).run w.val o
  { deps := r.2.map (sys.depOf w), out := r.1 }

variable [DecidableEq K] [DecidableEq D] [DecidableEq S]

/-- Whether a recorded input still shows what it showed. The fast path of decision E2: a recorded stat tuple equal
to the live one stands for unchanged bytes, without hashing; otherwise the digests are compared. -/
def Sys.inpOk (w : World I C S) (i : I) (d : D) (s : Option S) : Bool :=
  (match s with
    | some s' => decide (w.stat i = s')
    | none => false) || decide (sys.dig (w.val i) = d)

/-- Build a step: the demand (`b`) is a build of a lower rank, supplied by the caller. The result is the step's
output and the store afterwards; `none` only for want of fuel. -/
abbrev Builder (I K C D S : Type) := K → Store I K C D S → Option (C × Store I K C D S)

/-- Run a task against the live world, building the steps it demands (dynamic dependencies), and write down what it
read. -/
def Sys.exec (w : World I C S) (b : Builder I K C D S) :
    Task I K C → Store I K C D S → Option (C × List (Dep I K D S) × Store I K C D S)
  | .done c, σ => some (c, [], σ)
  | .input i f, σ =>
    match Sys.exec w b (f (w.val i)) σ with
    | none => none
    | some (c, ds, σ') => some (c, sys.depOf w (.inp i (w.val i)) :: ds, σ')
  | .step k f, σ =>
    match b k σ with
    | none => none
    | some (v, σ1) =>
      match Sys.exec w b (f v) σ1 with
      | none => none
      | some (c, ds, σ2) => some (c, sys.depOf w (.stp k v) :: ds, σ2)

/-- Verify a record's dependencies in order: stop at the first that changed. A recorded step is built (it may
re-run) and its output digest compared with the recorded one: early cutoff. -/
def Sys.check (w : World I C S) (b : Builder I K C D S) :
    List (Dep I K D S) → Store I K C D S → Option (Bool × Store I K C D S)
  | [], σ => some (true, σ)
  | .inp i d s :: rest, σ => if sys.inpOk w i d s then Sys.check w b rest σ else some (false, σ)
  | .stp k d :: rest, σ =>
    match b k σ with
    | none => none
    | some (v, σ1) => if sys.dig (some v) = d then Sys.check w b rest σ1 else some (false, σ1)

/-- Run the step and store its record. -/
def Sys.rebuild (w : World I C S) (b : Builder I K C D S) (k : K) (σ : Store I K C D S) :
    Option (C × Store I K C D S) :=
  match sys.exec w b (sys.task k) σ with
  | none => none
  | some (c, ds, σ1) => some (c, σ1.set k ⟨ds, c⟩)

/-- Build step `k` given a builder for the steps below it: serve a verified record, else run. -/
def Sys.buildStep (w : World I C S) (b : Builder I K C D S) (k : K) (σ : Store I K C D S) :
    Option (C × Store I K C D S) :=
  match σ k with
  | none => sys.rebuild w b k σ
  | some r =>
    match sys.check w b r.deps σ with
    | none => none
    | some (true, σ1) => some (r.out, σ1)
    | some (false, σ1) => sys.rebuild w b k σ1

/-- The build with `n` units of fuel (an upper bound on the depth of the demands). -/
def Sys.buildAt (w : World I C S) : Nat → Builder I K C D S
  | 0 => fun _ _ => none
  | n + 1 => Sys.buildStep sys w (Sys.buildAt w n)

/-! ## The history, and what the theorem assumes of it -/

/-- Every record in the store is the record that running its step in some world of the history `H` wrote. -/
def Faithful (H : World I C S → Prop) (σ : Store I K C D S) : Prop :=
  ∀ k r, σ k = some r → ∃ w₀ o₀, H w₀ ∧ IsClean sys.task w₀.val o₀ ∧ r = sys.recordOf w₀ o₀ k

theorem Faithful.mono {H H' : World I C S → Prop} (h : ∀ w, H w → H' w) {σ : Store I K C D S}
    (f : Faithful sys H σ) : Faithful sys H' σ := by
  intro k r hr
  obtain ⟨w₀, o₀, hw, hc, he⟩ := f k r hr
  exact ⟨w₀, o₀, h _ hw, hc, he⟩

/-- Every content the history ever shows: an input in some world, or a step output in the clean build of some
world. -/
def Occurs (H : World I C S → Prop) (v : Option C) : Prop :=
  (∃ w, H w ∧ ∃ i, w.val i = v) ∨ (∃ w o, H w ∧ IsClean sys.task w.val o ∧ ∃ k, v = some (o k))

/-- **Assumption D0, collision-freedom.** The digest tells apart any two contents the history shows. For the real
digest (BLAKE3, 256 bits) this holds unless a collision exists among those contents; it is stated for the finite
set of contents a session sees, not for all byte strings, because no function from byte strings to 32 bytes is
injective. -/
def CollisionFree (H : World I C S → Prop) : Prop :=
  ∀ a b, Occurs sys H a → Occurs sys H b → sys.dig a = sys.dig b → a = b

/-- **Assumption E2, the stat fast path.** A stat tuple that was settled when recorded and is equal now stands for
unchanged bytes. `Cache/Stamp.lean` derives it from a model of the clock and the file system. -/
def Stable (w₀ w : World I C S) : Prop :=
  ∀ i, w₀.settled i = true → w₀.stat i = w.stat i → w₀.val i = w.val i

theorem Stable.refl (w : World I C S) : Stable w w := fun _ _ _ => rfl

/-- **Hashing every input needs no E2.** If no recorded tuple is settled (the stat path never answers), `Stable` holds
of any two worlds, so `warm_eq_clean` assumes only D0. -/
theorem Stable.of_unsettled {w₀ w : World I C S} (h : ∀ i, w₀.settled i = false) : Stable w₀ w := by
  intro i hs _
  rw [h i] at hs
  exact absurd hs (by decide)

/-! ## Verifying a record -/

section Verify

variable {sys}

/-- A recorded input that verifies shows the same value now (the fast path and the digest are both sound). -/
theorem inpOk_sound {H : World I C S → Prop} (hcol : CollisionFree sys H) {w₀ w : World I C S}
    (h₀ : H w₀) (h : H w) (hst : Stable w₀ w) (i : I)
    (hok : sys.inpOk w i (sys.dig (w₀.val i)) (if w₀.settled i then some (w₀.stat i) else none) = true) :
    w.val i = w₀.val i := by
  unfold Sys.inpOk at hok
  have hcolw : sys.dig (w.val i) = sys.dig (w₀.val i) → w.val i = w₀.val i := fun hd =>
    hcol _ _ (Or.inl ⟨w, h, i, rfl⟩) (Or.inl ⟨w₀, h₀, i, rfl⟩) hd
  cases hs : w₀.settled i
  · simp [hs] at hok
    exact hcolw hok
  · simp [hs] at hok
    rcases hok with hstat | hd
    · exact (hst i hs hstat.symm).symm
    · exact hcolw hd

end Verify

end Cache
