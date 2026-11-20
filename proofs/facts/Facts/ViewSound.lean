import Facts.Sem
import Facts.Wf

/-!
# Views are sound

The view of a value at a block (design §5.2) is its base interval narrowed by the comparisons that dominate the
block. This file proves one narrowing at a time: given the registers at a refining edge, a value in the interval
before is in the interval after.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem predEval_negate (p : Pred) (x y : Int) : predEval p.negate x y = !predEval p x y := by
  cases p <;> simp only [predEval, Pred.negate] <;>
    first | (rw [← decide_not]; done) | (rw [← decide_not]; exact decide_eq_decide.mpr (by omega))

theorem predEval_mirror (p : Pred) (x y : Int) : predEval p.mirror x y = predEval p y x := by
  cases p <;> simp only [predEval, Pred.mirror] <;> (exact decide_eq_decide.mpr (by omega))

/-- Narrowing by `n p m` keeps `n`. -/
theorem refineBy_sound {p : Pred} {r bound : Interval} {n m : Int} (hn : r.contains n) (hm : bound.contains m)
    (hp : predEval p n m = true) : (refineBy p r bound).contains n := by
  obtain ⟨hn1, hn2⟩ := hn
  obtain ⟨hm1, hm2⟩ := hm
  cases p <;> simp only [predEval, decide_eq_true_eq] at hp <;> simp only [refineBy, Interval.contains, Interval.meet]
    <;> omega

theorem le_sqrt_of_mul_le (k t : Nat) (h : k * k ≤ t) : k ≤ Nat.sqrt t := by
  by_cases hk : k ≤ Nat.sqrt t
  · exact hk
  · exfalso
    have h1 : Nat.sqrt t + 1 ≤ k := by omega
    have h2 : (Nat.sqrt t + 1) * (Nat.sqrt t + 1) ≤ k * k := Nat.mul_le_mul h1 h1
    have h3 := Nat.lt_succ_sqrt t
    simp only [Nat.succ_eq_add_one] at h3
    omega

/-- If `n * n ≤ top` then `|n|` is at most the integer square root of `top`. -/
theorem abs_le_isqrt {n top : Int} (h : n * n ≤ top) : -((isqrt top.toNat : Nat) : Int) ≤ n ∧
    n ≤ ((isqrt top.toNat : Nat) : Int) := by
  have hk : n.natAbs * n.natAbs ≤ top.toNat := by
    have := Int.natAbs_mul_self' n
    have h2 : (n.natAbs : Int) * (n.natAbs : Int) ≤ top := by rw [this]; exact h
    have h3 : ((n.natAbs * n.natAbs : Nat) : Int) ≤ top := by push_cast; exact h2
    omega
  have := le_sqrt_of_mul_le _ _ hk
  unfold isqrt
  omega

theorem cutTop_sound {top : Int} {r : Interval} {n : Int} (hn : r.contains n) (h : n * n ≤ top) :
    (cutTop top r).contains n := by
  obtain ⟨hn1, hn2⟩ := hn
  have hsq : 0 ≤ n * n := by
    have := Int.natAbs_mul_self' n
    rw [← this]
    exact Int.mul_nonneg (Int.natCast_nonneg _) (Int.natCast_nonneg _)
  unfold cutTop
  by_cases ht : top < 0
  · simp only [ht, ite_true]; exact ⟨hn1, hn2⟩
  · simp only [ht, ite_false, Interval.contains, Interval.meet]
    have := abs_le_isqrt h
    omega

/-- Narrowing by `n * n p m` keeps `n`. -/
theorem squareCut_sound {p : Pred} {r bound : Interval} {n m : Int} (hn : r.contains n) (hm : bound.contains m)
    (hp : predEval p (n * n) m = true) : (squareCut p r bound).contains n := by
  obtain ⟨hm1, hm2⟩ := hm
  cases p <;> simp only [predEval, decide_eq_true_eq] at hp <;> simp only [squareCut]
  · exact cutTop_sound hn (by omega)
  · exact hn
  · exact cutTop_sound hn (by omega)
  · exact cutTop_sound hn (by omega)
  · exact hn
  · exact hn


/-- The register of `o` lies in the view `low` gives it at block `at_`. -/
def OperandLow (c : Ctx) (R : Regs) (low : Nat → Nat → Option Interval) (o at_ : Nat) : Prop :=
  ∀ lim n, (c.def_ o).ty.range = some lim → R o = some (.int n) → ((low o at_).getD lim).contains n

