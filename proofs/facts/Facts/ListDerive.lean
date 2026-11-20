import Facts.ListDefs

/-!
# The list operations derive sound facts

For each operation `Ctx.deriveList` knows, the lengths and element intervals it derives hold of the list the operation
computes, from the facts of its operands.
-/

set_option linter.unusedSimpArgs false

namespace Facts

theorem readOps_a_of_ne {R : Regs} {args : List Val} {i : Inst} (h : i.op ≠ .call) :
    (readOps R args i).a = R.read i.operands.a := by
  have : (i.op == .call) = false := by simpa using h
  simp [readOps, this]

theorem readOps_b {R : Regs} {args : List Val} {i : Inst} : (readOps R args i).b = R.read i.operands.b := rfl

theorem readOps_x {R : Regs} {args : List Val} {i : Inst} : (readOps R args i).x = i.operands.x.map R.read := rfl

theorem read_list {R : Regs} {o : Option Nat} {l : List Val} (h : (R.read o).bind Val.list? = some l) :
    ∃ w, o = some w ∧ R w = some (.list l) := by
  cases o with
  | none => simp [Regs.read] at h
  | some w =>
    refine ⟨w, rfl, ?_⟩
    simp only [Regs.read, Option.bind_some] at h
    cases hRw : R w with
    | none => rw [hRw] at h; simp at h
    | some val =>
      rw [hRw] at h
      cases val <;> simp [Val.list?] at h
      subst h; rfl

theorem hull_contains_left {a b : Interval} {n : Int} (h : a.contains n) : (a.hull b).contains n :=
  ⟨by have := h.1; simp only [Interval.hull]; omega, by have := h.2; simp only [Interval.hull]; omega⟩

theorem hull_contains_right {a b : Interval} {n : Int} (h : b.contains n) : (a.hull b).contains n :=
  ⟨by have := h.1; simp only [Interval.hull]; omega, by have := h.2; simp only [Interval.hull]; omega⟩

theorem mem_regOps_x {i : Inst} {o : Option Nat} {w : Nat} (ho : o ∈ i.operands.x) (hw : o = some w) :
    w ∈ regOps i := by
  unfold regOps
  simp only [List.mem_append, List.mem_filterMap, id]
  exact Or.inr ⟨o, ho, hw⟩

/-- A scalar operand's interval holds the integer its register has. -/
theorem scalar_sound {c : Ctx} {R : Regs} {i : Inst} {here : Nat} {o : Option Nat} {I : Interval}
    (hop : OperandSound c R here (· ∈ regOps i)) (hmem : ∀ w, o = some w → w ∈ regOps i)
    (h : c.scalar o here = some I) : ∃ w n, o = some w ∧ R w = some (.int n) ∧ I.contains n := by
  cases o with
  | none => simp [Ctx.scalar] at h
  | some w =>
    unfold Ctx.scalar at h
    by_cases hn : (c.def_ w).ty.range.isNone = true
    · simp [hn] at h
    · simp only [hn, Bool.false_eq_true, ite_false] at h
      obtain ⟨_, n, lim, hr, hc, _, _⟩ := operand_eq_raw hop (hmem w rfl) h
      exact ⟨w, n, rfl, hr, hc⟩


theorem eval_listPush {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} (hopc : i.op = .listPush)
    (hev : evalInst R args i ch = .val (.list l)) :
    ∃ w la e, i.operands.a = some w ∧ R w = some (.list la) ∧ R.read i.operands.b = some e ∧
      l = la ++ [e] ∧ (la.length : Int) + 1 ≤ maxListLength := by
  have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
  unfold evalInst evalOps at hev
  simp only [hopc, readOps_a_of_ne hnc, readOps_b] at hev
  cases hla : (R.read i.operands.a).bind Val.list? with
  | none => rw [hla] at hev; simp at hev
  | some la =>
    cases hb : R.read i.operands.b with
    | none => rw [hla, hb] at hev; simp at hev
    | some e =>
      rw [hla, hb] at hev
      by_cases hgt : (la.length : Int) + 1 > maxListLength
      · simp [hgt] at hev
      · simp only [hgt, ite_false, Res.val.injEq, Val.list.injEq] at hev
        obtain ⟨w, hw, hRw⟩ := read_list hla
        exact ⟨w, la, e, hw, hRw, rfl, hev.symm, by omega⟩

