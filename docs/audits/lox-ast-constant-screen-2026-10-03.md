# Lox AST/constant instruction screen — 2026-10-03

This is a historical checkpoint. The selected AST source and completed repeated
results are in [the newer report](lox-ast-carrier-checkpoint-2026-10-03.md).

The two next source candidates compose cleanly and pass qualification. A
complete one-round instruction screen shows less dynamic work in both tree
backends and in the LLVM VM. The canonical source remains the accepted
84-test checkpoint while three-round wall-time measurements run.

| Candidate | LLVM VM instruction reduction | QBE VM | LLVM tree | QBE tree |
| --- | ---: | ---: | ---: | ---: |
| Inline AST call/class matches | 0.0000% | approximately 0% | 1.7871% | 2.0784% |
| Readonly constant pool helper | 1.0547% | 0.0473% | approximately 0% | approximately 0% |
| Both | 1.0547% | 0.0473% | 1.7871% | 2.0784% |

These are geometric means over all 13 Lox workloads per engine. The screen
contains 208 matched source cells with exact outputs and all 832 PMU running
percentages equal to 100. Repeated wall-time and counter results will determine
whether these candidates become selected performance changes. Rust/Go parity
remains unmet in the [accepted checkpoint](lox-callee-table-checkpoint-2026-10-03.md).

The AST refactor keeps the expected match-arm operations and their order while
eliminating two owning getter returns. The VM refactor keeps the checked operand
read, IP increment, constant read and stack write in their original order. It
passes the frame readonly for the pool read. Bounds, overflow, COW and root
protocols remain enabled. The composed source changes four files and adds one
constant-operand boundary test, giving 85 public tests.

Fresh composed qualification passed 340 public tests across LLVM/QBE and
RC/native-GC-stress modes. Four additional explicit provider-backed executions
of the new boundary test passed. Actual unaccounted native guests passed 1,168
bounded comparisons, 12 operand-boundary comparisons and 96 AST call/class/root
and error comparisons. Eight checked RC refusal pairs matched. The matrix
retains its 80 explicit native-stress smoke omissions. Public Lox error streams
match exactly; internal malformed-node/bytecode native helper attribution and
tight source-step cutoffs remain outside those native parity claims.

The measured compiler and QBE are the unchanged selected `d14a7040…` / `99ad919d…`
pair. A fresh reproduction helper reconstructs all four complete 37-file sources
independently of future canonical migration changes. It reproduced all eight
mylang guests and Rust byte for byte and passed 260 ten-arm smoke checks. Fresh
Go has distinct path metadata and serves as behavior evidence; performance
measurements retain the original frozen Go ELF.

Exact receipts, source maps, scripts and reproduction commands are in
[the experiment](../../experiments/lox-ast-constant-20261003/README.md). The
source reviews and full native qualification are separate experiment records.
The original dirty checkout and `main` remain unchanged.
