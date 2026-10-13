The atom-operand shape is rejected for adoption. Its string-equality improvement
accompanies consistent numeric/control regressions and larger RSS. Coordinator
confirmed this decision; no production application or compiler was changed.

The independent untouched baseline and atom candidate are copied from frozen C2
source-002/lox and built with identical release/checked flags using compiler
9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a.
Only candidate interpreter.my differs: binary/logical operands first try literal
or resolved-local reads, preserving checked AST/env/slot/stack access and push;
every complex/global expression falls back to unchanged evaluate. The left value
is pushed before the RHS; logical short-circuiting still decides whether the RHS
runs. No AST/object view escapes, no roots disappear and no arithmetic overlay
is applied. Arithmetic experiment snapshots remain immutable.

Both verified canonical suites passed 103/103 with failed/skipped/unsupported/
cached zero. Twenty-eight source correctness runs passed in paired normal/stress
arms, including global/undefined/error-order controls, short-circuiting, RHS local
mutation and a forty-deep allocating RHS retaining the left string under GC.
Nineteen public AST/negative-index/bounds/kind/stack/order probe modes matched
exact exit status, stdout, error category/message and structured trap. Source
locations/call traces change as expected. Accepted negative AST/stack/slot/hops
semantics and short-circuiting an invalid RHS are preserved. Initial probe-only
fixtures failed because a Token owner was reused; raw failure logs and original
wrapper bytes are retained. Explicit Token.copy fixed the fixture; timed source
snapshots were never modified. Source/root/compiler/native/probe identities and
all commands/output/assembly are retained.

Native atom-helper true branches bypass recursive evaluate calls at binary
0x106bc2b/0x106bce4, with equivalent conditional fallback for logical operands.
The helper has an eight-byte stack prologue and no recursive interpreter calls;
original evaluate uses 1,208 bytes plus six saved registers. However candidate
evaluate now reserves 1,752 bytes (+544), and binary is newly outlined with a
1,208-byte frame. Related evaluator/helper code grows 8,861 -> 10,123 bytes.
These are actual native tradeoffs; frame/layout growth is not proven to be the
sole cause of the observed regressions. No whole-Runtime copy is inferred from
LLVM signatures.

Root-approved diagnostics started only after P3's six leases completed. Exact
existing fib.tree.28, binary_trees.tree.10 and string_equality.tree.10000 inputs
and outputs, unchanged pinned Zig, untouched C2 and atom-only candidate used CPU8,
two warmups and nine alternating paired rounds in three exclusive chunks/case.
Fresh Zig calibration preserves the 3x cutoff/120-second ceiling. All 81 wall
samples passed; no samples were failed, censored, trimmed or excluded. Twenty-seven
additional uninstrumented child peak RSS observations (three per arm/case) ran
separately after each case's nine wall pairs and are excluded from wall summaries.
All calibration, warmup, progress, wall/RSS receipts and identities are retained.

| Case | Candidate / C2 paired median | 95% median interval | C2 RSS median KiB | Candidate RSS median KiB |
| --- | ---: | --- | ---: | ---: |
| fib | 1.01961 | 1.00316–1.02495 | 5400 | 5584 |
| binary_trees | 1.04367 | 1.03559–1.05084 | 6916 | 7048 |
| string_equality | 0.97819 | 0.96591–0.99029 | 6268 | 6400 |

Intervals use 10,000 bootstrap resamples of nine complete pairs, seed42. These
small diagnostic samples establish the rejection decision, not full-suite parity.
The 2.18% string improvement does not justify 1.96% fib and 4.37% binary-tree
slowdowns, together with 1.91–3.41% higher process RSS. RSS is separate coarse
process peak data; no managed peak/traffic claim is made. Effects are not multiplied
with any other experiment, and no additional repetitions/prototypes were run.
Historical evidence, coordinator/peer source, micro campaign and local uncommitted
heap dependency remain unchanged. No push or feedback-log addition.