theorem listPush_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} {here : Nat}
    {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i) (hopc : i.op = .listPush)
    (hop : OperandSound c R here (· ∈ regOps i))
    (hlists : ∀ w la, R w = some (.list la) → (la.length : Int) ≤ maxListLength ∧ FactHolds c w la)
    (hev : evalInst R args i ch = .val (.list l)) :
    DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  obtain ⟨w, la, e, hw, hRw, hRb, hl, hlen⟩ := eval_listPush hopc hev
  obtain ⟨hlaM, hfa⟩ := hlists w la hRw
  have hval : ∀ V, c.scalar i.operands.b here = some V → ∃ n, e = .int n ∧ V.contains n := by
    intro V hV
    obtain ⟨wb, n, hbw, hRwb, hcn⟩ := scalar_sound hop (fun w' hw' => mem_regOps_b hw') hV
    rw [hbw] at hRb
    simp only [Regs.read, Option.bind_some, hRwb, Option.some.injEq] at hRb
    exact ⟨n, hRb.symm, hcn⟩
  have key : ∀ (oe : Option Interval) (J : Interval), ElemsIn oe la →
      (match oe with
       | some held => match c.scalar i.operands.b here with | some v => some (held.hull v) | none => none
       | none => none) = some J → ∀ e' ∈ la ++ [e], ∃ n, e' = .int n ∧ J.contains n := by
    intro oe J hel hJ e' he'
    cases oe with
    | none => simp at hJ
    | some held =>
      cases hs : c.scalar i.operands.b here with
      | none => rw [hs] at hJ; simp at hJ
      | some V =>
        rw [hs] at hJ
        simp only [Option.some.injEq] at hJ
        subst hJ
        rcases List.mem_append.mp he' with h | h
        · obtain ⟨n, hn, hc⟩ := hel held rfl e' h
          exact ⟨n, hn, hull_contains_left hc⟩
        · have : e' = e := by simpa using h
          subst this
          obtain ⟨n, hn, hc⟩ := hval V hs
          exact ⟨n, hn, hull_contains_right hc⟩
  have hlenIn := factHolds_len hfa
  have helIn := factHolds_elems hfa
  intro _
  unfold Ctx.deriveList
  simp only [hnk, hdi, hopc, hw, Bool.false_eq_true, ite_false]
  subst hl
  constructor
  · intro J hJ
    cases hq : (c.listFact? w).bind (fun x => x.len) with
    | none => rw [hq] at hJ; simp at hJ
    | some lv =>
      rw [hq] at hJ
      simp only [Option.map_some, Option.some.injEq] at hJ
      subst hJ
      have h1 := hlenIn lv hq
      simp only [Interval.contains] at h1 ⊢
      simp only [List.length_append, List.length_singleton]
      omega
  · intro J hJ e' he'
    cases hq : (c.listFact? w).bind (fun x => x.len) with
    | none => rw [hq] at hJ; exact key _ J helIn hJ e' he'
    | some lv =>
      rw [hq] at hJ
      by_cases hz : (lv.lo == 0 && lv.hi == 0) = true
      · simp only [hz, ite_true] at hJ
        cases hs : c.scalar i.operands.b here with
        | none => simp only [hs] at hJ; split at hJ <;> simp at hJ
        | some V =>
          simp only [hs, Option.some.injEq] at hJ
          subst hJ
          have h1 := hlenIn lv hq
          simp only [Bool.and_eq_true, beq_iff_eq] at hz
          have h0 : la.length = 0 := by simp only [Interval.contains] at h1; omega
          have hla : la = [] := List.eq_nil_of_length_eq_zero h0
          subst hla
          have : e' = e := by simpa using he'
          subst this
          exact hval V hs
      · simp only [hz, ite_false] at hJ
        exact key _ J helIn hJ e' he'

theorem eval_listNew {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} (hopc : i.op = .listNew)
    (hev : evalInst R args i ch = .val (.list l)) : l = [] := by
  unfold evalInst evalOps at hev
  simp only [hopc, Res.val.injEq, Val.list.injEq] at hev
  exact hev.symm

theorem listNew_sound {c : Ctx} {i : Inst} {l : List Val} {here : Nat} {d : Def} (hk : d.kind ≠ .phi)
    (hdi : d.inst = some i) (hopc : i.op = .listNew) (hl : l = []) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  intro _
  unfold Ctx.deriveList
  simp only [hnk, hdi, hopc, Bool.false_eq_true, ite_false]
  subst hl
  exact ⟨lenIn_some ⟨by simp [Interval.point], by simp [Interval.point]⟩, elemsIn_none _⟩

theorem failWith_ne_val (ck : Check) (v : Val) : failWith ck ≠ .val v := by
  cases ck <;> simp [failWith]

theorem eval_listPop {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} (hopc : i.op = .listPop)
    (hev : evalInst R args i ch = .val (.list l)) :
    ∃ w la, i.operands.a = some w ∧ R w = some (.list la) ∧ la ≠ [] ∧ l = la.dropLast := by
  have hnc : i.op ≠ .call := by rw [hopc]; intro h; cases h
  unfold evalInst evalOps at hev
  simp only [hopc, readOps_a_of_ne hnc] at hev
  cases hla : (R.read i.operands.a).bind Val.list? with
  | none => rw [hla] at hev; simp at hev
  | some la =>
    rw [hla] at hev
    by_cases hemp : la.isEmpty = true
    · simp only [hemp, ite_true] at hev
      exact absurd hev (failWith_ne_val _ _)
    · simp only [hemp, Bool.false_eq_true, ite_false, Res.val.injEq, Val.list.injEq] at hev
      obtain ⟨w, hw, hRw⟩ := read_list hla
      exact ⟨w, la, hw, hRw, by intro h; apply hemp; simp [h], hev.symm⟩

theorem listPop_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} {here : Nat}
    {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i) (hopc : i.op = .listPop)
    (hlists : ∀ w la, R w = some (.list la) → (la.length : Int) ≤ maxListLength ∧ FactHolds c w la)
    (hev : evalInst R args i ch = .val (.list l)) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  obtain ⟨w, la, hw, hRw, hne, hl⟩ := eval_listPop hopc hev
  obtain ⟨_, hfa⟩ := hlists w la hRw
  have hlenIn := factHolds_len hfa
  have helIn := factHolds_elems hfa
  have hlen : l.length + 1 = la.length := by
    subst hl
    rw [List.length_dropLast]
    have : 0 < la.length := List.length_pos_iff.mpr hne
    omega
  intro _
  unfold Ctx.deriveList
  simp only [hnk, hdi, hopc, hw, Bool.false_eq_true, ite_false]
  constructor
  · intro J hJ
    cases hq : (c.listFact? w).bind (fun x => x.len) with
    | none => rw [hq] at hJ; simp at hJ
    | some lv =>
      rw [hq] at hJ
      simp only [Option.map_some, Option.some.injEq] at hJ
      subst hJ
      have h1 := hlenIn lv hq
      simp only [Interval.contains] at h1 ⊢
      omega
  · intro J hJ e he
    have : e ∈ la := by subst hl; exact List.dropLast_subset la he
    exact helIn J hJ e this

