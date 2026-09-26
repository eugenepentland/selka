# D9 VM performance after direct frame loading

This 26-key sweep combines Debug compiler `adcbb4ca` with Lox source `6d54bace` (deferred IP publication, compact execution frames and direct match frame loading). It uses the exact `60b668cf` baseline, the mandated `pc.py` harness with tree-calibrated VM sizes, three interleaved instruction-count samples per binary on CPU 10, and exact stdout checks. All 26 candidate/baseline checks pass; hashes, raw samples and cycles are recorded in [the evidence](evidence/d9-vm-direct-frame-perf.json).

The compiler is the isolated performance branch, without the subsequent recursive-box and nested-container corrections. Final acceptance requires a joined compiler and all 43 workload keys on each backend. This sweep does **not** pass: the VM-only geomean is 1.19444 on QBE and 1.35771 on LLVM, with 4/13 and 9/13 keys respectively above 1.30.

| VM workload | QBE / baseline | LLVM / baseline |
| --- | ---: | ---: |
| binary_trees | 1.3746 | 1.7318 |
| closures | 1.4144 | 1.6569 |
| equality | 1.0551 | 1.2026 |
| fib | 1.1504 | 1.2504 |
| instantiation | 1.3071 | 1.3838 |
| invocation | 1.1901 | 1.3280 |
| method_call | 1.3058 | 1.6310 |
| properties | 1.1534 | 1.3025 |
| string_equality | 1.0610 | 1.1036 |
| strings | 1.1306 | 1.2231 |
| trees | 1.1584 | 1.3385 |
| zoo | 1.1451 | 1.3235 |
| zoo_batch | 1.1450 | 1.3226 |
