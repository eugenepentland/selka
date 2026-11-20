import VerifyIr.FnValues

/-!
# A17: a function value reaching an indirect call points to a function of the call's signature

`Reaches m fr g r v` is the small semantics of function values: which values register `r` of function `g` can hold.
`reaches_holds` proves that in a module whose every function the checker accepts, each such value holds at the
register's type; `a17` reads it at a `call_indirect`.
-/

namespace VerifyIr

/-! ## The function-free table -/

section Free
variable {m : Module} {fr : Array Bool}

theorem freeOK_size (h : m.freeOK fr = true) : fr.size = m.compounds.size := by
  unfold Module.freeOK at h
  simp only [Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

theorem freeOK_step (h : m.freeOK fr = true) {i : Nat} (hi : i < fr.size) : fr[i]! = m.freeStep fr i := by
  unfold Module.freeOK at h
  simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true, List.mem_range] at h
  exact h.2 i hi

/-- A free compound type: its entry exists and is set, and its step holds. -/
theorem free_compound (h : m.freeOK fr = true) {t : Ty} {c : Compound} (hc : m.compound? t = some c)
    (hf : freeTy fr t = true) : m.freeStep fr (t - Ty.firstCompound) = true ∧ m.compounds[t - Ty.firstCompound]? = some c := by
  unfold Module.compound? at hc
  split at hc
  · rename_i hcomp
    unfold freeTy at hf
    simp only [hcomp, Bool.not_true, Bool.false_or] at hf
    have hlt : t - Ty.firstCompound < fr.size := by
      rw [freeOK_size h]; exact (Array.getElem?_eq_some_iff.mp hc).1
    rw [Array.getElem?_eq_getElem hlt] at hf
    simp only [Option.getD_some] at hf
    have := freeOK_step h hlt
    rw [getElem!_pos fr _ hlt, hf] at this
    exact ⟨this.symm, hc⟩
  · cases hc

/-- A free type is not a function type, and the parts of a free compound are free. -/
theorem free_parts (h : m.freeOK fr = true) {t : Ty} {c : Compound} (hc : m.compound? t = some c)
    (hf : freeTy fr t = true) :
    (∀ s, c ≠ .fn s) ∧ (∀ fs, c = .record fs → ∀ x ∈ fs, freeTy fr x = true) ∧
    (∀ cs, c = .union cs → ∀ x ∈ cs, freeTy fr x = true) ∧
    (∀ e, (c = .list e ∨ c = .listView e ∨ c = .box e ∨ c = .borrowed e ∨ ∃ n v, c = .array e n v) → freeTy fr e = true) ∧
    (∀ k v, c = .dict k v → freeTy fr k = true ∧ freeTy fr v = true) := by
  obtain ⟨hs, hget⟩ := free_compound h hc hf
  unfold Module.freeStep at hs
  rw [hget] at hs
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · intro s e; subst e; simp at hs
  · intro fs e; subst e; simpa [List.all_eq_true] using hs
  · intro cs e; subst e; simpa [List.all_eq_true] using hs
  · intro e he
    rcases he with e' | e' | e' | e' | ⟨n, v, e'⟩ <;> subst e' <;> simpa using hs
  · intro k v e; subst e; simpa using hs

/-- The storage of a free type is free. -/
theorem free_storage (h : m.freeOK fr = true) : ∀ (n : Nat) (t : Ty), freeTy fr t = true → freeTy fr (m.storageTypeF n t) = true := by
  intro n
  induction n with
  | zero => intro t ht; simpa [Module.storageTypeF] using ht
  | succ n ih =>
    intro t ht
    unfold Module.storageTypeF
    split
    · rename_i inner hc
      exact ih inner ((free_parts h hc ht).2.2.2.1 inner (Or.inr (Or.inr (Or.inr (Or.inl rfl)))))
    · exact ht

theorem free_storageType (h : m.freeOK fr = true) {t : Ty} (ht : freeTy fr t = true) :
    freeTy fr (m.storageType t) = true := free_storage h _ t ht

/-- Free types read through their storage. -/
theorem free_of_storage_parts (h : m.freeOK fr = true) {t : Ty} {c : Compound} (ht : freeTy fr t = true)
    (hc : m.compound? (m.storageType t) = some c) :
    (∀ s, c ≠ .fn s) ∧ (∀ fs, c = .record fs → ∀ x ∈ fs, freeTy fr x = true) ∧
    (∀ cs, c = .union cs → ∀ x ∈ cs, freeTy fr x = true) ∧
    (∀ e, (c = .list e ∨ c = .listView e ∨ c = .box e ∨ c = .borrowed e ∨ ∃ n v, c = .array e n v) → freeTy fr e = true) ∧
    (∀ k v, c = .dict k v → freeTy fr k = true ∧ freeTy fr v = true) :=
  free_parts h hc (free_storageType h ht)

