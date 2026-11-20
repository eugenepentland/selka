import Semantics
import Checker

/-!
# Facts about the checker's Boolean tests

The checker is written with `Bool`-valued tests (`List.contains`, `List.all`, `==`).  This
file turns the ones the soundness proof needs into statements about membership, and
summarises what a passed instruction check (`InstOk`) and a passed edge check say.
-/

namespace Own

/-! ## Boolean helpers -/

theorem sub_iff {α : Type} [BEq α] [LawfulBEq α] (a b : List α) :
    sub a b = true ↔ ∀ x ∈ a, x ∈ b := by
  simp [sub]

theorem same_iff {α : Type} [BEq α] [LawfulBEq α] (a b : List α) :
    same a b = true ↔ ∀ x, x ∈ a ↔ x ∈ b := by
  unfold same
  simp only [Bool.and_eq_true, sub_iff]
  constructor
  · intro ⟨h1, h2⟩ x; exact ⟨h1 x, h2 x⟩
  · intro h; exact ⟨fun x hx => (h x).1 hx, fun x hx => (h x).2 hx⟩

theorem mem_without {α : Type} [BEq α] [LawfulBEq α] (l rm : List α) (x : α) :
    x ∈ without l rm ↔ x ∈ l ∧ x ∉ rm := by
  simp [without]

theorem nodupB_iff {α : Type} [BEq α] [LawfulBEq α] (l : List α) :
    nodupB l = true ↔ l.Nodup := by
  induction l with
  | nil => simp [nodupB]
  | cons x xs ih => simp [nodupB, ih, List.nodup_cons]

theorem find?_none_forall {α : Type} (l : List (α × Bool))
    (h : (l.find? fun p => !p.2) = none) : ∀ p ∈ l, p.2 = true := by
  intro p hp
  rw [List.find?_eq_none] at h
  have := h p hp
  simpa using this

/-- A list of tagged checks with no failure: all pass. -/
theorem chk_all {l : List Chk} (h : firstFail l = none) : ∀ p ∈ l, p.2.2 = true := by
  intro p hp
  unfold firstFail at h
  rw [Option.map_eq_none_iff, List.find?_eq_none] at h
  have := h p hp
  simpa using this

/-! ## The state components as membership -/

theorem rootLive_val (σ : AbsState) (n : ValId) : rootLive σ (.val n) = true ↔ n ∈ σ.L := by
  simp [rootLive]

theorem rootLive_slot (σ : AbsState) (n : ValId) (k : String) :
    rootLive σ (.slot n k) = true ↔ n ∈ σ.L := by
  simp [rootLive]

theorem rootLive_fwd (σ : AbsState) (n : ValId) : rootLive σ (.fwd n) = true ↔ n ∈ σ.L := by
  simp [rootLive]

theorem rootLive_caller (σ : AbsState) (i : Nat) : rootLive σ (.caller i) = true := by
  simp [rootLive]

theorem usable_borrowed {cc : CCtx} {σ : AbsState} {v : ValId} (hv : cc.st v = .borrowed)
    (hu : usable cc σ v = true) :
    v ∈ σ.D ∧ ∀ ρ ∈ Rget σ v, rootLive σ ρ = true := by
  simp [usable, hv] at hu
  exact hu

theorem usable_owning {cc : CCtx} {σ : AbsState} {v : ValId} (hv : (cc.st v).owning = true)
    (hu : usable cc σ v = true) : v ∈ σ.L := by
  unfold St.owning at hv
  unfold usable at hu
  split at hv <;> simp_all

theorem usable_imm {cc : CCtx} {σ : AbsState} {v : ValId}
    (hv : cc.st v = .scalar ∨ cc.st v = .immortal) : usable cc σ v = true := by
  rcases hv with hv | hv <;> simp [usable, hv]

/-! ## What a passed instruction check says -/

