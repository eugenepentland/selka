import Cache.Build

/-!
# The stat fast path (decision E2)

A recorded `file` input carries the stat tuple seen around a successful hash, and an unchanged tuple stands for
unchanged bytes. That is not a theorem about hashing: it is a claim about the operating system's clock and its
file times. This file states the claim exactly, in a model of one file's life, and derives `Stable` (the hypothesis
`hst` of `warm_eq_clean`) from it.

**The model.** Real time is a natural number. A file path changes content only at *writes* (a write, a truncate, a
rename over the path, an unlink and create: anything that gives the path other bytes). A write at time `t` is
stamped `ts t`, the ctime of the inode now at the path, by the kernel's clock, which lags real time by less than the
timestamp granule `g`: `ts t ≤ t < ts t + g` (K1). A `stat` at any later time shows a stamp at least as new as every
earlier write's (K2). Content depends only on the writes (K0).

**The age test** (the K3 rule, `src/core/racy.zig` and `unit_cache.observedAt`). Let `h` be the wall clock read before
the file is first stat'ed and hashed. The stat tuple is stored in the record only if `max(mtime, ctime) + W ≤ h`,
with `W` the window (two seconds). Write `c` for `max(mtime, ctime)`. A write after `h` is stamped above `h - g`, so
if the window is at least the granule (`g ≤ W`, the assumption that the file-time clock and the wall clock agree to
within `W` minus one tick) it is stamped above `c`, and an equal tuple later means no write since.

Without the age test (`W = 0` while `g > 0`: the code before the K3 fix, which trusted any equal tuple) two writes
within one granule share a stamp: `racy_without_age_test` shows a history of the model in which `Stable` fails.
-/

namespace Cache

variable {I C : Type}

/-- The life of every input path as the kernel and the clock make it. -/
structure FsModel (I C : Type) where
  /-- The timestamp granule: how far the kernel's file clock may lag real time. -/
  g : Nat
  /-- The age window of the age test: a stamp is pinned only if it is at least this much older than the observation. -/
  W : Nat
  /-- The content of the path at real time `t` (`none` when absent). -/
  content : I → Nat → Option C
  /-- The times at which the path's content is replaced. -/
  write : I → Nat → Prop
  /-- The stamp (ctime) the kernel gave the write at time `t`. -/
  ts : I → Nat → Nat
  /-- What a `stat` at time `t` shows: the stamp, or `none` when the path is absent. -/
  stampAt : I → Nat → Option Nat
  /-- K0: content changes only at writes. -/
  content_const : ∀ i t₁ t₂, t₁ ≤ t₂ → (∀ t, t₁ < t → t ≤ t₂ → ¬ write i t) → content i t₂ = content i t₁
  /-- K1: the kernel's file clock is within one granule below real time. -/
  ts_close : ∀ i t, write i t → ts i t ≤ t ∧ t < ts i t + g
  /-- K2: a `stat` after a write shows a stamp at least as new as the write's. -/
  stamp_ge : ∀ i t t', write i t → t ≤ t' → ∃ s, stampAt i t' = some s ∧ ts i t ≤ s

/-- The world a build sees at real time `h`: contents, stamps, and whether each stamp passes the age test. -/
def FsModel.world (m : FsModel I C) (h : Nat) : World I C (Option Nat) where
  val i := m.content i h
  stat i := m.stampAt i h
  settled i := match m.stampAt i h with
    | some c => decide (c + m.W ≤ h)
    | none => false

/-- **E2 follows from the clock model and the age test.** If the window is at least the granule (`g ≤ W`), a world
observed at time `h` is stable against every later world. -/
theorem FsModel.stable (m : FsModel I C) (hW : m.g ≤ m.W) {h h' : Nat} (hh : h ≤ h') :
    Stable (m.world h) (m.world h') := by
  intro i hs heq
  have heq' : m.stampAt i h = m.stampAt i h' := heq
  have hs' : (match m.stampAt i h with | some c => decide (c + m.W ≤ h) | none => false) = true := hs
  cases hc : m.stampAt i h with
  | none => simp [hc] at hs'
  | some c =>
    simp only [hc, decide_eq_true_eq] at hs'
    have hnw : ∀ t, h < t → t ≤ h' → ¬ m.write i t := by
      intro t ht1 ht2 hw
      obtain ⟨s, hst, hle⟩ := m.stamp_ge i t h' hw ht2
      rw [hc, hst] at heq'
      have hsc : c = s := Option.some.inj heq'
      obtain ⟨_, hlt⟩ := m.ts_close i t hw
      omega
    exact (m.content_const i h h' hh hnw).symm

/-- Without the window (`W = 0` while the granule is 5) the model has a history in which two writes share a stamp
(K0-K2 hold), the contents differ, and `Stable` fails: the first world's tuple passes the age test and an equal
tuple does not mean unchanged bytes. Writes at times 10 and 11 are both stamped 10; the world at time 10 sees
stamp 10 and the world at time 11 sees stamp 10. -/
theorem racy_without_age_test :
    ∃ m : FsModel Unit Nat, ∃ h h' : Nat, h ≤ h' ∧ ¬ Stable (m.world h) (m.world h') := by
  refine ⟨{
    g := 5
    W := 0
    content := fun _ t => if t < 10 then some 0 else if t < 11 then some 1 else some 2
    write := fun _ t => t = 10 ∨ t = 11
    ts := fun _ _ => 10
    stampAt := fun _ t => if t < 10 then some 0 else some 10
    content_const := ?_
    ts_close := ?_
    stamp_ge := ?_ }, 10, 11, by omega, ?_⟩
  · intro _ t₁ t₂ h12 hnw
    show (if t₂ < 10 then some 0 else if t₂ < 11 then some 1 else some 2) =
      (if t₁ < 10 then some 0 else if t₁ < 11 then some 1 else some 2)
    have h10 : t₁ < 10 → t₂ ≥ 10 → False := fun a b => hnw 10 a b |>.elim (Or.inl rfl)
    have h11 : t₁ < 11 → t₂ ≥ 11 → False := fun a b => hnw 11 a b |>.elim (Or.inr rfl)
    by_cases a1 : t₁ < 10
    · have : t₂ < 10 := by
        by_cases b : t₂ < 10
        · exact b
        · exact (h10 a1 (by omega)).elim
      simp [a1, this]
    · by_cases a2 : t₁ < 11
      · have : t₂ < 11 := by
          by_cases b : t₂ < 11
          · exact b
          · exact (h11 a2 (by omega)).elim
        have e1 : ¬ t₂ < 10 := by omega
        simp [a1, a2, this, e1]
      · have e1 : ¬ t₂ < 10 := by omega
        have e2 : ¬ t₂ < 11 := by omega
        simp [a1, a2, e1, e2]
  · intro _ t hw
    show (10 ≤ t) ∧ t < 10 + 5
    rcases hw with rfl | rfl <;> omega
  · intro _ t t' hw hle
    refine ⟨10, ?_, Nat.le_refl _⟩
    have : ¬ t' < 10 := by rcases hw with rfl | rfl <;> omega
    simp [this]
  · intro hst
    have := hst () (by simp [FsModel.world]) (by simp [FsModel.world])
    simp [FsModel.world] at this

end Cache