end Free

/-! ## Parts of well-typed values are well typed -/

section Parts
variable {m : Module} {fr : Array Bool}

/-- A type whose storage is free is free: the table is a fixed point, so an overlay of a free type is free. -/
theorem free_of_storage (h : m.freeOK fr = true) : ∀ (n : Nat) (t : Ty), freeTy fr (m.storageTypeF n t) = true →
    freeTy fr t = true := by
  intro n
  induction n with
  | zero => intro t ht; simpa [Module.storageTypeF] using ht
  | succ n ih =>
    intro t ht
    unfold Module.storageTypeF at ht
    split at ht
    · rename_i inner hc
      have hin := ih inner ht
      unfold Module.compound? at hc
      split at hc
      · rename_i hcomp
        have hlt : t - Ty.firstCompound < fr.size := by
          rw [freeOK_size h]; exact (Array.getElem?_eq_some_iff.mp hc).1
        have hstep := freeOK_step h hlt
        unfold Module.freeStep at hstep
        rw [hc] at hstep
        simp only at hstep
        unfold freeTy
        simp only [hcomp, Bool.not_true, Bool.false_or]
        rw [Array.getElem?_eq_getElem hlt]
        simp only [Option.getD_some]
        rw [getElem!_pos fr _ hlt] at hstep
        rw [hstep]; exact hin
      · cases hc
    · exact ht

theorem free_transfer (h : m.freeOK fr = true) {t t' : Ty} (he : m.storageType t = m.storageType t')
    (ht : freeTy fr t = true) : freeTy fr t' = true :=
  free_of_storage h _ t' (by unfold Module.storageType at he; rw [← he]; exact free_storageType h ht)

theorem holds_fn_storage {t : Ty} {s : Signature} (hfr : m.freeOK fr = true) (hc : m.compound? (m.storageType t) = some (.fn s))
    (hf : freeTy fr t = true) : False :=
  (free_of_storage_parts hfr hf hc).1 s rfl

/-- What a well-typed value of a function type is. -/
theorem holds_fn (hfr : m.freeOK fr = true) {t : Ty} {v : Val} {s : Signature} (h : Holds m fr t v)
    (hs : m.compound? (m.storageType t) = some (.fn s)) :
    ∃ k g, v = .fn k ∧ m.functions[k]? = some g ∧ g.sig = s ∧ s.linkage = .internal := by
  cases h with
  | free hf => exact absurd (holds_fn_storage hfr hs hf) id
  | fn hc hg hsig hl =>
    rw [hs] at hc; cases hc
    exact ⟨_, _, rfl, hg, hsig, hl⟩
  | record hc _ _ => rw [hs] at hc; cases hc
  | elems he _ =>
    rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hs] at he <;> cases he
  | dict hc _ _ => rw [hs] at hc; cases hc
  | tagged hc _ _ => rw [hs] at hc; cases hc

/-- A value read through another overlay of the same storage is well typed there too. -/
theorem holds_same (hfr : m.freeOK fr = true) {t t' : Ty} {v : Val} (he : m.storageType t = m.storageType t')
    (h : Holds m fr t v) : Holds m fr t' v := by
  cases h with
  | free hf => exact Holds.free (free_transfer hfr he hf)
  | fn hc hg hsig hl => exact Holds.fn (he ▸ hc) hg hsig hl
  | record hc hl hp => exact Holds.record (he ▸ hc) hl hp
  | elems hel hp =>
    refine Holds.elems ?_ hp
    unfold ElemOf at hel ⊢; rw [← he]; exact hel
  | dict hc hk hv => exact Holds.dict (he ▸ hc) hk hv
  | tagged hc hj hp => exact Holds.tagged (he ▸ hc) hj hp

