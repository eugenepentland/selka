import Facts.Rules
import Facts.Avail
import Facts.Sem
import Facts.IntLemmas

/-!
# Transfer rules are sound

For each operation, the interval the rule of design §4 derives contains the result the machine computes.
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- A type with a range is a fixed-width integer type, whose bounds are the standard ones. -/
theorem range_eq_arith {t : Ty} {lim : Interval} (h : t.range = some lim) :
    0 < t.bits ∧ lim.lo = Arith.lo t.signed t.bits ∧ lim.hi = Arith.hi t.signed t.bits := by
  cases t <;> simp [Ty.range, Ty.bits, Ty.signed, Arith.lo, Arith.hi] at h ⊢ <;> subst h <;> simp

theorem inRange_of_range {t : Ty} {lim : Interval} {n : Int} (h : t.range = some lim) (hn : lim.contains n) :
    Arith.inRange t.signed t.bits n := by
  obtain ⟨_, h1, h2⟩ := range_eq_arith h
  exact ⟨by rw [← h1]; exact hn.1, by rw [← h2]; exact hn.2⟩

/-- The `bit_xor` row: two nonnegative operands below `2^k` give a nonnegative result below `2^k`. -/
theorem xorVal_range {t : Ty} {lim : Interval} (hr : t.range = some lim) {x y : Int} (hx : lim.contains x)
    (hy : lim.contains y) (hx0 : 0 ≤ x) (hy0 : 0 ≤ y) {k : Nat} (hxk : x < 2 ^ k) (hyk : y < 2 ^ k) :
    0 ≤ xorVal t x y ∧ xorVal t x y < 2 ^ k := by
  obtain ⟨hn, h1, h2⟩ := range_eq_arith hr
  have hxr := inRange_of_range hr hx
  have hyr := inRange_of_range hr hy
  unfold xorVal
  generalize t.bits = n at hn h1 h2 hxr hyr ⊢
  have hxn : x.toNat < 2 ^ n := by
    have := hxr.2
    unfold Arith.hi at this
    cases hs : t.signed
    · rw [hs] at this; simp at this
      have h3 : (2 : Int) ^ n = ((2 ^ n : Nat) : Int) := by push_cast; rfl
      omega
    · rw [hs] at this; simp at this
      have h3 : (2 : Int) ^ (n - 1) ≤ (2 : Int) ^ n := by
        have : (2 ^ (n - 1) : Nat) ≤ 2 ^ n := Nat.pow_le_pow_right (by omega) (by omega)
        exact_mod_cast this
      have h4 : (2 : Int) ^ n = ((2 ^ n : Nat) : Int) := by push_cast; rfl
      omega
  have hyn : y.toNat < 2 ^ n := by
    have := hyr.2
    unfold Arith.hi at this
    cases hs : t.signed
    · rw [hs] at this; simp at this
      have h3 : (2 : Int) ^ n = ((2 ^ n : Nat) : Int) := by push_cast; rfl
      omega
    · rw [hs] at this; simp at this
      have h3 : (2 : Int) ^ (n - 1) ≤ (2 : Int) ^ n := by
        have : (2 ^ (n - 1) : Nat) ≤ 2 ^ n := Nat.pow_le_pow_right (by omega) (by omega)
        exact_mod_cast this
      have h4 : (2 : Int) ^ n = ((2 ^ n : Nat) : Int) := by push_cast; rfl
      omega
  have hax : (BitVec.ofInt n x).toNat = x.toNat := by
    have := Arith.ofInt_ofNat_toNat hxn
    rwa [Int.toNat_of_nonneg hx0] at this
  have hay : (BitVec.ofInt n y).toNat = y.toNat := by
    have := Arith.ofInt_ofNat_toNat hyn
    rwa [Int.toNat_of_nonneg hy0] at this
  have hz : (BitVec.ofInt n x ^^^ BitVec.ofInt n y).toNat = x.toNat ^^^ y.toNat := by
    rw [BitVec.toNat_xor, hax, hay]
  have hxk' : x.toNat < 2 ^ k := by
    have : x < ((2 ^ k : Nat) : Int) := by push_cast; exact hxk
    omega
  have hyk' : y.toNat < 2 ^ k := by
    have : y < ((2 ^ k : Nat) : Int) := by push_cast; exact hyk
    omega
  have hzk : x.toNat ^^^ y.toNat < 2 ^ k := Nat.xor_lt_two_pow hxk' hyk'
  cases hs : t.signed
  · simp only [Arith.ival, Bool.false_eq_true, ite_false, hz]
    refine ⟨Int.natCast_nonneg _, ?_⟩
    have : ((x.toNat ^^^ y.toNat : Nat) : Int) < ((2 ^ k : Nat) : Int) := by exact_mod_cast hzk
    push_cast at this
    exact this
  · simp only [Arith.ival, ite_true]
    have hx2 : x.toNat < 2 ^ (n - 1) := by
      have := hxr.2
      unfold Arith.hi at this
      rw [hs] at this; simp at this
      have h4 : (2 : Int) ^ (n - 1) = ((2 ^ (n - 1) : Nat) : Int) := by push_cast; rfl
      omega
    have hy2 : y.toNat < 2 ^ (n - 1) := by
      have := hyr.2
      unfold Arith.hi at this
      rw [hs] at this; simp at this
      have h4 : (2 : Int) ^ (n - 1) = ((2 ^ (n - 1) : Nat) : Int) := by push_cast; rfl
      omega
    have hz2 : x.toNat ^^^ y.toNat < 2 ^ (n - 1) := Nat.xor_lt_two_pow hx2 hy2
    have hpow : 2 ^ n = 2 * 2 ^ (n - 1) := by
      obtain ⟨m, hm⟩ : ∃ m, n = m + 1 := ⟨n - 1, by omega⟩
      rw [hm]; simp [Nat.pow_succ]; omega
    have hc : 2 * (BitVec.ofInt n x ^^^ BitVec.ofInt n y).toNat < 2 ^ n := by
      rw [hz]; omega
    rw [BitVec.toInt_eq_toNat_of_lt hc, hz]
    refine ⟨Int.natCast_nonneg _, ?_⟩
    have : ((x.toNat ^^^ y.toNat : Nat) : Int) < ((2 ^ k : Nat) : Int) := by exact_mod_cast hzk
    push_cast at this
    exact this


