/-!
# The admission rule for test receipts (`src/cache_plan_reference_v2.zig`)

`selka test` keeps, for each test, a receipt keyed by the Core call graph under the test's roots. After an edit it asks
the planner which receipts may be admitted. The host (`src/core/test_runner_graph.zig`, `prepare`) lists the nodes that
*changed* since the previous generation; the planner marks as **dirty** every node that can reach a changed node
(the callers, transitively), and admits the receipt of a test that was a candidate and has no dirty root.

This file states the rule and proves it sound against what a receipt depends on: the **labelled closure** of the
roots, the identity, body digest and callee identities of every node reachable from them. If a test's roots are not
dirty, the labelled closure of its roots in the new graph is the labelled closure of the same roots in the old graph
(`closure_labels_eq`), so anything that is a function of that closure is unchanged (`admit_sound`).

What it assumes of the host is `Complete`: a node the host did not list as changed has a node in the old graph with
the same identity, body digest and callee identities. `prepare` defines `changed` as exactly the nodes failing this
(it compares `identity`, `body` and the sorted `edges`), so `Complete` holds by construction there; the model states
it, and the differential in `scripts/cache_plan_diff.py` checks the necessary consequences on real graphs.
-/

namespace Cache.Admit

/-- A call graph over nodes numbered by `Nat`, with the host's facts: each node's logical identity (`none` for a
node without one), its body digest, and the sorted identities of its callees. -/
structure Graph (D : Type) where
  callees : Nat → List Nat
  identity : Nat → Option D
  body : Nat → D
  edgeIds : Nat → List D

variable {D : Type}

/-- Well-formed, as `nodes` and `validNodes` check: identities are unique, every callee has an identity, and the
sorted identity list of a node is the identities of its callees. -/
structure Wf (g : Graph D) : Prop where
  unique : ∀ x y, g.identity x ≠ none → g.identity x = g.identity y → x = y
  resolved : ∀ x, ∀ y ∈ g.callees x, g.identity y ≠ none
  edge_mem : ∀ x d, d ∈ g.edgeIds x ↔ ∃ y ∈ g.callees x, g.identity y = some d

/-- Reachability along calls. -/
inductive Reach (g : Graph D) : Nat → Nat → Prop where
  | refl (x : Nat) : Reach g x x
  | tail {x y z : Nat} : Reach g x y → z ∈ g.callees y → Reach g x z

/-- Dirty: a changed node, or a caller of a dirty node. -/
inductive Dirty (g : Graph D) (changed : Nat → Prop) : Nat → Prop where
  | base {x : Nat} : changed x → Dirty g changed x
  | caller {x y : Nat} : y ∈ g.callees x → Dirty g changed y → Dirty g changed x

/-- A dirty node is reached backwards: whoever reaches a dirty node is dirty. -/
theorem Dirty.of_reach {g : Graph D} {ch : Nat → Prop} {x z : Nat} (h : Reach g x z) (hz : Dirty g ch z) :
    Dirty g ch x := by
  induction h with
  | refl => exact hz
  | tail _ hc ih => exact ih (.caller hc hz)

/-- **Dirty means a changed node is reachable.** -/
theorem dirty_iff {g : Graph D} {ch : Nat → Prop} {x : Nat} :
    Dirty g ch x ↔ ∃ y, Reach g x y ∧ ch y := by
  constructor
  · intro h
    induction h with
    | base hc => exact ⟨_, .refl _, hc⟩
    | caller hmem _ ih =>
      obtain ⟨z, hz, hch⟩ := ih
      -- a path y ⇝ z extends to x → y ⇝ z
      refine ⟨z, ?_, hch⟩
      clear hch
      induction hz with
      | refl => exact .tail (.refl _) hmem
      | tail _ hc' ih' => exact .tail ih' hc'
  · rintro ⟨y, hr, hy⟩
    exact Dirty.of_reach hr (.base hy)