theorem elemOf_unique {t e e' : Ty} (h : ElemOf m t e) (h' : ElemOf m t e') : e = e' := by
  unfold ElemOf at h h'
  rcases h with h | h | h | ⟨_, _, h⟩ <;> rcases h' with h' | h' | h' | ⟨_, _, h'⟩ <;> rw [h] at h' <;>
    first | (cases h'; rfl) | cases h'

/-- The element type of a free type is free. -/
theorem free_elem (hfr : m.freeOK fr = true) {t e : Ty} (ht : freeTy fr t = true) (h : ElemOf m t e) :
    freeTy fr e = true := by
  unfold ElemOf at h
  rcases h with h | h | h | ⟨n, vec, h⟩
  · exact (free_of_storage_parts hfr ht h).2.2.2.1 e (Or.inl rfl)
  · exact (free_of_storage_parts hfr ht h).2.2.2.1 e (Or.inr (Or.inl rfl))
  · exact (free_of_storage_parts hfr ht h).2.2.2.1 e (Or.inr (Or.inr (Or.inl rfl)))
  · exact (free_of_storage_parts hfr ht h).2.2.2.1 e (Or.inr (Or.inr (Or.inr (Or.inr ⟨n, vec, rfl⟩))))

/-- A part of a well-typed value is well typed. -/
theorem part_holds (hfr : m.freeOK fr = true) {t₀ t : Ty} {v₀ v : Val} (hp : Part m t₀ v₀ t v) :
    Holds m fr t₀ v₀ → Holds m fr t v := by
  induction hp with
  | same he => exact fun h => holds_same hfr he h
  | field h₁ h₂ hc =>
    intro h
    cases h with
    | free hf => exact Holds.free ((free_of_storage_parts hfr hf hc).2.1 _ rfl _ (List.getElem_mem h₁))
    | record hc' _ hp' => rw [hc] at hc'; cases hc'; exact hp' _ h₁ h₂
    | elems he _ => unfold ElemOf at he; rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hc] at he <;> cases he
    | dict hc' _ _ => rw [hc] at hc'; cases hc'
  | elem he hmem =>
    intro h
    cases h with
    | free hf => exact Holds.free (free_elem hfr hf he)
    | record hc' _ _ =>
      unfold ElemOf at he; rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hc'] at he <;> cases he
    | elems he' hp' => rw [elemOf_unique he he']; exact hp' _ hmem
    | dict hc' _ _ =>
      unfold ElemOf at he; rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hc'] at he <;> cases he
  | key hc hmem =>
    intro h
    cases h with
    | free hf => exact Holds.free ((free_of_storage_parts hfr hf hc).2.2.2.2 _ _ rfl).1
    | record hc' _ _ => rw [hc] at hc'; cases hc'
    | elems he _ => unfold ElemOf at he; rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hc] at he <;> cases he
    | dict hc' hk _ => rw [hc] at hc'; cases hc'; exact hk _ _ hmem
  | value hc hmem =>
    intro h
    cases h with
    | free hf => exact Holds.free ((free_of_storage_parts hfr hf hc).2.2.2.2 _ _ rfl).2
    | record hc' _ _ => rw [hc] at hc'; cases hc'
    | elems he _ => unfold ElemOf at he; rcases he with he | he | he | ⟨_, _, he⟩ <;> rw [hc] at he <;> cases he
    | dict hc' _ hv => rw [hc] at hc'; cases hc'; exact hv _ _ hmem
  | payload hc hj =>
    intro h
    cases h with
    | free hf => exact Holds.free ((free_of_storage_parts hfr hf hc).2.2.1 _ rfl _ (List.mem_of_getElem? hj))
    | tagged hc' hj' hp' => rw [hc] at hc'; cases hc'; rw [hj] at hj'; cases hj'; exact hp'
  | trans _ _ ih₁ ih₂ => exact fun h => ih₂ (ih₁ h)

/-- A value built from parts of well-typed values is well typed. -/
theorem built_holds (hfr : m.freeOK fr = true) {ins : List (Ty × Val)} (hins : ∀ p ∈ ins, Holds m fr p.1 p.2)
    {t : Ty} {v : Val} (h : Built m fr ins t v) : Holds m fr t v := by
  induction h with
  | free hf => exact Holds.free hf
  | part hmem hp => exact part_holds hfr hp (hins _ hmem)
  | record hc hl _ ih => exact Holds.record hc hl ih
  | elems he _ ih => exact Holds.elems he ih
  | dict hc _ _ ihk ihv => exact Holds.dict hc ihk ihv
  | tagged hc hj _ ih => exact Holds.tagged hc hj ih

end Parts

/-! ## The small semantics -/

/-- Instruction `r` of function `g` is listed in a block a walk reaches (the translation's reached set). -/
def ListedReached (m : Module) (g r : Nat) : Prop :=
  ∃ (gf : Function) (d : Nat) (blk : Block), m.functions[g]? = some gf ∧ ((Fn.mk m gf).translate.reach[d]?.getD false) = true ∧
    gf.blocks[d]? = some blk ∧ some r ∈ blk.insts

/-- The type of register `r` of function `g`. -/
def regTy (m : Module) (g r : Nat) : Ty :=
  (((m.functions[g]?).bind fun gf => gf.insts[r]?).map (·.ty)).getD noTy

/-- The operations whose result `Reaches.built` describes: all but the function references, constants and parameters,
calls and forwarding copies, which have constructors of their own. -/
def builtOp : Op → Bool
  | .funcRef | .iconst | .fconst | .strConst | .undef | .textSentinel | .param | .call | .callIndirect | .copy => false
  | _ => true

/-- `Reaches m fr g r v`: register `r` of function `g` can hold `v`. -/
inductive Reaches (m : Module) (fr : Array Bool) : Nat → Nat → Val → Prop where
  /-- A function reference makes the pointer to the function it names. -/
  | funcRef {g r : Nat} {gf : Function} {i : Inst} : m.functions[g]? = some gf → gf.insts[r]? = some i →
      i.op = .funcRef → Reaches m fr g r (.fn i.data)
  /-- A constant made from nothing holds any value of its type. -/
  | made {g r : Nat} {gf : Function} {i : Inst} {v : Val} : m.functions[g]? = some gf → gf.insts[r]? = some i →
      Fn.madeFromNothing i.op = true → Reaches m fr g r v
  /-- A text or list sentinel is an empty block. -/
  | sentinel {g r : Nat} {gf : Function} {i : Inst} : m.functions[g]? = some gf → gf.insts[r]? = some i →
      i.op = .textSentinel → Reaches m fr g r (.agg [])
  /-- A parameter holds what a direct call passed in its position. -/
  | paramCall {g r h ci x0 x : Nat} {gf hf : Function} {i ca : Inst} {v : Val} :
      m.functions[g]? = some gf → gf.insts[r]? = some i → i.op = .param →
      ListedReached m h ci → m.functions[h]? = some hf → hf.insts[ci]? = some ca → ca.op = .call → ca.a = some g →
      ((Fn.mk m hf).extraOf ca.data)[i.data]? = some (some x0) → (Fn.mk m hf).resolve (some x0) = some x →
      Reaches m fr h x v → Reaches m fr g r v
  /-- A parameter holds what an indirect call through a pointer to the function passed in its position. -/
  | paramIndirect {g r h ci a0 a x0 x : Nat} {gf hf : Function} {i ca : Inst} {v : Val} :
      m.functions[g]? = some gf → gf.insts[r]? = some i → i.op = .param →
      ListedReached m h ci → m.functions[h]? = some hf → hf.insts[ci]? = some ca → ca.op = .callIndirect →
      ca.a = some a0 → (Fn.mk m hf).resolve (some a0) = some a → Reaches m fr h a (.fn g) →
      ((Fn.mk m hf).extraOf ca.data)[i.data]? = some (some x0) → (Fn.mk m hf).resolve (some x0) = some x →
      Reaches m fr h x v → Reaches m fr g r v
  /-- A direct call's result is what a reached `ret` of the callee returned. -/
  | retCall {h ci g rr x0 x : Nat} {hf gf : Function} {ca ri : Inst} {v : Val} :
      ListedReached m h ci → m.functions[h]? = some hf → hf.insts[ci]? = some ca → ca.op = .call → ca.a = some g →
      ListedReached m g rr → m.functions[g]? = some gf → gf.insts[rr]? = some ri → ri.op = .ret → ri.a = some x0 →
      (Fn.mk m gf).resolve (some x0) = some x → Reaches m fr g x v → Reaches m fr h ci v
  /-- An indirect call's result is what a reached `ret` of the function its callee points to returned. -/
  | retIndirect {h ci a0 a g rr x0 x : Nat} {hf gf : Function} {ca ri : Inst} {v : Val} :
      ListedReached m h ci → m.functions[h]? = some hf → hf.insts[ci]? = some ca → ca.op = .callIndirect →
      ca.a = some a0 → (Fn.mk m hf).resolve (some a0) = some a → Reaches m fr h a (.fn g) →
      ListedReached m g rr → m.functions[g]? = some gf → gf.insts[rr]? = some ri → ri.op = .ret → ri.a = some x0 →
      (Fn.mk m gf).resolve (some x0) = some x → Reaches m fr g x v → Reaches m fr h ci v
  /-- Any other operation's result is built from parts of values its operands hold (trusted: V5, V6). -/
  | built {h r : Nat} {hf : Function} {i : Inst} {ins : List (Ty × Val)} {v : Val} :
      ListedReached m h r → m.functions[h]? = some hf → hf.insts[r]? = some i → builtOp i.op = true →
      (os : List Nat) → (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), Reaches m fr h os[k] ins[k].2) →
      (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), ins[k].1 = regTy m h os[k]) → os.length = ins.length →
      Built m fr ins i.ty v → Reaches m fr h r v
  /-- A call to a function without a body (C or the runtime) returns a value built from parts of values the program holds
  (trusted: V7, the runtime's deep copies hand back the function values they were given). -/
  | external {h ci g : Nat} {hf gf : Function} {ca : Inst} {ins : List (Ty × Val)} {v : Val} :
      ListedReached m h ci → m.functions[h]? = some hf → hf.insts[ci]? = some ca → ca.op = .call → ca.a = some g →
      m.functions[g]? = some gf → gf.sig.linkage ≠ .internal →
      (os : List (Nat × Nat)) → (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), Reaches m fr os[k].1 os[k].2 ins[k].2) →
      (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), ins[k].1 = regTy m os[k].1 os[k].2) → os.length = ins.length →
      Built m fr ins ca.ty v → Reaches m fr h ci v
  /-- A parameter of a function the runtime calls back through a pointer (`map`, a task, a registered test) holds a
  value built from parts of values the program holds (trusted: V7). -/
  | callback {g r : Nat} {gf : Function} {i : Inst} {ins : List (Ty × Val)} {v : Val} :
      m.functions[g]? = some gf → gf.insts[r]? = some i → i.op = .param →
      (os : List (Nat × Nat)) → (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), Reaches m fr os[k].1 os[k].2 ins[k].2) →
      (∀ k (h₁ : k < ins.length) (h₂ : k < os.length), ins[k].1 = regTy m os[k].1 os[k].2) → os.length = ins.length →
      Built m fr ins i.ty v → Reaches m fr g r v