theorem eval_copy {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val}
    (hopc : i.op = .listCopy ∨ i.op = .listViewOf ∨ i.op = .borrow)
    (hev : evalInst R args i ch = .val (.list l)) : ∃ w, i.operands.a = some w ∧ R w = some (.list l) := by
  have hnc : i.op ≠ .call := by rcases hopc with h | h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hopc with h | h | h <;>
  · simp only [h, readOps_a_of_ne hnc] at hev
    cases hla : (R.read i.operands.a).bind Val.list? with
    | none => rw [hla] at hev; simp at hev
    | some la =>
      rw [hla] at hev
      simp only [Res.val.injEq, Val.list.injEq] at hev
      subst hev
      exact read_list hla

theorem copy_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} {here : Nat}
    {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i)
    (hopc : i.op = .listCopy ∨ i.op = .listViewOf ∨ i.op = .borrow)
    (hlists : ∀ w la, R w = some (.list la) → (la.length : Int) ≤ maxListLength ∧ FactHolds c w la)
    (hev : evalInst R args i ch = .val (.list l)) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  obtain ⟨w, hw, hRw⟩ := eval_copy hopc hev
  obtain ⟨_, hfa⟩ := hlists w l hRw
  intro _
  unfold Ctx.deriveList
  rcases hopc with h | h | h <;> simp only [hnk, hdi, h, hw, Bool.false_eq_true, ite_false] <;>
    exact ⟨factHolds_len hfa, factHolds_elems hfa⟩

