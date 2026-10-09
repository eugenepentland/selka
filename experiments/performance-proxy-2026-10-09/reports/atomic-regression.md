Juice: reference-improved → reference-atomic
Baseline 100; lower means fewer instructions per completed unit, not proportionally less time.

| Workload | Juice | Assessment | Repeat range |
|---|---:|---|---|
| bits-quick | 102.884 | more-work | 102.884–102.884 |
| bits-validation | 102.912 | more-work | 102.912–102.912 |

Selected-scenario index: 102.898 (weighted geometric mean).
Unchanged means within ±0.1%. Coverage: selected scenarios only.
Repeat ranges are observations, not confidence intervals.

bits-quick:

- static atomic_sites increased (0 → 1); hotness unresolved
- atomics per completed unit increased
- process_records: +1.000 instructions/record ({root}/kernel.c)
- 0x0000000004001400: +0.000 instructions/record (???)
- 0x00000000040013e0: -0.000 instructions/record (???)

bits-validation:

- static atomic_sites increased (0 → 1); hotness unresolved
- atomics per completed unit increased
- process_records: +1.000 instructions/record ({root}/kernel.c)
- 0x0000000004001400: +0.000 instructions/record (???)
- 0x00000000040013e0: -0.000 instructions/record (???)

Runtime estimate: uncalibrated.
