/-!
# Dominator trees and walks

The abstract facts the soundness proof uses about the control-flow graph and the verified dominator tree
(`domOK`), stated for an arbitrary graph so that they do not depend on the checker's data structures:

* `Walk succ b l`: a path from the entry `0` to `b`, newest block first, along `succ`;
* `TDom succ a b`: `a` is on every walk to `b` (true dominance, the relation the IR verifier's SSA
  rule is about);
* `Anc par a b`: `a` is `b` or an ancestor of `b` in the tree given by the parent function `par`;
* the property `S` of the tree (the parent of a block is an ancestor of each of its predecessors), and from it:
  every ancestor of a block lies on every walk to it, so a tree ancestor truly dominates (`mem_of_anc`).
-/

namespace Facts

/-- `Anc par a b`: `a` is `b` or an ancestor of `b`. -/
inductive Anc (par : Nat → Option Nat) : Nat → Nat → Prop where
  | refl (a : Nat) : Anc par a a
  | step {a b d : Nat} : par b = some d → Anc par a d → Anc par a b

namespace Anc
variable {par : Nat → Option Nat}

theorem trans {a b c : Nat} (h1 : Anc par a b) (h2 : Anc par b c) : Anc par a c := by
  induction h2 with
  | refl => exact h1
  | step hp _ ih => exact Anc.step hp ih

/-- An ancestor is `b` itself or an ancestor of `b`'s parent. -/
theorem cases {a b : Nat} (h : Anc par a b) : a = b ∨ ∃ d, par b = some d ∧ Anc par a d := by
  cases h with
  | refl => exact Or.inl rfl
  | step hp h' => exact Or.inr ⟨_, hp, h'⟩

end Anc

/-- A walk from the entry `0`, newest block first. -/
inductive Walk (succ : Nat → List Nat) : Nat → List Nat → Prop where
  | start : Walk succ 0 [0]
  | step {p b : Nat} {l : List Nat} : Walk succ p l → b ∈ succ p → Walk succ b (b :: l)

namespace Walk
variable {succ : Nat → List Nat}

theorem head {c : Nat} {l : List Nat} (h : Walk succ c l) : ∃ l', l = c :: l' := by
  cases h with
  | start => exact ⟨[], rfl⟩
  | step _ _ => exact ⟨_, rfl⟩

/-- A suffix of a walk, starting at any of its blocks, is a walk. -/
theorem suffix {c : Nat} {l : List Nat} (h : Walk succ c l) :
    ∀ (l1 l2 : List Nat) (y : Nat), l = l1 ++ y :: l2 → Walk succ y (y :: l2) := by
  induction h with
  | start =>
    intro l1 l2 y e
    cases l1 with
    | nil =>
      simp at e; obtain ⟨rfl, rfl⟩ := e; exact Walk.start
    | cons z zs =>
      exfalso
      have := congrArg List.length e
      simp at this
  | step hw hs ih =>
    rename_i p b l
    intro l1 l2 y e
    cases l1 with
    | nil =>
      simp at e; obtain ⟨rfl, rfl⟩ := e; exact Walk.step hw hs
    | cons z zs =>
      simp at e; obtain ⟨_, he⟩ := e
      exact ih zs l2 y he

/-- The block before the newest one on a walk is a predecessor of it. -/
theorem prev {c : Nat} {l : List Nat} (h : Walk succ c l) (hc : c ≠ 0) :
    ∃ p l', l = c :: l' ∧ Walk succ p l' ∧ c ∈ succ p := by
  cases h with
  | start => exact absurd rfl hc
  | step hw hs => exact ⟨_, _, rfl, hw, hs⟩

/-- A walk is nonempty and ends in the entry. -/
theorem length_pos {c : Nat} {l : List Nat} (h : Walk succ c l) : 0 < l.length := by
  obtain ⟨l', e⟩ := h.head
  rw [e]; simp

end Walk

/-- `a` is on every walk to `b`: true dominance (vacuous when no walk reaches `b`). -/
def TDom (succ : Nat → List Nat) (a b : Nat) : Prop := ∀ l, Walk succ b l → a ∈ l

/-- Some walk reaches `b`. -/
def Reach (succ : Nat → List Nat) (b : Nat) : Prop := ∃ l, Walk succ b l

namespace TDom
variable {succ : Nat → List Nat}

theorem refl (a : Nat) : TDom succ a a := by
  intro l h
  obtain ⟨l', e⟩ := h.head
  rw [e]; simp

theorem trans {a b c : Nat} (h1 : TDom succ a b) (h2 : TDom succ b c) : TDom succ a c := by
  intro l hl
  have hb := h2 l hl
  obtain ⟨l1, l2, e⟩ := List.append_of_mem hb
  have hw := hl.suffix l1 l2 b e
  have ha := h1 _ hw
  rw [e]
  simp only [List.mem_append]
  exact Or.inr ha

/-- The entry is on every walk. -/
theorem entry (b : Nat) : TDom succ 0 b := by
  intro l h
  induction h with
  | start => simp
  | step _ _ ih => exact List.mem_cons_of_mem _ ih

/-- A block with a walk to it is dominated by the dominator of any walk's block: a dominator of a reached block is
reached. -/
theorem reach_of {a b : Nat} (h : TDom succ a b) (hb : Reach succ b) : Reach succ a := by
  obtain ⟨l, hl⟩ := hb
  obtain ⟨l1, l2, e⟩ := List.append_of_mem (h l hl)
  exact ⟨_, hl.suffix l1 l2 a e⟩

