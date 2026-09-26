# RC narrowed collection receivers

`receivers.my` checks mutation through a compiler-created Option projection,
a caller snapshot, an independent named match binding, a narrowed dictionary,
and an older heap value mutated while an arena is open. Build it with the Debug
compiler and `--rc-runtime=stats`, optionally `--release`; main must return zero.

The exact defensive Option dispatch pattern is required for borrowed mutation
publication. A named match binding remains an ordinary independent snapshot.
The source owning edge is detached before the hidden receiver is filled; no
additional owning edge is fabricated for that compiler projection.

Validation: all four source tests pass on QBE and LLVM; all thirteen existing
`option_narrowing.my` tests pass on LLVM, including the previously failing
collection-method/index-write case. That case also passes QBE. The focused
structural test passes (one named plus eleven imported tests); Guardian88 passes.
Direct QBE counters are 33 allocations/33 retires, 24 acquires/57 releases,
8 hold acquires/releases; LLVM is recorded in `results.json.gz`.

A separate accepted-GC control (`f6bea5d9`, compiler SHA256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`)
also fails the caller-snapshot variant. This report does not classify that older
writeback defect as an RC regression, or claim to fix the GC path. The parent has
the follow-up finding; keeping the expanded fixture here avoids marking a known
GC failure as a passing default guest regression.