/-- What the registers say at a refining edge `e`: the comparison's operands hold integers, the comparison has the
value that selects the arm, and each operand is in its view at the comparison's block. -/
def EdgeFacts (c : Ctx) (R : Regs) (low : Nat → Nat → Option Interval) (e : Edge) : Prop :=
  ∀ a b, e.cmp.operands.a = some a → e.cmp.operands.b = some b →
    ∃ na nb, R a = some (.int na) ∧ R b = some (.int nb) ∧
      (∀ p0, Pred.ofImm e.cmp.imm = some p0 → predEval (if e.taken then p0 else p0.negate) na nb = true) ∧
      OperandLow c R low a e.source ∧ OperandLow c R low b e.source

/-- A square operand of the comparison holds the square of its factor. -/
def SqFacts (c : Ctx) (R : Regs) (e : Edge) : Prop :=
  ∀ raw w nraw nw, (e.cmp.operands.a = some raw ∨ e.cmp.operands.b = some raw) →
    isSquareOf c (some raw) w = true → R raw = some (.int nraw) → R w = some (.int nw) → nraw = nw * nw

theorem operandWith_some {c : Ctx} {low : Nat → Nat → Option Interval} {o : Nat} {at_ : Nat} {bound : Interval}
    (h : operandWith c low (some o) at_ = some bound) :
    ∃ lim, (c.def_ o).ty.range = some lim ∧ bound = (low o at_).getD lim := by
  cases hr : (c.def_ o).ty.range with
  | none => simp [operandWith, hr] at h
  | some lim =>
    simp [operandWith, hr] at h
    exact ⟨lim, rfl, h.symm⟩

theorem refineSquareWith_sound {c : Ctx} {R : Regs} {low : Nat → Nat → Option Interval} {e : Edge} {r : Interval}
    {v : Nat} {n : Int} {a b : Nat} (ha : e.cmp.operands.a = some a) (hb : e.cmp.operands.b = some b)
    (hef : EdgeFacts c R low e) (hsq : SqFacts c R e) (hv : R v = some (.int n))
    (hn : r.contains n) : (refineSquareWith c low r v e).contains n := by
  obtain ⟨na, nb, ra, rb, hp, lowA, lowB⟩ := hef a b ha hb
  unfold refineSquareWith
  simp only [ha, hb]
  by_cases hL : isSquareOf c (some a) v = true
  · simp only [hL, Bool.not_true, Bool.false_and, Bool.false_eq_true, ite_false, ite_true]
    cases hq : Pred.ofImm e.cmp.imm with
    | none => exact hn
    | some p0 =>
      simp only []
      cases hbound : operandWith c low (some b) e.source with
      | none => exact hn
      | some bound =>
        by_cases hbe : bound.isEmpty = true
        · simp only [hbe, ite_true]; exact hn
        simp only [hbe, Bool.false_eq_true, ite_false]
        obtain ⟨lim, hlim, hbd⟩ := operandWith_some hbound
        have hnb := lowB lim nb hlim rb
        rw [← hbd] at hnb
        have hna : na = n * n := hsq a v na n (Or.inl ha) hL ra hv
        have hpe := hp p0 hq
        subst hna
        exact squareCut_sound hn hnb hpe
  · by_cases hR : isSquareOf c (some b) v = true
    · simp only [hL, hR, Bool.not_true, Bool.not_false, Bool.true_and, Bool.false_eq_true,
        ite_false, ite_true]
      cases hq : Pred.ofImm e.cmp.imm with
      | none => exact hn
      | some p0 =>
        simp only []
        cases hbound : operandWith c low (some a) e.source with
        | none => exact hn
        | some bound =>
          by_cases hbe : bound.isEmpty = true
          · simp only [hbe, ite_true]; exact hn
          simp only [hbe, Bool.false_eq_true, ite_false]
          obtain ⟨lim, hlim, hbd⟩ := operandWith_some hbound
          have hna := lowA lim na hlim ra
          rw [← hbd] at hna
          have hnb : nb = n * n := hsq b v nb n (Or.inr hb) hR rb hv
          have hpe := hp p0 hq
          subst hnb
          have hm : predEval (if e.taken = true then p0 else p0.negate).mirror (n * n) na = true := by
            rw [predEval_mirror]; exact hpe
          exact squareCut_sound hn hna hm
    · simp only [hL, hR, Bool.not_true, Bool.not_false, Bool.true_and, Bool.and_self, ite_true]
      exact hn

