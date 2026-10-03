# Rejected balanced opcode dispatch

A private copy of selected AST changes only `vm.my`: 31 pure integer range decisions lead to the original 33 handler conditions/bodies, covering the same 37 opcode constants. The numeric group and ADD stay together. Handler bodies are byte-identical after indentation removal; operand reads, IP publication, root retirement, error order and unknown-opcode continuation stay in their original bodies. Host selection probes include every opcode, surrounding unknown values and signed integer endpoints. These checks establish the source transformation's structure; no guest behavior qualification was performed.

The checked d14 compiler and adjacent 99ad QBE build both RC guests successfully. Static disassembly shows that the LLVM main dispatch replaces its dense jump table with nested comparisons. The complete `vm::run` also grows on both backends:

| Static whole function | Selected LLVM | Balanced LLVM | Selected QBE | Balanced QBE |
| --- | ---: | ---: | ---: | ---: |
| Instructions | 5,586 | 5,748 | 8,606 | 9,396 |
| Calls | 486 | 486 | 440 | 440 |
| Conditional branches | 766 | 820 | 654 | 685 |

The trial stops here, unselected. Whole-function totals are code-size diagnostics, not executed-path costs; the loss of LLVM's primary jump table makes this unsuitable as a shared source improvement. No fresh benchmark, public/native qualification, GC qualification or composed-source claim follows.

Four `perf annotate` reports reuse the existing selected LLVM/QBE `fib` and `string_equality` cycle profiles; they launch no guest. QBE's comparison chain and partial-width boolean/tag stores identify further investigation targets. Sampled instruction percentages do not prove that the sampled store caused a stall and do not count executed instructions. All original profile data remains bound to the separate sealed gap-profile archive.

`review.json` binds exact source/compiler/ELF/runtime identities and the separate immutable static archive. `receipts.json.gz` retains 61 complete textual originals, including 37 candidate files, original build commands/logs/sidecars, all four disassemblies, range decisions and all four annotation reports. `balanced-rejected.patch` records the diagnostic source change and is not an accepted migration overlay. Main and the selected source/compiler are unchanged.
