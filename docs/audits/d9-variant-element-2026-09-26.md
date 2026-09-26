# D9 immediate variant element copies

Compiler `f8dad8e8` lets a managed-list element read feed an immediate variant dispatch from its checked backing address. The dispatch still copies its chosen payload into private arm storage before anything can collect or mutate the parent. The optimization declines alternate control entry, owned payloads, address-projected arm bindings and any pending COW action at the dispatch. Generic element-borrow and box rules are unchanged.

For `vm::load_frame`, emitted blits fall from seven to five and their total static byte count from 200 to 88: both whole 56-byte Obj snapshots disappear. The selected payload copies remain.

Both Debug compilers build source `6d54bace`. Three interleaved instruction-count samples on CPU 10 use the mandated `pc.py` sizes and exact stdout checks. The candidate compiler SHA-256 is `2e5e577f14fd1e27462afbfc4e4d46a5421bdd81f8229b1c1ee01b1a69701434`.

| VM workload | QBE / af9b1318 | LLVM / af9b1318 | QBE / baseline | LLVM / baseline |
| --- | ---: | ---: | ---: | ---: |
| binary trees | 0.9859 | 0.9871 | 1.3290 | 1.6635 |
| closures | 0.9775 | 0.9780 | 1.3427 | 1.5554 |
| fib | 0.9803 | 0.9735 | 1.0943 | 1.1540 |
| trees | 0.9782 | 0.9762 | 1.1059 | 1.2575 |

All stdout checks pass. This remains a targeted comparison, not acceptance: binary trees and closures still exceed 1.30, and a joined compiler must run all 43 workload keys per backend. The baseline remains exact `60b668cf`.

Validation: 25/25 focused COW tests; three new guest tests on each backend under native GC stress, including parent replacement and growth before a saved payload read; 44/44 successful byte-identical legacy IL comparisons. The final full gate passes 93/93 main steps (2,090 selected tests; some preceding focused verdicts cached), 51/51 QBE steps (428 tests), 29/29 build steps and 2/2 formatting steps. Guardian passes all 88 checks.

Raw evidence: [instruction samples and hashes](evidence/d9-variant-element-perf.json), [44-input switch-off comparison](evidence/d9-off-il-f8dad8e8.json).
