import Facts.RowFacts
import Arith.DivProven
import Arith.Shift
import Arith.Convert

/-!
# The emitter's lowering computes what the machine computes

Package C8 proves that the instruction sequence the emitter prints for an integer operation equals the operation's
specification, and, for the `proven` forms (`check = proven`), does so **under a fact as a hypothesis**: the divisor
is positive and the dividend non-negative; the shift count is in `[0, bits)`; the value is representable; the
sum does not overflow. The fact certificate's theorem delivers exactly those hypotheses: `RowFacts` (`RowFacts.lean`).
This file instantiates C8's theorems with them, so that for a `proven` instruction an honest execution reaches,
the emitted sequence's result is the machine's result.
-/

set_option linter.unusedSimpArgs false

namespace Facts

/-- The `DivKind` of an operation. -/
def divKindOf : Op → Option Arith.DivKind
  | .div => some .div | .rem => some .rem | .floorDiv => some .floorDiv | .floorRem => some .floorRem | _ => none

theorem divRes_inRange {n : Nat} (s : Bool) (k : Arith.DivKind) {x y : Int} (hx : Arith.inRange s n x)
    (hx0 : 0 ≤ x) (hy0 : 0 < y) : Arith.inRange s n (Arith.divRes k x y) := by
  have hlo := Arith.lo_nonpos s n
  obtain ⟨h1, h2⟩ := hx
  have e1 : 0 ≤ x / y := Int.ediv_nonneg hx0 (by omega)
  have e2 : x / y ≤ x := Int.ediv_le_self _ hx0
  have e3 : 0 ≤ x % y := Int.emod_nonneg x (by omega)
  have e4 : x % y ≤ x := by
    rw [Int.emod_def]
    have : 0 ≤ y * (x / y) := Int.mul_nonneg (by omega) e1
    omega
  cases k <;>
    simp only [Arith.divRes, Int.tdiv_eq_ediv_of_nonneg hx0, Int.fdiv_eq_ediv_of_nonneg x (Int.le_of_lt hy0),
      Int.tmod_eq_emod_of_nonneg hx0, Int.fmod_eq_emod_of_nonneg x (Int.le_of_lt hy0)] <;>
    exact ⟨by omega, by omega⟩

theorem connect_div {n : Nat} (hn : 0 < n) (s : Bool) (k : Arith.DivKind) {x y : Int}
    (hx : Arith.inRange s n x) (hy : Arith.inRange s n y) (hx0 : 0 ≤ x) (hy0 : 0 < y) :
    Arith.divProven Arith.Isa.exec n k.isRem (BitVec.ofInt n x) (BitVec.ofInt n y) =
      .ok (BitVec.ofInt n (Arith.divRes k x y)) := by
  have h1 : Arith.ival s (BitVec.ofInt n x) = x := Arith.ival_ofInt s hn hx
  have h2 : Arith.ival s (BitVec.ofInt n y) = y := Arith.ival_ofInt s hn hy
  rw [Arith.divProven_correct hn s k _ _ (by rw [h1]; exact hx0) (by rw [h2]; exact hy0)]
  unfold Arith.specDiv
  rw [h1, h2]
  have hne : y ≠ 0 := by omega
  simp only [hne, ite_false]
  simp [divRes_inRange s k hx hx0 hy0]

