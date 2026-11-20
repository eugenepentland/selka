import Facts.Proven

/-!
# The theorem (design section 7)

If the checker accepts every function of a module and the module's uses are dominated by their definitions, then
every execution of the module from an external entry (arguments in the stated parameter intervals) that honours the
assumptions of `AXIOMS.md` (`Adm`) satisfies, at every configuration it reaches:

1. every integer or boolean value of every frame lies in the interval stated for it and in its type's range (an empty
   interval says the value is never produced: no execution holds one);
2. no block stated dead is entered;
3. no instruction accepted as `proven` is undefined behaviour (the failing case of its unguarded form never arises).

The proofs are `stated_intervals` (`Sound.lean`), `no_dead_entered` (`Sound.lean`) and `proven_never_ub`
(`Proven.lean`); `Connect.lean` links item 3 to the emitter's lowering theorems.
-/

namespace Facts

/-- Design section 7, items 1 to 3, for every configuration an honest execution from an external entry reaches. -/
theorem fact_certificates_sound {m : Module} (hmod : ModOK m) (hwf : ModWf m) {g : Nat} {args : List Val}
    {cfg0 : Config} (he : Entry m g args cfg0) (hargs : ∀ c, ctxOf m g = some c → ArgsOK c args)
    (hadm0 : AdmCfg m cfg0) {cfg : Config} (hr : ReachA m cfg0 cfg) :
    (∀ fr ∈ cfg, ∀ c, ctxOf m fr.fn = some c → ∀ v n, fr.regs v = some (.int n) →
      (∀ r lim, (c.def_ v).stated = some r → (c.def_ v).ty.range = some lim → r.contains n) ∧
        (∀ lim, (c.def_ v).ty.range = some lim → lim.contains n)) ∧
    (∀ fr ∈ cfg, ∀ c, ctxOf m fr.fn = some c → ∀ b, c.f.blocks[fr.blk]? = some b → b.dead = false) ∧
    (∀ i, StepUb m cfg i → ∀ (fr : Frame) (rest : Config) (c : Ctx), cfg = fr :: rest → ctxOf m fr.fn = some c →
      ∀ b, c.f.blocks[fr.blk]? = some b → b.insts[fr.pc]? = some i → c.provenOut i fr.blk ≠ .proven) := by
  have h0 : CfgInv m cfg0 := entry_inv hmod he hargs hadm0
  refine ⟨?_, ?_, ?_⟩
  · intro fr hfr c hc v n hv
    exact stated_intervals hmod hwf h0 hr hfr hc hv
  · intro fr hfr c hc b hb
    exact no_dead_entered hmod hwf h0 hr hfr hc hb
  · intro i hub
    exact proven_never_ub hmod hwf h0 hr hub

end Facts
