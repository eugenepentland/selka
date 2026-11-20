import Facts.Proven

/-!
# What F7's rows say about the operands

For an instruction F7 accepted as `proven`, the values of its operands satisfy the row of its operation. The proof
of `Proven.lean` goes straight to "never undefined behaviour"; this file states the same facts as hypotheses of the
emitter's lowering theorems (`proofs/arith`, package C8): that is the link between the two proofs (`Connect.lean`).
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- The facts a `proven` row gives about the operand values of `i`, read from registers `R`. -/
def RowFacts (R : Regs) (i : Inst) : Prop :=
  match i.op with
  | .add => ∀ nx ny, (R.read i.operands.a).bind Val.int? = some nx → (R.read i.operands.b).bind Val.int? = some ny →
      ∀ lim, i.ty.range = some lim → lim.contains (nx + ny)
  | .sub => ∀ nx ny, (R.read i.operands.a).bind Val.int? = some nx → (R.read i.operands.b).bind Val.int? = some ny →
      ∀ lim, i.ty.range = some lim → lim.contains (nx - ny)
  | .mul => ∀ nx ny, (R.read i.operands.a).bind Val.int? = some nx → (R.read i.operands.b).bind Val.int? = some ny →
      ∀ lim, i.ty.range = some lim → lim.contains (nx * ny)
  | .div | .floorDiv | .rem | .floorRem => ∀ nx ny, (R.read i.operands.a).bind Val.int? = some nx →
      (R.read i.operands.b).bind Val.int? = some ny → 0 ≤ nx ∧ 0 < ny
  | .shiftLeft | .shiftRight => ∀ ny, (R.read i.operands.b).bind Val.int? = some ny → 0 ≤ ny ∧ ny < (i.ty.bits : Int)
  | .neg => ∀ nx, (R.read i.operands.a).bind Val.int? = some nx → ∀ lim, i.ty.range = some lim → lim.contains (-nx)
  | .convert => ∀ nx, (R.read i.operands.a).bind Val.int? = some nx → ∀ lim, i.ty.range = some lim → lim.contains nx
  | _ => True

/-- A check that reads no integers has no facts to give. -/
theorem rowFacts_of_not_reads {R : Regs} {i : Inst} (h : ¬ ReadsInts R i) : RowFacts R i := by
  unfold RowFacts
  unfold ReadsInts at h
  cases hopc : i.op <;> rw [hopc] at h <;> simp only [] at h ⊢
  case add | sub | mul | div | floorDiv | rem | floorRem =>
    intro nx ny hx hy
    first
      | (intro lim hl; exfalso; apply h
         obtain ⟨wa, ha, hRa⟩ := read_int hx
         obtain ⟨wb, hb, hRb⟩ := read_int hy
         exact ⟨⟨wa, nx, ha, hRa⟩, ⟨wb, ny, hb, hRb⟩⟩)
      | (exfalso; apply h
         obtain ⟨wa, ha, hRa⟩ := read_int hx
         obtain ⟨wb, hb, hRb⟩ := read_int hy
         exact ⟨⟨wa, nx, ha, hRa⟩, ⟨wb, ny, hb, hRb⟩⟩)
  case shiftLeft | shiftRight =>
    intro ny hy
    exfalso; apply h
    obtain ⟨wb, hb, hRb⟩ := read_int hy
    exact ⟨wb, ny, hb, hRb⟩
  case neg | convert =>
    intro nx hx lim hl
    exfalso; apply h
    obtain ⟨wa, ha, hRa⟩ := read_int hx
    exact ⟨wa, nx, ha, hRa⟩
  all_goals first | trivial | exact absurd trivial h

theorem proven_row_facts {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i)
    (hout : c.provenOut i fr.blk = .proven) : RowFacts fr.regs i := by
  have hop := operandSound_inv hc hw hinv hadm hb hk
  by_cases hr : ReadsInts fr.regs i
  rotate_left
  · exact rowFacts_of_not_reads hr
  obtain ⟨claim0, claim1, hrow, hchk0, hchk1, hrh⟩ := proven_unpack hout
    (partsVacuous_false hop (fun w n h => (vt_int hinv w n h).imp fun _ h => h.1) hr)
  have hty := hc.opTyped hb (List.mem_of_getElem? hk)
  have hvt := vt_int hinv
  unfold OpTyped at hty
  unfold rowHolds at hrh
  unfold Ctx.derivedParts at hchk0 hchk1
  unfold RowFacts
  cases hopc : i.op
  case add =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy lim hl
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    have := within_contains hrh.1 (arithmetic_contains (op := .add) hnx hny)
    rw [hl] at this
    exact this
  case sub =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy lim hl
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    have := within_contains hrh.1 (arithmetic_contains (op := .sub) hnx hny)
    rw [hl] at this
    exact this
  case mul =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy lim hl
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    have := within_contains hrh.1 (arithmetic_contains (op := .mul) hnx hny)
    rw [hl] at this
    exact this
  case div =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    exact ⟨by have := hnx.1; have := hrh.1; omega, by have := hny.1; have := hrh.2; omega⟩
  case floorDiv =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    exact ⟨by have := hnx.1; have := hrh.1; omega, by have := hny.1; have := hrh.2; omega⟩
  case rem =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    exact ⟨by have := hnx.1; have := hrh.1; omega, by have := hny.1; have := hrh.2; omega⟩
  case floorRem =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro nx ny hx hy
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk1
    exact ⟨by have := hnx.1; have := hrh.1; omega, by have := hny.1; have := hrh.2; omega⟩
  case shiftLeft =>
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro ny hy
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
    exact ⟨by have := hny.1; have := hrh.1; omega, by have := hny.2; have := hrh.2; omega⟩
  case shiftRight =>
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some, Bool.and_eq_true, decide_eq_true_eq] at hrh
    intro ny hy
    have hny := claim_mem hop (fun w hw => mem_regOps_b hw) hvt hy hchk0
    exact ⟨by have := hny.1; have := hrh.1; omega, by have := hny.2; have := hrh.2; omega⟩
  case neg =>
    have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
    simp only [hopc] at hrh hchk0 hchk1 hty
    simp only [Option.getD_some] at hrh
    intro nx hx lim hl
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    obtain ⟨w, hw', hRw⟩ := read_int hx
    have hxl := vt_lim hinv hty hw' hRw
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
    simp only [hopc] at hrh hchk0 hchk1
    simp only [Option.getD_some] at hrh
    intro nx hx lim hl
    have hnx := claim_mem hop (fun w hw => mem_regOps_a hnc hw) hvt hx hchk0
    have hlim : i.ty.range.getD anyIv = lim := by rw [hl]; rfl
    rw [hlim] at hrh
    exact within_contains hrh hnx
  all_goals trivial

end Facts