/-! ## What an accepted function's checks give -/

section Checks
variable {m : Module} {fr : Array Bool}

theorem verdict_typed {g : Function} (h : verdict m fr g = .ok ()) :
    m.freeOK fr = true ∧ (Fn.mk m g).typedCheck fr = true := by
  unfold verdict at h
  cases h1 : m.checkHeader g with
  | error e => simp [h1, bind, Except.bind] at h
  | ok _ =>
    cases h2 : bodyIdom m g with
    | error e => simp [h1, h2, bind, Except.bind] at h
    | ok idom =>
      simp only [h1, h2, bind, Except.bind] at h
      by_cases hs : (Fn.mk m g).translate.ssaCheck idom = true
      · simp only [hs, Bool.not_true] at h
        by_cases ht : (m.freeOK fr && (Fn.mk m g).typedCheck fr) = true
        · simpa using ht
        · simp [ht, reject, throw, throwThe, MonadExceptOf.throw] at h
      · simp [hs, reject, throw, throwThe, MonadExceptOf.throw] at h

variable {c : Fn}

theorem typed_const (h : c.typedCheck fr = true) {r : Nat} {i : Inst} (hi : c.f.insts[r]? = some i)
    (hc : i.op.isConstant = true) :
    c.sigOk (c.shape i) = true ∧ (Fn.madeFromNothing i.op = true → freeTy fr i.ty = true) := by
  unfold Fn.typedCheck at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have hmem : i ∈ c.f.insts.toList := Array.mem_toList_iff.mpr (Array.mem_of_getElem? hi)
  have := h.1 i hmem
  simp only [hc, Bool.not_true, Bool.false_or, Bool.and_eq_true, Bool.or_eq_true, Bool.not_eq_true'] at this
  refine ⟨this.1, fun hm => ?_⟩
  rcases this.2 with h' | h'
  · rw [hm] at h'; cases h'
  · exact h'

theorem typed_listed (h : c.typedCheck fr = true) {d r : Nat} {blk : Block} {i : Inst}
    (hreach : (c.translate.reach[d]?.getD false) = true) (hb : c.f.blocks[d]? = some blk) (hm : some r ∈ blk.insts)
    (hi : c.f.insts[r]? = some i) (hcopy : i.op ≠ .copy) : c.sigOk (c.shape i) = true := by
  unfold Fn.typedCheck at h
  simp only [Bool.and_eq_true, List.all_eq_true, List.mem_range] at h
  have hd : d < c.f.blocks.size := (Array.getElem?_eq_some_iff.mp hb).1
  have := h.2 d hd
  simp only [hreach, Bool.not_true, Bool.false_or] at this
  rw [Facts.arr_get!_of_get? hb, Array.all_eq_true_iff_forall_mem] at this
  have := this _ hm
  simp only [hi] at this
  simp only [Bool.or_eq_true, beq_iff_eq] at this
  rcases this with h' | h'
  · exact absurd h' hcopy
  · exact h'

theorem fnOf_spec {t : Ty} {s : Signature} (h : c.fnOf t = some s) :
    c.m.compound? (c.m.storageType t) = some (.fn s) := by
  unfold Fn.fnOf Fn.compoundOf at h
  split at h <;> simp_all

theorem listOf_spec {t e : Ty} (h : c.listOf t = some e) : c.m.compound? (c.m.storageType t) = some (.list e) := by
  unfold Fn.listOf Fn.compoundOf at h
  split at h <;> simp_all

theorem sig_funcRef {i : Inst} (h : c.sigOk (c.shape i) = true) (hop : i.op = .funcRef) :
    ∃ s gk, c.m.compound? (c.m.storageType i.ty) = some (.fn s) ∧ c.m.functions[i.data]? = some gk ∧ s = gk.sig ∧
      s.linkage = .internal := by
  unfold Fn.sigOk at h
  simp only [Fn.shape, hop] at h
  split at h
  · rename_i s hs
    split at h
    · rename_i gk hgk
      simp only [Bool.and_eq_true, beq_iff_eq] at h
      exact ⟨s, gk, fnOf_spec hs, hgk, h.1, h.2⟩
    · simp at h
  · simp at h

theorem sig_param {i : Inst} (h : c.sigOk (c.shape i) = true) (hop : i.op = .param) :
    c.f.sig.params[i.data]? = some i.ty := by
  unfold Fn.sigOk at h
  simp only [Fn.shape, hop, beq_iff_eq] at h
  exact h

theorem sig_sentinel {i : Inst} (h : c.sigOk (c.shape i) = true) (hop : i.op = .textSentinel) :
    i.ty = Ty.str ∨ ∃ e, c.m.compound? (c.m.storageType i.ty) = some (.list e) := by
  unfold Fn.sigOk at h
  simp only [Fn.shape, hop, Bool.or_eq_true, beq_iff_eq, Option.isSome_iff_exists] at h
  rcases h with h | ⟨e, he⟩
  · exact Or.inl h
  · exact Or.inr ⟨e, listOf_spec he⟩

theorem sig_ret {i : Inst} {x0 : Nat} (h : c.sigOk (c.shape i) = true) (hop : i.op = .ret) (ha : i.a = some x0) :
    c.typeOf x0 = c.f.sig.ret := by
  unfold Fn.sigOk at h
  simp [Fn.shape, hop, ha, Op.extraOnly] at h
  exact h.2

/-- A call's result is its callee's, and each argument has its parameter's type or the parameter is a leaf. -/
theorem sig_call {i : Inst} {g : Nat} {gf : Function} (h : c.sigOk (c.shape i) = true) (hop : i.op = .call)
    (ha : i.a = some g) (hg : c.m.functions[g]? = some gf) :
    i.ty = gf.sig.ret ∧ ∀ (k x0 : Nat) (p : Ty), (c.extraOf i.data)[k]? = some (some x0) → gf.sig.params[k]? = some p →
      c.typeOf x0 = p ∨ Ty.isCompound p = false := by
  unfold Fn.sigOk at h
  simp only [Fn.shape, hop, Op.hasExtra, ite_true] at h
  unfold Fn.callOk at h
  simp only [ha, hg, Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at h
  refine ⟨h.1.1, fun k x0 p hx hp => ?_⟩
  have hmem : (((some x0, p), k) : (Option Nat × Ty) × Nat) ∈ ((c.extraOf i.data).zip gf.sig.params).zipIdx := by
    rw [List.mk_mem_zipIdx_iff_getElem?, List.getElem?_zip_eq_some]; exact ⟨hx, hp⟩
  have := h.2 _ hmem
  simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, Bool.not_eq_true'] at this
  rcases this with h' | h'
  · exact Or.inl h'
  · exact Or.inr h'.2

/-- An indirect call's callee has a function type of internal linkage whose result and parameters are the call's. -/
theorem sig_callIndirect {i : Inst} {a0 : Nat} (h : c.sigOk (c.shape i) = true) (hop : i.op = .callIndirect)
    (ha : i.a = some a0) :
    ∃ s, c.m.compound? (c.m.storageType (c.typeOf a0)) = some (.fn s) ∧ s.linkage = .internal ∧ i.ty = s.ret ∧
      ∀ (k x0 : Nat) (p : Ty), (c.extraOf i.data)[k]? = some (some x0) → s.params[k]? = some p → c.typeOf x0 = p := by
  unfold Fn.sigOk at h
  simp only [Fn.shape, hop, ha, Op.hasExtra, Op.extraOnly, ite_true] at h
  split at h
  · rename_i s hs
    simp only [Bool.and_eq_true, beq_iff_eq] at h
    refine ⟨s, fnOf_spec hs, h.1.1, h.1.2, fun k x0 p hx hp => ?_⟩
    have ht := h.2
    unfold Fn.typesMatch at ht
    simp only [Bool.and_eq_true, beq_iff_eq, List.all_eq_true] at ht
    have hmem : ((some x0, p) : Option Nat × Ty) ∈ (c.extraOf i.data).zip s.params :=
      List.mem_of_getElem? (List.getElem?_zip_eq_some.mpr ⟨hx, hp⟩)
    simpa using ht.2 _ hmem
  · simp at h

theorem regTy_of {g r : Nat} {gf : Function} {i : Inst} (hg : m.functions[g]? = some gf) (hi : gf.insts[r]? = some i) :
    regTy m g r = i.ty := by
  simp [regTy, hg, hi]

theorem regTy_resolve {h x0 x : Nat} {hf : Function} (hh : m.functions[h]? = some hf)
    (hx : (Fn.mk m hf).resolve (some x0) = some x) : regTy m h x = (Fn.mk m hf).typeOf x0 := by
  unfold regTy Fn.typeOf
  rw [hx, hh]
  simp

theorem listed_typed (hacc : ∀ (g : Nat) gf, m.functions[g]? = some gf → verdict m fr gf = .ok ()) {h r : Nat}
    {hf : Function} {i : Inst} (hl : ListedReached m h r) (hh : m.functions[h]? = some hf) (hi : hf.insts[r]? = some i)
    (hcopy : i.op ≠ .copy) : (Fn.mk m hf).sigOk ((Fn.mk m hf).shape i) = true := by
  obtain ⟨gf, d, blk, hg, hreach, hb, hm⟩ := hl
  rw [hh] at hg; cases hg
  exact typed_listed (verdict_typed (hacc h hf hh)).2 hreach hb hm hi hcopy

end Checks

/-! ## The theorem -/

/-- The parts a value is built from hold, so it holds. -/
theorem built_from {m : Module} {fr : Array Bool} (hfr : m.freeOK fr = true) {ins : List (Ty × Val)} {os : List (Nat × Nat)}
    (ih : ∀ k (h₁ : k < ins.length) (h₂ : k < os.length), Holds m fr (regTy m os[k].1 os[k].2) ins[k].2)
    (htypes : ∀ k (h₁ : k < ins.length) (h₂ : k < os.length), ins[k].1 = regTy m os[k].1 os[k].2)
    (hlen : os.length = ins.length) {t : Ty} {v : Val} (hb : Built m fr ins t v) : Holds m fr t v := by
  refine built_holds hfr (fun p hp => ?_) hb
  obtain ⟨k, hk, hkp⟩ := List.getElem_of_mem hp
  have hko : k < os.length := by omega
  have := ih k hk hko
  rw [← htypes k hk hko] at this
  rw [← hkp]; exact this

/-- In a module the checker accepts, every value a register can hold is well typed at the register's type. -/
theorem reaches_holds {m : Module} {fr : Array Bool}
    (hacc : ∀ (g : Nat) gf, m.functions[g]? = some gf → verdict m fr gf = .ok ()) {g r : Nat} {v : Val}
    (h : Reaches m fr g r v) : Holds m fr (regTy m g r) v := by
  induction h with
  | @funcRef g r gf i hg hi hop =>
    have hv := verdict_typed (hacc g gf hg)
    obtain ⟨s, gk, hs, hgk, hsig, hl⟩ := sig_funcRef (typed_const hv.2 hi (by rw [hop]; rfl)).1 hop
    rw [regTy_of hg hi]
    exact Holds.fn hs hgk hsig.symm hl
  | @made g r gf i v hg hi hmade =>
    have hv := verdict_typed (hacc g gf hg)
    have hc : i.op.isConstant = true := by
      cases hop : i.op <;> simp_all [Fn.madeFromNothing, Op.isConstant]
    rw [regTy_of hg hi]
    exact Holds.free ((typed_const hv.2 hi hc).2 hmade)
  | @sentinel g r gf i hg hi hop =>
    have hv := verdict_typed (hacc g gf hg)
    rw [regTy_of hg hi]
    rcases sig_sentinel (typed_const hv.2 hi (by rw [hop]; rfl)).1 hop with he | ⟨e, he⟩
    · rw [he]; exact Holds.free (by simp [freeTy, Ty.isCompound, Ty.str, Ty.firstCompound])
    · exact Holds.elems (Or.inl he) (by simp)
  | @paramCall g r h ci x0 x gf hf i ca v hg hi hop hl hh hci hcop hca hx hres _ ih =>
    have hv := verdict_typed (hacc g gf hg)
    have hpar := sig_param (typed_const hv.2 hi (by rw [hop]; rfl)).1 hop
    have hsc := listed_typed hacc hl hh hci (by rw [hcop]; decide)
    obtain ⟨_, hargs⟩ := sig_call hsc hcop hca hg
    rw [regTy_resolve hh hres] at ih
    rw [regTy_of hg hi]
    rcases hargs _ _ _ hx hpar with he | he
    · rw [← he]; exact ih
    · exact Holds.free (by simp [freeTy, he])
  | @paramIndirect g r h ci a0 a x0 x gf hf i ca v hg hi hop hl hh hci hcop hca hres _ hx hresx _ ihc ihx =>
    have hv := verdict_typed (hacc g gf hg)
    have hpar := sig_param (typed_const hv.2 hi (by rw [hop]; rfl)).1 hop
    have hsc := listed_typed hacc hl hh hci (by rw [hcop]; decide)
    obtain ⟨s, hs, _, _, hargs⟩ := sig_callIndirect hsc hcop hca
    rw [regTy_resolve hh hres] at ihc
    obtain ⟨k, gk, hk, hgk, hsig, _⟩ := holds_fn (verdict_typed (hacc h hf hh)).1 ihc hs
    cases hk
    rw [hg] at hgk; cases hgk
    rw [regTy_resolve hh hresx] at ihx
    rw [regTy_of hg hi]
    have := hargs _ _ _ hx (by rw [← hsig]; exact hpar)
    rw [← this]; exact ihx
  | @retCall h ci g rr x0 x hf gf ca ri v hl hh hci hcop hca hlr hg hri hrop hra hres _ ih =>
    have hsc := listed_typed hacc hl hh hci (by rw [hcop]; decide)
    obtain ⟨hty, _⟩ := sig_call hsc hcop hca hg
    have hsr := listed_typed hacc hlr hg hri (by rw [hrop]; decide)
    have hret := sig_ret hsr hrop hra
    rw [regTy_resolve hg hres, hret] at ih
    rw [regTy_of hh hci, hty]; exact ih
  | @retIndirect h ci a0 a g rr x0 x hf gf ca ri v hl hh hci hcop hca hres _ hlr hg hri hrop hra hresx _ ihc ih =>
    have hsc := listed_typed hacc hl hh hci (by rw [hcop]; decide)
    obtain ⟨s, hs, _, hty, _⟩ := sig_callIndirect hsc hcop hca
    rw [regTy_resolve hh hres] at ihc
    obtain ⟨k, gk, hk, hgk, hsig, _⟩ := holds_fn (verdict_typed (hacc h hf hh)).1 ihc hs
    cases hk
    rw [hg] at hgk; cases hgk
    have hsr := listed_typed hacc hlr hg hri (by rw [hrop]; decide)
    have hret := sig_ret hsr hrop hra
    rw [regTy_resolve hg hresx, hret] at ih
    rw [regTy_of hh hci, hty, ← hsig]; exact ih
  | @built h r hf i ins v hl hh hi hop os _ htypes hlen hb ih =>
    have hfr := (verdict_typed (hacc h hf hh)).1
    rw [regTy_of hh hi]
    refine built_holds hfr (fun p hp => ?_) hb
    obtain ⟨k, hk, hkp⟩ := List.getElem_of_mem hp
    have hko : k < os.length := by omega
    have := ih k hk hko
    rw [← htypes k hk hko] at this
    rw [← hkp]; exact this
  | @external h ci g hf gf ca ins v hl hh hci hcop hca hg _ os _ htypes hlen hb ih =>
    rw [regTy_of hh hci]
    exact built_from (verdict_typed (hacc h hf hh)).1 ih htypes hlen hb
  | @callback g r gf i ins v hg hi _ os _ htypes hlen hb ih =>
    rw [regTy_of hg hi]
    exact built_from (verdict_typed (hacc g gf hg)).1 ih htypes hlen hb

/-- **A17.** In a module the checker accepts, the callee of every `call_indirect` of a reached block holds a pointer to an
internal function whose signature is the callee's type, whose result is the call's type and whose parameters are the
types of the call's arguments. -/
theorem a17 {m : Module} {fr : Array Bool}
    (hacc : ∀ (g : Nat) gf, m.functions[g]? = some gf → verdict m fr gf = .ok ()) {h ci a0 a : Nat} {hf : Function}
    {ca : Inst} {v : Val} (hl : ListedReached m h ci) (hh : m.functions[h]? = some hf) (hci : hf.insts[ci]? = some ca)
    (hop : ca.op = .callIndirect) (ha : ca.a = some a0) (hres : (Fn.mk m hf).resolve (some a0) = some a)
    (hv : Reaches m fr h a v) :
    ∃ k gk, v = .fn k ∧ m.functions[k]? = some gk ∧ gk.sig.linkage = .internal ∧ gk.sig.ret = ca.ty ∧
      ∀ (j x0 : Nat) (p : Ty), ((Fn.mk m hf).extraOf ca.data)[j]? = some (some x0) → gk.sig.params[j]? = some p →
        (Fn.mk m hf).typeOf x0 = p := by
  have hsc := listed_typed hacc hl hh hci (by rw [hop]; decide)
  obtain ⟨s, hs, _, hty, hargs⟩ := sig_callIndirect hsc hop ha
  have hheld := reaches_holds hacc hv
  rw [regTy_resolve hh hres] at hheld
  obtain ⟨k, gk, hk, hgk, hsig, hlink⟩ := holds_fn (verdict_typed (hacc h hf hh)).1 hheld hs
  refine ⟨k, gk, hk, hgk, by rw [hsig]; exact hlink, by rw [hsig, hty], fun j x0 p hx hp => hargs j x0 p hx ?_⟩
  rw [← hsig]; exact hp

end VerifyIr
