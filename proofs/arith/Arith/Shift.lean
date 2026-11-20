import Arith.Spec
import Arith.BVFacts

/-!
# Checked shifts

`shift` (`emit_number.instruction`) compares the count with the width as an unsigned number, so
one test rejects a negative signed count as well as a count `>= n`, and then emits `shl`, `ashr`
or `lshr`. The theorems: the checked form is `specShift`; the unchecked forms (`check = proven`)
are `specShift` under the fact `0 <= count < n`, and by it `shl`/`ashr`/`lshr` never see an
out-of-range count (which LLVM defines as poison).
-/

namespace Arith

variable {n : Nat}

theorem n_le_two_pow_pred (hn : 0 < n) : n ≤ 2 ^ (n - 1) := by
  have := Nat.lt_two_pow_self (n := n - 1)
  omega

/-- The unsigned comparison `count >= n` is exactly "negative or at least `n`" for the signed
reading of the count, and "at least `n`" for the unsigned reading. -/
theorem bad_count_iff (hn : 0 < n) (s : Bool) (c : BitVec n) :
    (n ≤ c.toNat) ↔ (ival s c < 0 ∨ (n : Int) ≤ ival s c) := by
  have hp : (n : Int) ≤ 2 ^ (n - 1) := by exact_mod_cast n_le_two_pow_pred hn
  have hlt : (c.toNat : Int) < 2 ^ n := by exact_mod_cast c.isLt
  have h2 := two_pow_eq hn
  cases s
  · simp only [ival_false]; omega
  · simp only [ival_true]
    have e := BitVec.toInt_eq_msb_cond c
    by_cases hm : c.msb = true
    · simp only [hm, ↓reduceIte] at e
      have hge := BitVec.msb_eq_true_iff_two_mul_ge.1 hm
      have hge' : (2 : Int) * c.toNat ≥ 2 ^ n := by exact_mod_cast hge
      push_cast at e
      omega
    · simp only [hm, Bool.false_eq_true, ↓reduceIte] at e
      omega

theorem ofInt_two_pow (n k : Nat) : BitVec.ofInt n ((2 : Int) ^ k) = BitVec.twoPow n k := by
  apply BitVec.eq_of_toNat_eq
  rw [BitVec.toNat_ofInt, BitVec.toNat_twoPow]
  have : ((2 : Int) ^ k % ((2 ^ n : Nat) : Int)) = ((2 ^ k % 2 ^ n : Nat) : Int) := by
    push_cast; rfl
  rw [this]; exact Int.toNat_natCast _

theorem shl_eq_ofInt (s : Bool) (a : BitVec n) (k : Nat) :
    a <<< k = BitVec.ofInt n (ival s a * 2 ^ k) := by
  rw [BitVec.shiftLeft_eq_mul_twoPow, BitVec.ofInt_mul, ofInt_ival, ofInt_two_pow]

theorem lshr_eq_ofInt (a : BitVec n) (k : Nat) :
    a >>> k = BitVec.ofInt n (ival false a / 2 ^ k) := by
  apply BitVec.eq_of_toNat_eq
  have : (ival false a / 2 ^ k) = (((a.toNat >>> k) : Nat) : Int) := by
    rw [ival_false, Nat.shiftRight_eq_div_pow]; push_cast; rfl
  rw [this, BitVec.toNat_ushiftRight]
  exact (ofInt_ofNat_toNat (Nat.lt_of_le_of_lt (Nat.shiftRight_le _ _) a.isLt)).symm

theorem ashr_eq_ofInt (a : BitVec n) (k : Nat) :
    a.sshiftRight k = BitVec.ofInt n (ival true a / 2 ^ k) := by
  have := BitVec.ofInt_toInt (x := a.sshiftRight k)
  rw [BitVec.toInt_sshiftRight, Int.shiftRight_eq_div_pow] at this
  push_cast at this
  rw [← this, ival_true]

theorem uge_width (n : Nat) (b : BitVec n) :
    Pred.uge.eval b (BitVec.ofNat n n) = decide (n ≤ b.toNat) := by
  have h : n < 2 ^ n := Nat.lt_two_pow_self
  have e : ((BitVec.ofNat n n)).toNat = n := by simp [Nat.mod_eq_of_lt h]
  simp only [Pred.eval, BitVec.ule, e]

theorem shift_correct (hn : 0 < n) (left s guard : Bool) (kind : Trap) (a b : BitVec n)
    (hg : guard = false → ¬ (ival s b < 0 ∨ (n : Int) ≤ ival s b)) :
    shift Isa.exec n left s guard kind a b = specShift kind left s n a b := by
  have hbad := bad_count_iff hn s b
  unfold shift specShift
  by_cases hb : n ≤ b.toNat
  · have hb' := hbad.1 hb
    have hguard : guard = true := by
      cases h : guard
      · exact absurd hb' (hg h)
      · rfl
    subst hguard
    simp [uge_width, hb, hb']
  · have hb' : ¬ (ival s b < 0 ∨ (n : Int) ≤ ival s b) := fun h => hb (hbad.2 h)
    have hk : (ival s b).toNat = b.toNat := by
      have : 0 ≤ ival s b := by omega
      rw [ival_eq_toNat b this]; simp
    simp only [hb', ↓reduceIte, hk]
    cases left
    · cases s
      · cases guard <;> simp [uge_width, hb, lshr_eq_ofInt]
      · cases guard <;> simp [uge_width, hb, ashr_eq_ofInt]
    · cases guard <;> simp [uge_width, hb, shl_eq_ofInt s]

end Arith
