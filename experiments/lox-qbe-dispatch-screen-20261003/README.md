# QBE dispatch screen: unselected

The bounded dispatch candidate `74bcecea` remains isolated. Its complete
156-cell smoke/stat matrix and 104-cell counter screen passed with 223 stable
guards and all four PMU events running at 100%. Its static improvements for
late opcodes do not produce a broad cycle benefit in this screen.

| Reduction versus selected control | LLVM VM | LLVM tree | QBE VM | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Instructions | 0.0004% | approximately 0% | 0.6961% | approximately 0% |
| Cycles | -0.0470% | 0.2342% | -2.1280% | 0.3788% |

Positive reduction means less work; negative means more. Each screen ratio
uses one paired round and the geometric mean across 13 workloads per engine.
Cycles are diagnostic and these are not repeated wall timings. No full wall
or counter matrix was run, and no speed or parity gain is selected.

QBE VM equality and string equality use 2.5567% and 3.4774% more instructions,
despite 3.8210% and 2.8181% fewer cycles in this round. Fib uses 1.9580% fewer
instructions but 4.5948% more cycles. Properties and zoo use 6.2789% and
5.5339% more cycles. Static dispatch inspection identifies extra work for early
opcodes, but the counters do not independently establish causality.

Qualification is separate: 20 focused tests, 2,488 fresh bounded unit tests,
523 QBE/native-build tests, 336 fresh public tests, 1,264 native program pairs
and eight checked refusal pairs passed. Eighty expensive native stress-smoke
cells remain explicitly omitted. Native error cases intentionally return 70;
checked refusals return 2. LLVM's allocated sections and complete program
layout match the selected control, and all 420 frontend records are unchanged.
The actual measured RC guests are exact copies of the qualified ELFs; separate
fresh rebuilds match their allocated sections and layout.

The independent proof and qualification reviews are in the adjacent
`lox-qbe-dispatch-review-20261003` and
`lox-qbe-dispatch-qualification-review-20261003` directories. Their freeze
precedes the author's final broad gate; the final author's package retains
that subsequent evidence. Earlier cache/postflight failures and the narrower
public helper window remain explicit in the sealed qualification package.

`closeout.json` independently validates every measurement row, input, command,
ELF reproduction and paired analysis. `archive.json` binds 332 original paths
to 261 objects under
`/home/epentland/ai/canopy/evidence/mylang-lox-compiler-screens-20261003/qbe-dispatch`,
with manifest SHA-256
`3b8c701d3e3abe7ffb77b96e475719cdc881aa60821e6c0a81ec484cf234a1c7`.
After-copy original checks and portable object verification passed. The exact
selected source37 and selected core `3b33df52` remain unchanged; main is not
modified.
