import Facts.Wf

/-!
# Which values an instruction can read

`Avail c B pc v`: value `v` is defined, and not redefined, by the time execution is at instruction `pc` of block
`B`: a constant or parameter; a phi of a block that dominates `B`; an instruction of a block that strictly dominates
`B`, or of `B` itself before `pc`. Dominance is true dominance on the control-flow graph (`TDom`), the relation the
IR verifier's SSA rule is about (`verify_ir.zig`, `available`).
-/

namespace Facts

/-- The control-flow graph of the context's function. -/
abbrev Ctx.succ (c : Ctx) : Nat → List Nat := cfgSucc c.f

/-- Value `v` is available at instruction `pc` of block `B`. -/
def Avail (c : Ctx) (B pc v : Nat) : Prop :=
  match (c.def_ v).kind with
  | .missing => False
  | .pre => True
  | .phi => ∃ D, (c.def_ v).block = some D ∧ TDom c.succ D B
  | .inst => ∃ D, (c.def_ v).block = some D ∧ ((D = B ∧ (c.def_ v).index < pc) ∨ (D ≠ B ∧ TDom c.succ D B))

/-- The registers an instruction reads: its operands (a call's `a` is the callee, not a register). -/
def regOps (i : Inst) : List Nat :=
  (if i.op == .call then [] else i.operands.a.toList) ++ i.operands.b.toList ++ i.operands.x.filterMap id

/-- Every use is dominated by its definition (what the IR verifier checks, `verify_ir.zig`): an operand is available
where its instruction runs, a phi operand at the end of its predecessor, a branch condition and a returned value at
the end of their block. Only reached blocks are constrained. -/
structure SsaWf (c : Ctx) : Prop where
  inst : ∀ {D k : Nat} {b : Block} {i : Inst} {v : Nat}, c.f.blocks[D]? = some b → b.insts[k]? = some i →
    Reach c.succ D → v ∈ regOps i → Avail c D k v
  phi : ∀ {D : Nat} {b : Block} {p : Phi} {e : PhiEdge} {pb : Block}, c.f.blocks[D]? = some b → p ∈ b.phis →
    e ∈ p.edges → c.f.blocks[e.block]? = some pb → Reach c.succ e.block →
    Avail c e.block pb.insts.length e.value
  branch : ∀ {D : Nat} {b : Block} {cond t e : Nat}, c.f.blocks[D]? = some b → b.term = .branch cond t e →
    Reach c.succ D → Avail c D b.insts.length cond
  ret : ∀ {D : Nat} {b : Block} {v : Nat}, c.f.blocks[D]? = some b → b.term = .ret (some v) →
    Reach c.succ D → Avail c D b.insts.length v

section Lemmas
variable {c : Ctx}

theorem Ctx.def_of_get? {v : Nat} {d : Def} (h : c.defs[v]? = some d) : c.def_ v = d := by
  simp [Ctx.def_, h]

theorem CtxOK.def_inst (hc : CtxOK c) {D k : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[D]? = some b)
    (hk : b.insts[k]? = some i) : c.def_ i.value = instDef D k i :=
  Ctx.def_of_get? (defsOK_inst hc.defs hb hk)

theorem CtxOK.def_phi (hc : CtxOK c) {D k : Nat} {b : Block} {p : Phi} (hb : c.f.blocks[D]? = some b)
    (hk : b.phis[k]? = some p) : c.def_ p.value = phiDef D k p :=
  Ctx.def_of_get? (defsOK_phi hc.defs hb hk)

theorem CtxOK.def_pre (hc : CtxOK c) {k : Nat} {i : Inst} (hk : c.f.pre[k]? = some i) :
    c.def_ i.value = preDef i k :=
  Ctx.def_of_get? (defsOK_pre hc.defs hk)

/-- A value whose definition is an instruction is the value of an instruction at the recorded position. -/
theorem CtxOK.inst_of_def (hc : CtxOK c) {v : Nat} (hk : (c.def_ v).kind = .inst) :
    ∃ D b i, (c.def_ v).block = some D ∧ c.f.blocks[D]? = some b ∧ b.insts[(c.def_ v).index]? = some i ∧
      i.value = v ∧ (c.def_ v).inst = some i := by
  have hd : c.defs[v]? = some (c.def_ v) := by
    unfold Ctx.def_ at hk ⊢
    cases hv : c.defs[v]? with
    | none => simp [hv] at hk <;> simp [Def.kind] at hk
    | some d => simp
  exact defItemOK_inst hk (defsOK_conv hc.defs hd)

/-- A value whose definition is a phi is the value of a phi at the recorded position. -/
theorem CtxOK.phi_of_def (hc : CtxOK c) {v : Nat} (hk : (c.def_ v).kind = .phi) :
    ∃ D b p, (c.def_ v).block = some D ∧ c.f.blocks[D]? = some b ∧ b.phis[(c.def_ v).index]? = some p ∧
      p.value = v ∧ (c.def_ v).phi = some p := by
  have hd : c.defs[v]? = some (c.def_ v) := by
    unfold Ctx.def_ at hk ⊢
    cases hv : c.defs[v]? with
    | none => simp [hv] at hk <;> simp [Def.kind] at hk
    | some d => simp
  exact defItemOK_phi hk (defsOK_conv hc.defs hd)

end Lemmas

/-- The definition of `v` is a constant or parameter, or lies in a block that dominates `D`. -/
def Above (c : Ctx) (v D : Nat) : Prop :=
  (c.def_ v).kind = .pre ∨ ∃ Dv, (c.def_ v).block = some Dv ∧ TDom c.succ Dv D

section AvailLemmas
variable {c : Ctx}

theorem Avail.above {B pc v : Nat} (h : Avail c B pc v) : Above c v B := by
  unfold Avail at h
  unfold Above
  cases hk : (c.def_ v).kind <;> rw [hk] at h <;> simp only at h
  · exact Or.inl rfl
  · obtain ⟨D, hD, hd⟩ := h
    exact Or.inr ⟨D, hD, hd⟩
  · obtain ⟨D, hD, hd⟩ := h
    refine Or.inr ⟨D, hD, ?_⟩
    rcases hd with ⟨rfl, _⟩ | ⟨_, hd⟩
    · exact TDom.refl _
    · exact hd

theorem Above.trans {v D D' : Nat} (h : Above c v D) (hd : TDom c.succ D D') : Above c v D' := by
  rcases h with h | ⟨Dv, hD, hv⟩
  · exact Or.inl h
  · exact Or.inr ⟨Dv, hD, hv.trans hd⟩

/-- A value available before an instruction is available after it, together with the value that instruction defines
(and nothing else). -/
theorem avail_step (hc : CtxOK c) {B pc : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[B]? = some b)
    (hk : b.insts[pc]? = some i) {v : Nat} : Avail c B (pc + 1) v ↔ Avail c B pc v ∨ v = i.value := by
  have hdi := hc.def_inst hb hk
  unfold Avail
  cases hkind : (c.def_ v).kind
  · constructor
    · intro h; exact absurd h id
    · rintro (h | h)
      · exact h
      · subst h; rw [hdi] at hkind; simp [instDef] at hkind
  · constructor
    · intro _; exact Or.inl trivial
    · intro _; trivial
  · constructor
    · intro h; exact Or.inl h
    · rintro (h | h)
      · exact h
      · subst h; rw [hdi] at hkind; simp [instDef] at hkind
  · constructor
    · rintro ⟨D, hD, hd⟩
      rcases hd with ⟨hDB, hlt⟩ | hd
      · by_cases hlt' : (c.def_ v).index < pc
        · exact Or.inl ⟨D, hD, Or.inl ⟨hDB, hlt'⟩⟩
        · right
          have heq : (c.def_ v).index = pc := by omega
          obtain ⟨D', b', i', hD', hb', hi', hv', _⟩ := hc.inst_of_def hkind
          rw [hD] at hD'
          cases hD'
          subst hDB
          rw [hb] at hb'
          cases hb'
          rw [heq, hk] at hi'
          cases hi'
          exact hv'.symm
      · exact Or.inl ⟨D, hD, Or.inr hd⟩
    · rintro (⟨D, hD, hd⟩ | h)
      · refine ⟨D, hD, ?_⟩
        rcases hd with ⟨hDB, hlt⟩ | hd
        · exact Or.inl ⟨hDB, by omega⟩
        · exact Or.inr hd
      · subst h
        refine ⟨B, ?_, Or.inl ⟨rfl, ?_⟩⟩
        · rw [hdi]; rfl
        · rw [hdi]; show pc < pc + 1; omega

/-- An instruction's own value is not available before it runs. -/
theorem not_avail_self (hc : CtxOK c) {B pc : Nat} {b : Block} {i : Inst} (hb : c.f.blocks[B]? = some b)
    (hk : b.insts[pc]? = some i) : ¬ Avail c B pc i.value := by
  intro h
  have hdi := hc.def_inst hb hk
  unfold Avail at h
  rw [hdi] at h
  simp only [instDef] at h
  obtain ⟨D, hD, hd⟩ := h
  cases hD
  rcases hd with ⟨_, hlt⟩ | ⟨hne, _⟩
  · omega
  · exact hne rfl

end AvailLemmas

end Facts