/-- What the host says about a node of the new graph and a node of the old graph being the same node. -/
def Matches (g g₀ : Graph D) (x x₀ : Nat) : Prop :=
  g.identity x ≠ none ∧ g.identity x = g₀.identity x₀ ∧ g.body x = g₀.body x₀ ∧ g.edgeIds x = g₀.edgeIds x₀

/-- **The host's obligation.** A node not listed as changed matches some node of the old graph. -/
def Complete (g g₀ : Graph D) (changed : Nat → Prop) : Prop :=
  ∀ x, ¬ changed x → ∃ x₀, Matches g g₀ x x₀

/-- Everything a receipt can depend on at a node. -/
def Graph.label (g : Graph D) (x : Nat) : Option D × D × List D := (g.identity x, g.body x, g.edgeIds x)

/-- The labels of the closure under some roots. -/
def Graph.labels (g : Graph D) (roots : List Nat) (l : Option D × D × List D) : Prop :=
  ∃ r ∈ roots, ∃ y, Reach g r y ∧ g.label y = l

section Soundness

variable {g g₀ : Graph D} {ch : Nat → Prop}

/-- The nodes below a clean root are clean, and match old nodes by identity. -/
theorem match_of_clean (wf₀ : Wf g₀) (hc : Complete g g₀ ch) {x x₀ : Nat}
    (hx : ¬ Dirty g ch x) (hid : g.identity x = g₀.identity x₀) (hne : g.identity x ≠ none) :
    Matches g g₀ x x₀ := by
  obtain ⟨x₁, hm⟩ := hc x (fun h => hx (.base h))
  have : x₁ = x₀ := wf₀.unique x₁ x₀ (by rw [← hm.2.1]; exact hne) (by rw [← hm.2.1, hid])
  subst this; exact hm

/-- From a clean root, every node reachable in the new graph matches a node reachable from the old root. -/
theorem new_to_old (wf : Wf g) (wf₀ : Wf g₀) (hc : Complete g g₀ ch) {r r₀ : Nat}
    (hr : ¬ Dirty g ch r) (hid : g.identity r = g₀.identity r₀) (hne : g.identity r ≠ none) :
    ∀ y, Reach g r y → ∃ y₀, Reach g₀ r₀ y₀ ∧ Matches g g₀ y y₀ := by
  intro y hy
  induction hy with
  | refl => exact ⟨r₀, .refl _, match_of_clean wf₀ hc hr hid hne⟩
  | @tail y z hry hz ih =>
    obtain ⟨y₀, hry₀, hm⟩ := ih
    have hzne := wf.resolved y z hz
    obtain ⟨d, hd⟩ : ∃ d, g.identity z = some d := by
      cases h : g.identity z with
      | none => exact absurd h hzne
      | some d => exact ⟨d, rfl⟩
    have hmem : d ∈ g.edgeIds y := (wf.edge_mem y d).2 ⟨z, hz, hd⟩
    have hmem₀ : d ∈ g₀.edgeIds y₀ := by rw [← hm.2.2.2]; exact hmem
    obtain ⟨z₀, hz₀, hd₀⟩ := (wf₀.edge_mem y₀ d).1 hmem₀
    have hzclean : ¬ Dirty g ch z := fun h => hr (Dirty.of_reach hry (.caller hz h))
    exact ⟨z₀, .tail hry₀ hz₀, match_of_clean wf₀ hc hzclean (by rw [hd, hd₀]) hzne⟩

