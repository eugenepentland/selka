Juice: pre-p1 → mylang-baseline
Baseline 100; lower means fewer instructions per completed unit, not proportionally less time.

| Workload | Juice | Assessment | Repeat range |
|---|---:|---|---|
| sum-quick | 100.622 | more-work | 100.622–100.622 |
| sum-validation | 100.075 | unchanged | 100.075–100.075 |

Selected-scenario index: 100.348 (weighted geometric mean).
Unchanged means within ±0.1%. Coverage: selected scenarios only.
Repeat ranges are observations, not confidence intervals.

sum-quick:

- linked library set changed; costs include library startup/work
- static atomic_sites increased (0 → 45); hotness unresolved
- semantic counter contracts changed

sum-validation:

- linked library set changed; costs include library startup/work
- static atomic_sites increased (0 → 45); hotness unresolved
- semantic counter contracts changed

Runtime estimate: uncalibrated.
