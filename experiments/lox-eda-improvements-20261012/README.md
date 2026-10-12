# Lox and EDA: five parallel improvements

Work in progress. Implements the [audited plan](../../docs/audits/lox-eda-improvement-plan-2026-10-12.md)
from audit commit `b854dbcd895bf81061b33bebc30328ceaa986972`.
`source/` is a new working copy of the previously qualified checked-ownership
applications; historical sources and benchmark evidence stay frozen.
`source-baseline.json` pins the initial application bytes.

| Worker | Assignment | Reserved application files |
| --- | --- | --- |
| P1 | Scalar VM frames and scoped instruction reads | `source/lox/vm.my`, new VM helper module; heap frame-layout patch goes through coordinator |
| P2 | Borrowed tree AST and separated mutable state | `source/lox/interpreter.my` |
| P3 | Scoped object queries | `source/lox/heap.my` excluding frame layout, `lox_strings.my`, `output.my`; other callers go through coordinator/P1/P2 |
| P4 | EDA AST traversal and fresh construction | `source/eda/*.my` except `kicad_sch_textbox.my` and its tests |
| P5 | Overlap scanning and index sorting | `source/eda/kicad_sch_textbox.my` and its tests |

Each worker owns its new uniquely named tests and `Pxx/` evidence directory.
Unlisted files and all compiler/runtime changes require coordinator reservation.
Five Sol 6.1 workers use low reasoning effort, separate worktrees, one pinned
compiler installation, and the shared build admission queue. No nested workers,
peer merges, historical evidence changes, pushes or unrelated branch updates.

The coordinator owns integration, manifests, full verification and timing windows.
Preserve the 3× fresh Zig runtime cutoff and all 60 benchmark case identities.
Report runtime, managed allocation traffic/peak, process RSS and compile costs
separately. Stop optimization at a green verification gate and report measured
differences for review. No performance or completion claims yet.
