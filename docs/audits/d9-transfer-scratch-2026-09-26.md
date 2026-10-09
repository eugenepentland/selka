# D9 transfer scratch and alias storage evidence

Compiler commit `adcbb4ca` removes a redundant aggregate operand snapshot before a real COW transfer, removes ownership-elided match-binding self-stores, and omits clearing unused physical alias slots. Reads and GC roots continue to resolve aliases to the canonical slot. The previous cold failure-result clearing optimization now applies only in value-semantics mode.

The Debug compiler SHA-256 is `6961ce9eae4b97bc8a1db8fe15e5dce6d94eca713537798d0b6ed5f578222ff9`. Both compared candidates compile the same deferred-IP Lox source (main SHA-256 `18c1f669b1683123e635256c9f66c6db2766383391371c3822e61df7d9732274`). The exact `60b668cf` baseline compiler SHA-256 is `48427e9ac1c01b74e60d1b4c098c8fc149a6b5fef3c07e110c7fb4ba16cbb545`.

`pc.py` provides calibrated sizes, exact stdout checks and instruction counters. Three interleaved samples per candidate run on CPU 10; table ratios compare median retired instructions against compiler `9f42e5a9`.

| VM workload | QBE | LLVM |
| --- | ---: | ---: |
| binary trees | 0.9461 | 0.9938 |
| closures | 0.9192 | 0.9923 |
| fib | 0.9228 | 0.9911 |
| trees | 0.9415 | 0.9956 |

Actual QBE assembly memset call sites fall from 24 to 2 in `vm::run`, 43 to 18 in `interpreter::execute`, and 1 to 0 in `heap::push`. LLVM already removes most unused clears, so its improvement is smaller. These eight samples isolate the compiler change; they are not D9 performance acceptance. Several ratios against the baseline still exceed 1.30.

Switch-off emission matches the exact historical compiler byte-for-byte on all 44 parity inputs. The two module-using inputs (`sort_records.my`, `text_ops.my`) use project emission; all compiler invocations succeed. Every function, entry and runtime-data IL section is compared.

Validation: full gate passes 93/93 main steps (2,095 selected tests), 51/51 QBE steps (428 tests), 29/29 build steps, and 2/2 formatting steps. Returned-payload snapshot guests pass on QBE and LLVM under native GC stress. Guardian passes all 88 checks.

Raw measurements: [eight-key samples](evidence/d9-transfer-scratch-perf.json) and [44-input switch-off comparison](evidence/d9-off-il-adcbb4ca.json).
