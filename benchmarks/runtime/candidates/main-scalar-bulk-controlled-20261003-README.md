This controlled diagnostic reruns unchanged bytes_scan, call_direct,
result_propagate and record_construct at both original sizes with current
main1fd1d566, d348026f, scalarb3ff3bfb and bulk33e781a1, plus the exact
original winner. Full revisions, compiler modes, receipts, installed assets,
commands and executable hashes are in the exact accompanying JSON. Main uses
a ReleaseFast compiler; candidates use Debug compilers and ReleaseFast guests.
No compiler-mode guest-byte equivalence is assumed.

Nine guests per plan, 15 randomized rounds and three warmups produced 1,080
samples, 216 warmups, 72 memory probes and 216 selected edge probes. Two newly
compiled sources also passed 480 full-inventory MyLang edge probes. Independent
replay passed all 72 sample groups. CPU 2 averaged 99.61% busy, sibling CPU 3
averaged 1.10%, powersave was active, and no frequency warnings were recorded.

Ratios below are from the same session. Intervals are paired exploratory 95%
bootstrap intervals, without correction for repeated tuning or multiple
comparisons. Historic targets and the original checksum contracts remain fixed.

| Contrast | LLVM small | LLVM large | QBE small | QBE large |
|---|---|---|---|---|
| Bulk/scalar bytes_scan | 0.479 [0.473,0.483] | 0.218 [0.211,0.224] | 0.182 [0.179,0.185] | 0.038 [0.035,0.038] |
| Bulk/original bytes_scan | 0.474 [0.466,0.480] | 0.216 [0.211,0.222] | 0.967 [0.950,0.978] | 0.219 [0.187,0.226] |
| Bulk/main call_direct | 0.582 [0.571,0.587] | 0.560 [0.548,0.630] | 1.038 [1.025,1.051] | 1.051 [0.980,1.073] |
| Bulk/main result_propagate | 0.664 [0.633,0.671] | 0.685 [0.680,0.697] | 1.041 [1.001,1.063] | 1.042 [1.036,1.053] |
| Bulk/main record_construct | 0.927 [0.882,0.930] | 0.921 [0.919,0.925] | 0.952 [0.933,0.963] | 0.954 [0.951,0.962] |

The original bytes winner is the frozen old MyLang LLVM binary, separately
hash-verified and rerun; current main is a distinct source. Faster observations
need independent confirmation and do not themselves close historical absolute
targets. The large QBE call interval overlaps one; small call and both Result
intervals still support modest regressions against current main. The additional
QBE zero simplification reduces call time versus scalarb3ff by about15%, Result
time by about9%, and construction time by about11%. Bulk bytes and zero
simplification are combined in source33e781a1, so this diagnostic does not
isolate every individual source change.

Untimed QBE compute-entry assembly captures retain exact symbol, command,
source/compiler and binary hashes. Frames are 3,128 bytes for b3ff and 2,968 for
33e781a1, compared with main3,048 and d3484,248. Whole-function static instruction
counts are 10,394 and 9,429, respectively; static stack references are 2,572
and 2,366. Untaken paths and runtime glue are included. These counts are
supporting evidence, not executed costs or causal attribution.

This separate nine-guest schema is not a full six-arm acceptance report. Final
ReleaseFast full-suite and independent confirmation measurements remain
required. The static archive and exact gzip JSON preserve reviewable evidence.
