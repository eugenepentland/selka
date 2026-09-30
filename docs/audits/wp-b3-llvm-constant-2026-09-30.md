# WP-B3 LLVM literal-bound continuation

This isolated continuation starts from composed40bd74a0. Exact frozen
A5/3226 invocation attribution identified11,370,004 extra dynamic minimum-int
constant loads in `vm::run`; it does not attribute those loads to a particular
inlining or register-pressure heuristic. All count saturation/refusal checks
remain required. This checkpoint changes only LLVM's proof/lowering of signed
64-bit add/sub by±1 and leaves QBE emission unchanged.

The producer already precedes its bound comparison in the same block. A fresh
literal `storel` to a singly-defined `alloc8 8` fixes the loaded value until any
possible writer, store, ordinary/nested call, blit, address escape/derivation,
unknown opcode or control boundary resets all reaching-store facts. Historical
escape implies no noalias/nocapture property. A captured scalar value survives
later memory writes. The proof rejects other allocation extents/alignment,
load widths, pointer operands, extern-symbol literals, changed operands/bounds
and cross-block facts. It replaces exactly `a>MAX-1` or `a<MIN+1` with the
corresponding intrinsic bit; wrapped values, loads, failure branches, cleanup,
trap operands and source positions stay in place. No operation gains nsw/nuw
or a speculative memory/call effect.

The strict first prototype admitted only1 VM subtraction; its patch, compiler,
receipt and logs remain in owned `.tmp/strict-proof/`. The approved local
refinement admits32 ssub and48 sadd calls. All410 production input IL units
are byte-identical between those builds; actual LLVM VM minimum-int MOVabs
sites fall42→0 and jo/jno sites rise27→76. Both actual invocation binaries
print30000. This is code-shape evidence, not quantitative acceptance.

Four mathematical forms,24 refusal boundaries and6 historical/captured-value
cases are covered by the tagged translator tests. Five explicit golden rows
change only arithmetic/overflow-flag IR and retain the prior adapter IR in
`expected_before_constant_overflow`. The new CLI test compares12 boundary
pairs including full trap detail, trace and record against QBE; the existing
28-width-boundary suite also passes. Pre-final extern-literal cleanup checks
passed15 focused unit entries,13 golden entries,3+3 CLI entries,36 fresh guests
across RC/GC/stress/release/GC-release/stats,140 QBE-build tests,27 input/format
steps and88 Guardian checks. The final extern cleanup has passed the focused
unit root and12 install steps; final functional receipts and independent
review will be recorded separately without changing this frozen source.

Final compiler SHA256: `3b291af9a19e074664ca2828540a0ac7a55809b907ef9697539b4c3b90a21d73`.
QBE SHA256: `bcc56938e384d19a707870ff61f5d14fde1edeebe32d47b25058de39db4c93c6`.
Root owns composed86-row dev/smoke/full measurements and the final broad gate.
No timing CPUs were claimed, no samples were collected and no acceptance
waiver is asserted by this checkpoint.