theorem range_lo_nonpos {t : Ty} {lim : Interval} (h : t.range = some lim) : lim.lo ≤ 0 := by
  obtain ⟨hn, h1, _⟩ := range_eq_arith h
  rw [h1]
  unfold Arith.lo
  cases t.signed <;> simp
  have : (0 : Int) ≤ 2 ^ (t.bits - 1) := by
    have := Nat.two_pow_pos (t.bits - 1)
    exact_mod_cast Nat.le_of_lt this
  omega

/-- The result of an arithmetic operation that produced a value: exact and in range, or (wrapping form) reduced. -/
theorem ofInt_val {t : Ty} {lim : Interval} {ck : Check} {r : Int} {w : Val} (hr : t.range = some lim)
    (h : Res.ofInt t ck r = .val w) :
    (lim.contains r ∧ w = .int r) ∨ (¬ lim.contains r ∧ ck = .none ∧ w = .int (wrapTo t r)) := by
  unfold Res.ofInt at h
  rw [hr] at h
  simp only [] at h
  split at h
  · rename_i hin
    cases h
    exact Or.inl ⟨hin, rfl⟩
  · rename_i hout
    cases ck <;> simp only [] at h
    · cases h; exact Or.inr ⟨hout, rfl, rfl⟩
    · cases h
    · cases h

/-- The operand intervals the rules read hold the registers' values, which lie in their types; for the registers `S`
names. -/
def OperandSound (c : Ctx) (R : Regs) (here : Nat) (S : Nat → Prop) : Prop :=
  ∀ (w : Nat) (I : Interval), S w → c.operandRaw (some w) here = some I →
    ∃ n lim, R w = some (.int n) ∧ I.contains n ∧ (c.def_ w).ty.range = some lim ∧ lim.contains n