theorem ival_ofInt_wrap {t : Ty} {lim : Interval} (h : t.range = some lim) (v : Int) :
    Arith.ival t.signed (BitVec.ofInt t.bits v) = wrapTo t v := by
  obtain ⟨hn, h1, h2⟩ := range_eq_arith h
  have hspan := pow_half hn
  have hH : (0 : Int) < 2 ^ (t.bits - 1) := by
    have := Nat.two_pow_pos (t.bits - 1)
    exact_mod_cast this
  have hM : ((2 ^ t.bits : Nat) : Int) = 2 ^ t.bits := by push_cast; rfl
  unfold wrapTo
  rw [h]
  simp only []
  rw [h1, h2]
  unfold Arith.lo Arith.hi
  cases hs : t.signed
  · simp only [Arith.ival, Bool.false_eq_true, ite_false, BitVec.toNat_ofInt]
    have hnn : 0 ≤ v % ((2 ^ t.bits : Nat) : Int) := Int.emod_nonneg v (by rw [hM]; omega)
    rw [Int.toNat_of_nonneg hnn]
    have : (2 : Int) ^ t.bits - 1 - 0 + 1 = 2 ^ t.bits := by omega
    rw [this]
    push_cast
    simp
  · simp only [Arith.ival, ite_true, BitVec.toInt_ofInt]
    rw [Int.bmod_def, hM]
    have hq : (2 : Int) ^ (t.bits - 1) - 1 - -2 ^ (t.bits - 1) + 1 = 2 ^ t.bits := by omega
    rw [hq]
    have hr1 := Int.emod_nonneg v (show (2 : Int) ^ t.bits ≠ 0 by omega)
    have hr2 := Int.emod_lt_of_pos v (show (0 : Int) < 2 ^ t.bits by omega)
    have hadd : (v - -(2 : Int) ^ (t.bits - 1)) % 2 ^ t.bits = (v % 2 ^ t.bits + 2 ^ (t.bits - 1)) % 2 ^ t.bits := by
      have e1 : v - -(2 : Int) ^ (t.bits - 1) = v + 2 ^ (t.bits - 1) := by omega
      rw [e1, Int.add_emod]
      have : (2 : Int) ^ (t.bits - 1) % 2 ^ t.bits = 2 ^ (t.bits - 1) := Int.emod_eq_of_lt (by omega) (by omega)
      rw [this]
    rw [hadd]
    have hcase : (v % 2 ^ t.bits < (2 ^ t.bits + 1) / 2) ∨ ¬ (v % 2 ^ t.bits < (2 ^ t.bits + 1) / 2) := by omega
    rcases hcase with hc | hc
    · have e2 : (v % 2 ^ t.bits + 2 ^ (t.bits - 1)) % 2 ^ t.bits = v % 2 ^ t.bits + 2 ^ (t.bits - 1) :=
        Int.emod_eq_of_lt (by omega) (by omega)
      rw [e2]
      simp only [hc, ite_true]
      omega
    · have e2 : (v % 2 ^ t.bits + 2 ^ (t.bits - 1)) % 2 ^ t.bits = v % 2 ^ t.bits + 2 ^ (t.bits - 1) - 2 ^ t.bits := by
        have e3 : v % 2 ^ t.bits + 2 ^ (t.bits - 1) - 2 ^ t.bits + 2 ^ t.bits * 1 = v % 2 ^ t.bits + 2 ^ (t.bits - 1) := by omega
        calc (v % 2 ^ t.bits + 2 ^ (t.bits - 1)) % 2 ^ t.bits
            = (v % 2 ^ t.bits + 2 ^ (t.bits - 1) - 2 ^ t.bits + 2 ^ t.bits * 1) % 2 ^ t.bits := by rw [e3]
          _ = (v % 2 ^ t.bits + 2 ^ (t.bits - 1) - 2 ^ t.bits) % 2 ^ t.bits := Int.add_mul_emod_self_left _ _ _
          _ = v % 2 ^ t.bits + 2 ^ (t.bits - 1) - 2 ^ t.bits := Int.emod_eq_of_lt (by omega) (by omega)
      rw [e2]
      simp only [hc, ite_false]
      omega


