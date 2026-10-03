# Remaining checked Lox performance gap

The selected AST source still executes substantially more instructions than
Rust. These ratios come from the completed 780-cell counter factorial, using
matched per-case medians and then geometric means across 13 workloads. Both
engines use the calibrated tree tier for counters. This is a derivative of
existing measurements, not a new performance run.

| Selected AST / Rust | LLVM VM | LLVM tree | QBE VM | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Instructions | 2.458× | 4.089× | 5.746× | 7.817× |
| Cycles | 2.774× | 4.098× | 5.153× | 7.379× |
| Branches | 2.815× | 4.065× | 5.387× | 6.887× |
| Branch misses | 1.804× | 1.933× | 5.194× | 4.112× |

The large cycle ratios therefore accompany large instruction counts. They
support focusing on generated work and ownership/check lowering; these
counters alone do not partition the cost among copies, checks and memory
access. The selected tree wall gain remains 3.05% LLVM /2.48% QBE relative to
the preceding source84. Full checked semantics remain a requirement.

The completed byte-storage trial gives no convincing runtime improvement:
LLVM VM wall time is 0.6211% higher and QBE VM 0.2345% lower, with median
paired spreads of 1.402% /1.098%. Its diagnostic instruction screen is
1.2402% higher on LLVM VM and 0.2574% lower on QBE VM. The byte source and
its qualified AST composition remain isolated.

Exact LLVM path inspection finds an extra dispatch register move and two
extra instructions on an in-bounds nonnegative local-operand read. A static
model for `string_equality` roughly accounts for its observed instruction
increase; it is a model, not a dynamic opcode trace. A checked direct-u8
dispatch rewrite leaves both backends' static code counts unchanged and is
rejected. The separate generic byte-index compiler guard adds five successful
path instructions; cheaper standalone guard shapes still add at least three
relative to selected code. No new compiler variant was selected from them.

[Counter derivative](lox-remaining-gap-counters-2026-10-03.json) retains the
raw receipt/helper hashes and full paired comparisons.
[AST checkpoint](lox-ast-carrier-checkpoint-2026-10-03.md) records selection,
qualification and the sealed evidence.
[Byte wall trial](../../experiments/lox-byte-source-screen-20261003/README.md),
[dispatch diagnostics](../../experiments/lox-byte-dispatch-static-20261003/README.md)
and [guard diagnostics](../../experiments/lox-byte-refusal-diag-20261003/README.md)
retain their separate evidence and limits. `main` remains unchanged.
