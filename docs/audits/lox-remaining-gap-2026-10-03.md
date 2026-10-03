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

Twelve subsequent sampled profiles of the selected LLVM/QBE/Rust guests
locate work for the next experiments. VM dispatch dominates simple workloads;
QBE `fib` also samples heavily in `numeric` and frame loading. Tree profiles
show ownership helper, allocation and collector costs. The
[profile receipts](../../experiments/lox-gap-profile-20261003/README.md)
retain all raw data and same-build symbol mappings. These within-process
percentages guide investigation; they do not partition the measured absolute
gap or select a new optimization.

The subsequent bounded native-variant ownership trial completed 468 paired
wall cells and 468 counter cells, following 156 smoke/stat checks and a
104-cell diagnostic screen. QBE tree wall time falls 8.1563% with 2.6607%
fewer instructions, while LLVM tree wall time rises 1.6608% despite 0.9942%
fewer instructions. VM aggregate timing remains roughly flat. It remains
unselected: LLVM tree string equality regresses 8.88%. Static review finds
extra native tag/region branches and larger evaluator code; the region
argument is dynamic, so a literal-zero shortcut has no existing proof.

A separate fresh-zeroed bool variant-store trial leaves aggregate instruction
counts effectively unchanged. Its 24-cell focused follow-up shows 4.733%
lower QBE VM equality wall time but no consistent string-equality gain. This
partial diagnostic does not establish a broad win and does not select the
candidate. The [variant compiler screens](../../experiments/lox-variant-compiler-screens-20261003/README.md)
retain both candidates' exact qualification/build reviews, all 1,580 current
observations, 223 stable guards per preparation, independent paired-arithmetic
checks and immutable archive receipts. Earlier failed/superseded preparations
are retained separately. Selected source/compiler and main remain unchanged.

A subsequent numeric-tag trial widens nine fresh-zeroed tag writes without
changing payload operations or control flow. All 156 smoke cells and 104
counter cells passed, with unchanged aggregate instructions. Its one-round
QBE cycle aggregate rises 1.4513% for VM and 0.1247% for tree; no QBE workload
improves by more than 1%. The screen supplies no broad benefit, so this trial
is also closed unselected without a wall matrix. The same compiler-screen
package retains its 260 rows, independent proof/build qualification and sealed
archive. These three variant trials now contain 1,840 validated observations.
