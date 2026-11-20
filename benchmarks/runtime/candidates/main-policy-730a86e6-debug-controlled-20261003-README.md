The corrected source `730a86e62b47c922dc1411d24b5868c3bd2132f3` was
measured against current main `1fd1d566793dcae92449d937aca595c55ee318c8`,
scalar policy `1ec716ce1c4658ad876deed742ceecc35b02afd7`, early candidate
d348026f, and each case's exact original winner. Main uses a ReleaseFast host
compiler; the other sources use Debug hosts. Every guest uses ReleaseFast.
This is a same-session regression screen, separate from final ReleaseFast
acceptance and independent confirmation. The full receipts bind guest commands,
source/compiler/assets/clock/binary hashes and effective native backends.

Six families at both frozen sizes, nine guests, 15 randomized rounds and three
warmups produced 1,620 samples, 324 warmups, 324 selected edge probes and 108
memory probes. Newly supplied policy and corrected manifests additionally
passed 480 full-inventory MyLang edge probes. Independent replay passed all
108 sample groups. CPU2 averaged 99.68% busy and sibling CPU3 4.46%; powersave
was active and no frequency warning was recorded. Average load cannot exclude
short interference. All guest invocations used the global timing lock.

The corrected/policy intervals overlap one in all 24 backend/case/size rows.
The corrected P2 safety fix preserves the prior performance behavior in this
screen. The paired corrected/current-main ratios below retain the LLVM float
and QBE Result regressions. QBE direct-call intervals overlap one in this run,
so earlier small regressions remain unresolved by this screen.

| Case | Backend | Small corrected/main, 95% interval | Large corrected/main, 95% interval |
|---|---|---|---|
| integer_math | my-llvm | 0.860 [0.829,0.917] | 0.845 [0.823,0.901] |
| integer_math | my-qbe | 0.429 [0.416,0.447] | 0.432 [0.417,0.441] |
| float_math | my-llvm | 1.059 [1.013,1.097] | 1.077 [1.052,1.128] |
| float_math | my-qbe | 0.496 [0.476,0.519] | 0.491 [0.474,0.503] |
| call_direct | my-llvm | 0.591 [0.562,0.607] | 0.546 [0.517,0.571] |
| call_direct | my-qbe | 1.024 [0.998,1.035] | 1.043 [0.986,1.060] |
| option_handle | my-llvm | 0.606 [0.595,0.642] | 0.543 [0.513,0.570] |
| option_handle | my-qbe | 0.838 [0.827,0.853] | 0.839 [0.787,0.857] |
| result_propagate | my-llvm | 0.667 [0.643,0.733] | 0.600 [0.558,0.656] |
| result_propagate | my-qbe | 1.029 [1.010,1.077] | 1.043 [1.022,1.088] |
| record_construct | my-llvm | 0.738 [0.709,0.811] | 0.735 [0.697,0.765] |
| record_construct | my-qbe | 0.925 [0.898,0.954] | 0.948 [0.912,0.979] |

Intervals are paired bootstrap intervals for ratios of medians, exploratory
and uncorrected for repeated tuning or multiple comparisons. These unchanged
sources support direct same-session comparisons; historical target comparisons
and cross-session ratios are separate claims. The all-arm common-ISA limitation
still applies to original references.

The accompanying static archive binds the actual published QBE compute IL
unit to its cache manifest: 510,140 bytes, SHA256
`1e3b75fa69d1d46395a1cdb4cff088ba9cfd282adcad967e10dc804f6076f51d`.
It has zero loop-unswitch markers and zero specialized-entry labels. The
corrected fixture admits no P2 specialization. Its entry symbol is 43,823 bytes
for QBE and 20,050 bytes for LLVM; QBE has 9,429 static instructions and a
2,968-byte frame, LLVM 4,148 instructions and a 728-byte frame. Whole-function
assembly includes untaken paths and runtime glue and is not executed kernel
cost. This is Debug-host qualification code; final RF code is captured separately.
The prior 12-copy prototype and its reported growth are superseded faulty-source
evidence. Correctness and specialization budgets were retained; compute
specialization remains an open capability/measurement gap.

Raw JSON SHA256: `c08a8fad53674e8c9b1fac04ee3a047480a261e5fd9240c5eff5c5aa5357da92`.
The archive embeds receipts and helper input hashes. The original frozen ports,
checksums and 80 acceptance targets were unchanged.
