# Lox and EDA: five parallel improvements

All five implementations are integrated. The complete registered verification
gate passed all 46 selected actions with stable inputs and no reused actions;
see [summary](verification-summary.json) and the [full receipt](verification-receipt.json.gz).
Both integrated applications passed the primary qualification: 75 Lox and 317 EDA
unit tests with leak checking, three 974-case Lox conformance runs plus smoke/GC
checks, 102 EDA golden comparisons and nine error cases across three arms.
The remaining build-mode matrix and full-workload measurements are in progress.

Implements the [audited plan](../../docs/audits/lox-eda-improvement-plan-2026-10-12.md)
from audit commit `b854dbcd895bf81061b33bebc30328ceaa986972`.
Application sources are frozen at `fcca1c13f92b4ef02b8ad2dcd7349cc45ec273eb`.
`source/` is a new working copy of the previously qualified checked-ownership
applications; historical sources and benchmark evidence stay frozen.
`source-baseline.json` pins the initial application bytes.

| Worker | Assignment | Reserved application files |
| --- | --- | --- |
| [P1](P1/handoff.md) | Scalar VM frames and scoped instruction reads | `source/lox/vm.my`, new VM helper module; heap frame-layout patch goes through coordinator |
| [P2](P2/handoff.md) | Borrowed tree AST and separated mutable state | `source/lox/interpreter.my` |
| [P3](P3/handoff.md) | Scoped object queries | `source/lox/heap.my` excluding frame layout, `lox_strings.my`, `output.my`; other callers go through coordinator/P1/P2 |
| [P4](P4/handoff.md) | EDA AST traversal and fresh construction | `source/eda/*.my` except `kicad_sch_textbox.my` and its tests |
| [P5](P5/handoff.md) | Overlap scanning and index sorting | `source/eda/kicad_sch_textbox.my` and its tests |

Each worker owns its new uniquely named tests and `Pxx/` evidence directory.
Unlisted files and all compiler/runtime changes require coordinator reservation.
Five Sol 6.1 workers use low reasoning effort, separate worktrees, one pinned
compiler installation, and the shared build admission queue. No nested workers,
peer merges, historical evidence changes, pushes or unrelated branch updates.

The coordinator owns integration, manifests, full verification and timing windows.
Preserve the 3× fresh Zig runtime cutoff and all 60 benchmark case identities.
Report runtime, managed allocation traffic/peak, process RSS and compile costs
separately. Optimization is stopped at the green verification gate; remaining
work records qualification and measurements for review. No full-workload
performance claims yet.

The worker probes remove the targeted copy costs. They also identify a capacity
tradeoff: P4's depth-24 parser probe reduces cumulative managed traffic from
45,472 to 15,136 bytes while peak live managed bytes rise from 5,536 to 10,880.
Fresh child transfer preserves spare list capacity. This is not a process RSS
measurement; capacity tuning is deferred.

The integrated Lox directory discovers 75 tests: the prior 65 plus six P2 and
four P3 tests. All passed with leak checking. The earlier P2 handoff's claim that
its `_tests.my` module required a separate provider run was incorrect: directory
discovery includes it, and these tests never invoke the clock native. The mode
matrix uses the actual production imports and retains the separate P1 CLI cases.
The initial qualification harness expected 69; its successful 75-test output is
preserved with an immutable command journal before resuming conformance.

EDA's first directory attempt recorded 184 passes and 133 native exit-70 failures.
That attempt is preserved in `qualification/eda-attempt1/`. The original cause is
unproven. The unchanged board module passed baseline, candidate and exact cached
protocol replays ([diagnosis](P4/diagnosis/README.md)); a fresh full run using a
private cache on `/tmp` passed all 317 tests with the same compiler, sources,
flags and leak checking. No tests were removed or assertions weakened.
