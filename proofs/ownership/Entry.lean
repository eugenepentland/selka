import Invariant

/-!
# The invariant holds at function entry
-/

namespace Own

/-- The machine state at entry. -/
def entryDState (f : Function) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool) :
    DState :=
  { heap := h0, pend := pend0, env := f.initEnv args, facts := fun _ => none }

theorem mem_entry_L (cc : CCtx) (v : ValId) :
    v ∈ (entryState cc).L ↔ v ∈ cc.f.paramVals ∧ cc.st v = .owned := by
  unfold entryState
  simp [List.mem_filter]

theorem mem_entry_D (cc : CCtx) (v : ValId) :
    v ∈ (entryState cc).D ↔ v ∈ cc.f.paramVals ∧ cc.st v = .borrowed := by
  unfold entryState
  simp [List.mem_filter]

theorem lookup_map_self {α β : Type} [BEq α] [LawfulBEq α] (l : List α) (g : α → β) (w : α)
    (h : w ∈ l) : (l.map fun v => (v, g v)).lookup w = some (g w) := by
  induction l with
  | nil => simp at h
  | cons v vs ih =>
    simp only [List.map_cons, List.lookup_cons]
    by_cases hv : v == w
    · have : v = w := by simpa using hv
      subst this; simp
    · have hne : v ≠ w := by simpa using hv
      have hw : w ∈ vs := by
        rcases List.mem_cons.1 h with rfl | h'
        · exact absurd rfl hne
        · exact h'
      have hv' : (w == v) = false := by
        cases h : (w == v)
        · rfl
        · exact absurd (by simpa using h : w = v).symm hne
      simp [hv', ih hw]

theorem mem_normRoots {l : List Root} {r : Root} : r ∈ normRoots l ↔ r ∈ l := by
  unfold normRoots
  exact List.mem_eraseDups

theorem Rget_entry (cc : CCtx) (w : ValId) (hw : w ∈ (entryState cc).D) :
    Rget (entryState cc) w = normRoots (cc.c.parents w) := by
  unfold Rget entryState at *
  have hw' : w ∈ cc.f.paramVals.filter fun v => cc.st v == .borrowed := hw
  rw [lookup_map_self _ (fun v => normRoots (cc.c.parents v)) w hw']
  rfl

theorem entry_P (cc : CCtx) : (entryState cc).P = [] := rfl
theorem entry_G (cc : CCtx) : (entryState cc).G = [] := rfl
theorem entry_F (cc : CCtx) : (entryState cc).F = [] := rfl

theorem initEnv_param (f : Function) (args : Nat → Val) (hn : f.paramVals.Nodup) (n : Nat)
    (v : ValId) (h : f.paramVals[n]? = some v) : f.initEnv args v = args n := by
  unfold Function.initEnv Function.paramIdx
  rw [idxOf?_of_nodup _ hn v n h]

theorem initEnv_nonparam (f : Function) (args : Nat → Val) (v : ValId)
    (h : ∀ n : Nat, f.paramVals[n]? ≠ some v) : f.initEnv args v = .imm := by
  unfold Function.initEnv Function.paramIdx
  cases hi : idxOf? f.paramVals v with
  | none => rfl
  | some n => exact absurd (idxOf?_spec _ _ _ hi) (h n)

/-- An argument passed for a parameter whose certificate state is `scalar` is an immediate: the
parameter's type holds no allocation (the exporter's claim, AXIOMS A9). -/
def ScalarArgs (cc : CCtx) (args : Nat → Val) : Prop :=
  ∀ n v, cc.f.paramVals[n]? = some v → cc.st v = .scalar → args n = .imm

/-- The invariant holds at entry, for the entry state of the checker. -/
theorem inv_entry (cc : CCtx) (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (hs : Static cc args h0 pend0) (hsc : ScalarArgs cc args) :
    Inv cc args h0 (entryState cc) (entryDState cc.f args h0 pend0) := by
  obtain ⟨hpre, hlens, hpok, hnodup, _⟩ := hs
  obtain ⟨_, hspec⟩ := paramsOk_spec cc.c _ _ 0 hpok
  have kindOf : ∀ (n : Nat) (v : ValId), cc.f.paramVals[n]? = some v →
      ∃ k, cc.f.params[n]? = some k := by
    intro n v h
    have hlt : n < cc.f.paramVals.length := (List.getElem?_eq_some_iff.1 h).1
    exact ⟨_, List.getElem?_eq_getElem (by omega)⟩
  have kinds : ∀ (n : Nat) (v : ValId) (k : St), cc.f.paramVals[n]? = some v →
      cc.f.params[n]? = some k →
      (k = .scalar ∧ cc.st v = .scalar) ∨
      (k = .owned ∧ (cc.st v = .owned ∨ cc.st v = .scalar)) ∨
      (k = .borrowed ∧ cc.st v = .borrowed ∧ cc.c.parents v = [.caller n]) := by
    intro n v k h1 h2
    have := hspec n v k h1 h2
    simpa [CCtx.st] using this
  have mem_param : ∀ v : ValId, v ∈ cc.f.paramVals → ∃ n : Nat, cc.f.paramVals[n]? = some v := by
    intro v hv
    exact List.mem_iff_getElem?.1 hv
  have env_param : ∀ (n : Nat) (v : ValId), cc.f.paramVals[n]? = some v →
      (entryDState cc.f args h0 pend0).env v = args n := by
    intro n v h
    exact initEnv_param cc.f args hnodup n v h
  refine
    { imm := ?_, stk := ?_, nostk := ?_, Lown := ?_, Lbd := ?_, Lval := ?_, Linj := ?_, Dst := ?_, Dbd := ?_,
      Dval := ?_, Dcov := ?_, Pin := ?_, Gin := ?_, Pout := ?_, Fin := ?_, frame := ?_,
      dead := ?_, unused := ?_, acct := ?_, abLive := ?_, Ldisj := ?_, abFree := ?_, Lfree := ?_, lentSeen := ?_, lentCov := ?_, heldSeen := ?_, heldCov := ?_ }
  · intro v hv
    by_cases hp : ∃ n : Nat, cc.f.paramVals[n]? = some v
    · obtain ⟨n, hn⟩ := hp
      obtain ⟨k, hk⟩ := kindOf n v hn
      rw [env_param n v hn]
      rcases kinds n v k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · exact hpre.scalar n hk
      · rcases hs with hs | hs
        · rcases hv with hv | hv | hv | hv <;> simp [hs] at hv
        · exact hsc n v hn hs
      · rcases hv with hv | hv | hv | hv <;> simp [hs] at hv
    · exact initEnv_nonparam cc.f args v (fun n hn => hp ⟨n, hn⟩)
  · intro v hv
    by_cases hp : ∃ n : Nat, cc.f.paramVals[n]? = some v
    · obtain ⟨n, hn⟩ := hp
      obtain ⟨k, hk⟩ := kindOf n v hn
      rcases kinds n v k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [hs] at hv; cases hv
      · rcases hs with hs | hs <;> rw [hs] at hv <;> cases hv
      · rw [hs] at hv; cases hv
    · exact Or.inl (initEnv_nonparam cc.f args v (fun n hn => hp ⟨n, hn⟩))
  · intro v hv hstk
    by_cases hp : ∃ n : Nat, cc.f.paramVals[n]? = some v
    · obtain ⟨n, hn⟩ := hp
      obtain ⟨k, hk⟩ := kindOf n v hn
      rw [env_param n v hn] at hstk
      rcases kinds n v k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [hpre.scalar n hk] at hstk; cases hstk
      · rcases hpre.owned n hk with h | ⟨t, h, _⟩ <;> rw [h] at hstk <;> cases hstk
      · rcases (hpre.borrowed n hk).1 with h | ⟨fp, h⟩ <;> rw [h] at hstk <;> cases hstk
    · have hi : (entryDState cc.f args h0 pend0).env v = .imm :=
        initEnv_nonparam cc.f args v (fun n hn => hp ⟨n, hn⟩)
      rw [hi] at hstk; cases hstk
  · intro v hv
    obtain ⟨_, h2⟩ := (mem_entry_L cc v).1 hv
    simp [h2, St.owning]
  · intro v hv
    exact paramVals_lt cc.f v ((mem_entry_L cc v).1 hv).1
  · intro v hv
    obtain ⟨h1, h2⟩ := (mem_entry_L cc v).1 hv
    obtain ⟨n, hn⟩ := mem_param v h1
    obtain ⟨k, hk⟩ := kindOf n v hn
    rw [env_param n v hn]
    have hko : k = .owned := by
      rcases kinds n v k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h2] at hs; cases hs
      · rfl
      · rw [h2] at hs; cases hs
    subst hko
    rcases hpre.owned n hk with h | ⟨t, ht, hl, _⟩
    · left; exact h
    · right; exact ⟨t, ht, hl⟩
  · intro v hv w hw t hvt hwt
    obtain ⟨h1, h2⟩ := (mem_entry_L cc v).1 hv
    obtain ⟨h3, h4⟩ := (mem_entry_L cc w).1 hw
    obtain ⟨n, hn⟩ := mem_param v h1
    obtain ⟨m, hm⟩ := mem_param w h3
    obtain ⟨kn, hkn⟩ := kindOf n v hn
    obtain ⟨km, hkm⟩ := kindOf m w hm
    have hon : kn = .owned := by
      rcases kinds n v kn hn hkn with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h2] at hs; cases hs
      · rfl
      · rw [h2] at hs; cases hs
    have hom : km = .owned := by
      rcases kinds m w km hm hkm with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h4] at hs; cases hs
      · rfl
      · rw [h4] at hs; cases hs
    subst hon hom
    rw [env_param n v hn] at hvt
    rw [env_param m w hm] at hwt
    have := hpre.ownedDisjoint n m t hkn hkm hvt hwt
    subst this
    rw [hn] at hm
    exact Option.some.inj hm
  · intro w hw
    exact ((mem_entry_D cc w).1 hw).2
  · intro w hw
    exact paramVals_lt cc.f w ((mem_entry_D cc w).1 hw).1
  · intro w hw
    obtain ⟨h1, h2⟩ := (mem_entry_D cc w).1 hw
    obtain ⟨n, hn⟩ := mem_param w h1
    obtain ⟨k, hk⟩ := kindOf n w hn
    rw [env_param n w hn]
    have hkb : k = .borrowed := by
      rcases kinds n w k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h2] at hs; cases hs
      · rcases hs with hs | hs <;> rw [h2] at hs <;> cases hs
      · rfl
    subst hkb
    rcases (hpre.borrowed n hk).1 with h | ⟨fp, h⟩
    · left; exact h
    · right; exact ⟨fp, h⟩
  · intro w hw _ fp hfp x hx
    obtain ⟨h1, h2⟩ := (mem_entry_D cc w).1 hw
    obtain ⟨n, hn⟩ := mem_param w h1
    obtain ⟨k, hk⟩ := kindOf n w hn
    rw [env_param n w hn] at hfp
    have hpar : k = .borrowed ∧ cc.c.parents w = [.caller n] := by
      rcases kinds n w k hn hk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, hp⟩
      · rw [h2] at hs; cases hs
      · rcases hs with hs | hs <;> rw [h2] at hs <;> cases hs
      · exact ⟨rfl, hp⟩
    obtain ⟨rfl, hpar⟩ := hpar
    have hmem : Root.caller n ∈ Rget (entryState cc) w := by
      rw [Rget_entry cc w hw, mem_normRoots, hpar]; simp
    refine ⟨Root.caller n, hmem, rfl, hk, ?_⟩
    have halive := (hpre.borrowed n hk).2
    rw [hfp] at halive
    obtain ⟨l, hl⟩ := halive x hx
    rw [hfp]
    exact ⟨x, hx, l, hl, hl⟩
  · intro v hv
    simp [entry_P] at hv
  · intro g hg
    simp [entry_G] at hg
  · intro v hv t hvt k hpend
    obtain ⟨h1, h2⟩ := (mem_entry_L cc v).1 hv
    obtain ⟨n, hn⟩ := mem_param v h1
    obtain ⟨kk, hkk⟩ := kindOf n v hn
    rw [env_param n v hn] at hvt
    have hko : kk = .owned := by
      rcases kinds n v kk hn hkk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h2] at hs; cases hs
      · rfl
      · rw [h2] at hs; cases hs
    subst hko
    rcases hpre.owned n hkk with h | ⟨t', ht', _, hp⟩
    · rw [h] at hvt; cases hvt
    · rw [ht'] at hvt
      cases hvt
      simp [entryDState, hp] at hpend
  · intro f hf
    simp [entry_F] at hf
  · intro x t hx _; exact hx
  · intro x hx; exact hx
  · intro x hx; exact hx
  · intro x t hx
    by_cases hO : OwnedArg cc.f args t
    · left
      obtain ⟨n, hn, hargs⟩ := hO
      obtain ⟨hlen, _⟩ := paramsOk_spec cc.c _ _ 0 hpok
      have hlt : n < cc.f.paramVals.length := by
        have := (List.getElem?_eq_some_iff.1 hn).1; omega
      let v := cc.f.paramVals[n]'hlt
      have hv : cc.f.paramVals[n]? = some v := by simp [v]
      have hstv : cc.st v = .owned := by
        obtain ⟨_, hspec2⟩ := paramsOk_spec cc.c _ _ 0 hpok
        have := hspec2 n v .owned hv hn
        rcases this with ⟨h, _⟩ | ⟨_, hs⟩ | ⟨h, _⟩
        · cases h
        · rcases hs with hs | hs
          · exact hs
          · exfalso
            have himm : args n = .imm := hsc n v hv hs
            rw [himm] at hargs; cases hargs
        · cases h
      refine ⟨v, (mem_entry_L cc v).2 ⟨List.mem_of_getElem? hv, hstv⟩, ?_⟩
      rw [env_param n v hv, hargs]
    · right; left; exact ⟨hx, hO⟩
  · intro t h
    exact False.elim h
  · intro v _ t _ h
    exact h
  · intro t h
    exact False.elim h
  · intro v hv t hvt x hx
    obtain ⟨h1, h2⟩ := (mem_entry_L cc v).1 hv
    obtain ⟨n, hn⟩ := mem_param v h1
    obtain ⟨kk, hkk⟩ := kindOf n v hn
    rw [env_param n v hn] at hvt
    have hko : kk = .owned := by
      rcases kinds n v kk hn hkk with ⟨rfl, hs⟩ | ⟨rfl, hs⟩ | ⟨rfl, hs, _⟩
      · rw [h2] at hs; cases hs
      · rfl
      · rw [h2] at hs; cases hs
    subst hko
    exact ⟨n, hkk, hvt⟩
  · intro g x h
    exact False.elim h
  · intro g x h
    exact False.elim h
  · intro g x h
    exact False.elim h
  · intro g x h
    exact False.elim h

end Own
