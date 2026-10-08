# FB1 slow-step ledger — 2026-10-08

No completed FB1 command exceeded five minutes uncontended. No check was weakened,
no timeout/threshold was raised, and no case or mode was dropped. Full timing,
affinity and concurrent-process records are retained in `logs/` and `commands/`;
`timing-index.json` indexes every JSON receipt with a wall time. Fuzz workers also
retain each build and execution's time in `fuzz50-final/*/commands.jsonl`.

The initial cold focused compiler build queued170.53s on bench admission and took
4.65s admitted (recorded separately). Final heavy commands acquire bench lock before
slot admission and run the timer inside the slot, so admission wait is separate
from admitted command time and actual reserved-CPU exclusion is visible.

| Step | Seconds | Receipt | Investigation |
|---|---:|---|---|
| package-full-gate-final | 153.809 | `logs/package-full-gate-final.json` | below five minutes |
| package-fuzz50-final | 133.521 | `logs/package-fuzz50-final.json` | below five minutes |
| package-full-gate | 106.493 | `logs/package-full-gate.json` | below five minutes |
| all46-final | 81.808 | `logs/all46-final.json` | below five minutes |
| all46-four-modes | 79.695 | `logs/all46-four-modes.json` | below five minutes |
| p1-applications | 38.974 | `logs/p1-applications.json` | below five minutes |
| package-frozen-conformance | 29.236 | `logs/package-frozen-conformance.json` | below five minutes |
| package-frozen-conformance-final | 27.253 | `logs/package-frozen-conformance-final.json` | below five minutes |
| p1-final-2 | 27.070 | `logs/p1-final-2.json` | below five minutes |
| install-debug-1 | 19.300 | `logs/install-debug-1.json` | below five minutes |

The native LLVM remark collector performs extra same-flags compiles, recorded in
its additive stats (`compiles` and nanoseconds). P1's complete collection takes
27.070s; no command required a speed investigation. A remark cache could reuse
exact tool identity, complete compile flags and emitted unit bytes, but is a
follow-up opportunity rather than a speed-rule blocker at the current timings.

CPU10 performance-budget receipts remain coordinator-owned while the user's
benchmark window forbids this package from using CPU10. Slot timings are not
substituted for those measurements.
