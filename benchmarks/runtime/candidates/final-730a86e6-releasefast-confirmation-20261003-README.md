This independent session reran exact final source
`730a86e62b47c922dc1411d24b5868c3bd2132f3` on the final
ReleaseFast guests after the complete six-arm milestone. It preselected six
regression families and JSON/Lox, then added every provisional original-reference
win family. Eleven cases, both frozen sizes, seven guests, 15 randomized rounds
and three warmups provide 2310 samples, 462 warmups,
462 selected edge probes and 154 RSS probes.
The scalar-policy manifest also passed 240 full-inventory
MyLang edge checks. Independent diagnostic replay validates all 154 groups.

All guest invocations used CPU2/global timing lock. CPU2 busy average
99.55%, sibling CPU3
0.22%; powersave was active.
Frequency warnings: []. Average load does not exclude short interference.
The main/final comparison uses ReleaseFast host compilers at exact source1fd1d566
and730a86e6. Scalar-policy1ec host is Debug, guests ReleaseFast; this extra control
is qualified by its recorded mode and no general guest-equivalence assumption.
No archived timing rounds are paired.

The full capture has 7 numerical frozen closures and153 rows still above1.00.
A demonstrated-faster-original claim requires upper paired95% bounds below1 in
both the full session and this independent session. Meeting the frozen target
additionally requires the full frozen ratio<=1.00. Fixed-target arithmetic alone
and near-target rows do not establish independent speed evidence.

| Provisional family / size | Backend | Full frozen ratio | Full concurrent original ratio,95% interval | Independent original ratio,95% interval | Final evidence status |
|---|---|---:|---:|---:|---|
| mutate_nested / small | my-llvm | 1.0081 | 0.9899 [0.9806,0.9960] | 0.9877 [0.9779,0.9937] | independently_faster_original_but_frozen_target_open |
| bytes_scan / small | my-llvm | 0.4152 | 0.4073 [0.4054,0.4114] | 0.4114 [0.4076,0.4141] | frozen_target_met_and_independently_faster |
| bytes_scan / small | my-qbe | 0.9729 | 0.9543 [0.9517,0.9611] | 0.9560 [0.9476,0.9638] | frozen_target_met_and_independently_faster |
| bytes_scan / large | my-llvm | 0.2148 | 0.2093 [0.2081,0.2117] | 0.2099 [0.2087,0.2129] | frozen_target_met_and_independently_faster |
| bytes_scan / large | my-qbe | 0.2273 | 0.2214 [0.2192,0.2227] | 0.2219 [0.2182,0.2242] | frozen_target_met_and_independently_faster |
| string_search / small | my-llvm | 0.9952 | 0.9948 [0.9901,0.9968] | 0.9944 [0.9894,0.9992] | frozen_target_met_and_independently_faster |
| string_search / large | my-llvm | 0.8967 | 0.8913 [0.8839,0.8983] | 0.8908 [0.8876,0.8941] | frozen_target_met_and_independently_faster |
| string_search / large | my-qbe | 0.9547 | 0.9489 [0.9378,0.9586] | 0.9449 [0.9439,0.9492] | frozen_target_met_and_independently_faster |

All160 backend/case/size outcomes, including unselected/open targets, are retained
in the companion status JSON. Confirmation does not silently remove any target.
Same-session current-main/final and scalar-policy controls follow:

