# Coordinator handoff

All five requested application improvements are integrated and qualified. Further
optimization stopped at the green registered gate. Final performance outcomes are
reported in [COMPARISON.md](COMPARISON.md), with every cutoff retained.

## Identities and scope

- Integration branch: `codex/lox-eda-improvements-20261012`.
- Audit/integration base: `b854dbcd895bf81061b33bebc30328ceaa986972`.
- Frozen application implementation: `fcca1c13f92b4ef02b8ad2dcd7349cc45ec273eb`.
- Registered gate revision: `639d359d1c0f161eb90184d78b7c4a11c0511f76`.
- Compiler source: `8b7d59eba868775b1b8d7f64c54b07abdd23d470`.
- Compiler SHA256: `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.

These are source refactors in `source/lox/` and `source/eda/`, using the unchanged
compiler installation pinned by `build/{lox,eda}/build-receipt.json`. Historical
sources, foreign executables and old results were preserved. The canonical
example trees and language/runtime implementation were not replaced by this
experiment. [Code input proof](code-input-proof.json) records the unchanged
application and compiler/build trees across qualification and later evidence
commits. Full source, input and executable identities are checked by `report.py`.

Five Sol 6.1 workers with low reasoning effort worked in separate worktrees;
their source commits, file ownership, reduced probes and outstanding limitations
are recorded in [P1](P1/handoff.md), [P2](P2/handoff.md), [P3](P3/handoff.md),
[P4](P4/handoff.md) and [P5](P5/handoff.md). Shared `heap.my` changes were integrated
by the coordinator. No shared compiler/runtime contract change was required.

## Qualification

`scripts/verify_cache.py` ran directly with the pinned Zig, four native jobs and
8 GiB maximum RSS through its own shared admission. All 46 registered actions
passed, zero were reused, and inputs were stable. The full receipt is preserved
in `verification-receipt.json.gz`; `verification-summary.json` lists each action.
This is the complete registered verification profile; the distinct opt-in long
qualification profile was not requested or claimed.

Both applications pass checked ownership in verified release, release,
unoptimized debug, optimized debug and release without facts. Every mode has
75 passing Lox tests and 317 passing EDA tests, with zero cached, failed, skipped
or unsupported unit outcomes. The Lox matrix also runs 16 candidate CLI
regressions and 16 baseline controls per mode. Primary qualification additionally
passes three 974-case Lox conformance runs, smoke/GC checks, 34 EDA goldens across
three arms and nine EDA error cases across three arms. See `matrix-summary.json`,
`integrated-test-inventory.json` and `qualification/`.

The initial Lox harness expected the wrong test count; its successful 75-test
output and pre-resume journal are preserved. EDA's first exit-70 attempt is
preserved with an explicitly unproven cause; the unchanged application passed
fresh qualification. A separate EDA no-facts failure was traced to the per-user
`/tmp` quota. That exact mode passed with a fresh cache on the main disk, with
compiler, flags, tests and leak checking unchanged. See the README and P4's
diagnosis for original failures and recovery evidence.

Normal commit hooks run Guardian; no Guardian feedback log was changed. The
selected guest LLVM and native binaries pass the recorded RC-symbol audit.
Completed checked counter runs must have zero RC/uniqueness events and zero
managed exit-live bytes before the report can be generated.

## Measurement and reproduction

Source `/home/epentland/.config/mylang/dev-env.sh` in the integration worktree.
The complete pinned compiler installation lives under
`.tmp/text-gaps/coordinator/common-002/install/`; retain `bin`, `libexec` and
`tools` together. Builds and timing use the shared `MYLANG_SLOT_DIR`; other
sessions were allowed to finish rather than interrupted.

The run used `build.py`, `qualify.py`, `matrix.py`, `prepare.py`,
`schedule.py --group all`, `count.py --group {eda,tree,vm}` and
`compile_measure.py`. These are evidence harnesses, not commands to overwrite a
completed run. Use a new evidence/output root for another experiment. Runtime
dispatch permits resuming complete chunks only; it deliberately refuses an
interrupted chunk that needs explicit inspection.

All 60 original benchmark identities remain: 34 EDA, 13 tree and 13 VM. Each
completed case has two warmups, nine alternating wall samples and three separate
process RSS samples. Both checked arms use 3× the median of five fresh Zig Fast
calibration samples, with a 120-second ceiling. Timed-out arms retain the censor
status and do not receive invented runtime, RSS or counter measurements.

Counters are separate instrumented runs. RSS is child-process peak RSS, not
managed memory or an aggregate concurrent process-tree peak. Host snapshots at
both ends of each timing chunk document possible contention but do not prove
continuous isolation. Compiler measurements use three alternating before/after
cold/warm pairs; admission wait is excluded. The superseded polling-timer attempt
is retained and excluded from final ratios.

After measurement, `report.py` validates all 138 runtime receipts, 60 counter
coverage records, six compilation pairs and their pinned identities.
`archive_evidence.py` archives ignored raw runtime/counter files and independently
reads back every member against SHA256. The resulting report, CSV, JSON, archive
and manifest are the review artifacts. `ZIG-PERCENTAGES.md` gives the requested
per-test percentages against Zig ReleaseFast.

A late external-cache deletion interrupted VM trees RSS collection. All 26
expected-output files were recovered from tracked historical copies with matching
SHA256 pins. The incomplete RSS block alone was repeated for all eligible arms;
no wall sample or inherited timeout was replaced. Original journals and the
explicitly versioned recovery harnesses are preserved in `input-recovery/`.
See its README for the missing-input diagnosis and validated recovery.

## Remaining boundaries

P4's fresh construction retains spare capacity: its depth-24 reduced probe cuts
traffic from 45,472 to 15,136 bytes while increasing managed peak from 5,536 to
10,880 bytes. This measured tradeoff is retained for review. P3 preserves owned
snapshot accessors and mutation paths where scoped mutable union access is not
supported. Dense P5 overlap comparisons can remain quadratic; auxiliary storage
is the improvement. Remaining full-workload cutoffs require a separate tuning
decision, not weaker qualification or a higher deadline.

The rewritten VM source compiled under RC is 1.156× the original RC source
across 13 cases, with eight case medians over 5% slower. Tree improves to 0.833×
and EDA is 1.000× overall under RC. This source-control tradeoff is separate
from checked before/after performance; its exact VM hot-spot cause remains
unprofiled and further tuning is deferred.

The package still contains RC control/compatibility paths in this pinned compiler;
this application batch does not establish default promotion or legacy RC
retirement, and does not change bootstrap packaging. Lox's own tracing collector,
direct destruction and normal heap allocation remain valid. No pushes, local-main
advance or independent bootstrap merge were performed for this batch.