/-- The view of a register holding an integer is not empty, so `operand` is the view. -/
theorem operand_eq_raw {c : Ctx} {R : Regs} {here : Nat} {S : Nat → Prop} (hop : OperandSound c R here S) {w : Nat}
    (hw : S w) {I : Interval} (h : c.operand (some w) here = some I) :
    c.operandRaw (some w) here = some I ∧ ∃ n lim, R w = some (.int n) ∧ I.contains n ∧ (c.def_ w).ty.range = some lim ∧
      lim.contains n := by
  unfold Ctx.operand at h
  cases hr : c.operandRaw (some w) here with
  | none => rw [hr] at h; simp at h
  | some r =>
    rw [hr] at h
    obtain ⟨n, lim, hRw, hrc, hl, hlc⟩ := hop w r hw hr
    have hne : r.isEmpty = false := by
      cases he : r.isEmpty with
      | false => rfl
      | true =>
        simp only [Interval.isEmpty, decide_eq_true_eq] at he
        have := hrc.1; have := hrc.2; omega
    simp only [hne, Bool.false_eq_true, ite_false, Option.some.injEq] at h
    subst h
    exact ⟨rfl, n, lim, hRw, hrc, hl, hlc⟩

/-- The registers an instruction reads are not never-produced values: no emptied view. -/
theorem emptyView_false {c : Ctx} {R : Regs} {here : Nat} {S : Nat → Prop} (hop : OperandSound c R here S) {w : Nat}
    (hw : S w) {n : Int} (hR : R w = some (.int n)) (hty : ∃ lim, (c.def_ w).ty.range = some lim) :
    c.emptyView (some w) here = false := by
  unfold Ctx.emptyView
  obtain ⟨lim, hl⟩ := hty
  cases hr : c.operandRaw (some w) here with
  | none => simp [Ctx.operandRaw, operandWith, hl] at hr
  | some r =>
    obtain ⟨n', lim', hRw, hrc, _, _⟩ := hop w r hw hr
    rw [hR] at hRw
    simp only [Option.some.injEq, Val.int.injEq] at hRw
    subst hRw
    show r.isEmpty = false
    cases he : r.isEmpty with
    | false => rfl
    | true =>
      simp only [Interval.isEmpty, decide_eq_true_eq] at he
      have := hrc.1; have := hrc.2; omega

theorem operand_some {c : Ctx} {o : Option Nat} {here : Nat} {I : Interval} (h : c.operand o here = some I) :
    ∃ w, o = some w := by
  cases o with
  | none => simp [Ctx.operand, Ctx.operandRaw, operandWith] at h
  | some w => exact ⟨w, rfl⟩

theorem mem_regOps_a {i : Inst} {w : Nat} (hnc : i.op ≠ .call) (h : i.operands.a = some w) : w ∈ regOps i := by
  unfold regOps
  have : (i.op == .call) = false := by simpa using hnc
  simp [this, h]

theorem mem_regOps_b {i : Inst} {w : Nat} (h : i.operands.b = some w) : w ∈ regOps i := by
  unfold regOps
  simp [h]