theorem eval_listSet {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val}
    (hopc : i.op = .listSet ∨ i.op = .arraySet) (hev : evalInst R args i ch = .val (.list l)) :
    ∃ w la x0 xs e, i.operands.a = some w ∧ R w = some (.list la) ∧ i.operands.x = x0 :: xs ∧ R.read x0 = some e ∧
      l.length = la.length ∧ ∀ e' ∈ l, e' ∈ la ∨ e' = e := by
  have hnc : i.op ≠ .call := by rcases hopc with h | h <;> rw [h] <;> intro h' <;> cases h'
  unfold evalInst evalOps at hev
  rcases hopc with h | h <;>
  · simp only [h, readOps_a_of_ne hnc, readOps_b, readOps_x] at hev
    cases hla : (R.read i.operands.a).bind Val.list? with
    | none => rw [hla] at hev; simp at hev
    | some la =>
      cases hk : (R.read i.operands.b).bind Val.int? with
      | none => rw [hla, hk] at hev; simp at hev
      | some k =>
        cases hx : i.operands.x with
        | nil => rw [hla, hk, hx] at hev; simp at hev
        | cons x0 xs =>
          cases hr : R.read x0 with
          | none => rw [hla, hk, hx] at hev; simp [hr] at hev
          | some e =>
            rw [hla, hk, hx] at hev
            simp only [List.map_cons, hr] at hev
            by_cases hc : 0 ≤ k ∧ k < (la.length : Int)
            · simp only [hc, and_self, ite_true, Res.val.injEq, Val.list.injEq] at hev
              obtain ⟨w, hw, hRw⟩ := read_list hla
              refine ⟨w, la, x0, xs, e, hw, hRw, rfl, hr, ?_, ?_⟩
              · rw [← hev]; simp
              · intro e' he'
                rw [← hev] at he'
                exact List.mem_or_eq_of_mem_set he'
            · simp only [hc, ite_false] at hev
              exact absurd hev (failWith_ne_val _ _)