/-- And the other way: every node reachable from the old root is matched by one reachable from the new root. -/
theorem old_to_new (wf : Wf g) (wf₀ : Wf g₀) (hc : Complete g g₀ ch) {r r₀ : Nat}
    (hr : ¬ Dirty g ch r) (hid : g.identity r = g₀.identity r₀) (hne : g.identity r ≠ none) :
    ∀ y₀, Reach g₀ r₀ y₀ → ∃ y, Reach g r y ∧ Matches g g₀ y y₀ := by
  intro y₀ hy
  induction hy with
  | refl => exact ⟨r, .refl _, match_of_clean wf₀ hc hr hid hne⟩
  | @tail y₀ z₀ hry hz₀ ih =>
    obtain ⟨y, hry', hm⟩ := ih
    have hzne₀ := wf₀.resolved y₀ z₀ hz₀
    obtain ⟨d, hd₀⟩ : ∃ d, g₀.identity z₀ = some d := by
      cases h : g₀.identity z₀ with
      | none => exact absurd h hzne₀
      | some d => exact ⟨d, rfl⟩
    have hmem₀ : d ∈ g₀.edgeIds y₀ := (wf₀.edge_mem y₀ d).2 ⟨z₀, hz₀, hd₀⟩
    have hmem : d ∈ g.edgeIds y := by rw [hm.2.2.2]; exact hmem₀
    obtain ⟨z, hz, hd⟩ := (wf.edge_mem y d).1 hmem
    have hzclean : ¬ Dirty g ch z := fun h => hr (Dirty.of_reach hry' (.caller hz h))
    exact ⟨z, .tail hry' hz, match_of_clean wf₀ hc hzclean (by rw [hd, hd₀]) (wf.resolved y z hz)⟩

/-- **A clean test has the same labelled closure.** If no root of a test is dirty, and the old test had roots with the
same identities, the labels of everything reachable from the roots are the same in both graphs. -/
theorem closure_labels_eq (wf : Wf g) (wf₀ : Wf g₀) (hc : Complete g g₀ ch) {roots roots₀ : List Nat}
    (hclean : ∀ r ∈ roots, ¬ Dirty g ch r) (hne : ∀ r ∈ roots, g.identity r ≠ none)
    (hfwd : ∀ r ∈ roots, ∃ r₀ ∈ roots₀, g.identity r = g₀.identity r₀)
    (hbwd : ∀ r₀ ∈ roots₀, ∃ r ∈ roots, g.identity r = g₀.identity r₀) :
    g.labels roots = g₀.labels roots₀ := by
  funext l
  apply propext
  constructor
  · rintro ⟨r, hr, y, hy, rfl⟩
    obtain ⟨r₀, hr₀, hid⟩ := hfwd r hr
    obtain ⟨y₀, hy₀, hm⟩ := new_to_old wf wf₀ hc (hclean r hr) hid (hne r hr) y hy
    refine ⟨r₀, hr₀, y₀, hy₀, ?_⟩
    obtain ⟨_, h1, h2, h3⟩ := hm
    simp [Graph.label, h1, h2, h3]
  · rintro ⟨r₀, hr₀, y₀, hy₀, rfl⟩
    obtain ⟨r, hr, hid⟩ := hbwd r₀ hr₀
    obtain ⟨y, hy, hm⟩ := old_to_new wf wf₀ hc (hclean r hr) hid (hne r hr) y₀ hy₀
    refine ⟨r, hr, y, hy, ?_⟩
    obtain ⟨_, h1, h2, h3⟩ := hm
    simp [Graph.label, h1, h2, h3]

/-- **Soundness of admission.** Whatever a test's outcome is a function of the labelled closure of its roots (and
nothing else that changed: the test's settings, the compiler and the runtime are in the key), a test with no dirty root
has the outcome it had. -/
theorem admit_sound {R : Type} (outcome : ((Option D × D × List D) → Prop) → R)
    (wf : Wf g) (wf₀ : Wf g₀) (hc : Complete g g₀ ch) {roots roots₀ : List Nat}
    (hclean : ∀ r ∈ roots, ¬ Dirty g ch r) (hne : ∀ r ∈ roots, g.identity r ≠ none)
    (hfwd : ∀ r ∈ roots, ∃ r₀ ∈ roots₀, g.identity r = g₀.identity r₀)
    (hbwd : ∀ r₀ ∈ roots₀, ∃ r ∈ roots, g.identity r = g₀.identity r₀) :
    outcome (g.labels roots) = outcome (g₀.labels roots₀) := by
  rw [closure_labels_eq wf wf₀ hc hclean hne hfwd hbwd]

end Soundness

end Cache.Admit