| Case | Backend | Small final/main,95% interval | Large final/main,95% interval | Small final/policy,95% interval | Large final/policy,95% interval |
|---|---|---:|---:|---:|---:|
| integer_math | my-llvm | 0.8546 [0.8523,0.8557] | 0.8453 [0.8431,0.8532] | 0.9994 [0.9966,1.0018] | 0.9949 [0.9933,1.0042] |
| integer_math | my-qbe | 0.4718 [0.4712,0.4734] | 0.4653 [0.4636,0.4661] | 0.9995 [0.9985,1.0032] | 1.0008 [0.9976,1.0051] |
| float_math | my-llvm | 1.0521 [1.0508,1.0530] | 1.0617 [1.0578,1.0630] | 0.9991 [0.9973,1.0004] | 1.0003 [0.9981,1.0021] |
| float_math | my-qbe | 0.4738 [0.4732,0.4742] | 0.4657 [0.4640,0.4671] | 0.9999 [0.9982,1.0007] | 1.0006 [0.9957,1.0021] |
| call_direct | my-llvm | 0.5784 [0.5775,0.5797] | 0.5412 [0.5394,0.5423] | 1.0001 [0.9984,1.0026] | 1.0008 [0.9969,1.0032] |
| call_direct | my-qbe | 1.0501 [1.0465,1.0520] | 1.0484 [1.0443,1.0519] | 0.9984 [0.9948,1.0026] | 0.9972 [0.9961,1.0022] |
| option_handle | my-llvm | 0.5807 [0.5781,0.5836] | 0.5135 [0.5112,0.5151] | 0.9995 [0.9974,1.0036] | 0.9992 [0.9976,1.0005] |
| option_handle | my-qbe | 0.8545 [0.8528,0.8564] | 0.8562 [0.8543,0.8592] | 1.0008 [0.9968,1.0034] | 0.9988 [0.9973,1.0024] |
| result_propagate | my-llvm | 0.6397 [0.6377,0.6438] | 0.5994 [0.5917,0.6067] | 1.0009 [0.9952,1.0041] | 0.9965 [0.9796,1.0075] |
| result_propagate | my-qbe | 1.0491 [1.0469,1.0515] | 1.0485 [1.0425,1.0530] | 0.9987 [0.9955,1.0022] | 0.9997 [0.9983,1.0036] |
| record_construct | my-llvm | 0.7270 [0.7244,0.7277] | 0.7183 [0.7130,0.7195] | 1.0007 [0.9970,1.0043] | 1.0035 [0.9954,1.0076] |
| record_construct | my-qbe | 0.9533 [0.9520,0.9553] | 0.9584 [0.9550,0.9600] | 0.9991 [0.9956,1.0024] | 0.9999 [0.9955,1.0015] |
| json_transform | my-llvm | 0.3494 [0.3485,0.3510] | 0.3144 [0.3135,0.3153] | 1.0019 [0.9987,1.0065] | 0.9981 [0.9942,1.0044] |
| json_transform | my-qbe | 0.4250 [0.4227,0.4267] | 0.3936 [0.3923,0.3949] | 1.0039 [0.9969,1.0089] | 1.0051 [1.0015,1.0085] |
| lox_eval | my-llvm | 0.5287 [0.5274,0.5308] | 0.5198 [0.5174,0.5208] | 0.9986 [0.9965,1.0001] | 1.0000 [0.9986,1.0022] |
| lox_eval | my-qbe | 0.5235 [0.5201,0.5259] | 0.5116 [0.5099,0.5135] | 1.0015 [0.9981,1.0062] | 0.9999 [0.9951,1.0063] |
| bytes_scan | my-llvm | 0.4104 [0.4064,0.4138] | 0.2101 [0.2097,0.2127] | 1.0047 [0.9948,1.0186] | 0.9912 [0.9874,1.0020] |
| bytes_scan | my-qbe | 0.1246 [0.1241,0.1255] | 0.0246 [0.0242,0.0248] | 1.0044 [0.9913,1.0155] | 0.9930 [0.9863,1.0082] |
| mutate_nested | my-llvm | 0.9882 [0.9751,0.9956] | 0.9933 [0.9852,1.0043] | 0.9988 [0.9929,1.0045] | 1.0032 [0.9915,1.0140] |
| mutate_nested | my-qbe | 0.9811 [0.9787,0.9863] | 0.8898 [0.8833,0.8971] | 0.9992 [0.9951,1.0055] | 1.0019 [0.9912,1.0109] |
| string_search | my-llvm | 0.9900 [0.9813,0.9967] | 0.8609 [0.8569,0.8635] | 0.9983 [0.9966,1.0037] | 0.9990 [0.9951,1.0030] |
| string_search | my-qbe | 0.8168 [0.8142,0.8213] | 0.9429 [0.9415,0.9472] | 0.9996 [0.9906,1.0053] | 0.9991 [0.9970,1.0021] |

The final/policy columns are exact reciprocals of the recorded policy/final
ratios, with interval endpoints inverted; they do not create a new unrecorded
measurement. Current-main/final ratios and original-reference ratios use only
new same-session rounds. The generic diagnostic tool warning that one session
alone is not independent proof remains true in isolation; this artifact binds
it as the second session after the separately retained full milestone.

Intervals are exploratory and uncorrected for repeated tuning, winner selection
or multiple comparisons. No application ratio is an additive causal contribution;
profiles and counting-mode ownership diagnostics are separate. The frozen
all-arm common-ISA limitation, calibration limits, single-probe RSS and missing
guest compile-duration measurements remain. No aggregate score pools workloads.

Raw confirmation SHA256: `9a1a112b939204496cc298122194fe276cdf13934b6ded79b25f5375ffe2ca15`.
Full comparison SHA256: `dbb1906bcac50cb015171cce52ff68a0297f728db81e9ec4927f4f158117d473`.
Final evidence counts: `{'no_demonstrated_faster_claim': 152, 'independently_faster_original_but_frozen_target_open': 1, 'frozen_target_met_and_independently_faster': 7}`.

The initial independent replay rejected this otherwise complete report because
the verifier assumed a common original winning arm at both sizes. String search
has original LLVM at small and original QBE at large. The corrected verifier
counts the qualification multiset from each actual plan; seven focused tests
include this change-of-winner case and reject corruption. Corrected replay
passed154 groups without modifying timings or raw evidence. The archive retains
the original independent rejection log, old verifier bytes/Git blob, corrected
verifier/tests, exact source hashes and successful replay. The previous blob is
`b3e85eec0cb10e8368d97c5d2506b460651a4640`; its SHA256 is
`91b3e92f830c16bc21f022688280f0b122ba73ff8fd0c4fb6bd6cfcdb7f4f33c`.

All eight provisional original-reference wins confirmed. Seven also meet the
fixed historical target; nested-mutation small remains1.0081 and therefore open.
LLVM float arithmetic remains5.2–6.2% slower than current main, QBE direct-call
and Result remain4.8–5.0% slower, with paired intervals above1.00. JSON improves
versus current main to LLVM0.349/0.314 and QBE0.425/0.394; Lox to LLVM0.529/0.520
and QBE0.524/0.512. These application gains do not make their original fastest
reference targets close. All24 six-family final/policy intervals overlap1,
consistent with no admitted P2 fixture specialization. The policy control's
Debug host mode remains explicit. LLVM small string-search confirmation has
upper bound0.9992, very close to1; exploratory/repeated-comparison limits matter.