theorem listSet_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} {here : Nat}
    {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i) (hopc : i.op = .listSet ∨ i.op = .arraySet)
    (hop : OperandSound c R here (· ∈ regOps i))
    (hlists : ∀ w la, R w = some (.list la) → (la.length : Int) ≤ maxListLength ∧ FactHolds c w la)
    (hev : evalInst R args i ch = .val (.list l)) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  obtain ⟨w, la, x0, xs, e, hw, hRw, hx, hRx, hlen, hmem⟩ := eval_listSet hopc hev
  obtain ⟨_, hfa⟩ := hlists w la hRw
  have hlenIn := factHolds_len hfa
  have helIn := factHolds_elems hfa
  have hval : ∀ V, c.scalar x0 here = some V → ∃ n, e = .int n ∧ V.contains n := by
    intro V hV
    obtain ⟨wb, n, hbw, hRwb, hcn⟩ := scalar_sound hop (fun w' hw' => mem_regOps_x (by rw [hx]; simp) hw') hV
    rw [hbw] at hRx
    simp only [Regs.read, Option.bind_some, hRwb, Option.some.injEq] at hRx
    exact ⟨n, hRx.symm, hcn⟩
  intro _
  unfold Ctx.deriveList
  rcases hopc with h | h <;> simp only [hnk, hdi, h, hw, hx, Bool.false_eq_true, ite_false] <;>
  · constructor
    · intro J hJ
      have := hlenIn J hJ
      simp only [Interval.contains] at this ⊢
      omega
    · intro J hJ e' he'
      cases hq : (c.listFact? w).bind (fun x => x.elems) with
      | none => rw [hq] at hJ; simp at hJ
      | some held =>
        rw [hq] at hJ
        cases hs : c.scalar x0 here with
        | none => simp only [hs] at hJ; simp at hJ
        | some V =>
          simp only [hs, Option.some.injEq] at hJ
          subst hJ
          rcases hmem e' he' with h1 | h1
          · obtain ⟨n, hn, hc⟩ := helIn held hq e' h1
            exact ⟨n, hn, hull_contains_left hc⟩
          · subst h1
            obtain ⟨n, hn, hc⟩ := hval V hs
            exact ⟨n, hn, hull_contains_right hc⟩

theorem eval_recordMake {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} (hopc : i.op = .recordMake)
    (hty : i.ty = .list) (hev : evalInst R args i ch = .val (.list l)) :
    l = i.operands.x.map fun o => (R.read o).getD .other := by
  unfold evalInst evalOps at hev
  simp only [hopc, hty, readOps_x, ite_true, Res.val.injEq, Val.list.injEq, List.map_map] at hev
  rw [← hev]
  rfl

/-- The element hull of the operands `xs` (read from position `k0`) is an interval holding every operand's value. -/
theorem hullFold_sound {c : Ctx} {R : Regs} {here : Nat} :
    ∀ (xs : List (Option Nat)) (k0 : Nat) (acc : Option Interval) (ys : List (Option Nat)),
      (∀ o ∈ xs, ∀ I, c.scalar o here = some I → ∃ n, (R.read o).getD .other = .int n ∧ I.contains n) →
      (∀ J, acc = some J → ∀ o ∈ ys, ∃ n, (R.read o).getD .other = .int n ∧ J.contains n) →
      (k0 = 0 → ys = []) →
      ∀ J, (xs.zipIdx k0).foldl (c.hullStep here) acc = some J →
        ∀ o ∈ ys ++ xs, ∃ n, (R.read o).getD .other = .int n ∧ J.contains n := by
  intro xs
  induction xs with
  | nil =>
    intro k0 acc ys _ hacc _ J hJ o ho
    simp only [List.zipIdx_nil, List.foldl_nil] at hJ
    simp only [List.append_nil] at ho
    exact hacc J hJ o ho
  | cons o0 rest ih =>
    intro k0 acc ys hs hacc hk0 J hJ o ho
    simp only [List.zipIdx_cons, List.foldl_cons] at hJ
    have hs0 := hs o0 (List.mem_cons_self ..)
    have hsrest : ∀ o ∈ rest, ∀ I, c.scalar o here = some I → ∃ n, (R.read o).getD .other = .int n ∧ I.contains n :=
      fun o hmem => hs o (List.mem_cons_of_mem _ hmem)
    have hacc' : ∀ J', c.hullStep here acc (o0, k0) = some J' → ∀ o' ∈ ys ++ [o0],
        ∃ n, (R.read o').getD .other = .int n ∧ J'.contains n := by
      intro J' hJ' o' ho'
      unfold Ctx.hullStep at hJ'
      by_cases hz : (k0 == 0) = true
      · simp only [hz, ite_true] at hJ'
        have hk : k0 = 0 := by simpa using hz
        have hy := hk0 hk
        subst hy
        simp only [List.nil_append, List.mem_singleton] at ho'
        subst ho'
        exact hs0 J' hJ'
      · simp only [hz, Bool.false_eq_true, ite_false] at hJ'
        cases hac : acc with
        | none => rw [hac] at hJ'; simp at hJ'
        | some held =>
          rw [hac] at hJ'
          cases hv : c.scalar o0 here with
          | none => simp only [hv] at hJ'; simp at hJ'
          | some V =>
            simp only [hv, Option.some.injEq] at hJ'
            subst hJ'
            rcases List.mem_append.mp ho' with h1 | h1
            · obtain ⟨n, hn, hc⟩ := hacc held hac o' h1
              exact ⟨n, hn, hull_contains_left hc⟩
            · have : o' = o0 := by simpa using h1
              subst this
              obtain ⟨n, hn, hc⟩ := hs0 V hv
              exact ⟨n, hn, hull_contains_right hc⟩
    have := ih (k0 + 1) (c.hullStep here acc (o0, k0)) (ys ++ [o0]) hsrest hacc' (by intro h; omega) J hJ o
    simp only [List.append_assoc, List.singleton_append] at this
    exact this ho

theorem recordMake_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val} {here : Nat}
    {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i) (hopc : i.op = .recordMake)
    (hop : OperandSound c R here (· ∈ regOps i))
    (hev : evalInst R args i ch = .val (.list l)) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  by_cases hty : i.ty = .list
  · have hl := eval_recordMake hopc hty hev
    intro _
    unfold Ctx.deriveList
    simp only [hnk, hdi, hopc, hty, Bool.false_eq_true, ite_false, bne_self_eq_false]
    constructor
    · refine lenIn_some ⟨?_, ?_⟩ <;> simp [hl, Interval.point]
    · intro J hJ e he
      have hs : ∀ o ∈ i.operands.x, ∀ I, c.scalar o here = some I →
          ∃ n, (R.read o).getD .other = .int n ∧ I.contains n := by
        intro o ho I hI
        obtain ⟨w, n, hw, hRw, hcn⟩ := scalar_sound hop (fun w' hw' => mem_regOps_x ho hw') hI
        refine ⟨n, ?_, hcn⟩
        rw [hw]
        simp [Regs.read, hRw]
      have := hullFold_sound i.operands.x 0 none [] hs (by intro J h; cases h) (fun _ => rfl) J hJ
      rw [hl] at he
      obtain ⟨o, ho, rfl⟩ := List.mem_map.mp he
      exact this o (by simpa using ho)
  · intro hknown
    unfold Ctx.deriveList at hknown
    simp [hnk, hdi, hopc, hty] at hknown

/-- Every instruction that makes a list derives sound facts. -/
theorem deriveList_inst_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch : Val} {l : List Val}
    {here : Nat} {d : Def} (hk : d.kind ≠ .phi) (hdi : d.inst = some i)
    (hop : OperandSound c R here (· ∈ regOps i))
    (hlists : ∀ w la, R w = some (.list la) → (la.length : Int) ≤ maxListLength ∧ FactHolds c w la)
    (hev : evalInst R args i ch = .val (.list l)) : DerivSound (c.deriveList d here) l := by
  have hnk : (d.kind == .phi) = false := by simpa using hk
  cases hopc : i.op
  case listNew => exact listNew_sound hk hdi hopc (eval_listNew hopc hev)
  case listPush => exact listPush_sound hk hdi hopc hop hlists hev
  case listPop => exact listPop_sound hk hdi hopc hlists hev
  case listCopy => exact copy_sound hk hdi (Or.inl hopc) hlists hev
  case listViewOf => exact copy_sound hk hdi (Or.inr (Or.inl hopc)) hlists hev
  case borrow => exact copy_sound hk hdi (Or.inr (Or.inr hopc)) hlists hev
  case listSet => exact listSet_sound hk hdi (Or.inl hopc) hop hlists hev
  case arraySet => exact listSet_sound hk hdi (Or.inr hopc) hop hlists hev
  case recordMake => exact recordMake_sound hk hdi hopc hop hev
  all_goals
    intro hknown
    unfold Ctx.deriveList at hknown
    simp [hnk, hdi, hopc] at hknown

/-- Folding the hull of the intervals of a list of edges gives an interval holding all of them. -/
theorem hullFoldOpt {f : PhiEdge → Option Interval} :
    ∀ (live : List PhiEdge) (acc : Option Interval) (J : Interval),
      live.foldl (fun (acc : Option Interval) e =>
        match f e with
        | none => acc
        | some r => some (match acc with | none => r | some so => so.hull r)) acc = some J →
      (∀ e ∈ live, ∀ r, f e = some r → ∀ n, r.contains n → J.contains n) ∧
        (∀ K, acc = some K → ∀ n, K.contains n → J.contains n) := by
  intro live
  induction live with
  | nil =>
    intro acc J h
    simp only [List.foldl_nil] at h
    refine ⟨fun e he r hr n hn => (by cases he), ?_⟩
    intro K hK n hn
    rw [h] at hK
    cases hK
    exact hn
  | cons e rest ih =>
    intro acc J h
    simp only [List.foldl_cons] at h
    obtain ⟨h1, h2⟩ := ih _ J h
    constructor
    · intro e' he' r hr n hn
      rcases List.mem_cons.mp he' with rfl | hrest
      · rw [hr] at h2
        cases acc with
        | none => exact h2 r rfl n hn
        | some so => exact h2 (so.hull r) rfl n (hull_contains_right hn)
      · exact h1 e' hrest r hr n hn
    · intro K hK n hn
      cases hf : f e with
      | none => rw [hf] at h2; exact h2 K hK n hn
      | some r =>
        rw [hf] at h2
        subst hK
        exact h2 (K.hull r) rfl n (hull_contains_left hn)

/-- A phi joins sound facts when its block is entered along a live edge. -/
theorem joinLists_sound {c : Ctx} {p : Phi} {blk : Nat} {e0 : PhiEdge} {l : List Val} (he : e0 ∈ p.edges)
    (hlive : edgeLive c e0.block blk = true) (hf : FactHolds c e0.value l) :
    DerivSound (c.joinLists p blk) l := by
  have hmem : e0 ∈ p.edges.filter fun e => edgeLive c e.block blk := List.mem_filter.mpr ⟨he, hlive⟩
  have hne : (p.edges.filter fun e => edgeLive c e.block blk).isEmpty = false := by
    cases hl : p.edges.filter fun e => edgeLive c e.block blk with
    | nil => rw [hl] at hmem; cases hmem
    | cons _ _ => rfl
  intro _
  unfold Ctx.joinLists
  simp only [hne, Bool.false_eq_true, ite_false]
  constructor
  · intro J hJ
    by_cases hk : (p.edges.filter fun e => edgeLive c e.block blk).all
        (fun e => ((c.listFact? e.value).bind (·.len)).isSome) = true
    · simp only [hk, ite_true] at hJ
      obtain ⟨h1, _⟩ := hullFoldOpt _ none J hJ
      have hk0 := (List.all_eq_true.mp hk) e0 hmem
      cases hr : (c.listFact? e0.value).bind (·.len) with
      | none => rw [hr] at hk0; simp at hk0
      | some r => exact h1 e0 hmem r hr _ (factHolds_len hf r hr)
    · simp only [hk, Bool.false_eq_true, ite_false] at hJ
      cases hJ
  · intro J hJ e he'
    by_cases hk : (p.edges.filter fun e => edgeLive c e.block blk).all
        (fun e => ((c.listFact? e.value).bind (·.elems)).isSome) = true
    · simp only [hk, ite_true] at hJ
      obtain ⟨h1, _⟩ := hullFoldOpt _ none J hJ
      have hk0 := (List.all_eq_true.mp hk) e0 hmem
      cases hr : (c.listFact? e0.value).bind (·.elems) with
      | none => rw [hr] at hk0; simp at hk0
      | some r =>
        obtain ⟨n, hn, hc⟩ := factHolds_elems hf r hr e he'
        exact ⟨n, hn, h1 e0 hmem r hr n hc⟩
    · simp only [hk, Bool.false_eq_true, ite_false] at hJ
      cases hJ

/-! ### Reading a list through its views and phis -/

theorem liveList_zero (c : Ctx) (v : Nat) : c.liveList 0 v = v := rfl

/-- A phi's live list is the phi or the value of an edge along which its block can be entered. -/
theorem liveList_phi {c : Ctx} {v fuel : Nat} {p : Phi} {blk : Nat} (hk : (c.def_ v).kind = .phi)
    (hp : (c.def_ v).phi = some p) (hb : (c.def_ v).block = some blk) {e0 : PhiEdge} (he0 : e0 ∈ p.edges)
    (hlive : edgeLive c e0.block blk = true) :
    c.liveList (fuel + 1) v = v ∨ c.liveList (fuel + 1) v = e0.value := by
  unfold Ctx.liveList
  simp only [hk, hp, hb]
  generalize hl : p.edges.filter (fun e => (c.reached[e.block]?.getD false) && edgeOpen c e.block blk) = live
  have hmem : e0 ∈ live := by
    rw [← hl]
    exact List.mem_filter.mpr ⟨he0, by simpa [edgeLive] using hlive⟩
  cases live with
  | nil => cases hmem
  | cons e rest =>
    by_cases hall : rest.all (fun e' => e'.value == e.value) = true
    · right
      simp only [hall, ite_true]
      rcases List.mem_cons.mp hmem with rfl | hr
      · rfl
      · exact (beq_iff_eq.mp ((List.all_eq_true.mp hall) e0 hr)).symm
    · left
      simp [hall]

/-- An instruction's live list is the instruction's value, or the live list of the list it views. -/
theorem liveList_inst {c : Ctx} {v fuel : Nat} {i : Inst} (hk : (c.def_ v).kind = .inst)
    (hi : (c.def_ v).inst = some i) :
    c.liveList (fuel + 1) v = v ∨
      ∃ a, (i.op = .listViewOf ∨ i.op = .borrow) ∧ i.operands.a = some a ∧ c.liveList (fuel + 1) v = c.liveList fuel a := by
  by_cases hv : (i.op == .listViewOf || i.op == .borrow) = true
  · cases ha : i.operands.a with
    | none =>
      left
      rw [Ctx.liveList]
      simp [hk, hi, hv, ha]
    | some a =>
      right
      refine ⟨a, ?_, rfl, ?_⟩
      · simpa using hv
      · rw [Ctx.liveList]
        simp [hk, hi, hv, ha]
  · left
    rw [Ctx.liveList]
    simp [hk, hi, hv]

/-- A constant, parameter or other `pre` value is its own live list. -/
theorem liveList_pre {c : Ctx} {v fuel : Nat} (hk : (c.def_ v).kind = .pre) : c.liveList (fuel + 1) v = v := by
  unfold Ctx.liveList
  simp [hk]

theorem deriveList_phi {c : Ctx} {d : Def} {here : Nat} {p : Phi} {blk : Nat} (hk : d.kind = .phi)
    (hp : d.phi = some p) (hb : d.block = some blk) : c.deriveList d here = c.joinLists p blk := by
  unfold Ctx.deriveList
  simp [hk, hp, hb]

end Facts