/-- One narrowing by a refining edge keeps a value that is in the interval. -/
theorem refineWith_sound {c : Ctx} {R : Regs} {low : Nat → Nat → Option Interval} {e : Edge} {r : Interval}
    {v : Nat} {n : Int} (hef : EdgeFacts c R low e) (hsq : SqFacts c R e) (hv : R v = some (.int n))
    (hn : r.contains n) : (refineWith c low r v e).contains n := by
  unfold refineWith
  cases ha : e.cmp.operands.a with
  | none => simp only [ha]; exact hn
  | some left =>
    cases hb : e.cmp.operands.b with
    | none => simp only [ha, hb]; exact hn
    | some right =>
      simp only [ha, hb]
      obtain ⟨na, nb, ra, rb, hp, lowA, lowB⟩ := hef left right ha hb
      by_cases hne : (left != v && right != v) = true
      · simp only [hne, ite_true]
        exact refineSquareWith_sound ha hb hef hsq hv hn
      · simp only [hne, ite_false]
        cases hq : Pred.ofImm e.cmp.imm with
        | none => exact hn
        | some p0 =>
          simp only []
          by_cases hl : left = v
          · subst hl
            simp only [bne_self_eq_false, beq_self_eq_true, ite_true, ite_false]
            cases hbound : operandWith c low (some right) e.source with
            | none => exact hn
            | some bound =>
              by_cases hbe : bound.isEmpty = true
              · simp only [hbe, ite_true]; exact hn
              simp only [hbe, Bool.false_eq_true, ite_false]
              obtain ⟨lim, hlim, hbd⟩ := operandWith_some hbound
              have hnb := lowB lim nb hlim rb
              rw [← hbd] at hnb
              have hna : na = n := by rw [ra] at hv; cases hv; rfl
              have hpe := hp p0 hq
              subst hna
              exact refineBy_sound hn hnb hpe
          · have hr : right = v := by
              by_cases hrv : right = v
              · exact hrv
              · exact absurd (by simp [hl, hrv]) hne
            subst hr
            have hl' : (left == right) = false := by simp [hl]
            have hl'' : (left != right) = true := by simp [hl]
            simp only [hl', hl'', Bool.false_eq_true, ite_false, ite_true]
            cases hbound : operandWith c low (some left) e.source with
            | none => exact hn
            | some bound =>
              by_cases hbe : bound.isEmpty = true
              · simp only [hbe, ite_true]; exact hn
              simp only [hbe, Bool.false_eq_true, ite_false]
              obtain ⟨lim, hlim, hbd⟩ := operandWith_some hbound
              have hna := lowA lim na hlim ra
              rw [← hbd] at hna
              have hnb : nb = n := by rw [rb] at hv; cases hv; rfl
              have hpe := hp p0 hq
              subst hnb
              have hm : predEval (if e.taken = true then p0 else p0.negate).mirror nb na = true := by
                rw [predEval_mirror]; exact hpe
              exact refineBy_sound hn hna hm

/-- Walking the dominator chain from `x` and narrowing at each refining edge keeps the value, when each edge's
facts hold. -/
theorem chainRefine_sound {c : Ctx} {R : Regs} {low : Nat → Nat → Option Interval} {v : Nat} {n : Int}
    (hv : R v = some (.int n))
    (steps : Nat) : ∀ (x : Nat) (r : Interval),
      (∀ y e, Anc (parentOf c.idom) y x → refining c y = some e → EdgeFacts c R low e ∧ SqFacts c R e) →
      r.contains n → (chainRefineWith c low v x steps r).contains n := by
  induction steps with
  | zero => intro x r _ hn; exact hn
  | succ steps ih =>
    intro x r hedge hn
    simp only [chainRefineWith]
    have hr' : (match refining c x with
        | some e => refineWith c low r v e
        | none => r).contains n := by
      cases hx : refining c x with
      | none => exact hn
      | some e =>
        obtain ⟨h1, h2⟩ := hedge x e (Anc.refl _) hx
        exact refineWith_sound h1 h2 hv hn
    cases hp : Ctx.parent? c x with
    | none => exact hr'
    | some d =>
      exact ih d _ (fun y e hy => hedge y e (hy.trans (Anc.step hp (Anc.refl _)))) hr'

