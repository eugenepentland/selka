# QBE private scratch aliases: unselected

The isolated compiler candidate `9c5f283c` replaces proven single-use scratch
address copies with direct load addresses. It preserves load widths, positions,
control flow and checked behavior. It remains unselected after the full wall
matrix provides no broad elapsed-time benefit.

| Reduction versus selected control | LLVM VM | LLVM tree | QBE VM | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Screen instructions | approximately 0% | approximately 0% | 2.2347% | -0.0099% |
| Screen cycles | 0.4135% | 0.1005% | -0.8287% | -0.9279% |
| Full wall time | 0.2395% | 1.1830% | -0.1246% | -0.7434% |

Positive reduction means less work; negative means more. The screen uses one
paired round over 13 workloads per engine. Wall timing uses three paired rounds
and each case's median ratio before the geometric mean across 13 cases. The
small aggregate increases do not establish a statistically meaningful regression.
LLVM allocated code and full program layout are identical, so its timing
variation supplies no compiler improvement claim. No elapsed-time or parity gain
is selected. No full counter matrix was run.

All 156 smoke/stat checks, 104 screen observations and 468 wall observations
completed with matching outputs, source postchecks and unchanged 223 measured
input guards. The measured guests are exact copies of the qualified RC ELFs;
fresh reproduction ELFs separately match their allocated sections and layout.
The first invalid `timing` CLI phase was refused before any benchmark process;
its status-2 wrapper/log are preserved, and the complete `time` phase has a
distinct receipt.

The legacy strict closeout failed because the preparation guard list omitted
two **unmeasured fresh reproduction runtime archives**. A bin-only compiler
prefix builds those archives into the private rebuild cache, whereas earlier
trials reused already guarded installed archives. Their current hashes match
the premeasurement build receipt, and the measured qualified ELF/runtime inputs
were fully guarded; this does not retroactively add those paths to the original
guard set. `limits.json` records the exact gap. The archive below is an immutable
evidence snapshot, rather than a successful legacy strict closeout. A separate
prospective preparation protocol will cover both runtime layouts before the next
trial. Frozen helpers and receipts remain unchanged.

Compiler qualification is separate and complete: 17 focused tests, 2,485 bounded
unit tests, 520 QBE/compiler tests, 336 fresh public comparisons, 1,264 exact
native/AST pairs and eight checked refusals. Eighty expensive native-stress
smoke cells remain explicit omissions. The author's package and independent
source/artifact/full-stream reviews are retained beside this report. Generic
acceptance used a private source copy with its exact Git/index/topology scope
recorded; actual guest qualification used the frozen compiler and four exact
RC/GC executables. Guardian passed without waivers or baseline edits.

The static ablation isolates the VM effect to one `s1` alias. It promotes 236
stores and 237 reads, reduces the fixed frame from 5,528 to 4,760 bytes, and
removes 24 cold bounds-failure call sites. The five `s0` alias rewrites leave VM
assembly unchanged. Those counts do not explain dynamic regressions causally.

`archive.json` records 344 original paths and 266 verified objects under
`/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/qbe-scratch-alias-unselected`.
Manifest SHA-256 is
`616917a8c63f4360cf798f53ff2913232a0681da1a5f618a125c0d1fd5468196`.
Original bytes were rechecked after copying; portable verification independently
checks the saved objects without requiring live original paths. The manifest
explicitly records the failed strict-closeout scope and no selection claim.