/-- True dominance is antisymmetric on reached blocks. -/
theorem antisymm {a b : Nat} (hb : Reach succ b) (h1 : TDom succ a b) (h2 : TDom succ b a) : a = b := by
  obtain ⟨l0, hl0⟩ := hb
  have key : ∀ n : Nat, ∀ l : List Nat, l.length ≤ n → Walk succ b l → a = b := by
    intro n
    induction n with
    | zero =>
      intro l hl hw
      have := hw.length_pos
      omega
    | succ n ih =>
      intro l hl hw
      obtain ⟨l1, l2, e⟩ := List.append_of_mem (h1 l hw)
      have hwa := hw.suffix l1 l2 a e
      have hb' := h2 _ hwa
      rcases List.mem_cons.mp hb' with hba | hbl2
      · exact hba.symm
      · obtain ⟨l3, l4, e2⟩ := List.append_of_mem hbl2
        have hwb : Walk succ b (b :: l4) := hwa.suffix (a :: l3) l4 b (by simp [e2])
        apply ih (b :: l4) _ hwb
        have h3 := congrArg List.length e
        have h4 := congrArg List.length e2
        simp at h3 h4
        simp
        omega
  exact key l0.length l0 (Nat.le_refl _) hl0

/-- A dominator of the single predecessor `P` of a block dominates the block. -/
theorem of_single {a x P : Nat} (hx : x ≠ 0) (hsingle : ∀ p, x ∈ succ p → p = P) (h : TDom succ a P) :
    TDom succ a x := by
  intro l hl
  obtain ⟨p, l', e, hw, hs⟩ := hl.prev hx
  have hp : p = P := hsingle p hs
  subst hp
  rw [e]
  exact List.mem_cons_of_mem _ (h l' hw)

/-- A dominator of a successor that is not the successor itself dominates the block. -/
theorem of_succ {a x B : Nat} (hs : x ∈ succ B) (hne : a ≠ x) (h : TDom succ a x) : TDom succ a B := by
  intro l hl
  have := h (x :: l) (Walk.step hl hs)
  rcases List.mem_cons.mp this with h1 | h1
  · exact absurd h1 hne
  · exact h1

/-- A block with a single predecessor `P` does not dominate `P` when `P` is reached. -/
theorem not_single {x P : Nat} (hx : x ≠ 0) (hsingle : ∀ p, x ∈ succ p → p = P) (hP : Reach succ P) :
    ¬ TDom succ x P := by
  intro hdom
  obtain ⟨l0, hl0⟩ := hP
  have key : ∀ n : Nat, ∀ l : List Nat, l.length ≤ n → Walk succ P l → False := by
    intro n
    induction n with
    | zero =>
      intro l hl hw
      have := hw.length_pos
      omega
    | succ n ih =>
      intro l hl hw
      obtain ⟨l1, l2, e⟩ := List.append_of_mem (hdom l hw)
      have hwx := hw.suffix l1 l2 x e
      obtain ⟨p, l', e', hwp, hs⟩ := hwx.prev hx
      have hp : p = P := hsingle p hs
      subst hp
      have hl' : l' = l2 := (List.cons.inj e').2.symm
      subst hl'
      apply ih l' _ hwp
      have h3 := congrArg List.length e
      simp at h3
      omega
  exact key l0.length l0 (Nat.le_refl _) hl0

end TDom

/-- The graph and the verified tree. -/
structure Graph where
  succ : Nat → List Nat
  par : Nat → Option Nat
  /-- Blocks the verified tree reaches. -/
  tr : Nat → Prop
  entry_tr : tr 0
  par_entry : par 0 = none
  succ_tr : ∀ p b, tr p → b ∈ succ p → tr b
  /-- The property `S`: the parent of a block is an ancestor of each reachable predecessor. -/
  parent_anc : ∀ p b, tr p → b ∈ succ p → b ≠ 0 → ∃ d, par b = some d ∧ Anc par d p
  entry_nopred : ∀ p, 0 ∉ succ p

namespace Graph
variable (G : Graph)

theorem walk_tr {c : Nat} {l : List Nat} (h : Walk G.succ c l) : G.tr c := by
  induction h with
  | start => exact G.entry_tr
  | step _ hs ih => exact G.succ_tr _ _ ih hs

/-- Every ancestor of the last block of a walk occurs in it. -/
theorem mem_of_anc {c : Nat} {l : List Nat} (h : Walk G.succ c l) {a : Nat} (ha : Anc G.par a c) : a ∈ l := by
  induction h generalizing a with
  | start =>
    cases ha.cases with
    | inl e => subst e; simp
    | inr h' =>
      obtain ⟨d, hd, _⟩ := h'
      rw [G.par_entry] at hd; cases hd
  | step hw hs ih =>
    rename_i p b l
    cases ha.cases with
    | inl e => subst e; simp
    | inr h' =>
      obtain ⟨d, hd, had⟩ := h'
      by_cases hb : b = 0
      · subst hb; exact absurd hs (G.entry_nopred p)
      · obtain ⟨d', hd', hdp⟩ := G.parent_anc p b (G.walk_tr hw) hs hb
        rw [hd] at hd'; cases hd'
        exact List.mem_cons_of_mem _ (ih (had.trans hdp))

/-- A tree ancestor truly dominates. -/
theorem tdom_of_anc {a c : Nat} (ha : Anc G.par a c) : TDom G.succ a c := fun _ h => G.mem_of_anc h ha

end Graph

end Facts
