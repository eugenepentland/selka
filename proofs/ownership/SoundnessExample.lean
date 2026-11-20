import Soundness
import CheckerTests

/-!
# The theorem applied to concrete functions

`check_sound` instantiated at two functions of `CheckerTests.lean`; the checker accepts them by
evaluation in the kernel (the others are accepted by the `#guard`s of `CheckerTests.lean`).
-/

namespace Own
namespace Ex

open Own.Tests

/-- A list is allocated and dropped: no execution faults and every return meets `Post`. -/
theorem allocDrop_safe (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (hpre : Pre okAllocDrop.1 args h0 pend0)
    (hsc : ScalarArgs (mkCC okAllocDrop.1 okAllocDrop.2) args) :
    Safe okAllocDrop.1 okAllocDrop.2 args h0 pend0 :=
  check_sound _ _ (by decide +kernel) args h0 pend0 hpre hsc

/-- A record field is taken, updated and written back by `record_set`: the take protocol. -/
theorem recordTake_safe (args : Nat → Val) (h0 : Heap) (pend0 : Addr → String → Bool)
    (hpre : Pre okRecordTake.1 args h0 pend0)
    (hsc : ScalarArgs (mkCC okRecordTake.1 okRecordTake.2) args) :
    Safe okRecordTake.1 okRecordTake.2 args h0 pend0 :=
  check_sound _ _ (by decide +kernel) args h0 pend0 hpre hsc

end Ex
end Own

#print axioms Own.Ex.allocDrop_safe
#print axioms Own.Ex.recordTake_safe
