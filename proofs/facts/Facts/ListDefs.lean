import Facts.Trans
import Facts.Accept

/-!
# List facts

What the stated facts of a list (`len`, `elems`) say of the list a register holds, which of them the checker accepts
without a derivation (the assumptions A6 for lists), and that every other one follows from F2.
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- The list has a length in the interval, if one is stated. -/
def LenIn (o : Option Interval) (l : List Val) : Prop := ∀ I, o = some I → I.contains l.length

/-- Every element of the list is an integer in the interval, if one is stated. -/
def ElemsIn (o : Option Interval) (l : List Val) : Prop :=
  ∀ I, o = some I → ∀ e ∈ l, ∃ n, e = .int n ∧ I.contains n

/-- The list satisfies the fact stated of value `v` itself. -/
def FactHolds (c : Ctx) (v : Nat) (l : List Val) : Prop :=
  match c.listFact? v with
  | none => True
  | some fact => LenIn fact.len l ∧ ElemsIn fact.elems l

/-- What a sound derivation says: when the operation knows, the derived intervals hold of the result. -/
def DerivSound (d : Derivation) (l : List Val) : Prop :=
  d.known = true → LenIn d.len l ∧ ElemsIn d.elems l

/-- Every list a register holds satisfies the stated fact of each value it can be read through. -/
def ListInv (c : Ctx) (R : Regs) : Prop :=
  ∀ v l, R v = some (.list l) → ∀ fuel, FactHolds c (c.liveList fuel v) l

/-- The stated length of list `v` is one the checker accepts without a derivation (A6). -/
def LenAssumed (c : Ctx) (v : Nat) (I : Interval) : Prop :=
  (∃ fact, c.listFact? v = some fact ∧ fact.len = some I) ∧
  ((c.deriveList (c.def_ v) ((c.def_ v).block.getD 0)).known = false ∨
    (c.deriveList (c.def_ v) ((c.def_ v).block.getD 0)).len = none)

/-- The stated element interval of list `v` is one the checker accepts without a derivation (A6). -/
def ElemsAssumed (c : Ctx) (v : Nat) (I : Interval) : Prop :=
  (∃ fact, c.listFact? v = some fact ∧ fact.elems = some I) ∧
  ((c.deriveList (c.def_ v) ((c.def_ v).block.getD 0)).known = false ∨
    (c.deriveList (c.def_ v) ((c.def_ v).block.getD 0)).elems = none)

theorem listFact?_get {c : Ctx} {u : Nat} {fact : ListFact} (h : c.listFact? u = some fact) :
    c.lists[u]? = some (some fact) := by
  unfold Ctx.listFact? at h
  cases hg : c.lists[u]? with
  | none => rw [hg] at h; simp at h
  | some o =>
    rw [hg] at h
    cases o with
    | none => simp at h
    | some f => simp only [Option.getD_some, Option.some.injEq] at h; rw [h]

theorem lenIn_none (l : List Val) : LenIn none l := by intro I h; cases h

theorem elemsIn_none (l : List Val) : ElemsIn none l := by intro I h; cases h

theorem lenIn_some {I : Interval} {l : List Val} (h : I.contains l.length) : LenIn (some I) l := by
  intro J hJ
  cases hJ
  exact h

theorem elemsIn_some {I : Interval} {l : List Val}
    (h : ∀ e ∈ l, ∃ n, e = .int n ∧ I.contains n) : ElemsIn (some I) l := by
  intro J hJ
  cases hJ
  exact h

/-- The stated length of the fact of an operand, as the derivation reads it. -/
theorem factHolds_len {c : Ctx} {a : Nat} {l : List Val} (h : FactHolds c a l) :
    LenIn ((c.listFact? a).bind (·.len)) l := by
  unfold FactHolds at h
  intro I hI
  cases hf : c.listFact? a with
  | none => rw [hf] at hI; simp at hI
  | some fact =>
    rw [hf] at h hI
    exact h.1 I hI

theorem factHolds_elems {c : Ctx} {a : Nat} {l : List Val} (h : FactHolds c a l) :
    ElemsIn ((c.listFact? a).bind (·.elems)) l := by
  unfold FactHolds at h
  intro I hI
  cases hf : c.listFact? a with
  | none => rw [hf] at hI; simp at hI
  | some fact =>
    rw [hf] at h hI
    exact h.2 I hI

/-! ### What F2 gives -/

theorem listOne_ok {known : Bool} {fault : Out} {stated got : Option Interval} {s found : Interval}
    (hall : ∀ o ∈ listOne known fault stated got, o.fault? = none) (hfault : fault.fault?.isSome = true)
    (hs : stated = some s) (hk : known = true) (hg : got = some found) : found.within s = true := by
  subst hs hk hg
  by_cases hw : found.within s = true
  · exact hw
  · exfalso
    have := hall fault (by simp [listOne, hw])
    rw [this] at hfault
    simp at hfault

