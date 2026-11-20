# D9 roots on allocating transfer paths

Compiler `af9b1318` moves root publication for an inline COW transfer into its allocating fallback. The fast pointer checks and share-bit stores cannot collect. The fallback roots every live original local and operand, and the runtime roots its private output while replacing pinned descendants. Failure handling, root restoration, non-inline transfers, and arenas retain their existing behavior.

The Debug compiler builds the same `6d54bace` direct-frame Lox source as the preceding `adcbb4ca` compiler. Three interleaved instruction-count samples on CPU 10 use the mandated `pc.py` sizes and exact stdout checks. All compared stdout checks pass.

| VM workload | QBE / preceding | LLVM / preceding | QBE / baseline | LLVM / baseline |
| --- | ---: | ---: | ---: | ---: |
| binary trees | 0.9807 | 0.9731 | 1.3480 | 1.6853 |
| closures | 0.9712 | 0.9598 | 1.3736 | 1.5904 |
| fib | 0.9704 | 0.9480 | 1.1163 | 1.1854 |
| trees | 0.9759 | 0.9623 | 1.1306 | 1.2881 |

This targeted comparison is not acceptance: binary trees and closures remain above the 1.30 limit, and the final joined compiler must run all 43 workload keys on each backend. The baseline is the exact `60b668cf` compiler.

Validation: all 44 historical parity inputs compile successfully and have byte-identical switch-off IL against that baseline. The full gate passes 93/93 main steps (2,096 selected tests), 51/51 QBE steps (428 tests), 29/29 build steps and 2/2 formatting steps. The focused COW suite passes 24/24. Both new pinned and ordinary snapshot guests pass under native GC stress on QBE and LLVM. Guardian passes all 88 checks.

Raw evidence: [instruction samples and hashes](evidence/d9-inline-transfer-roots-perf.json), [44-input switch-off comparison](evidence/d9-off-il-af9b1318.json).
