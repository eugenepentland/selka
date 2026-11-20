/-!
# Integer interpretations

`ival s x` is the mathematical integer a bit vector denotes when it is read signed (`s = true`)
or unsigned. `lo s n` and `hi s n` are the bounds of the type `iN`/`uN` the compiler calls
`i8 … u64`. Everything is generic in the width `n`; the eight widths the emitter uses are
instances.
-/

namespace Arith

/-- The integer a bit vector denotes: two's complement when `s` (signed), plain binary otherwise. -/
def ival (s : Bool) {n : Nat} (x : BitVec n) : Int :=
  if s then x.toInt else (x.toNat : Int)

/-- Smallest value of the integer type of width `n` and signedness `s`. -/
def lo (s : Bool) (n : Nat) : Int :=
  if s then -((2 : Int) ^ (n - 1)) else 0

/-- Largest value of the integer type of width `n` and signedness `s`. -/
def hi (s : Bool) (n : Nat) : Int :=
  if s then (2 : Int) ^ (n - 1) - 1 else (2 : Int) ^ n - 1

/-- `v` is a value of the integer type `(s, n)`. -/
def inRange (s : Bool) (n : Nat) (v : Int) : Prop :=
  lo s n ≤ v ∧ v ≤ hi s n

instance (s : Bool) (n : Nat) (v : Int) : Decidable (inRange s n v) :=
  inferInstanceAs (Decidable (_ ∧ _))

theorem ival_inRange (s : Bool) {n : Nat} (hn : 0 < n) (x : BitVec n) : inRange s n (ival s x) := by
  have hp : (2 : Int) ^ n = 2 * (2 : Int) ^ (n - 1) := by
    obtain ⟨k, rfl⟩ : ∃ k, n = k + 1 := ⟨n - 1, by omega⟩
    simp [Int.pow_succ]; omega
  cases s
  · have := x.isLt
    simp only [ival, inRange, lo, hi, Bool.false_eq_true, ↓reduceIte]
    have : (x.toNat : Int) < 2 ^ n := by exact_mod_cast x.isLt
    omega
  · have h1 := BitVec.le_toInt x
    have h2 := BitVec.toInt_lt (x := x)
    simp only [ival, inRange, lo, hi, ↓reduceIte]
    omega

theorem ival_ofInt (s : Bool) {n : Nat} (hn : 0 < n) {v : Int} (h : inRange s n v) :
    ival s (BitVec.ofInt n v) = v := by
  have hp : (2 : Int) ^ n = 2 * (2 : Int) ^ (n - 1) := by
    obtain ⟨k, rfl⟩ : ∃ k, n = k + 1 := ⟨n - 1, by omega⟩
    simp [Int.pow_succ]; omega
  cases s
  · simp only [ival, inRange, lo, hi, Bool.false_eq_true, ↓reduceIte] at *
    rw [BitVec.toNat_ofInt]
    have : v % ((2 ^ n : Nat) : Int) = v := by
      apply Int.emod_eq_of_lt <;> push_cast <;> omega
    rw [this]; omega
  · simp only [ival, inRange, lo, hi, ↓reduceIte] at *
    rw [BitVec.toInt_ofInt]
    apply Int.bmod_eq_of_le <;> push_cast <;> omega

theorem ofInt_ival (s : Bool) {n : Nat} (x : BitVec n) : BitVec.ofInt n (ival s x) = x := by
  cases s
  · simp [ival]
  · simp [ival]

end Arith

namespace Arith

theorem ival_false {n : Nat} (x : BitVec n) : ival false x = (x.toNat : Int) := rfl
theorem ival_true {n : Nat} (x : BitVec n) : ival true x = x.toInt := rfl

theorem ival_eq_zero (s : Bool) {n : Nat} (x : BitVec n) : ival s x = 0 ↔ x = 0#n := by
  cases s
  · simp [ival, BitVec.toNat_eq]
  · simp only [ival_true]
    constructor
    · intro h; apply BitVec.eq_of_toInt_eq; rw [h, BitVec.toInt_zero]
    · intro h; subst h; exact BitVec.toInt_zero

theorem ofInt_ofNat_toNat {n m : Nat} (h : m < 2 ^ n) : (BitVec.ofInt n (m : Int)).toNat = m := by
  rw [BitVec.toNat_ofInt]
  have : ((m : Int) % ((2 ^ n : Nat) : Int)) = m := Int.emod_eq_of_lt (Int.natCast_nonneg _) (by exact_mod_cast h)
  rw [this]; simp

end Arith
