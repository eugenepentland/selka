import Facts.Sound

/-!
# Proven checks cannot fail (design §7, item 3)

An instruction accepted by F7 as `proven` is never undefined behaviour: its operands lie in the intervals of its
site, and the row of its operation rules out the failing case of its form.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem ite_proven {p : Prop} [Decidable p] {x y : Out} (h : (if p then x else y) = Out.proven) :
    x = Out.proven ∨ y = Out.proven := by
  by_cases hp : p
  · left; simpa [hp] using h
  · right; simpa [hp] using h

theorem proven_unpack {c : Ctx} {i : Inst} {here : Nat} (h : c.provenOut i here = .proven)
    (hnv : c.partsVacuous i here = false) :
    ∃ claim0 claim1 : Option Interval, hasRow i.op = true ∧
      provenCheck claim0 (c.derivedParts i here).1 = true ∧ provenCheck claim1 (c.derivedParts i here).2 = true ∧
      (rowHolds i claim0 claim1).getD false = true := by
  unfold Ctx.provenOut at h
  by_cases hr : hasRow i.op = true
  · simp only [hr, Bool.not_true, Bool.false_eq_true, ite_false] at h
    cases hs : c.site? i.value with
    | none => rw [hs] at h; simp at h
    | some site =>
      rw [hs] at h
      simp only [hnv, Bool.false_eq_true, ite_false] at h
      refine ⟨site.parts[0]?.bind id, site.parts[1]?.bind id, hr, ?_⟩
      by_cases hc : (provenCheck (site.parts[0]?.bind id) (c.derivedParts i here).fst &&
          provenCheck (site.parts[1]?.bind id) (c.derivedParts i here).snd) = true
      · simp only [Bool.and_eq_true] at hc
        refine ⟨hc.1, hc.2, ?_⟩
        by_cases hrow : (rowHolds i (site.parts[0]?.bind id) (site.parts[1]?.bind id)).getD false = true
        · exact hrow
        · simp only [hc, Bool.and_eq_true, Bool.not_true, Bool.false_eq_true, ite_false, hrow] at h
          exfalso
          revert h
          cases hop : i.op <;> simp [hop] <;>
            (try (intro hh; split at hh
                  · cases hh
                  · rcases ite_proven hh with h | h
                    · cases h
                    · rcases ite_proven h with h | h <;> cases h)) <;>
            (try (intro hh; split at hh <;> cases hh))
      · simp [hc] at h
  · simp [hr] at h

/-- The registers the check of an instruction reads are integers (those `Ctx.partsVacuous` looks at). -/
def ReadsInts (R : Regs) (i : Inst) : Prop :=
  match i.op with
  | .add | .sub | .mul | .div | .rem | .floorDiv | .floorRem =>
    (∃ wa na, i.operands.a = some wa ∧ R wa = some (.int na)) ∧ (∃ wb nb, i.operands.b = some wb ∧ R wb = some (.int nb))
  | .neg | .convert => ∃ wa na, i.operands.a = some wa ∧ R wa = some (.int na)
  | .shiftLeft | .shiftRight | .arrayGet | .arraySet | .listGet | .listGetField | .listSet =>
    ∃ wb nb, i.operands.b = some wb ∧ R wb = some (.int nb)
  | _ => True

/-- A check whose registers are integers is not vacuous. -/
theorem partsVacuous_false {c : Ctx} {R : Regs} {i : Inst} {here : Nat}
    (hop : OperandSound c R here (· ∈ regOps i))
    (hint : ∀ w n, R w = some (.int n) → ∃ lim, (c.def_ w).ty.range = some lim) (hr : ReadsInts R i) :
    c.partsVacuous i here = false := by
  unfold Ctx.partsVacuous
  unfold ReadsInts at hr
  have hnc : ∀ op, i.op = op → op ≠ .call → i.op ≠ .call := fun op h h' => by rw [h]; exact h'
  cases hopc : i.op <;> rw [hopc] at hr <;> simp only [] at hr ⊢
  case add | sub | mul | div | rem | floorDiv | floorRem =>
    obtain ⟨⟨wa, na, ha, hRa⟩, ⟨wb, nb, hb, hRb⟩⟩ := hr
    have hnc' : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [ha, hb, emptyView_false hop (mem_regOps_a hnc' ha) hRa (hint wa na hRa),
      emptyView_false hop (mem_regOps_b hb) hRb (hint wb nb hRb), Bool.or_false]
  case neg | convert =>
    obtain ⟨wa, na, ha, hRa⟩ := hr
    have hnc' : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [ha, emptyView_false hop (mem_regOps_a hnc' ha) hRa (hint wa na hRa)]
  case shiftLeft | shiftRight | arrayGet | arraySet | listGet | listGetField | listSet =>
    obtain ⟨wb, nb, hb, hRb⟩ := hr
    simp only [hb, emptyView_false hop (mem_regOps_b hb) hRb (hint wb nb hRb)]
  all_goals rfl

