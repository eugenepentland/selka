# Fixed-array nested writeback reduction

The source checker in the A07 compiler identified by `results.json` admits
`minimal.my`. Its post-ownership IR (`facts.stdout`) still retains the selected
managed `Cell` before changing a scalar field and releases the old slot after
writing the array. This is a lowering blocker, not an admitted zero-RC native run.

`change` normalizes the same signed dynamic index twice. The read uses phi `%8`
and the write uses phi `%18`; both join `index` and `index + 2`, but arbitrary phi
equivalence is not a safe general inference. A07 owns the fix: capture one
normalized index for the exact typed parent/index writeback relation and preserve
that SSA identity through read and write.

A07's array-slot transfer prototype reuses the record transfer's dominance,
every-path-reaches-update-or-trap, earlier-live-read and intervening-use checks.
Unknown index pairs remain potential aliases. Candidate transfer requires the
same proven index; distinct constant slots may be disjoint. The review requested
`array_get` in the recursive managed-part liveness walk. Array transfer does not
inherit record-only whole-unpack or through-other-field shortcuts.

The registered A06 regression module covers a side-effecting negative index
evaluated once, a dynamic signed helper index, retained independent snapshots,
counted cleanup and linked-symbol/LLVM audits. IR controls require retention for
an unknown live alias and a conditional replacement. These tests require the A07
production fix; this directory records the pre-fix reproducer, not qualification.
