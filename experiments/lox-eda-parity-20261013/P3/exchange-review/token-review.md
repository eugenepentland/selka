# Brief read-only review of transfer token dataflow

P7 replaced the dominating-read scan with `src/core/transfers.zig`. Source
identities are in `token-review-inputs.json`. P3 made no P7 edits and launched
no compiler or guest jobs. The following conclusions are source inspection,
not independent native qualification.

The implementation addresses the earlier reported matcher gaps: same-key
writes consume one token; sibling paths must merge; a preheader token cannot
survive a consumed loop backedge; field-prefix overlap consumes a token;
dictionary key reads cannot pair with value stores. Raw P7 tests explicitly
cover sequential one-use, sibling paths, cross-block restoration, preheader
versus in-loop read, dictionary-key exclusion, and 512 distinct slots.

Incoming state is monotone (`absent` to a concrete token/empty, then at most
`ambiguous`). Each incoming-state change schedules a block once. Read and write
transfer functions reset to fixed local tokens or empty, so the propagation
converges without repeated scans of candidate reads or dominator walks. Each
key resets scratch allocation; the output bitmap and key set persist. This
bounds dataflow visits and per-key scratch independently of iteration count.

No demonstrated source/native blocker was found. Two remaining IR invariant
questions were sent directly to P7 and coordinator:

1. `overlap` requires equal index SSA references. Different dynamic indices may
   be equal at runtime. Exact IR `read(L,i); write(L,j); write(L,i)` preserves
   the i token across the j write even when i equals j. Normal receiver SSA
   versioning may exclude this shape; this review did not prove that invariant
   across all rewrites. It is not a confirmed source-level leak.
2. Different concrete read tokens merge into `ambiguous`, even if both paths
   took the same physical slot. If such joined-token owned-read IR is admitted,
   false pairing plus ordinary old-slot cleanup could release an owner also
   held by a transferred result. Marker/lowering invariants must exclude or
   reject that shape. Ambiguous pairing is not inherently a safe cleanup
   fallback. No public-source reproducer was demonstrated.

The stated `O(keys * (instructions + edges))` bound describes dataflow visits
assuming constant-time key normalization. `ir.Function.resolve` instead walks
an uncompressed forwarding-copy chain. Read/store keys are recomputed inside
each per-key scan, so key normalization adds a forwarding-chain factor.
Precomputing normalized keys once would move this cost outside the per-key
iteration. The existing 512-slot test has no forwarding chains; no compile-time
regression was measured by P3.

P7 reports raw regressions/scaling and existing nested list/dictionary tests
passed, with its frozen008 five-mode verifier in progress. Those are owner
reports; P3 did not independently execute them. P7 owns any fixes, final
installation identities, and final qualification claims.