theorem connect_shift {n : Nat} (hn : 0 < n) (left s : Bool) (kind : Arith.Trap) {x c : Int}
    (hx : Arith.inRange s n x) (hc : Arith.inRange s n c) (h0 : 0 ≤ c) (h1 : c < n) :
    Arith.shift Arith.Isa.exec n left s false kind (BitVec.ofInt n x) (BitVec.ofInt n c) =
      .ok (BitVec.ofInt n (if left then x * 2 ^ c.toNat else x / 2 ^ c.toNat)) := by
  have hx' : Arith.ival s (BitVec.ofInt n x) = x := Arith.ival_ofInt s hn hx
  have hc' : Arith.ival s (BitVec.ofInt n c) = c := Arith.ival_ofInt s hn hc
  rw [Arith.shift_correct hn left s false kind _ _ (by intro _; rw [hc']; omega)]
  unfold Arith.specShift
  rw [hx', hc']
  have : ¬ (c < 0 ∨ (n : Int) ≤ c) := by omega
  simp only [this, ite_false]
  cases left <;> simp

theorem connect_convert {wf wt : Nat} (hwf : 0 < wf) (sf st : Bool) (kind : Arith.Trap) {x : Int}
    (hx : Arith.inRange sf wf x) (h : Arith.inRange st wt x) :
    Arith.convert Arith.Isa.exec sf st wf wt false kind (BitVec.ofInt wf x) = .ok (BitVec.ofInt wt x) := by
  have hx' : Arith.ival sf (BitVec.ofInt wf x) = x := Arith.ival_ofInt sf hwf hx
  rw [Arith.convert_proven hwf sf st kind _ (by rw [hx']; exact h)]
  unfold Arith.specConvert
  rw [hx']
  simp [h]

/-- A proven `add` (`nsw` for a signed type, `nuw` for an unsigned one) whose exact sum is in range is not poison. -/
theorem connect_add {n : Nat} (hn : 0 < n) (s : Bool) {x y : Int} (hx : Arith.inRange s n x)
    (hy : Arith.inRange s n y) (hr : Arith.inRange s n (x + y)) :
    Arith.addPoison s (!s) (BitVec.ofInt n x) (BitVec.ofInt n y) = false := by
  have hx' := Arith.ival_ofInt s hn hx
  have hy' := Arith.ival_ofInt s hn hy
  cases s
  · simp only [Arith.ival, Bool.false_eq_true, ite_false] at hx' hy'
    have hr' := hr
    simp only [Arith.inRange, Arith.lo, Arith.hi, Bool.false_eq_true, ite_false] at hr'
    have hp : ((2 ^ n : Nat) : Int) = (2 : Int) ^ n := by push_cast; rfl
    unfold Arith.addPoison
    simp only [Bool.not_false, Bool.false_and, Bool.false_or, Bool.true_and, decide_eq_false_iff_not]
    omega
  · simp only [Arith.ival, ite_true] at hx' hy'
    unfold Arith.addPoison
    simp [hx', hy', hr]

theorem connect_sub {n : Nat} (hn : 0 < n) (s : Bool) {x y : Int} (hx : Arith.inRange s n x)
    (hy : Arith.inRange s n y) (hr : Arith.inRange s n (x - y)) :
    Arith.subPoison s (!s) (BitVec.ofInt n x) (BitVec.ofInt n y) = false := by
  have hx' := Arith.ival_ofInt s hn hx
  have hy' := Arith.ival_ofInt s hn hy
  cases s
  · simp only [Arith.ival, Bool.false_eq_true, ite_false] at hx' hy'
    have hr' := hr
    simp only [Arith.inRange, Arith.lo, Arith.hi, Bool.false_eq_true, ite_false] at hr'
    unfold Arith.subPoison
    simp only [Bool.not_false, Bool.false_and, Bool.false_or, Bool.true_and, decide_eq_false_iff_not]
    omega
  · simp only [Arith.ival, ite_true] at hx' hy'
    unfold Arith.subPoison
    simp [hx', hy', hr]

theorem connect_mul {n : Nat} (hn : 0 < n) (s : Bool) {x y : Int} (hx : Arith.inRange s n x)
    (hy : Arith.inRange s n y) (hr : Arith.inRange s n (x * y)) :
    Arith.mulPoison s (!s) (BitVec.ofInt n x) (BitVec.ofInt n y) = false := by
  have hx' := Arith.ival_ofInt s hn hx
  have hy' := Arith.ival_ofInt s hn hy
  cases s
  · simp only [Arith.ival, Bool.false_eq_true, ite_false] at hx' hy'
    have hr' := hr
    simp only [Arith.inRange, Arith.lo, Arith.hi, Bool.false_eq_true, ite_false] at hr'
    have hp : ((2 ^ n : Nat) : Int) = (2 : Int) ^ n := by push_cast; rfl
    have hx0 : 0 ≤ x := hx.1
    have hy0 : 0 ≤ y := hy.1
    have ex : (BitVec.ofInt n x).toNat = x.toNat := by omega
    have ey : (BitVec.ofInt n y).toNat = y.toNat := by omega
    unfold Arith.mulPoison
    simp only [Bool.not_false, Bool.false_and, Bool.false_or, Bool.true_and, decide_eq_false_iff_not, ex, ey]
    have hprod : ((x.toNat * y.toNat : Nat) : Int) = x * y := by
      push_cast; rw [Int.toNat_of_nonneg hx0, Int.toNat_of_nonneg hy0]
    have hlt : ((x.toNat * y.toNat : Nat) : Int) < ((2 ^ n : Nat) : Int) := by rw [hprod, hp]; omega
    have : x.toNat * y.toNat < 2 ^ n := by exact_mod_cast hlt
    omega
  · simp only [Arith.ival, ite_true] at hx' hy'
    unfold Arith.mulPoison
    simp [hx', hy', hr]


/-! ### At a frame about to run a proven instruction -/

theorem ofInt_in {t : Ty} {lim : Interval} (ck : Check) {r : Int} (hl : t.range = some lim) (h : lim.contains r) :
    Res.ofInt t ck r = .val (.int r) := by
  unfold Res.ofInt
  rw [hl]
  simp only [h.1, h.2, and_self, ite_true]

theorem inRange_of_contains {t : Ty} {lim : Interval} {n : Int} (h : t.range = some lim) (hn : lim.contains n) :
    Arith.inRange t.signed t.bits n := inRange_of_range h hn

/-- A proven division, remainder, floor division or floor remainder: the emitted `udiv`/`urem` gives the result the
machine computes. -/
theorem lower_div {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) (hout : c.provenOut i fr.blk = .proven)
    {k : Arith.DivKind} (hdk : divKindOf i.op = some k) {nx ny : Int}
    (hx : (fr.regs.read i.operands.a).bind Val.int? = some nx)
    (hy : (fr.regs.read i.operands.b).bind Val.int? = some ny) (ch : Val) :
    Arith.divProven Arith.Isa.exec i.ty.bits k.isRem (BitVec.ofInt i.ty.bits nx) (BitVec.ofInt i.ty.bits ny) =
        .ok (BitVec.ofInt i.ty.bits (Arith.divRes k nx ny)) ∧
      evalInst fr.regs fr.args i ch = .val (.int (Arith.divRes k nx ny)) := by
  have hrf := proven_row_facts hc hw hff hinv hadm hb hk hout
  have hty := hc.opTyped hb (List.mem_of_getElem? hk)
  have hop4 : i.op = .div ∨ i.op = .rem ∨ i.op = .floorDiv ∨ i.op = .floorRem := by
    cases hopc : i.op <;> simp [divKindOf, hopc] at hdk ⊢
  have hnc : i.op ≠ .call := by rcases hop4 with h | h | h | h <;> rw [h] <;> intro e <;> cases e
  obtain ⟨wa, hwa, hRa⟩ := read_int hx
  obtain ⟨wb, hwb, hRb⟩ := read_int hy
  have hxy : 0 ≤ nx ∧ 0 < ny := by
    rcases hop4 with h | h | h | h <;> (simp only [RowFacts, h] at hrf; exact hrf nx ny hx hy)
  have htyab : (∃ w, i.operands.a = some w ∧ (c.def_ w).ty = i.ty) ∧ (∃ w, i.operands.b = some w ∧ (c.def_ w).ty = i.ty) := by
    rcases hop4 with h | h | h | h <;> (simp only [OpTyped, h] at hty; exact hty)
  have hlim : ∃ lim, i.ty.range = some lim ∧ lim.contains nx := by
    obtain ⟨w, hw', htw⟩ := htyab.1
    rw [hwa] at hw'
    cases hw'
    obtain ⟨lim', hl', hc'⟩ := vt_int hinv _ nx hRa
    rw [htw] at hl'
    exact ⟨lim', hl', hc'⟩
  have hlimy : ∃ lim, i.ty.range = some lim ∧ lim.contains ny := by
    obtain ⟨w, hw', htw⟩ := htyab.2
    rw [hwb] at hw'
    cases hw'
    obtain ⟨lim', hl', hc'⟩ := vt_int hinv _ ny hRb
    rw [htw] at hl'
    exact ⟨lim', hl', hc'⟩
  obtain ⟨lim, hl, hnx⟩ := hlim
  obtain ⟨lim2, hl2, hny⟩ := hlimy
  rw [hl] at hl2
  cases hl2
  obtain ⟨hn, _, _⟩ := range_eq_arith hl
  have hxr := inRange_of_range hl hnx
  have hyr := inRange_of_range hl hny
  refine ⟨connect_div hn _ k hxr hyr hxy.1 hxy.2, ?_⟩
  -- the machine
  have hres : lim.contains (Arith.divRes k nx ny) := by
    have hin := divRes_inRange i.ty.signed k hxr hxy.1 hxy.2
    obtain ⟨_, h1, h2⟩ := range_eq_arith hl
    exact ⟨by rw [h1]; exact hin.1, by rw [h2]; exact hin.2⟩
  have hne : ny ≠ 0 := by omega
  unfold evalInst evalOps
  rcases hop4 with h | h | h | h
  all_goals
    have hkk : divKindOf i.op = some k := hdk
    simp only [h, readOps_a_val hnc, readOps_b, hx, hy, hne, ite_false]
  · simp only [divKindOf, h, Option.some.injEq] at hkk
    subst hkk
    simp only [Arith.divRes] at hres ⊢
    rw [ofInt_in _ hl hres]
  · simp only [divKindOf, h, Option.some.injEq] at hkk
    subst hkk
    simp [Arith.divRes]
  · simp only [divKindOf, h, Option.some.injEq] at hkk
    subst hkk
    simp only [Arith.divRes] at hres ⊢
    rw [ofInt_in _ hl hres]
  · simp only [divKindOf, h, Option.some.injEq] at hkk
    subst hkk
    simp [Arith.divRes]


/-- A proven conversion to an integer type: the emitted bit movement gives the machine's value. The source operand
has its own type. -/
theorem lower_convert {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) (hout : c.provenOut i fr.blk = .proven)
    (hop : i.op = .convert) {lim : Interval} (hlim : i.ty.range = some lim) {nx : Int}
    (hx : (fr.regs.read i.operands.a).bind Val.int? = some nx) (ch : Val) (kind : Arith.Trap) :
    ∃ (wa : Nat) (lima : Interval), i.operands.a = some wa ∧ (c.def_ wa).ty.range = some lima ∧
      Arith.convert Arith.Isa.exec (c.def_ wa).ty.signed i.ty.signed (c.def_ wa).ty.bits i.ty.bits false kind
          (BitVec.ofInt (c.def_ wa).ty.bits nx) = .ok (BitVec.ofInt i.ty.bits nx) ∧
        evalInst fr.regs fr.args i ch = .val (.int nx) := by
  have hrf := proven_row_facts hc hw hff hinv hadm hb hk hout
  unfold RowFacts at hrf
  simp only [hop] at hrf
  have hnc : i.op ≠ .call := by rw [hop]; intro e; cases e
  obtain ⟨wa, hwa, hRa⟩ := read_int hx
  obtain ⟨lima, hla, hca⟩ := vt_int hinv wa nx hRa
  have hnl := hrf nx hx lim hlim
  obtain ⟨hwf, _, _⟩ := range_eq_arith hla
  refine ⟨wa, lima, hwa, hla, connect_convert hwf _ _ kind (inRange_of_range hla hca)
    (inRange_of_range hlim hnl), ?_⟩
  unfold evalInst evalOps
  simp only [hop, readOps_a_val hnc, hx]
  exact ofInt_in _ hlim hnl

/-- A proven addition, subtraction or multiplication: the emitted `nsw`/`nuw` operation is not poison. -/
theorem lower_arith {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) (hout : c.provenOut i fr.blk = .proven)
    {lim : Interval} (hlim : i.ty.range = some lim) {nx ny : Int}
    (hx : (fr.regs.read i.operands.a).bind Val.int? = some nx)
    (hy : (fr.regs.read i.operands.b).bind Val.int? = some ny) (ch : Val) :
    (i.op = .add → Arith.addPoison i.ty.signed (!i.ty.signed) (BitVec.ofInt i.ty.bits nx) (BitVec.ofInt i.ty.bits ny) = false ∧
        evalInst fr.regs fr.args i ch = .val (.int (nx + ny))) ∧
      (i.op = .sub → Arith.subPoison i.ty.signed (!i.ty.signed) (BitVec.ofInt i.ty.bits nx) (BitVec.ofInt i.ty.bits ny) = false ∧
        evalInst fr.regs fr.args i ch = .val (.int (nx - ny))) ∧
      (i.op = .mul → Arith.mulPoison i.ty.signed (!i.ty.signed) (BitVec.ofInt i.ty.bits nx) (BitVec.ofInt i.ty.bits ny) = false ∧
        evalInst fr.regs fr.args i ch = .val (.int (nx * ny))) := by
  have hrf := proven_row_facts hc hw hff hinv hadm hb hk hout
  have hty := hc.opTyped hb (List.mem_of_getElem? hk)
  unfold RowFacts at hrf
  unfold OpTyped at hty
  obtain ⟨wa, hwa, hRa⟩ := read_int hx
  obtain ⟨wb, hwb, hRb⟩ := read_int hy
  obtain ⟨hn, _, _⟩ := range_eq_arith hlim
  have hlx : ∀ w nz, fr.regs w = some (.int nz) → (c.def_ w).ty = i.ty → lim.contains nz := by
    intro w nz hR ht
    obtain ⟨lim', hl', hc'⟩ := vt_int hinv w nz hR
    rw [ht, hlim] at hl'
    cases hl'
    exact hc'
  refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩
  all_goals
    have hnc : i.op ≠ .call := by rw [h]; intro e; cases e
    simp only [h] at hrf hty
    obtain ⟨⟨w1, hw1, ht1⟩, ⟨w2, hw2, ht2⟩⟩ := hty
    rw [hwa] at hw1
    rw [hwb] at hw2
    cases hw1
    cases hw2
    have hnx := hlx wa nx hRa ht1
    have hny := hlx wb ny hRb ht2
    have hres := hrf nx ny hx hy lim hlim
    have hxr := inRange_of_range hlim hnx
    have hyr := inRange_of_range hlim hny
    have hrr := inRange_of_range hlim hres
  · refine ⟨connect_add hn _ hxr hyr hrr, ?_⟩
    unfold evalInst evalOps
    simp only [h, readOps_a_val hnc, readOps_b, hx, hy]
    rw [ofInt_in _ hlim hres]
  · refine ⟨connect_sub hn _ hxr hyr hrr, ?_⟩
    unfold evalInst evalOps
    simp only [h, readOps_a_val hnc, readOps_b, hx, hy]
    rw [ofInt_in _ hlim hres]
  · refine ⟨connect_mul hn _ hxr hyr hrr, ?_⟩
    unfold evalInst evalOps
    simp only [h, readOps_a_val hnc, readOps_b, hx, hy]
    rw [ofInt_in _ hlim hres]


theorem count_inRange {t : Ty} {lim : Interval} (h : t.range = some lim) {c : Int} (h0 : 0 ≤ c)
    (h1 : c < (t.bits : Int)) : Arith.inRange t.signed t.bits c := by
  cases t <;> simp [Ty.range, Ty.bits, Ty.signed] at h <;> subst h <;>
    simp only [Ty.bits, Ty.signed, Arith.inRange, Arith.lo, Arith.hi] at h1 ⊢ <;> simp <;> omega

/-- A proven shift: the emitted shift (no guard) gives the machine's value. -/
theorem lower_shift {c : Ctx} (hc : CtxOK c) (hw : SsaWf c) (hff : c.firstFault = none) {fr : Frame}
    (hinv : FrameInv c fr) (hadm : AdmFrame c fr.regs fr.blk) {b : Block} {i : Inst}
    (hb : c.f.blocks[fr.blk]? = some b) (hk : b.insts[fr.pc]? = some i) (hout : c.provenOut i fr.blk = .proven)
    (hop : i.op = .shiftLeft ∨ i.op = .shiftRight) {lim : Interval} (hlim : i.ty.range = some lim) {nx ny : Int}
    (hx : (fr.regs.read i.operands.a).bind Val.int? = some nx)
    (hy : (fr.regs.read i.operands.b).bind Val.int? = some ny) (ch : Val) (kind : Arith.Trap) :
    ∃ r, Arith.shift Arith.Isa.exec i.ty.bits (decide (i.op = .shiftLeft)) i.ty.signed false kind
        (BitVec.ofInt i.ty.bits nx) (BitVec.ofInt i.ty.bits ny) = .ok r ∧
      evalInst fr.regs fr.args i ch = .val (.int (Arith.ival i.ty.signed r)) := by
  have hrf := proven_row_facts hc hw hff hinv hadm hb hk hout
  have hty := hc.opTyped hb (List.mem_of_getElem? hk)
  unfold RowFacts at hrf
  unfold OpTyped at hty
  have hnc : i.op ≠ .call := by rcases hop with h | h <;> rw [h] <;> intro e <;> cases e
  have hcnt : 0 ≤ ny ∧ ny < (i.ty.bits : Int) := by
    rcases hop with h | h <;> (simp only [h] at hrf; exact hrf ny hy)
  obtain ⟨wa, hwa, hRa⟩ := read_int hx
  have hnx : lim.contains nx := by
    have htya : ∃ w, i.operands.a = some w ∧ (c.def_ w).ty = i.ty := by
      rcases hop with h | h <;> (simp only [h] at hty; exact hty)
    obtain ⟨w, hw', htw⟩ := htya
    rw [hwa] at hw'
    cases hw'
    obtain ⟨lim', hl', hc'⟩ := vt_int hinv _ nx hRa
    rw [htw, hlim] at hl'
    cases hl'
    exact hc'
  obtain ⟨hn, _, _⟩ := range_eq_arith hlim
  have hxr := inRange_of_range hlim hnx
  have hyr := count_inRange hlim hcnt.1 hcnt.2
  refine ⟨_, connect_shift hn (decide (i.op = .shiftLeft)) i.ty.signed kind hxr hyr hcnt.1 hcnt.2, ?_⟩
  rw [ival_ofInt_wrap hlim]
  unfold evalInst evalOps
  have hg : 0 ≤ ny ∧ ny < (i.ty.bits : Int) := hcnt
  rcases hop with h | h
  · simp only [h, readOps_a_val hnc, readOps_b, hx, hy, hg, and_self, ite_true, decide_true]
  · have hne : i.op ≠ .shiftLeft := by rw [h]; intro e; cases e
    have hd : decide (Op.shiftRight = Op.shiftLeft) = false := by decide
    simp only [h, readOps_a_val hnc, readOps_b, hx, hy, hg, and_self, ite_true, hd, Bool.false_eq_true, ite_false]
    have hdiv : nx >>> ny.toNat = nx / 2 ^ ny.toNat := by
      rw [Int.shiftRight_eq_div_pow]; push_cast; rfl
    rw [hdiv]
    have hlo := range_lo_nonpos hlim
    have hin : lim.contains (nx / 2 ^ ny.toNat) := by
      rw [← hdiv]
      by_cases hnn : 0 ≤ nx
      · have := shr_nonneg_step nx ny.toNat hnn
        exact ⟨by omega, by have := hnx.2; omega⟩
      · have := shr_neg_step nx ny.toNat (by omega)
        have hhi : 0 ≤ lim.hi := by
          obtain ⟨_, _, h2⟩ := range_eq_arith hlim
          rw [h2]; exact Arith.hi_nonneg _ hn
        exact ⟨by have := hnx.1; omega, by omega⟩
    rw [wrapTo_of_contains hlim hin]

end Facts
