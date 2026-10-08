# Minimal final-result annotation proposal

No production files have been edited. Prefer a typed frontend annotation
over a pseudo-call in QBE IL: a call could affect upstream frame positioning,
alias classifications and profitability before LLVM removes it.

1. In qbe_scalar.checkedDivRem, after the existing signed floor-rem final
   correction add, emit `# myl-floor-result %vN D` only under LLVM scalar
   policy, signed 64-bit type, floor_rem operation, and a strictly positive
   literal from the existing `self.pushedLiteral(self.pc)` proof. That proof
   checks immediate linear fall-through, no incoming branch target and exact
   stack growth. Zero, negative, unknown or narrower-type divisors are left
   unchanged. The existing arithmetic, zero/MIN guards and trap calls/order
   remain unchanged.
2. In the LLVM IL reader, recognize this dedicated marker. Require two
   fields, a valid positive signed-i64 bound, and a same-block immediately
   preceding `l add` instruction defining that exact temporary. Refuse
   malformed/misplaced markers. Store the bound keyed by that stable parsed
   Instruction pointer in function Hints, rather than keyed only by the
   temporary name: temporaries are mutable cells and the raw srem and final
   correction can reuse a name.
3. In LLVM instruction lowering, after rendering that specific final add
   and storing its result, load its i64 destination slot, emit
   `icmp ult result,D`, declare `llvm.assume(i1)` once and emit the intrinsic.
   LLVM mem2reg promotes the just-defined slot and corresponding assumption
   to the correct SSA value. Other writes to the same temporary get no
   assumption. This is not a generic IL call, bytecode operation or runtime
   helper, so it adds no guest-visible step, heap accounting or frame charge.
   LLVM call-frame positioning sees no extra IL call.

The marker is a frontend semantic certificate, like existing address hints;
its authority is the positive floor-rem proof, not a broad structural match
over unknown integer arithmetic. The reader's immediate-instruction binding
prevents it from being applied to a prior raw remainder or a different write.
Existing text passes preserve comment lines alongside instruction bodies; any
pass that drops this marker only drops the optimization. Tests must cover
marker adjacency through those passes and mutable temporary reuse.

Default QBE scalar policy writes identical IL. LLVM-scalar-policy output
fed through QBE still has valid comment-only annotations and identical
operations; QBE never sees an intrinsic call or needs fallback linkage.

Required focused checks before timing: positive/negative/MIN/zero-divisor
semantic outcomes; checked-add overflow and refusal/trap streams unchanged;
no marker for non-floor, unknown, zero/negative, branch-target or narrower
divisor; malformed/misplaced marker refusal; exact translated SSA range on
the final result; negative recurrence retains signed correction; QBE emitted
operations unchanged; existing LLVM-scalar-policy-through-QBE tests pass.
Then inspect actual frozen text/other kernels and shared-helper layout, build
source-bound artifacts and qualify under normal policies. No source change
or benchmark modification is authorized by this evidence archive alone.