/-- The fill caps keep a value that is at most `M` wherever a cap applies. -/
theorem capsFold_sound {c : Ctx} {v at_ : Nat} {n : Int}
    (hcap : ∀ cap ∈ c.caps, cap.value = v → c.dominates cap.block at_ = true → n ≤ maxListLength) :
    ∀ (l : List Cap), (∀ cap ∈ l, cap ∈ c.caps) → ∀ (r : Interval), r.contains n →
      (l.foldl (fun (r : Interval) (cap : Cap) =>
        if cap.value == v && c.dominates cap.block at_ then { r with hi := min r.hi maxListLength } else r) r).contains n := by
  intro l
  induction l with
  | nil => intro _ r hn; exact hn
  | cons cap rest ih =>
    intro hsub r hn
    simp only [List.foldl_cons]
    apply ih (fun x hx => hsub x (List.mem_cons_of_mem _ hx))
    by_cases h : (cap.value == v && c.dominates cap.block at_) = true
    · simp only [h, ite_true]
      have h1 : cap.value = v := by simpa using (Bool.and_eq_true_iff.mp h).1
      have h2 : c.dominates cap.block at_ = true := (Bool.and_eq_true_iff.mp h).2
      have := hcap cap (hsub cap (List.mem_cons_self ..)) h1 h2
      obtain ⟨hn1, hn2⟩ := hn
      exact ⟨hn1, by simp only []; omega⟩
    · simp only [h, ite_false]; exact hn

/-- One level of the view keeps the value. -/
theorem viewStep_sound {c : Ctx} {R : Regs} {low : Nat → Nat → Option Interval} {v at_ : Nat} {n : Int}
    (hv : R v = some (.int n))
    (hcap : ∀ cap ∈ c.caps, cap.value = v → c.dominates cap.block at_ = true → n ≤ maxListLength)
    (hedge : ∀ y e, Anc (parentOf c.idom) y at_ → refining c y = some e → EdgeFacts c R low e ∧ SqFacts c R e)
    {r0 : Interval} (hb : base c v = some r0) (hn : r0.contains n) :
    ∃ r, viewStep c low v at_ = some r ∧ r.contains n := by
  unfold viewStep
  rw [hb]
  simp only []
  refine ⟨_, rfl, ?_⟩
  apply chainRefine_sound hv _ _ _ hedge
  exact capsFold_sound hcap c.caps (fun _ h => h) r0 hn

/-- A view at block `B` keeps the value, whatever the fuel, when the registers satisfy the base intervals and the
facts of the refining edges on `B`'s dominator chain. -/
theorem viewN_sound {c : Ctx} {R : Regs} {B : Nat}
    (hbase : ∀ v n lim, (c.def_ v).ty.range = some lim → R v = some (.int n) → ((base c v).getD lim).contains n)
    (hlim : ∀ v n lim, (c.def_ v).ty.range = some lim → R v = some (.int n) → lim.contains n)
    (hcaps : ∀ cap ∈ c.caps, c.dominates cap.block B = true → ∀ n, R cap.value = some (.int n) → n ≤ maxListLength)
    (hedge : ∀ fuel y e, Anc (parentOf c.idom) y B → refining c y = some e →
      EdgeFacts c R (viewN c fuel) e ∧ SqFacts c R e)
    (fuel : Nat) {v : Nat} {n : Int} {lim : Interval} (hty : (c.def_ v).ty.range = some lim)
    (hv : R v = some (.int n)) : ((viewN c fuel v B).getD lim).contains n := by
  cases fuel with
  | zero => exact hbase v n lim hty hv
  | succ fuel =>
    simp only [viewN]
    cases hb : base c v with
    | none =>
      have := hlim v n lim hty hv
      simp only [viewStep, hb]
      exact this
    | some r0 =>
      have hn : r0.contains n := by have := hbase v n lim hty hv; rw [hb] at this; exact this
      obtain ⟨r, hr, hrn⟩ := viewStep_sound (low := viewN c fuel) hv
        (fun cap hcm hcv hd => by subst hcv; exact hcaps cap hcm hd n hv) (hedge fuel) hb hn
      rw [hr]
      exact hrn

end Facts
