# Development loop measurements and limits

Use `python3 scripts/verify_cache.py --zig /path/to/pinned/zig` for complete
verification with reusable evidence. The coordinator owns admission. The retained
`scripts/cache_session.py` accepts the same options through its `verify` request.
These developer commands do not change installed compiler or guest-test defaults.

The first development-loop pass adds optional limits and diagnostic reports:

| Option | Meaning |
| --- | --- |
| `--build-timeout-seconds N` | Deadline for each admitted inventory/preparation command |
| `--gate-timeout-seconds N` | Deadline for the admitted selected gate as a whole |
| `--warn-after-seconds N` | Advisory target for coordinator elapsed time excluding admission queues |

Values must be positive finite seconds. No new deadline is enabled by default.
Hard deadlines begin after admission and source revalidation, when the worker is
released. They do not include the queue, and they are command limits rather than
individual test limits. Changing an enforced limit conservatively changes receipt
identity; changing the advisory target preserves reusable evidence and pass/fail.

A timed-out command returns 124. Its isolated Linux supervisor terminates and reaps
owned descendants, including helpers that start new process sessions. After normal
command exit, descendants get up to two seconds to finish existing temporary-cache
cleanup; this time counts against the execution deadline and is interruptible.
Live descendants remaining afterward are incomplete execution, status 125.
Cancellation terminates the owned tree; another coordinator's work remains owned
by that coordinator. None of these incomplete outcomes publishes new success
receipts. A subsequent request can retry. The supervisor preserves inheritable
descriptors used by admission and child tooling. Admission's memory-settle helper
has separate ownership and retains its original delay after a worker finishes or
is cancelled.

`.mylang-cache/verification-v1/last-run.json` records admission wait, input validation,
worker duration, final validation, publication, selected/reused actions and the
advisory loop target. Preparation failures also record their stage and status.
Per-action `invalidation` compares exact selected file identities and common
identity fields with the previous stable request. The previous request may have
failed; these differences are observations, not proof that it produced a receipt.
Missing, corrupt or oversized diagnostic summaries yield unknown explanations.

File additions, deletions and content/metadata changes name their path. Common
tool, environment and build-configuration changes currently identify
the changed digest field rather than its individual members. The diagnostic files
are separate from successful execution receipts and cannot authorize reuse.

Bounded stdout/stderr captures are kept under `last-logs/{inventory,preparation,gate}`
in the same cache directory, with an 8 MiB ceiling per stream. They retain raw
command output locally and are overwritten on the next corresponding execution.
Report entries describe only captures made in that request. Captures, explanations
and report-storage errors are diagnostic and do not change the execution verdict.
Stream truncation and unavailable measurements are explicit.

Zig build summaries supply nested step durations, selected test counts and reported
per-process peak RSS. Registered actions have stable group/member labels that
also appear in the inventory's `action_metadata`. These steps may overlap: do not sum them to claim elapsed
gate time or aggregate concurrent memory. Test exclusions from sharding are
reported as skips, not unexecuted required coverage. Summary precision is whatever
the build tool printed, including rounded minute durations. Full group durations,
individual test timings, CPU time and aggregate peak memory are not yet measured.
The parser bounds bytes, lines and observation count separately from log capture.

The first dependency split introduces `juice_pure`: 29 reviewed synthetic
contract/parser/report/calibration tests. Nine native Python Runner tests and the
native collector checks remain in the fresh `juice` group; live runtime collection
remains fresh too. New test classes default to the fresh group. All original tests
remain required. Whole-compiler and common configuration identities remain
conservative; this change does not establish function-level Zig test reuse.

Inventory v2 binds each receipt to its own registered action membership. Global
coverage is still validated on every request; adding inventory metadata alone
does not invalidate unrelated groups. The coordinator recognizes the existing
data-only `build_test_inputs.zig` declarations and binds their expanded local
recipes. This projection also requires the reviewed build-configuration fingerprint;
changes to its consumers disable projection until requalified. Unrecognized syntax
retains broad configuration identity. Changes to `build.zig` and other common
execution semantics still invalidate all groups.

The independent `tooling_unit` group runs 27 named pure tooling tests (plus the
root import test) without linking the compiler. Its prepared artifact and declared
source closure are separate, so compiler-only edits can preserve its evidence.
The larger unit group still has broad source fixtures: edits to the extracted
tooling tests can still invalidate that group. This is a directional improvement,
not complete isolation of every native test dependency. Use `test-tooling-units`
or `scripts/focused_test.py tooling FILTER` to run the new root explicitly.

The report's `action_budgets` evaluates the current request diagnostically. The
[budget evaluator](verification-budgets.md) combines archived compatible reports
and reevaluates advisory targets without executing tests. A single measurement
cannot establish a calibrated target. Failures, reused results, incomplete logs
and ambiguous timing rows do not become fresh samples. Hard limits remain opt-in
command controls, and no per-action deadline is enabled by calibration.

Next steps are broader native boundaries, individual test timing, qualified action
deadlines and narrower producer identities. The
[DL1–DL8 plan](../audits/selka-development-loop-plan-2026-10-11.md) and
[bootstrap handoff](../audits/selka-development-loop-bootstrap-handoff-2026-10-11.md)
define the larger work and ownership. The active self-hosting branch owns compiler
porting; this tooling pass preserves its completion and performance requirements.
