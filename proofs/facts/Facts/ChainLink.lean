import Facts.Census
import Facts.Static

/-!
# The census counts what the proof covers

`Ctx.chainProvedB` (the Boolean the census counts) implies `ChainProved`, the Prop the frame invariant is stated for:
the number `factcheck --census` prints as `reductions_proved_by_chain` is a number of phis the proof covers.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem chainProvedB_sound {c : Ctx} (hc : CtxOK c) {p : Phi} {H : Nat} {tb : Block} (hy : c.f.blocks[H]? = some tb)
    (hp : p ∈ tb.phis) {stated : Interval} (h : c.chainProvedB p H stated = true) : ChainProved c p H stated := by
  obtain ⟨hkind, hblk, hphi⟩ := phi_def_of_mem hc hy hp
  unfold Ctx.chainProvedB at h
  cases hcnt : c.countedAt H with
  | none => simp [hcnt] at h
  | some k =>
    simp only [hcnt] at h
    by_cases hcond : (k.counter == p.value || p.edges.length != 2) = true
    · simp [hcond] at h
    · simp only [hcond, Bool.false_eq_true, ite_false] at h
      have hne : k.counter ≠ p.value := by
        intro heq
        apply hcond
        simp [heq]
      have hlen : p.edges.length = 2 := by
        cases h2 : (p.edges.length != 2) with
        | true => exact absurd (by simp [h2]) hcond
        | false => simpa using h2
      cases hl : p.edges[k.latchIndex]? with
      | none => simp [hl] at h
      | some latchE =>
        cases he : p.edges[1 - k.latchIndex]? with
        | none => simp [hl, he] at h
        | some entryE =>
          cases hlim : (c.def_ k.counter).ty.range with
          | none => simp [hl, he, hlim] at h
          | some lim =>
            simp only [hl, he, hlim] at h
            cases hg : c.jGrowth H (growthBudget + 2) p.value latchE.value with
            | none => simp [hg] at h
            | some step =>
              cases hs : c.operand (some entryE.value) entryE.block with
              | none => simp [hg, hs] at h
              | some start =>
                cases ht : c.tripBound H with
                | none => simp [hg, hs, ht] at h
                | some trips =>
                  cases hb : c.operand (some k.bound) H with
                  | none => simp [hg, hs, ht, hb] at h
                  | some bound =>
                    simp only [hg, hs, ht, hb, Bool.and_eq_true, decide_eq_true_eq, Bool.or_eq_true] at h
                    refine ⟨⟨k, latchE, entryE, step, start, trips, growthBudget + 2, hkind, hphi, hblk, hcnt, hne, hlen,
                      hl, he, hg, hs, ht⟩, lim, hlim, ?_, ?_⟩
                    · intro I hI
                      rw [hb] at hI
                      cases hI
                      exact h.1
                    · rcases h.2 with hw | hm
                      · exact Or.inl hw
                      · exact Or.inr (Ctx.hullMeetWithin_spec hm)

end Facts
