# P9 immutable-byte iteration, scalar prerequisite

This is an untimed code-generation diagnostic, not a parity measurement. The
standalone source uses parameterized byte sums and XOR sums, plus an indexed
control; it does not use benchmark function names or fixture dispatch.

The change lets the existing RC read-loop certificate admit immutable byte
iteration. The guarded copy keeps stable storage under caller or journal
anchors and removes only checks its existing range proof establishes. The
unbounded XOR sum still checks signed overflow at each addition, so masks
outside the byte range and seeds close to signed boundaries remain exact.

`xor_octets-before.s` has 25 instructions from `.Lbb27` through `.Lbb33` in its
steady loop. `xor_octets-scalar-after.s` has 15 from `.Lbb44` through `.Lbb47`.
Neither contains a vectorized reduction. The emitted function grows because
the guarded copy retains the original fallback: total assembly instructions
rise from 183 to 224. `indexed_octets` is unchanged. All artifact hashes and
counts are recorded in `p9-byte-iteration.json`.

Validation: 20 focused Zig tests passed, including native accounted versus
unaccounted comparisons across empty/short/tail/long inputs, negative and
out-of-byte masks, MIN/MAX seeds, exact trap details, and mutation/callback/
step-accounting refusal. The two guest tests pass QBE RC, QBE GC and LLVM;
they cover byte views, masks, tails and immutable buffer snapshots.

The next experiment is a general guarded bulk XOR reduction. Its admission
must additionally prove an 8-bit mask and enough signed sum headroom before
calling a heap-free reduction helper; guard failure must enter the original
loop. No timing claim is made for this scalar prerequisite.
