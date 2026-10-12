# Interpreter Runtime projection migration

The coordinator approved replacing three temporary Runtime copies with direct
`mut it.rt` calls. The original migrated source is frozen as `before.my.gz`
(SHA256 `3cacf6b0c40e8ddf85488fb8914f5c6ef1610d021a4bd522f950eedb96647a52`).
The new source is `after.my.gz`
(SHA256 `423128bd964643674ddc4eddd41ce3e18bd6433f5fe60cbaf7392c6a2f92d8ba`).
It removes three `.copy()` sites, replacing ten source lines with four.

Both exact sources ran with the same Support5 compiler source
`a1f19edf255c8c0886731d8d7cce450d5f657720`, compiler SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
Both preserve the registered three output lines, all 40 × 500 inner iterations,
zero RC events and zero exit-live bytes. LLVM ABI marker and selected forbidden
linked-helper audits pass. Final all-five-mode and installed-runtime qualification
remains required on the integrated compiler; this is an intermediate release run.

| Whole-program managed metric | Explicit Runtime temporaries | Direct Runtime projections |
| --- | ---: | ---: |
| Allocations | 351,287 | 70,790 |
| Allocation bytes | 1,634,431,400 | 4,827,392 |
| Reallocation growth bytes | 27,262,288 | 87,552 |
| List copy events | 262,493 | 22,253 |
| List copy bytes | 1,614,810,180 | 510,064 |
| Peak live managed bytes | 227,784 | 227,784 |

This is a source migration improvement, not a same-source compiler improvement.
Allocation traffic and peak are distinct; the unchanged peak is not an RSS result.
No uninstrumented runtime or RSS comparison was run. Admission waited 406 seconds,
separate from build/run elapsed records, which are not used for performance claims.

`callee_slot` is still read before allocation; `total` expressions retain their
original evaluation order. No removed temporary was observed through the outer
interpreter between extraction and publication, and those callees have no escaping
callbacks or external observations. The selected callable payload copy remains
live across allocation. `kept`, `snapshot_then_store`, and Builder's copied `comp`
remain independent snapshots; `note(self, mut comp, ...)` must read the original
Builder while changing the temporary component. Iteration counts, inputs and every
registered output oracle are unchanged.

`comparison.json` records compiler, source, binary, LLVM, Zig and harness hashes;
`raw-manifest.json` identifies losslessly compressed raw build/run/counts/LLVM and
source files. The original A09 measurement and its source identity remain intact.
