# Lox and EDA: five parallel improvements

All five implementations are integrated. The complete registered verification
gate passed all 46 selected actions with stable inputs and no reused actions;
see [summary](verification-summary.json) and the [full receipt](verification-receipt.json.gz).
Both integrated applications passed the primary qualification: 75 Lox and 317 EDA
unit tests with leak checking, three 974-case Lox conformance runs plus smoke/GC
checks, 102 EDA golden comparisons and nine error cases across three arms.
Both applications also pass all five ownership build modes (verified release,
release, unoptimized debug, optimized debug and release without facts), with
zero cached unit outcomes. See [matrix summary](matrix-summary.json).

The runtime protocol processed all 60 frozen cases: the improved checked source
completed **50/60**, versus **1/60** for the previous checked source. Ten candidate
cases hit the requested 3× fresh Zig cutoff and retain no exact runtime ratio.
These are application source improvements on one unchanged compiler.
All 50 runtime-eligible checked cases also completed separate counter runs with
zero RC/uniqueness events and zero managed bytes live at exit.

| Completed subset | Complete | vs Zig Fast | vs Rust | vs Go |
| --- | ---: | ---: | ---: | ---: |
| Lox tree | 12/13 | 1.634× | 1.276× | 1.150× |
| Lox VM | 11/13 | 2.360× | 1.596× | 1.679× |
| EDA | 27/34 | 1.800× | 1.596× | 0.646× |

Ratios are geometric means over completed pairs only; lower is better.
The cutoff cases prevent full-group scores. See [comparison](COMPARISON.md) and
[every test as a percentage of Zig runtime](ZIG-PERCENTAGES.md).
Tree equality, the only completed direct checked before/after pair, runs at
0.483× its previous time and reduces allocation traffic from 2,700,085,496 to
63,762,456 bytes (97.6%). Managed peak falls from 7,398,384 to 6,065,504 bytes;
median process peak RSS falls from 10,240 to 6,724 KiB. These metrics are distinct.

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
work records qualification and measurements for review. Completed-subset
comparisons do not establish performance on the censored cases.

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

The EDA no-facts matrix initially failed before test execution because `/tmp`
enforces a per-user quota despite ample global free space. The failure and
original journal are preserved under `matrix/eda/no-facts-attempt1/`. The same
317 tests passed using a fresh cache and temporary directory on the main disk;
compiler, sources, flags and leak checking stayed unchanged.

The first compile-timing attempt is preserved in `compilation-polling-attempt1/`
and excluded from final ratios. Python's timed wait quantized short warm builds;
the corrected harness uses a blocking wait with a separate deadline timer. All
six cold/warm pairs were repeated, with fresh caches and unchanged sources.

The final VM trees RSS block was interrupted when expected-output files disappeared
from an external worktree cache. All 26 expected files were recovered from tracked
historical copies with matching SHA256 pins. Only the incomplete RSS block was
repeated for all eligible arms; no wall sample or inherited timeout was replaced.
The original journal, frozen harnesses and explicit recovery versions are retained
in [input recovery](input-recovery/README.md).

Review artifacts are [results.json](results.json), [per-cell.csv](per-cell.csv),
[runtime samples](runtime-summary.json.gz), [raw evidence](raw-evidence.tar.gz)
and its [readback-verified manifest](raw-evidence-manifest.json). The
[coordinator handoff](handoff.md), [item ledger](item-ledger.json) and
[code input proof](code-input-proof.json) record exact revisions and qualification
boundaries. The selected checked guest binaries pass the recorded RC audit;
this source-only application batch does not claim default promotion, package-wide
RC removal or legacy compatibility retirement.

The RC source control exposes a separate performance tradeoff: rewritten VM
source takes 1.156× the original RC source runtime across all 13 cases; eight
case medians are over 5% slower. Tree improves to 0.833× and EDA is 1.000×
overall under RC. This compares different sources, not an isolated memory-mode
effect. Its exact VM hot-spot cause is unprofiled and remains for review.