/-- The checks of one instruction, as propositions. -/
structure InstOk (cc : CCtx) (σ : AbsState) (i : Inst) : Prop where
  par : parentsOk cc i = true
  r3 : ∀ r ∈ i.reads, cc.st r ≠ .borrowed → usable cc σ r = true
  r4 : ∀ r ∈ i.reads, cc.st r = .borrowed → usable cc σ r = true
  pu : parentsUsable cc σ i = true
  c5 : ∀ k ∈ i.consumes, cc.st k ≠ .borrowed
  c2 : ∀ k ∈ i.consumes,
    (cc.st k = .scalar ∨ cc.st k = .immortal ∨ cc.st k = .stack ∨ cc.st k = .none) ∨
    ((cc.st k).owning = true ∧ k ∈ σ.L)
  j6a : (cc.ownConsumed i).Nodup
  j6b : ∀ k ∈ cc.ownConsumed i, k ∉ i.reads
  j6c : ∀ k ∈ cc.ownConsumed i, ∀ o ∈ i.reads ++ i.consumes, o ≠ k →
    (∀ r ∈ rootsOf cc σ o, r.ownedBy k = false) ∨ loanOfOwnedConstruct cc i o = true
  j7 : stackOk cc i = true
  j8a : ∀ k ∈ cc.ownConsumed i, σ.pendingAny k = true →
    i.isClosing = true ∧ i.consumes.head? = some k
  j8take : takeOk cc σ i = true
  j8close : closeOk cc σ i = true
  guard : ∀ d, i.dst = some d → i.cls = .parameter ∨ ∀ g ∈ σ.G, g.2.2.1.mentions d = false
  dstNew : ∀ d, i.dst = some d → i.cls ≠ .parameter → (cc.st d).owning = true → d ∉ σ.L
  /-- the shape of a lend (J1, design §10.2) -/
  lend : lendOk cc i = true
  /-- a group is consumed only by its join (J2, design §10.4) -/
  gj : groupJoinOk cc σ i = true
  /-- no loan held by a live owned value ends here, unless the holder is consumed by the instruction and
  its loans end with it (J4) -/
  loans : ∀ x ∈ σ.L, ((cc.ownConsumed i).contains x = true ∧ carries cc i = false) ∨
    ∀ r ∈ Rget σ x, r.endsAt (dyingOwners cc i) (takenSlot cc i) = false
  /-- the class and the state agree with the operation table (J1 `classOk`) -/
  cok : classOk cc i = true
  /-- the call line names an entry of the callee table (J1 `call-entry`, C9.2) -/
  centry : callEntryOk cc i = true
  /-- the arguments fit the entry's parameters (J1 `call-arity`) -/
  carity : callArityOk cc i = true
  /-- a scalar parameter receives a scalar (J1 `call-scalar`, A9) -/
  cscalar : callScalarOk cc i = true
  /-- the value follows the entry's result (J1 `call-result`) -/
  cresult : callResultOk cc i = true
  /-- a borrowed value lists the arguments of the borrow contract as parents (J1 `call-from`) -/
  cfrom : callFromOk cc i = true
  /-- a constructor with an owned or `emptied` result reads a borrow only of an owner it consumes, or one it lists
  as a parent (J6 `construct-read`, lane VAL); the proof does not use it (NOTES item 13) -/
  cread : constructReadOk cc σ i = true

theorem mem_ownConsumed {cc : CCtx} {i : Inst} {k : ValId} :
    k ∈ cc.ownConsumed i ↔ k ∈ i.consumes ∧ (cc.st k).owning = true := by
  simp [CCtx.ownConsumed]

theorem instOk_of_fail_none {cc : CCtx} {σ : AbsState} {i : Inst}
    (h : instFail cc σ i = none) : InstOk cc σ i := by
  have hall : ∀ p ∈ instChecks cc σ i, p.2.2 = true := chk_all h
  simp only [instChecks, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp,
    forall_eq] at hall
  obtain ⟨h1, h1l, _hviews, h1b, hce, hca, hcs, hcr, hcf, h3, h4, h4b, h5, h2, hgj, h7, h6a, h6b, h6c, hcrd, h8t, h8a, h8c, hloan, hg, hdst, _hnull⟩ := hall
  refine ⟨h1b, ?_, ?_, h4b, ?_, ?_, ?_, ?_, ?_, h7, ?_, h8t, h8c, ?_, ?_, h1l, hgj, ?_, h1, hce, hca, hcs, hcr, hcf, hcrd⟩
  · intro r hr hne
    have := List.all_eq_true.1 h3 r hr
    simpa [hne] using this
  · intro r hr hb
    have := List.all_eq_true.1 h4 r hr
    simpa [hb] using this
  · intro k hk
    have := List.all_eq_true.1 h5 k hk
    simpa using this
  · intro k hk
    have := List.all_eq_true.1 h2 k hk
    cases hs : cc.st k <;> simp_all [St.owning]
  · exact (nodupB_iff _).1 h6a
  · intro k hk
    have := List.all_eq_true.1 h6b k hk
    simpa using this
  · intro k hk o ho hne
    have h2 := List.all_eq_true.1 (List.all_eq_true.1 h6c k hk) o ho
    simp only [Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true'] at h2
    rcases h2 with (h2 | h2) | h2
    · exact absurd h2 hne
    · left
      intro r hr
      simpa using List.any_eq_false.1 h2 r hr
    · right; exact h2
  · intro k hk hkP
    have h : (cc.ownConsumed i).all (fun k => !σ.pendingAny k || (i.isClosing && i.consumes.head? == some k)) = true := by
      unfold pendingOk at h8a
      simp only [Bool.and_eq_true] at h8a
      exact h8a.1
    have := List.all_eq_true.1 h k hk
    simpa [hkP] using this
  · intro d hd
    simp only [hd] at hg
    by_cases hp : i.cls = .parameter
    · left; exact hp
    · right
      intro g hgm
      simp only [hp, beq_iff_eq, Bool.or_eq_true, Bool.not_eq_true', false_or] at hg
      have := List.any_eq_false.1 hg g hgm
      simpa using this
  · intro d hd hnp hown
    simp only [hd] at hdst
    simp only [hnp, beq_iff_eq, Bool.or_eq_true, Bool.false_or] at hdst
    simpa [hown] using hdst
  · intro x hx
    unfold loansOk at hloan
    have := List.all_eq_true.1 hloan x hx
    simp only [Bool.or_eq_true, Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true] at this
    exact this

end Own
