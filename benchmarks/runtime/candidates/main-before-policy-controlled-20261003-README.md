This session tests the LLVM scalar policy at exact source
`1ec716ce1c4658ad876deed742ceecc35b02afd7` against source33e781a1, d348026f
and current main1fd1d566, plus each unchanged case's exact original winner.
Main uses a ReleaseFast host compiler; candidates use Debug host compilers and
ReleaseFast guests. The direct policy/before contrast uses matching host modes.
Receipts, guest commands, installed assets and binary hashes are in the exact
JSON; compiler-mode guest-byte equivalence is not assumed.

Five cases at both original sizes, nine guests, 15 randomized rounds and three
warmups produced 1,350 samples, 270 warmups, 90 memory probes and 270 selected
edge probes. The two newly compiled sources also passed 480 full-inventory
MyLang edge probes. Independent replay passed all 90 sample groups. CPU2 was
99.52% busy and sibling CPU3 averaged0.55%; powersave was active and no frequency
warnings were recorded.

These ratios use the same session. Intervals are exploratory paired 95%
bootstrap intervals, uncorrected for repeated tuning or multiple comparisons.

| LLVM contrast | Small | Large |
|---|---|---|
| Policy/before integer_math | 0.741 [0.726,0.757] | 0.727 [0.718,0.735] |
| Policy/main integer_math | 0.843 [0.829,0.870] | 0.846 [0.841,0.859] |
| Policy/before float_math | 0.945 [0.935,0.957] | 0.938 [0.926,0.954] |
| Policy/main float_math | 1.061 [1.049,1.072] | 1.055 [1.040,1.069] |
| Policy/main call_direct | 0.575 [0.568,0.592] | 0.540 [0.534,0.550] |
| Policy/main result_propagate | 0.639 [0.627,0.642] | 0.595 [0.591,0.599] |
| Policy/main record_construct | 0.731 [0.722,0.742] | 0.694 [0.684,0.743] |

Keeping checked divide/remainder for LLVM to optimize recovers the measured
integer regression and improves float time against the previous candidate.
LLVM float still regresses against current main by roughly5–6% in this session.
QBE policy/before intervals overlap one for every selected case and size,
consistent with unchanged QBE lowering. QBE call/main ratios remain1.036 small
and1.033 large; Result/main1.049 and1.051. Their intervals are above one, so these
residual regressions remain explicit even though other mechanisms improved.

The source owner reported 31 focused policy/cache tests, 58 executable LLVM
constant-divisor cases with llvm-v1 trace confirmation, full-width checked
arithmetic differential checks and Guardian88 passing for this source. These
checks support the specific policy change; a final full semantic gate and
ReleaseFast acceptance/independent confirmation are separate requirements.
No historic target or original port was changed, and this nine-guest diagnostic
cannot substitute for the complete six-arm milestone.