theorem operand_a {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {here : Nat} {X : Interval}
    (hnc : i.op ≠ .call) (hop : OperandSound c R here (· ∈ regOps i)) (hX : c.operand i.operands.a here = some X) :
    ∃ w n lim, i.operands.a = some w ∧ (readOps R args i).a = some (.int n) ∧ X.contains n ∧
      (c.def_ w).ty.range = some lim ∧ lim.contains n := by
  obtain ⟨w, hw⟩ := operand_some hX
  rw [hw] at hX
  obtain ⟨_, n, lim, hr, hc, hl, hlc⟩ := operand_eq_raw hop (mem_regOps_a hnc hw) hX
  refine ⟨w, n, lim, hw, ?_, hc, hl, hlc⟩
  have hcall : (i.op == .call) = false := by simpa using hnc
  simp only [readOps, Regs.read, hw, Option.bind_some, hr, hcall]
  simp

theorem operand_b {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {here : Nat} {X : Interval}
    (hop : OperandSound c R here (· ∈ regOps i)) (hX : c.operand i.operands.b here = some X) :
    ∃ w n lim, i.operands.b = some w ∧ (readOps R args i).b = some (.int n) ∧ X.contains n ∧
      (c.def_ w).ty.range = some lim ∧ lim.contains n := by
  obtain ⟨w, hw⟩ := operand_some hX
  rw [hw] at hX
  obtain ⟨_, n, lim, hr, hc, hl, hlc⟩ := operand_eq_raw hop (mem_regOps_b hw) hX
  refine ⟨w, n, lim, hw, ?_, hc, hl, hlc⟩
  simp only [readOps, Regs.read, hw, Option.bind_some, hr]

/-- The operands of integer arithmetic have the instruction's type. -/
def OpTyped (c : Ctx) (i : Inst) : Prop :=
  match i.op with
  | .add | .sub | .mul | .saturatingAdd | .floorDiv | .div | .floorRem | .rem | .bitXor =>
    (∃ w, i.operands.a = some w ∧ (c.def_ w).ty = i.ty) ∧ (∃ w, i.operands.b = some w ∧ (c.def_ w).ty = i.ty)
  | .neg | .shiftLeft | .shiftRight => ∃ w, i.operands.a = some w ∧ (c.def_ w).ty = i.ty
  | _ => True

theorem arithmetic_contains {op : Op} {X Y : Interval} {nx ny : Int} (hx : X.contains nx) (hy : Y.contains ny) :
    (arithmetic op X Y).contains (match op with | .add => nx + ny | .sub => nx - ny | _ => nx * ny) := by
  obtain ⟨hx1, hx2⟩ := hx
  obtain ⟨hy1, hy2⟩ := hy
  cases op <;> simp only [arithmetic, Interval.contains]
  all_goals first
    | omega
    | exact mul_between hx1 hx2 hy1 hy2

theorem within_iff {a b : Interval} : a.within b = true ↔ a.hi < a.lo ∨ (b.lo ≤ a.lo ∧ a.hi ≤ b.hi) := by
  simp [Interval.within, Interval.isEmpty]

theorem within_contains {a b : Interval} {n : Int} (h : a.within b = true) (hn : a.contains n) : b.contains n := by
  rw [within_iff] at h
  rcases h with h | h
  · have := hn.1; have := hn.2; omega
  · exact ⟨by have := hn.1; omega, by have := hn.2; omega⟩

theorem meet_contains {a b : Interval} {n : Int} (ha : a.contains n) (hb : b.contains n) : (a.meet b).contains n := by
  obtain ⟨a1, a2⟩ := ha
  obtain ⟨b1, b2⟩ := hb
  exact ⟨by simp only [Interval.meet]; omega, by simp only [Interval.meet]; omega⟩


theorem arith_tail {i : Inst} {limits e : Interval} {nv r : Int} (hlim : i.ty.range = some limits)
    (hvl : limits.contains nv) (hr : e.contains r) (h : Res.ofInt i.ty i.check r = .val (.int nv)) :
    (if e.within limits then ({ range := e, assumed := false } : Derived)
     else { range := if i.check == .none then limits else e.meet limits, assumed := false }).range.contains nv := by
  rcases ofInt_val hlim h with ⟨hin, hnv⟩ | ⟨hout, hck, hnv⟩
  · cases hnv
    by_cases hw : e.within limits = true
    · simp only [hw, ite_true]; exact hr
    · simp only [hw, ite_false]
      by_cases hck : i.check == Check.none
      · simp only [hck, ite_true]; exact hvl
      · simp only [hck, ite_false]; exact meet_contains hr hin
  · by_cases hw : e.within limits = true
    · exact absurd (within_contains hw hr) hout
    · simp only [hw, ite_false]
      have : (i.check == Check.none) = true := by simp [hck]
      simp only [this, ite_true]; exact hvl

theorem decideCmp_sound {p : Pred} {X Y : Interval} {nx ny : Int} {b : Bool} (h : decideCmp p X Y = some b)
    (hX : X.contains nx) (hY : Y.contains ny) : predEval p nx ny = b := by
  obtain ⟨hx1, hx2⟩ := hX
  obtain ⟨hy1, hy2⟩ := hY
  cases p <;> simp only [decideCmp, predEval] at h ⊢
  all_goals (repeat' split at h) <;> simp_all <;> first | omega | skip

theorem compare_sound {c : Ctx} {i : Inst} {here : Nat} {X Y : Interval} {nx ny nv : Int} {p : Pred}
    (hx : c.operand i.operands.a here = some X) (hy : c.operand i.operands.b here = some Y)
    (hq : Pred.ofImm i.imm = some p) (hX : X.contains nx) (hY : Y.contains ny)
    (hnv : nv = if predEval p nx ny = true then 1 else 0) : (c.compare i here).contains nv := by
  simp only [Ctx.compare, hx, hy, hq]
  cases hd : decideCmp p X Y with
  | none =>
    show (0 : Int) ≤ nv ∧ nv ≤ 1
    split at hnv <;> omega
  | some b =>
    have := decideCmp_sound hd hX hY
    rw [this] at hnv
    cases b <;> simp at hnv
    · show (0 : Int) ≤ nv ∧ nv ≤ 0
      omega
    · show (1 : Int) ≤ nv ∧ nv ≤ 1
      omega

theorem typed_lim {c : Ctx} {i : Inst} {limits limA : Interval} {wa : Nat} {o : Option Nat}
    (ht : ∃ w, o = some w ∧ (c.def_ w).ty = i.ty) (hw : o = some wa) (hlA : (c.def_ wa).ty.range = some limA)
    (hlim : i.ty.range = some limits) : limA = limits := by
  obtain ⟨w, hw', hwt⟩ := ht
  rw [hw] at hw'
  cases hw'
  rw [hwt, hlim] at hlA
  cases hlA
  rfl

theorem divLike_tail {i : Inst} {limits X Y : Interval} {nx ny r nv : Int}
    (hlim : i.ty.range = some limits) (hlnp : limits.lo ≤ 0) (hnx : limits.contains nx) (hXc : X.contains nx)
    (hYc : Y.contains ny) (hXl : 0 ≤ X.lo) (hYl : 0 < Y.lo) (hr : r = nx / ny)
    (h : Res.ofInt i.ty i.check r = .val (.int nv)) :
    ({ lo := X.lo / Y.hi, hi := X.hi / Y.lo } : Interval).contains nv := by
  obtain ⟨hx1, hx2⟩ := hXc
  obtain ⟨hy1, hy2⟩ := hYc
  have hrng := div_range (xl := X.lo) (xh := X.hi) (dl := Y.lo) (dh := Y.hi) hXl hYl hx1 hx2 hy1 hy2
  rw [← hr] at hrng
  rcases ofInt_val hlim h with ⟨_, hnv⟩ | ⟨hout, _, _⟩
  · simp only [Val.int.injEq] at hnv
    subst hnv
    exact hrng
  · exfalso
    apply hout
    have h0 : 0 ≤ r := by rw [hr]; exact Int.ediv_nonneg (by omega) (by omega)
    have h1 : r ≤ nx := by rw [hr]; exact Int.ediv_le_self _ (by omega)
    exact ⟨by omega, by have := hnx.2; omega⟩

theorem lt_pow_bitLength (n : Nat) : n < 2 ^ bitLength n := by
  unfold bitLength
  split
  · rename_i h; subst h; simp
  · exact Nat.lt_log2_self

theorem derive_sound {c : Ctx} {R : Regs} {args : List Val} {i : Inst} {ch v : Val} {limits : Interval} {here : Nat}
    (hop : OperandSound c R here (· ∈ regOps i)) (hty : OpTyped c i)
    (hdef : (c.def_ i.value).inst = some i ∧ (c.def_ i.value).ty = i.ty)
    (hlim : i.ty.range = some limits) (hev : evalInst R args i ch = .val v) (hvt : ValTy i.ty v)
    (hal : Allowed i v) (hna : (c.deriveRule i limits here).assumed = false)
    (hp : i.op ≠ .param) (hl : i.op ≠ .listLen) (hg1 : i.op ≠ .listGet) (hg2 : i.op ≠ .arrayGet)
    (hc : i.op ≠ .call) :
    ∃ n, v = .int n ∧ (c.deriveRule i limits here).range.contains n := by
  obtain ⟨nv, hv, hvl⟩ : ∃ n, v = .int n ∧ limits.contains n := by
    have := hvt
    unfold ValTy at this
    rw [hlim] at this
    obtain ⟨n, h1, h2, h3⟩ := this
    exact ⟨n, h1, h2, h3⟩
  refine ⟨nv, hv, ?_⟩
  subst hv
  unfold evalInst evalOps at hev
  unfold OpTyped at hty
  cases hopc : i.op
  case iconst =>
    simp only [Ctx.deriveRule, hopc]
    simp only [hopc] at hev
    cases hev
    simp only [Interval.point, Interval.contains, constantOf, hdef.1, hdef.2]
    omega
  case add =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => simp only [hx]; exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => simp only [hx, hy]; exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        simp only [hx, hy]
        exact arith_tail hlim hvl (arithmetic_contains (op := .add) hXc hYc) hev
  case sub =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        exact arith_tail hlim hvl (arithmetic_contains (op := .sub) hXc hYc) hev
  case mul =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        exact arith_tail hlim hvl (arithmetic_contains (op := .mul) hXc hYc) hev
  case saturatingAdd =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?, hlim] at hev
        cases hev
        obtain ⟨hx1, hx2⟩ := hXc
        obtain ⟨hy1, hy2⟩ := hYc
        simp only [Interval.contains]
        constructor <;> omega
  case cmp =>
    simp only [Ctx.deriveRule, hopc]
    have h01 : nv = 0 ∨ nv = 1 := by
      simp only [hopc] at hev
      split at hev
      · rename_i p nx ny hp hx hy
        cases hev
        split <;> simp
      · cases hev
    cases hx : c.operand i.operands.a here with
    | none =>
      simp only [Ctx.compare, hx]; show (0 : Int) ≤ nv ∧ nv ≤ 1; omega
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none =>
        simp only [Ctx.compare, hx, hy]; show (0 : Int) ≤ nv ∧ nv ≤ 1; omega
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        cases hq : Pred.ofImm i.imm with
        | none => rw [hq] at hev; cases hev
        | some p =>
          rw [hq] at hev
          simp only [Res.val.injEq, Val.int.injEq] at hev
          exact compare_sound hx hy hq hXc hYc hev.symm
  case not =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
      simp only [hopc, hra, Option.bind_some, Val.int?] at hev
      simp only [Res.val.injEq, Val.int.injEq] at hev
      subst hev
      obtain ⟨hx1, hx2⟩ := hXc
      show 1 - X.hi ≤ 1 - nx ∧ 1 - nx ≤ 1 - X.lo
      omega
  case strLen =>
    simp only [Ctx.deriveRule, hopc]
    have := hal
    simp only [Allowed, hopc, Val.int.injEq] at this
    obtain ⟨n, hn, h1, h2⟩ := this
    subst hn
    exact ⟨h1, h2⟩
  case dictEntries =>
    simp only [Ctx.deriveRule, hopc]
    have := hal
    simp only [Allowed, hopc, Val.int.injEq] at this
    obtain ⟨n, hn, h1, h2⟩ := this
    subst hn
    exact ⟨h1, h2⟩
  case shiftRight =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        split at hev
        · rename_i hcnt
          simp only [Res.val.injEq, Val.int.injEq] at hev
          subst hev
          by_cases hc2 : Y.lo < 0 ∨ ↑i.ty.bits ≤ Y.hi
          · simp only [hc2, ite_true]; exact hvl
          · simp only [hc2, ite_false]
            have hc3 : 0 ≤ Y.lo := by omega
            have hc4 : Y.hi < ↑i.ty.bits := by omega
            obtain ⟨hy1, hy2⟩ := hYc
            have := shr_range (xl := X.lo) (xh := X.hi) (x := nx) (lo := Y.lo.toNat) (hi := Y.hi.toNat)
              (s := ny.toNat) hXc.1 hXc.2 (by omega) (by omega)
            exact this
        · unfold failWith at hev
          cases hck : i.check <;> simp only [hck] at hev <;> cases hev
  case floorDiv =>
    simp only [Ctx.deriveRule, hopc]
    simp only [hopc] at hty
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        have hAL := typed_lim hty.1 hwa hlA hlim
        subst hAL
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        split at hev
        · unfold failWith at hev
          cases hck : i.check <;> simp only [hck] at hev <;> cases hev
        · by_cases hcond : Y.lo ≤ 0 ∨ X.lo < 0
          · simp only [hcond, ite_true]; exact hvl
          · simp only [hcond, ite_false]
            have hXl : 0 ≤ X.lo := by omega
            have hYl : 0 < Y.lo := by omega
            rw [Int.fdiv_eq_ediv_of_nonneg nx (by have := hYc.1; omega)] at hev
            exact divLike_tail hlim (range_lo_nonpos hlim) hlcA hXc hYc hXl hYl rfl hev
  case div =>
    simp only [Ctx.deriveRule, hopc]
    simp only [hopc] at hty
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        have hAL := typed_lim hty.1 hwa hlA hlim
        subst hAL
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        split at hev
        · unfold failWith at hev
          cases hck : i.check <;> simp only [hck] at hev <;> cases hev
        · by_cases hcond : Y.lo ≤ 0 ∨ X.lo < 0
          · simp only [hcond, ite_true]; exact hvl
          · simp only [hcond, ite_false]
            have hXl : 0 ≤ X.lo := by omega
            have hYl : 0 < Y.lo := by omega
            rw [Int.tdiv_eq_ediv_of_nonneg (by have := hXc.1; omega)] at hev
            exact divLike_tail hlim (range_lo_nonpos hlim) hlcA hXc hYc hXl hYl rfl hev
  case floorRem =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        split at hev
        · unfold failWith at hev
          cases hck : i.check <;> simp only [hck] at hev <;> cases hev
        · simp only [Res.val.injEq, Val.int.injEq] at hev
          subst hev
          by_cases hcond : Y.lo ≤ 0
          · simp only [hcond, ite_true]; exact hvl
          · simp only [hcond, ite_false]
            obtain ⟨hy1, hy2⟩ := hYc
            have hny : 0 ≤ ny := by omega
            rw [Int.fmod_eq_emod_of_nonneg nx hny]
            by_cases hc2 : X.lo ≥ 0 ∧ X.hi < Y.lo
            · simp only [hc2, and_self, ite_true]
              rw [Int.emod_eq_of_lt (by have := hXc.1; omega) (by have := hXc.2; omega)]
              exact hXc
            · simp only [hc2, ite_false]
              have h1 := Int.emod_nonneg nx (show ny ≠ 0 by omega)
              have h2 := Int.emod_lt_of_pos nx (show 0 < ny by omega)
              show 0 ≤ nx % ny ∧ nx % ny ≤ Y.hi - 1
              omega
  case rem =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        split at hev
        · unfold failWith at hev
          cases hck : i.check <;> simp only [hck] at hev <;> cases hev
        · simp only [Res.val.injEq, Val.int.injEq] at hev
          subst hev
          by_cases hcond : Y.lo ≤ 0 ∨ X.lo < 0
          · simp only [hcond, ite_true]; exact hvl
          · simp only [hcond, ite_false]
            obtain ⟨hy1, hy2⟩ := hYc
            obtain ⟨hx1, hx2⟩ := hXc
            have hnx : 0 ≤ nx := by omega
            rw [Int.tmod_eq_emod_of_nonneg hnx]
            have := emod_range hnx (show 0 < ny by omega)
            show 0 ≤ nx % ny ∧ nx % ny ≤ min X.hi (Y.hi - 1)
            omega
  case bitXor =>
    simp only [Ctx.deriveRule, hopc]
    simp only [hopc] at hty
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      cases hy : c.operand i.operands.b here with
      | none => exact hvl
      | some Y =>
        obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
        obtain ⟨wb, ny, limB, hwb, hrb, hYc, hlB, hlcB⟩ := operand_b (args := args) hop hy
        have hAL := typed_lim hty.1 hwa hlA hlim
        have hBL := typed_lim hty.2 hwb hlB hlim
        subst hAL
        subst hBL
        simp only [hopc, hra, hrb, Option.bind_some, Val.int?] at hev
        simp only [Res.val.injEq, Val.int.injEq] at hev
        subst hev
        by_cases hcond : X.lo < 0 ∨ Y.lo < 0
        · simp only [hcond, ite_true]; exact hvl
        · simp only [hcond, ite_false]
          obtain ⟨hx1, hx2⟩ := hXc
          obtain ⟨hy1, hy2⟩ := hYc
          have hnx : 0 ≤ nx := by omega
          have hny : 0 ≤ ny := by omega
          have hk := lt_pow_bitLength (max X.hi Y.hi).toNat
          have hxk : nx < 2 ^ bitLength (max X.hi Y.hi).toNat := by
            have : nx ≤ (max X.hi Y.hi) := by omega
            have h2 : (nx.toNat : Int) ≤ ((max X.hi Y.hi).toNat : Int) := by omega
            have h3 : ((max X.hi Y.hi).toNat : Int) < ((2 ^ bitLength (max X.hi Y.hi).toNat : Nat) : Int) := by
              exact_mod_cast hk
            push_cast at h3
            omega
          have hyk : ny < 2 ^ bitLength (max X.hi Y.hi).toNat := by
            have : ny ≤ (max X.hi Y.hi) := by omega
            have h2 : (ny.toNat : Int) ≤ ((max X.hi Y.hi).toNat : Int) := by omega
            have h3 : ((max X.hi Y.hi).toNat : Int) < ((2 ^ bitLength (max X.hi Y.hi).toNat : Nat) : Int) := by
              exact_mod_cast hk
            push_cast at h3
            omega
          have hx := xorVal_range hlim hlcA hlcB hnx hny hxk hyk
          apply meet_contains _ hvl
          show 0 ≤ xorVal i.ty nx ny ∧ xorVal i.ty nx ny ≤
            (if bitLength (max X.hi Y.hi).toNat = 0 then 0 else 2 ^ bitLength (max X.hi Y.hi).toNat - 1)
          split
          · rename_i h0
            rw [h0] at hx
            simp at hx
            omega
          · omega
  case convert =>
    simp only [Ctx.deriveRule, hopc]
    cases hx : c.operand i.operands.a here with
    | none => exact hvl
    | some X =>
      obtain ⟨wa, nx, limA, hwa, hra, hXc, hlA, hlcA⟩ := operand_a (args := args) hc hop hx
      simp only [hopc, hra, Option.bind_some, Val.int?] at hev
      by_cases hcond : (i.check == Check.none) = true ∧ (!X.within limits) = true
      · simp only [hcond, and_self, ite_true]; exact hvl
      · simp only [hcond, ite_false]
        rcases ofInt_val hlim hev with ⟨hin, hnv⟩ | ⟨hout, hck, _⟩
        · simp only [Val.int.injEq] at hnv
          subst hnv
          exact meet_contains hXc hin
        · exfalso
          apply hcond
          refine ⟨by simp [hck], ?_⟩
          by_cases hw : X.within limits = true
          · exact absurd (within_contains hw hXc) hout
          · simpa using hw
  all_goals first
    | (exfalso; exact hp hopc)
    | (exfalso; exact hl hopc)
    | (exfalso; exact hg1 hopc)
    | (exfalso; exact hg2 hopc)
    | (exfalso; exact hc hopc)
    | (exfalso; simp [Ctx.deriveRule, hopc] at hna)

end Facts