/-- An operation that is undefined behaviour read its integer registers. -/
theorem ub_reads_ints {R : Regs} {args : List Val} {i : Inst} {ch : Val} (hub : evalInst R args i ch = .ub) :
    ReadsInts R i := by
  have hns : evalInst R args i ch ≠ .stuck := by rw [hub]; intro h; cases h
  unfold ReadsInts
  cases hopc : i.op
  case add | sub | mul | div | rem | floorDiv | floorRem =>
    obtain ⟨wa, wb, na, nb, ha, hb, hRa, hRb⟩ := two_ints_of_eval (by simp [hopc]) hns
    exact ⟨⟨wa, na, ha, hRa⟩, ⟨wb, nb, hb, hRb⟩⟩
  case neg | convert =>
    obtain ⟨wa, na, ha, hRa⟩ := one_int_of_eval (by simp [hopc]) hns
    exact ⟨wa, na, ha, hRa⟩
  case shiftLeft | shiftRight =>
    obtain ⟨wa, wb, na, nb, ha, hb, hRa, hRb⟩ := two_ints_of_eval (by simp [hopc]) hns
    exact ⟨wb, nb, hb, hRb⟩
  case arrayGet | arraySet | listGet | listSet =>
    exact index_int_of_eval (by simp [hopc]) hns
  case listGetField =>
    exfalso
    unfold evalInst evalOps at hub
    simp [hopc] at hub
  all_goals trivial

theorem range_wide {t : Ty} {lim : Interval} {n : Int} (h : t.range = some lim) (hn : lim.contains n) :
    wideIv.contains n := by
  obtain ⟨h1, h2⟩ := hn
  show -(2 : Int) ^ 65 ≤ n ∧ n ≤ 2 ^ 65
  cases t <;> simp [Ty.range, Ty.bits, Ty.signed] at h <;> subst h <;> simp only [] at h1 h2 <;> constructor <;> omega

theorem range_neg {t : Ty} {lim : Interval} (h : t.range = some lim) (hlo : lim.lo ≠ 0) : lim.hi = -lim.lo - 1 := by
  obtain ⟨hn, h1, h2⟩ := range_eq_arith h
  unfold Arith.lo at h1
  unfold Arith.hi at h2
  cases hs : t.signed
  · rw [hs] at h1; simp at h1; exact absurd h1 hlo
  · rw [hs] at h1 h2; simp at h1 h2; omega

