This session measures unchanged contracts with current main
`1fd1d566793dcae92449d937aca595c55ee318c8` (ReleaseFast compiler),
`d348026f52eb02792e8c0c1d07dae7f6c8e26bd7` (Debug compiler), and
`b3ff3bfb41ba94bc023651e34be24a41e6a2f5f0` (Debug compiler), plus each
case's exact original winner. All guests use ReleaseFast/LLVM O3 as recorded.
Compiler-mode guest-byte equivalence remains unestablished. Installed runtime
assets are keyed by guest mode; no Debug-runtime assumption is made.

Six cases at both original sizes use seven guests, 15 randomized rounds and
three warmups: 1,260 samples, 252 warmups, 84 memory probes, 252 selected edge
probes and 240 full-inventory MyLang edge probes for the newly compiled b3ff
source. Independent diagnostic replay passed all 84 sample groups. CPU 2 was
99.57% busy; sibling CPU 3 averaged 2.55%, powersave was active, and no frequency
warnings were recorded. These counters cannot exclude short interference.

Ratios below are b3ff/current-main from this same session. Intervals are paired,
exploratory 95% bootstrap intervals, uncorrected for multiple comparisons or
repeated tuning. Historical targets stay unchanged.

| Case | LLVM small | LLVM large | QBE small | QBE large |
|---|---|---|---|---|
| call_direct | 0.559 [0.518,0.609] | 0.557 [0.528,0.574] | 1.248 [1.189,1.283] | 1.256 [1.181,1.290] |
| option_handle | 0.628 [0.576,0.650] | 0.563 [0.555,0.577] | 1.003 [0.991,1.031] | 1.013 [0.984,1.025] |
| result_propagate | 0.671 [0.649,0.692] | 0.682 [0.670,0.716] | 1.177 [1.139,1.203] | 1.207 [1.166,1.235] |
| record_construct | 0.887 [0.816,0.947] | 0.918 [0.887,0.991] | 1.097 [1.075,1.136] | 1.075 [1.052,1.118] |
| integer_math | 1.149 [1.139,1.170] | 1.180 [1.162,1.206] | 0.514 [0.510,0.519] | 0.510 [0.506,0.514] |
| float_math | 1.082 [0.965,1.249] | 1.112 [1.050,1.123] | 0.473 [0.451,0.527] | 0.452 [0.446,0.459] |

The compact checked-product change in b3ff reduces QBE call time relative to
d348 by roughly 35% (ratios 0.650 small and 0.641 large), with intervals below
one. QBE calls and Results still regress against current main; Option intervals
overlap one. LLVM integer regression is supported at both sizes, while the
small float interval overlaps one. LLVM b3ff/d348 intervals overlap one for
every selected case/size. These observations justify follow-up ablations; the
combined b3ff source also includes dictionary transactions, module provenance
and scalar byte changes, so this session alone cannot isolate each change.

The accompanying gzip retains exact JSON bytes with compiler/source/asset and
guest hashes, commands, calibration, order, checksums, samples and intervals.
The decompressed JSON SHA256 is
`dda649dd4201a7b9499f0855f8a127125162f6e36f8cbc97372a685946121fb1`.
This separate seven-guest schema is a controlled diagnostic, not a full six-arm
acceptance report or an independent faster-than-reference confirmation.
