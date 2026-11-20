import Cache.Admit

/-!
# The planner, run: `cache_plan_reference_v2` in Lean

The same algorithm as `src/cache_plan_reference_v2.zig`, on the same bytes: it reads the `SLKCP002` request the host
sends the planner (`cache_plan_protocol_v2.zig`) and writes the payload of the reply (the reply minus its 64-byte
envelope), so a request recorded from a real `selka test` run is a trace for both planners and their replies can be
compared byte for byte.

What is *proved* is the decision that matters: a receipt is admitted iff it was a candidate and no root is dirty
(`reused_iff`), and `checkDirty` is a linear check that a dirty set is exactly the backward closure of `changed`
(`checkDirty_sound`, against `Cache.Admit.Dirty`). The program computes the dirty set the way the Zig does (breadth
first over the reverse edges, recording each node's distance from the changed nodes) and refuses to answer unless
`checkDirty` accepts it. The other outputs (the reverse index, the strongly connected groups, the batches, the work
counts) are computed, not proved; the differential compares them with the Zig's.
-/

set_option linter.unusedSimpArgs false

namespace Cache.Plan

open Cache.Admit

/-! ## The spec side: the dirty set a certificate must equal -/

/-- The call graph of a request as a `Cache.Admit.Graph` (identities are the host's business). -/
def graphOf (callees : Array (Array Nat)) : Graph Unit where
  callees x := (callees.getD x #[]).toList
  identity _ := none
  body _ := ()
  edgeIds _ := []

/-- A certificate that `dirty` is the backward closure of `changed`: it contains `changed`, is closed under callers,
and every dirty node is changed or calls a dirty node closer to a changed one (`dist`). Linear in the graph. -/
def checkDirty (callees : Array (Array Nat)) (changed dirty : Array Bool) (dist : Array Nat) : Bool :=
  dirty.size == callees.size && changed.size == callees.size &&
  (List.range callees.size).all fun x =>
    (!(changed.getD x false) || dirty.getD x false) &&
    ((callees.getD x #[]).toList.all fun y => !(dirty.getD y false) || dirty.getD x false) &&
    (!(dirty.getD x false) || changed.getD x false ||
      (callees.getD x #[]).toList.any fun y => dirty.getD y false && decide (dist.getD y 0 < dist.getD x 0))

theorem getD_ge {α : Type} (a : Array α) (i : Nat) (d : α) (h : a.size ≤ i) : a.getD i d = d := by
  simp [Array.getD, Nat.not_lt.mpr h]

/-- **A certified dirty set is the backward closure of `changed`.** -/
theorem checkDirty_sound (callees : Array (Array Nat)) (changed dirty : Array Bool) (dist : Array Nat)
    (h : checkDirty callees changed dirty dist = true) (x : Nat) :
    dirty.getD x false = true ↔ Dirty (graphOf callees) (fun y => changed.getD y false = true) x := by
  unfold checkDirty at h
  simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true, List.mem_range] at h
  obtain ⟨⟨hd, hc⟩, hall⟩ := h
  have hdirty_out : ∀ y, callees.size ≤ y → dirty.getD y false = false := fun y hy => getD_ge _ _ _ (hd ▸ hy)
  have hchg_out : ∀ y, callees.size ≤ y → changed.getD y false = false := fun y hy => getD_ge _ _ _ (hc ▸ hy)
  have hcal_out : ∀ y, callees.size ≤ y → callees.getD y #[] = #[] := fun y hy => getD_ge _ _ _ hy
  constructor
  · -- by strong induction on the distance
    have key : ∀ n, ∀ x, dist.getD x 0 = n → dirty.getD x false = true →
        Dirty (graphOf callees) (fun y => changed.getD y false = true) x := by
      intro n
      induction n using Nat.strongRecOn with
      | _ n ih =>
        intro x hn hx
        have hxn : x < callees.size := by
          by_cases hlt : x < callees.size
          · exact hlt
          · have := hdirty_out x (Nat.not_lt.mp hlt)
            rw [this] at hx; exact absurd hx (by decide)
        have h3 := (hall x hxn)
        simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', List.any_eq_true, List.all_eq_true,
          decide_eq_true_eq] at h3
        obtain ⟨_, h3⟩ := h3
        rcases h3 with (h3 | h3) | ⟨y, hy, hyd, hlt⟩
        · rw [hx] at h3; exact absurd h3 (by decide)
        · exact .base h3
        · have hyd' : dirty.getD y false = true := hyd
          exact .caller (y := y) (by simpa [graphOf] using hy)
            (ih (dist.getD y 0) (hn ▸ hlt) y rfl hyd')
    exact key _ x rfl
  · intro hD
    induction hD with
    | @base x hx =>
      have hxn : x < callees.size := by
        by_cases hlt : x < callees.size
        · exact hlt
        · have := hchg_out x (Nat.not_lt.mp hlt)
          rw [this] at hx; exact absurd hx (by decide)
      have h1 := (hall x hxn)
      simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at h1
      have h1 := h1.1.1
      rcases h1 with h1 | h1
      · rw [hx] at h1; exact absurd h1 (by decide)
      · exact h1
    | @caller x y hmem _ ih =>
      have hxn : x < callees.size := by
        by_cases hlt : x < callees.size
        · exact hlt
        · have h0 := hcal_out x (Nat.not_lt.mp hlt)
          have hmem' : y ∈ (callees.getD x #[]).toList := hmem
          rw [h0] at hmem'
          simp at hmem'
      have h2 := (hall x hxn)
      simp only [Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true', List.all_eq_true] at h2
      have h2 := h2.1.2 y (by simpa [graphOf] using hmem)
      rcases h2 with h2 | h2
      · rw [ih] at h2; exact absurd h2 (by decide)
      · exact h2

/-- The admission decision of the Zig: a test is reused iff it was a candidate and no root is dirty. -/
def reusedAt (candidates : Array Bool) (roots : Array (Array Nat)) (dirty : Array Bool) (i : Nat) : Bool :=
  candidates.getD i false && (roots.getD i #[]).toList.all fun r => !(dirty.getD r false)

/-- **The decision is the rule.** Given a certified dirty set, test `i` is reused iff it is a candidate and none of its
roots can reach a changed node: exactly the hypothesis of `Cache.Admit.admit_sound`. -/
theorem reused_iff (callees : Array (Array Nat)) (changed dirty : Array Bool) (dist : Array Nat)
    (h : checkDirty callees changed dirty dist = true) (candidates : Array Bool) (roots : Array (Array Nat))
    (i : Nat) :
    reusedAt candidates roots dirty i = true ↔
      candidates.getD i false = true ∧
        ∀ r ∈ (roots.getD i #[]).toList, ¬ Dirty (graphOf callees) (fun y => changed.getD y false = true) r := by
  simp only [reusedAt, Bool.and_eq_true, List.all_eq_true, Bool.not_eq_true']
  constructor
  · rintro ⟨hc, hr⟩
    refine ⟨hc, fun r hmem hd => ?_⟩
    have := hr r hmem
    have := (checkDirty_sound callees changed dirty dist h r).2 hd
    simp_all
  · rintro ⟨hc, hr⟩
    refine ⟨hc, fun r hmem => ?_⟩
    cases hd : dirty.getD r false
    · rfl
    · exact absurd ((checkDirty_sound callees changed dirty dist h r).1 hd) (hr r hmem)

end Cache.Plan
