import ProgramLink
import ProgramSite

/-!
# Soundness of a whole program (the corollary of design §6)

**Corollary** (`runs_sound`, `main_no_leak`).  Let `prog` be a program all of whose functions
pass `check` and whose callee tables link to the functions they name (`ProgWf`; the call sites then agree with their
callees, `callWf_of_site`).  Then for every
function of the program, every call depth `d` and every run of the function that starts in a
state meeting its before-the-call condition (`Pre`):
* the run does not fault, whatever it calls, and
* if it returns normally, its after-return condition (`Post`) holds.

Hence, started on an empty heap, a function with a scalar result (`main`) that returns normally
leaves no allocation live.  The proof is by induction on the call depth `d` of the run: a run
at depth `d + 1` is an execution whose calls are runs at depth `d`, each of which satisfies
its callee's contract by the induction hypothesis; so every step of the execution is one the
per-function invariant covers (`good_pstep`).  A recursive call is a run at smaller depth, so
recursion is covered, and every finite execution has a finite depth.

Calls to functions outside the program (`extern func`, `myl_core_*`) are resolved by the
contract (`Step.inst`), which is design assumption A5.
-/

namespace Own

variable {prog : Program}

/-- What the reachability invariant gives at an instruction: the invariant and the passed check at
the state the instruction runs from (for a trap block, the state of the edge the execution took). -/
theorem Good.inst_ok {cc : CCtx} {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    {inn : BlockId → Option AbsState} {b k : Nat} {ds : DState} {i : Inst}
    (hc : Good cc args h0 pend0 inn (.run b k ds)) (hat : cc.f.instAt b k = some i) :
    ∃ σ, Inv cc args h0 σ ds ∧ InstOk cc σ i := by
  simp only [Function.instAt, Option.bind_eq_some_iff] at hat
  obtain ⟨blk, hblk, hik⟩ := hat
  have hlt : k < blk.insts.length := (List.getElem?_eq_some_iff.1 hik).1
  have hdrop : blk.insts.drop k = i :: blk.insts.drop (k + 1) := by
    rw [List.drop_eq_getElem_cons hlt]
    have : blk.insts[k] = i := by simpa [List.getElem?_eq_getElem hlt] using hik
    rw [this]
  obtain ⟨_, σ, σo, _, hI, hrun, _⟩ := hc blk hblk
  rw [hdrop] at hrun
  obtain ⟨hfail, _⟩ := hrun.cons_inv
  exact ⟨σ, hI, instOk_of_fail_none hfail⟩

/-- The call instruction at a position is an instruction of the function. -/
theorem instAt_mem {f : Function} {b k : Nat} {i : Inst} (hat : f.instAt b k = some i) :
    ∃ blk, blk ∈ f.blocks ∧ i ∈ blk.insts := by
  simp only [Function.instAt, Option.bind_eq_some_iff] at hat
  obtain ⟨blk, hblk, hik⟩ := hat
  exact ⟨blk, Function.block?_mem hblk, List.mem_of_getElem? hik⟩

/-- What the induction hypothesis of `runs_sound` says of the runs of the callees. -/
def CalleesOk (prog : Program) (d : Nat) : Prop :=
  ∀ (g : Nat) (fc : Function × Certificate), prog[g]? = some fc →
    ∀ (args : Nat → Val) (h : Heap) (pend : Addr → String → Bool), Pre fc.1 args h pend →
    ScalarArgs (mkCC fc.1 fc.2) args →
    ∀ out, RunsAt prog d g args h pend out → out ≠ .fault ∧
      ∀ ds v, out = .ret ds v →
        Post fc.1 args { heap := h, pend := pend, env := fc.1.initEnv args, facts := fun _ => none }
          ds v

/-- A step of the program semantics preserves the reachability invariant, given that runs of
the callees (`R`) satisfy their contracts. -/
theorem good_pstep (hw : ProgWf prog) {d : Nat} (IH : CalleesOk prog d)
    {j : Nat} {fc : Function × Certificate} (hj : prog[j]? = some fc)
    {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    (hs : Static (mkCC fc.1 fc.2) args h0 pend0) {inn : BlockId → Option AbsState}
    (hver : ∀ b, b < (mkCC fc.1 fc.2).f.blocks.length →
      verifyBlock (mkCC fc.1 fc.2) inn b = none)
    {c c' : Config} (hc : Good (mkCC fc.1 fc.2) args h0 pend0 inn c)
    (hst : PStep prog (RunsAt prog d) (Ctx.entering fc.1 fc.2 args) c c') :
    Good (mkCC fc.1 fc.2) args h0 pend0 inn c' := by
  cases hst with
  | loc hstep _ => exact good_step hs hver hc hstep
  | call hcall hg hrun =>
    rename_i b k i e g ds out
    unfold Program.callAt at hcall
    simp only [entering_fn] at hcall
    cases hat : fc.1.instAt b k with
    | none => rw [hat] at hcall; simp at hcall
    | some i' =>
      rw [hat] at hcall
      simp only at hcall
      cases hent : fc.1.entryOf i' with
      | none => rw [hent] at hcall; simp at hcall
      | some e' =>
        rw [hent] at hcall
        simp only at hcall
        by_cases hcond : (i'.cls == Class.call && e'.kind == CalleeKind.program) = true
        · rw [if_pos hcond] at hcall
          have hk : e'.kind = .program := by
            have := hcond
            simp only [Bool.and_eq_true, beq_iff_eq] at this
            exact this.2
          cases hidx : prog.indexOf e'.name with
          | none => rw [hidx] at hcall; simp at hcall
          | some g' =>
            rw [hidx] at hcall
            simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at hcall
            obtain ⟨rfl, rfl, rfl⟩ := hcall
            have hat' : (mkCC fc.1 fc.2).f.instAt b k = some i' := hat
            obtain ⟨σ, hI, hok⟩ := hc.inst_ok hat'
            have hfc : fc ∈ prog := List.mem_of_getElem? hj
            obtain ⟨g2, fg, hi2, hfg, htag⟩ := hw.entry_link hfc (entryOf_mem hent) hk
            rw [hidx] at hi2
            have hg2 : g2 = g' := (Option.some.inj hi2).symm
            subst hg2
            have hwc : CallWf fc.2 fg i' (i'.argsOf e') := callWf_of_site hok hent hk htag
            have hpre := pre_of_call hs hI hok hwc
            have hsc := scalarArgs_of_call hI hwc
            cases out with
            | fault =>
              exact absurd rfl (IH g2 fg hfg _ _ _ hpre hsc _ hrun).1
            | trap => exact trivial
            | ret dsr v =>
              obtain ⟨_, hpost⟩ := IH g2 fg hfg _ _ _ hpre hsc _ hrun
              have hE := effect_of_post_next hs hI hok hwc (hpost dsr v rfl)
              have hat2 : (Ctx.entering fc.1 fc.2 args).fn.instAt b k = some i' := hat
              have := good_step hs hver hc (Step.inst hat2 hg hE)
              exact this
        · rw [if_neg hcond] at hcall
          simp at hcall

theorem good_pstar (hw : ProgWf prog) {d : Nat} (IH : CalleesOk prog d)
    {j : Nat} {fc : Function × Certificate} (hj : prog[j]? = some fc)
    {args : Nat → Val} {h0 : Heap} {pend0 : Addr → String → Bool}
    (hs : Static (mkCC fc.1 fc.2) args h0 pend0) {inn : BlockId → Option AbsState}
    (hver : ∀ b, b < (mkCC fc.1 fc.2).f.blocks.length →
      verifyBlock (mkCC fc.1 fc.2) inn b = none)
    {c c' : Config} (hc : Good (mkCC fc.1 fc.2) args h0 pend0 inn c)
    (hst : PStar prog (RunsAt prog d) (Ctx.entering fc.1 fc.2 args) c c') :
    Good (mkCC fc.1 fc.2) args h0 pend0 inn c' := by
  induction hst with
  | refl => exact hc
  | step h _ ih => exact ih (good_pstep hw IH hj hs hver hc h)

/-- **Every run of a function of a well-formed program is safe.** -/
theorem runs_sound (hw : ProgWf prog) : ∀ d : Nat, CalleesOk prog d := by
  intro d
  induction d with
  | zero => intro g fc hfc args h pend hpre hsc out hr; exact hr.elim
  | succ d ih =>
    intro g fc hfc args h pend hpre hsc out hr
    obtain ⟨fc', hfc', c', hstar, hout⟩ := hr
    have hfeq : fc' = fc := Option.some.inj (hfc'.symm.trans hfc)
    subst hfeq
    have hchk := hw.checked fc' (List.mem_of_getElem? hfc)
    obtain ⟨hs, hver, hgood⟩ := check_start fc'.1 fc'.2 hchk args h pend hpre hsc
    have := good_pstar hw ih hfc hs hver hgood hstar
    cases c' with
    | run b k ds => simp [Config.out?] at hout
    | ret ds v =>
      simp only [Config.out?, Option.some.injEq] at hout
      subst hout
      exact ⟨(by intro h'; cases h'), fun ds' v' h' => by cases h'; exact this⟩
    | trap =>
      simp only [Config.out?, Option.some.injEq] at hout
      subst hout
      exact ⟨(by intro h'; cases h'), (by intro ds v h'; cases h')⟩
    | fault k => exact this.elim

/-- A function with a scalar result, started on an empty heap, that returns normally leaves
no allocation live: nothing it allocated is leaked. -/
theorem main_no_leak (hw : ProgWf prog) {g : Nat} {fc : Function × Certificate}
    (hfc : prog[g]? = some fc) (args : Nat → Val) (pend : Addr → String → Bool)
    (hpre : Pre fc.1 args (fun _ => .unused) pend) (hsc : ScalarArgs (mkCC fc.1 fc.2) args)
    (hres : fc.1.result = .scalar)
    {d : Nat} {ds : DState} {v : Val}
    (hr : RunsAt prog d g args (fun _ => .unused) pend (.ret ds v)) :
    ∀ x t, ds.heap x ≠ .live t := by
  obtain ⟨_, hpost⟩ := runs_sound hw d g fc hfc args _ pend hpre hsc _ hr
  have hp := hpost ds v rfl
  have hv : v = .imm := by
    have := hp.shape
    unfold ResultShape at this
    rw [hres] at this
    exact this
  intro x t hx
  rcases hp.created x rfl with h | h | ⟨r, hvr, _⟩
  · rw [h] at hx; cases hx
  · rw [h] at hx; cases hx
  · rw [hv] at hvr; cases hvr

#print axioms Own.runs_sound
#print axioms Own.main_no_leak

end Own
