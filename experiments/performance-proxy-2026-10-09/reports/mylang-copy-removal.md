Juice: mylang-baseline → mylang-improved
Baseline 100; lower means fewer instructions per completed unit, not proportionally less time.

| Workload | Juice | Assessment | Repeat range |
|---|---:|---|---|
| sum-quick | 84.327 | less-work | 84.327–84.327 |
| sum-validation | 83.728 | less-work | 83.728–83.728 |

Selected-scenario index: 84.027 (weighted geometric mean).
Unchanged means within ±0.1%. Coverage: selected scenarios only.
Repeat ranges are observations, not confidence intervals.

sum-quick:

- alloc_bytes: 2099904 → 192 (allocator-dependent)
- allocs: 67 → 3
- free_bytes: 2099904 → 192 (allocator-dependent)
- frees: 67 → 3
- peak_live_bytes: 33000 → 192 (allocator-dependent)
- main.my:6 main::checksum / list_push: 262144 → 0 emitted executions (added or removed location)
- main.my:8 main::checksum / bounds_check: 262144 → 0 emitted executions (added or removed location)
- main.my:3 main::checksum / release_unique: 64 → 0 emitted executions (added or removed location)
- main.my:28 main::main / overflow_check: 64 → 0 emitted executions (added or removed location)
- main.my:26 main::main / overflow_check: 0 → 64 emitted executions (added or removed location)

sum-validation:

- alloc_bytes: 16797888 → 192 (allocator-dependent)
- allocs: 515 → 3
- free_bytes: 16797888 → 192 (allocator-dependent)
- frees: 515 → 3
- peak_live_bytes: 33000 → 192 (allocator-dependent)
- main.my:6 main::checksum / list_push: 2097152 → 0 emitted executions (added or removed location)
- main.my:8 main::checksum / bounds_check: 2097152 → 0 emitted executions (added or removed location)
- main.my:3 main::checksum / release_unique: 512 → 0 emitted executions (added or removed location)
- main.my:28 main::main / overflow_check: 512 → 0 emitted executions (added or removed location)
- main.my:26 main::main / overflow_check: 0 → 512 emitted executions (added or removed location)

Runtime estimate: uncalibrated.