theorem listRest_within {c : Ctx} {fact : ListFact} {d : Def} {blk : Option Nat}
    (hall : ∀ o ∈ c.listRest fact d blk, o.fault? = none) :
    (∀ s found, fact.len = some s → (c.deriveList d (blk.getD 0)).known = true →
      (c.deriveList d (blk.getD 0)).len = some found → found.within s = true) ∧
    (∀ s found, fact.elems = some s → (c.deriveList d (blk.getD 0)).known = true →
      (c.deriveList d (blk.getD 0)).elems = some found → found.within s = true) := by
  unfold Ctx.listRest at hall
  constructor
  · intro s found hs hk hg
    exact listOne_ok (fun o ho => hall o (List.mem_append_left _ ho)) (by simp [Out.fault?]) hs hk hg
  · intro s found hs hk hg
    exact listOne_ok (fun o ho => hall o (List.mem_append_right _ ho)) (by simp [Out.fault?]) hs hk hg

theorem Ctx.list_ok {c : Ctx} (h : c.firstFault = none) {fact : ListFact} (hf : fact ∈ c.f.aux.lists)
    (hreach : ∀ b, (c.def_ fact.value).block = some b → c.reached[b]? = some true) :
    ∀ o ∈ c.listRest fact (c.def_ fact.value) (c.def_ fact.value).block, o.fault? = none := by
  have := (Ctx.ff_parts h).2.2.1
  rw [List.findSome?_eq_none_iff] at this
  intro o ho
  apply this
  unfold Ctx.listOuts
  rw [List.mem_flatMap]
  refine ⟨fact, hf, ?_⟩
  unfold Ctx.listFactOut
  cases hb : (c.def_ fact.value).block with
  | none => simpa [hb] using ho
  | some b =>
    have hr := hreach b hb
    have hr' : (c.reached[b]?.getD false) = true := by rw [hr]; rfl
    simp only [hb, hr', Bool.not_true, Bool.false_eq_true, ite_false]
    rw [hb] at ho
    exact ho

/-- A list satisfies the fact stated of its value when the operation that made it derives the stated intervals, or
the checker accepts them as assumptions. -/
theorem factHolds_of_deriv {c : Ctx} (hff : c.firstFault = none) (hCtx : CtxOK c) {u : Nat} {l : List Val}
    (hreach : ∀ b, (c.def_ u).block = some b → c.reached[b]? = some true)
    (hsound : DerivSound (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)) l)
    (hlen : ∀ I, LenAssumed c u I → I.contains l.length)
    (helems : ∀ I, ElemsAssumed c u I → ∀ e ∈ l, ∃ n, e = .int n ∧ I.contains n) : FactHolds c u l := by
  unfold FactHolds
  cases hf : c.listFact? u with
  | none => trivial
  | some fact =>
    have hspec := Facts.listsOK_mem hCtx.lists (v := u) (fact := fact) (listFact?_get hf)
    obtain ⟨hval, hmem⟩ := hspec
    have hok := Ctx.list_ok hff hmem (by rw [hval]; exact hreach)
    rw [hval] at hok
    obtain ⟨hlw, hew⟩ := listRest_within hok
    constructor
    · intro I hI
      by_cases hk : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).known = true ∧
          ∃ found, (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).len = some found
      · obtain ⟨hk1, found, hfound⟩ := hk
        exact within_contains (hlw I found hI hk1 hfound) ((hsound hk1).1 found hfound)
      · apply hlen
        refine ⟨⟨fact, hf, hI⟩, ?_⟩
        by_cases hk1 : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).known = true
        · right
          cases hg : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).len with
          | none => rfl
          | some found => exact absurd ⟨hk1, found, hg⟩ hk
        · left; simpa using hk1
    · intro I hI e he
      by_cases hk : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).known = true ∧
          ∃ found, (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).elems = some found
      · obtain ⟨hk1, found, hfound⟩ := hk
        obtain ⟨n, hn, hc⟩ := (hsound hk1).2 found hfound e he
        exact ⟨n, hn, within_contains (hew I found hI hk1 hfound) hc⟩
      · apply helems I _ e he
        refine ⟨⟨fact, hf, hI⟩, ?_⟩
        by_cases hk1 : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).known = true
        · right
          cases hg : (c.deriveList (c.def_ u) ((c.def_ u).block.getD 0)).elems with
          | none => rfl
          | some found => exact absurd ⟨hk1, found, hg⟩ hk
        · left; simpa using hk1

end Facts