/-- A viewed operand lying within a site's claim puts the register's value in the claim. -/
theorem claim_mem {c : Ctx} {R : Regs} {B : Nat} {i : Inst} {o : Option Nat} {n : Int} {claim : Option Interval}
    (hop : OperandSound c R B (· ∈ regOps i)) (hmem : ∀ w, o = some w → w ∈ regOps i)
    (hty : ∀ w n, R w = some (.int n) → ∃ lim, (c.def_ w).ty.range = some lim ∧ lim.contains n)
    (hrd : (R.read o).bind Val.int? = some n) (hchk : provenCheck claim (c.operand o B) = true) :
    (claim.getD wideIv).contains n := by
  obtain ⟨w, ho, hRw⟩ := read_int hrd
  subst ho
  obtain ⟨lim, hl, hlc⟩ := hty w n hRw
  have hraw : c.operandRaw (some w) B = some ((viewN c (viewFuel c) w B).getD lim) := by
    simp only [Ctx.operandRaw, operandWith, hl]
  obtain ⟨n', lim', hR', hI, hl', hlc'⟩ := hop w _ (hmem w rfl) hraw
  rw [hRw] at hR'
  simp only [Option.some.injEq, Val.int.injEq] at hR'
  subst hR'
  have hop' : c.operand (some w) B = some ((viewN c (viewFuel c) w B).getD lim) := by
    unfold Ctx.operand
    rw [hraw]
    simp only [isEmpty_false_of_contains hI, Bool.false_eq_true, ite_false]
  cases claim with
  | none => exact range_wide hl hlc
  | some part =>
    rw [hop'] at hchk
    simp only [provenCheck] at hchk
    exact within_contains hchk hI


theorem ofInt_ne_ub {t : Ty} {ck : Check} {r : Int} (h : ∀ lim, t.range = some lim → lim.contains r) :
    Res.ofInt t ck r ≠ .ub := by
  unfold Res.ofInt
  cases hr : t.range with
  | none => simp
  | some lim =>
    have := h lim hr
    simp only [this.1, this.2, and_self, ite_true]
    simp

theorem failWith_proven_ub (ck : Check) (h : ck ≠ .exact) : failWith ck = .ub := by
  cases ck <;> simp [failWith] at h ⊢

theorem vt_int {c : Ctx} {fr : Frame} (hinv : FrameInv c fr) :
    ∀ w n, fr.regs w = some (.int n) → ∃ lim, (c.def_ w).ty.range = some lim ∧ lim.contains n := by
  intro w n h
  have hv := (hinv.val w _ h).1
  obtain ⟨lim, hl⟩ := int_typed hv
  obtain ⟨n', hn', hc⟩ := ValTy.int hl hv
  simp only [Val.int.injEq] at hn'
  subst hn'
  exact ⟨lim, hl, hc⟩

theorem arith_row_safe {i : Inst} {op : Op} {first second : Interval} {r : Int}
    (hw : (arithmetic op first second).within (i.ty.range.getD anyIv) = true)
    (hr : (arithmetic op first second).contains r) : Res.ofInt i.ty i.check r ≠ .ub := by
  apply ofInt_ne_ub
  intro lim hl
  have := within_contains hw hr
  rw [hl] at this
  exact this

theorem claim_len {c : Ctx} {a : Nat} {l : List Val} {claim : Option Interval} {part : Interval}
    (hlh : ListHolds c a l) (hclaim : claim = some part)
    (hchk : provenCheck claim ((c.listFact? (c.liveList c.count a)).bind (·.len)) = true) :
    part.contains l.length := by
  subst hclaim
  unfold ListHolds at hlh
  cases hf : c.listFact? (c.liveList c.count a) with
  | none => rw [hf] at hchk; simp [provenCheck] at hchk
  | some fact =>
    rw [hf] at hlh hchk
    simp only [Option.bind_some] at hchk
    cases hfl : fact.len with
    | none => rw [hfl] at hchk; simp [provenCheck] at hchk
    | some known =>
      rw [hfl] at hchk
      simp only [provenCheck] at hchk
      exact within_contains hchk (hlh.1 known hfl)

theorem vt_lim {c : Ctx} {fr : Frame} (hinv : FrameInv c fr) {i : Inst} {w : Nat} {n : Int}
    (hw : ∃ w', i.operands.a = some w' ∧ (c.def_ w').ty = i.ty) (ha : i.operands.a = some w)
    (hR : fr.regs w = some (.int n)) : ∀ lim, i.ty.range = some lim → lim.contains n := by
  intro lim hl
  obtain ⟨w', hw', hty⟩ := hw
  rw [ha] at hw'
  cases hw'
  obtain ⟨lim', hl', hc'⟩ := vt_int hinv w n hR
  rw [hty, hl] at hl'
  cases hl'
  exact hc'

theorem vt_lim_b {c : Ctx} {fr : Frame} (hinv : FrameInv c fr) {i : Inst} {w : Nat} {n : Int}
    (hw : ∃ w', i.operands.b = some w' ∧ (c.def_ w').ty = i.ty) (ha : i.operands.b = some w)
    (hR : fr.regs w = some (.int n)) : ∀ lim, i.ty.range = some lim → lim.contains n := by
  intro lim hl
  obtain ⟨w', hw', hty⟩ := hw
  rw [ha] at hw'
  cases hw'
  obtain ⟨lim', hl', hc'⟩ := vt_int hinv w n hR
  rw [hty, hl] at hl'
  cases hl'
  exact hc'

theorem proven_safe {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i)
    (hout : c.provenOut i fr.blk = .proven) (harr : ArrayTy fr.regs fr.args i) (ch : Val) :
    evalInst fr.regs fr.args i ch ≠ .ub := by
  have hop := operandSound_inv hc hw hinv hadm hb hk
  have hty := hc.opTyped hb (List.mem_of_getElem? hk)
  have hvt := vt_int hinv
  intro hub
  obtain ⟨claim0, claim1, hrow, hchk0, hchk1, hrh⟩ := proven_unpack hout
    (partsVacuous_false hop (fun w n h => (hvt w n h).imp fun _ h => h.1) (ub_reads_ints hub))
  unfold evalInst evalOps at hub
  unfold OpTyped at hty
  unfold rowHolds at hrh
  unfold Ctx.derivedParts at hchk0 hchk1
  cases hopc : i.op
  case add =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
        have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        exact arith_row_safe hrh.1 (arithmetic_contains (op := .add) hnx hny) hub
  case sub =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
        have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        exact arith_row_safe hrh.1 (arithmetic_contains (op := .sub) hnx hny) hub
  case mul =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
        have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        exact arith_row_safe hrh.1 (arithmetic_contains (op := .mul) hnx hny) hub
  case shiftLeft =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
        have hg : 0 ≤ ny ∧ ny < (i.ty.bits : Int) := ⟨by have := hny.1; have := hrh.1; omega,
          by have := hny.2; have := hrh.2; omega⟩
        simp only [hg, and_self, ite_true] at hub
        cases hub
  case shiftRight =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
        have hg : 0 ≤ ny ∧ ny < (i.ty.bits : Int) := ⟨by have := hny.1; have := hrh.1; omega,
          by have := hny.2; have := hrh.2; omega⟩
        simp only [hg, and_self, ite_true] at hub
        cases hub
  case floorDiv =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1 hty
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        have hnx0 : 0 ≤ nx := by have := hnx.1; have := hrh.1; omega
        have hny0 : 0 < ny := by have := hny.1; have := hrh.2; omega
        have hne : ny ≠ 0 := by omega
        simp only [hne, ite_false] at hub
        obtain ⟨w, hw, hRw⟩ := read_int hx
        have hxl := vt_lim hinv hty.1 hw hRw
        refine ofInt_ne_ub (fun lim hl => ?_) hub
        rw [Int.fdiv_eq_ediv_of_nonneg nx (by omega)]
        have h1 : 0 ≤ nx / ny := Int.ediv_nonneg hnx0 (by omega)
        have h2 : nx / ny ≤ nx := Int.ediv_le_self _ hnx0
        have h3 := range_lo_nonpos hl
        have h4 := (hxl lim hl).2
        exact ⟨by omega, by omega⟩
  case div =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1 hty
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        have hnx0 : 0 ≤ nx := by have := hnx.1; have := hrh.1; omega
        have hny0 : 0 < ny := by have := hny.1; have := hrh.2; omega
        have hne : ny ≠ 0 := by omega
        simp only [hne, ite_false] at hub
        obtain ⟨w, hw, hRw⟩ := read_int hx
        have hxl := vt_lim hinv hty.1 hw hRw
        refine ofInt_ne_ub (fun lim hl => ?_) hub
        rw [Int.tdiv_eq_ediv_of_nonneg hnx0]
        have h1 : 0 ≤ nx / ny := Int.ediv_nonneg hnx0 (by omega)
        have h2 : nx / ny ≤ nx := Int.ediv_le_self _ hnx0
        have h3 := range_lo_nonpos hl
        have h4 := (hxl lim hl).2
        exact ⟨by omega, by omega⟩
  case floorRem =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        have hne : ny ≠ 0 := by have := hny.1; have := hrh.2; omega
        simp only [hne, ite_false] at hub
        cases hub
  case rem =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hx, hy] at hub; simp at hub
      | some ny =>
        rw [hx, hy] at hub
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
        have hne : ny ≠ 0 := by have := hny.1; have := hrh.2; omega
        simp only [hne, ite_false] at hub
        cases hub
  case neg =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1 hty
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      rw [hx] at hub
      simp only [Option.getD_some] at hrh
      have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
      obtain ⟨w, hw, hRw⟩ := read_int hx
      have hxl := vt_lim hinv hty hw hRw
      refine ofInt_ne_ub (fun lim hl => ?_) hub
      have hlim : i.ty.range.getD anyIv = lim := by rw [hl]; rfl
      rw [hlim] at hrh
      have hx1 := hxl lim hl
      by_cases hlo : lim.lo = 0
      · simp only [hlo, beq_self_eq_true, ite_true, Bool.and_eq_true, beq_iff_eq] at hrh
        have h1 := hnx.1
        have h2 := hnx.2
        exact ⟨by have := hx1.2; omega, by have := hx1.2; omega⟩
      · have hlo' : (lim.lo == 0) = false := by simp [hlo]
        simp only [hlo', Bool.false_eq_true, ite_false, decide_eq_true_eq] at hrh
        have h1 := hnx.1
        have hhi := range_neg hl hlo
        exact ⟨by have := hx1.2; omega, by omega⟩
  case convert =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_val hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hx : (fr.regs.read i.operands.a).bind Val.int? with
    | none => rw [hx] at hub; simp at hub
    | some nx =>
      rw [hx] at hub
      simp only [Option.getD_some] at hrh
      have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
      refine ofInt_ne_ub (fun lim hl => ?_) hub
      have hlim : i.ty.range.getD anyIv = lim := by rw [hl]; rfl
      rw [hlim] at hrh
      exact within_contains hrh hnx
  case arrayGet =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    obtain ⟨l, hla, hlen⟩ := harr (Or.inl hopc)
    simp only [hopc, readOps_b] at hub hrh hchk0 hchk1
    rw [hla] at hub
    simp only [Option.bind_some, Val.list?] at hub
    cases hy : (fr.regs.read i.operands.b).bind Val.int? with
    | none => rw [hy] at hub; simp at hub
    | some k =>
      rw [hy] at hub
      simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
      have hk := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
      have hg : 0 ≤ k ∧ k < (l.length : Int) := ⟨by have := hk.1; have := hrh.1; omega,
        by have := hk.2; have := hrh.2; omega⟩
      simp only [hg, and_self, ite_true] at hub
      cases hub
  case arraySet =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    obtain ⟨l, hla, hlen⟩ := harr (Or.inr hopc)
    simp only [hopc, readOps_b] at hub hrh hchk0 hchk1
    rw [hla] at hub
    simp only [Option.bind_some, Val.list?] at hub
    cases hy : (fr.regs.read i.operands.b).bind Val.int? with
    | none => rw [hy] at hub; simp at hub
    | some k =>
      rw [hy] at hub
      simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
      have hk := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
      have hg : 0 ≤ k ∧ k < (l.length : Int) := ⟨by have := hk.1; have := hrh.1; omega,
        by have := hk.2; have := hrh.2; omega⟩
      cases hxs : (readOps fr.regs fr.args i).x with
      | nil => rw [hxs] at hub; simp at hub
      | cons e rest =>
        cases e with
        | none => rw [hxs] at hub; simp at hub
        | some e =>
          rw [hxs] at hub
          simp only [hg, and_self, ite_true] at hub
          cases hub
  case listGet =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_of_ne hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hl : (fr.regs.read i.operands.a).bind Val.list? with
    | none => rw [hl] at hub; simp at hub
    | some l =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hl, hy] at hub; simp at hub
      | some k =>
        rw [hl, hy] at hub
        obtain ⟨w, hwa, hRw⟩ := read_list hl
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        obtain ⟨⟨hsome, hlo⟩, hhi⟩ := hrh
        obtain ⟨part, hpart⟩ := Option.isSome_iff_exists.mp hsome
        have hk := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
        simp only [hwa] at hchk1
        have hlen := claim_len (listHolds_of_fact (hinv.lst w l hRw c.count)) hpart hchk1
        rw [hpart] at hhi
        simp only [Option.getD_some] at hhi
        have hg : 0 ≤ k ∧ k < (l.length : Int) := ⟨by have := hk.1; omega, by have := hk.2; have := hlen.1; omega⟩
        simp only [hg, and_self, ite_true] at hub
        cases hub
  case listGetField =>
    simp only [hopc] at hub
    cases hub
  case listSet =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_of_ne hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hl : (fr.regs.read i.operands.a).bind Val.list? with
    | none => rw [hl] at hub; simp at hub
    | some l =>
      cases hy : (fr.regs.read i.operands.b).bind Val.int? with
      | none => rw [hl, hy] at hub; simp at hub
      | some k =>
        rw [hl, hy] at hub
        obtain ⟨w, hwa, hRw⟩ := read_list hl
        simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
        obtain ⟨⟨hsome, hlo⟩, hhi⟩ := hrh
        obtain ⟨part, hpart⟩ := Option.isSome_iff_exists.mp hsome
        have hk := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
        simp only [hwa] at hchk1
        have hlen := claim_len (listHolds_of_fact (hinv.lst w l hRw c.count)) hpart hchk1
        rw [hpart] at hhi
        simp only [Option.getD_some] at hhi
        have hg : 0 ≤ k ∧ k < (l.length : Int) := ⟨by have := hk.1; omega, by have := hk.2; have := hlen.1; omega⟩
        cases hxs : (readOps fr.regs fr.args i).x with
        | nil => rw [hxs] at hub; simp at hub
        | cons e rest =>
          cases e with
          | none => rw [hxs] at hub; simp at hub
          | some e =>
            rw [hxs] at hub
            simp only [hg, and_self, ite_true] at hub
            cases hub
  case listPop =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc, readOps_a_of_ne hnc, readOps_b] at hub hrh hchk0 hchk1
    cases hl : (fr.regs.read i.operands.a).bind Val.list? with
    | none => rw [hl] at hub; simp at hub
    | some l =>
      rw [hl] at hub
      obtain ⟨w, hwa, hRw⟩ := read_list hl
      simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
      obtain ⟨hsome, hone⟩ := hrh
      obtain ⟨part, hpart⟩ := Option.isSome_iff_exists.mp hsome
      simp only [hwa] at hchk0
      have hlen := claim_len (listHolds_of_fact (hinv.lst w l hRw c.count)) hpart hchk0
      rw [hpart] at hone
      simp only [Option.getD_some] at hone
      have hne : l.isEmpty = false := by
        cases l with
        | nil => have h1 := hlen.1; simp at h1; omega
        | cons x xs => rfl
      simp only [hne, Bool.false_eq_true, ite_false] at hub
      cases hub
  all_goals (exfalso; simp [hasRow, hopc] at hrow)


/-- Design §7, item 3: no instruction the certificate has F7 prove can fail, in any honest execution. -/
theorem proven_never_ub {m : Module} (hmod : ModOK m) (hwf : ModWf m) {cfg0 cfg : Config} (h0 : CfgInv m cfg0)
    (hr : ReachA m cfg0 cfg) {i : Inst} (hub : StepUb m cfg i) :
    ∀ (fr : Frame) (rest : Config) (c : Ctx), cfg = fr :: rest → ctxOf m fr.fn = some c →
      ∀ (b : Block), c.f.blocks[fr.blk]? = some b → b.insts[fr.pc]? = some i → c.provenOut i fr.blk ≠ .proven := by
  intro fr rest c hcfg hc b hb hk hout
  cases hub with
  | @inst fr' rest' f blk i' ch hf hb' hk' harr hev =>
    cases hcfg
    obtain ⟨c', hc', hok, hw, hff, hcm, hinv, hadm⟩ := frame_ctx hmod hwf (reach_inv hmod hwf h0 hr)
      (List.mem_cons_self ..)
    rw [hc] at hc'
    cases hc'
    have hfc : c.f = f := by
      have := (ctxOf_spec hc).1
      rw [hf] at this
      exact (Option.some.inj this).symm
    have hbb : blk = b := by
      rw [hfc] at hb
      rw [hb'] at hb
      exact (Option.some.inj hb)
    subst hbb
    rw [hk'] at hk
    cases hk
    exact proven_safe hok hw hff hinv hadm hb hk' hout harr ch hev

end Facts
