# Development loop measurements and limits

Use `python3 scripts/verify_cache.py --zig /path/to/pinned/zig` for complete
verification with reusable evidence. The coordinator owns admission. The retained
`scripts/cache_session.py` accepts the same options through its `verify` request.
These developer commands do not change installed compiler or guest-test defaults.

`--profile complete` is the default. `--profile quick --quick-actions 3` schedules
at most three pending actions, prioritizing changed dependencies and inexpensive
work using explicitly heuristic hints. It reports outstanding required action IDs
in `profile_coverage` and returns 3 for partial feedback, even if all eligible
results were already cached. It cannot report complete verification. The next
complete request reuses qualified completed work and executes the remainder.
Cold preparation still builds the required native artifacts; quick selection
does not promise a five-second cold build.

`--profile long-qualification` runs the complete gate and reports the separate
fuzz and wall-clock qualification obligations. It returns 3 while those results
are outstanding; this profile does not itself run an external benchmark campaign
or establish self-hosting acceptance. The retained session accepts all profile
options in the existing `verify` request arguments. No additional scheduler or
scheduled job is installed.

The first development-loop pass adds optional limits and diagnostic reports:

| Option | Meaning |
| --- | --- |
| `--build-timeout-seconds N` | Deadline for each admitted inventory/preparation command |
| `--gate-timeout-seconds N` | Deadline for the admitted selected gate as a whole |
| `--warn-after-seconds N` | Advisory target for coordinator elapsed time excluding admission queues |
| `--budget-policy PATH` | Version 1 report-only policy with separate expected, regression, deadline, memory and work observations |

Values must be positive finite seconds. No new deadline is enabled by default.
Hard deadlines begin after admission and source revalidation, when the worker is
released. They do not include the queue, and they are command limits rather than
individual test limits. Changing an enforced limit conservatively changes receipt
identity; changing the advisory target preserves reusable evidence and pass/fail.
Scoped policies distinguish admitted action, setup/build and individual-test
clocks. Missing or incompatible measurements remain unknown. Policy loading errors
are reported without changing the test verdict. Automatic per-action enforcement
remains unqualified; a report-only deadline value never installs a watchdog.

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
Failed stability checks also retain bounded `stability_diagnostics`: snapshot
role, path or host facet, observed reason, and unknown/truncated status. An edit
restored to its old bytes still invalidates watch authority. Reading a diagnostic
does not clear dirty state. Retained-session runtime failures include the same
bounded reason in their restart message.

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
the build tool printed, including rounded minute durations. The verification
self-tests use a supported unittest collector that records every selected test,
its outcome and duration, and runner-process CPU/RSS. Each request uses fresh
temporary sidecars; reused results receive no invented fresh timings. Unsupported
native and guest per-test timings, full group durations, and aggregate concurrent
memory remain explicitly unknown. `action_coverage` includes every current action.
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

`text_scalar_unit` separates eight existing number-grammar/format tests plus one
root import test, including both embedded oracle files. Run
`scripts/focused_test.py text-scalar FILTER` or `zig build test-text-scalar-units`
through build admission. Unfiltered `test-units` includes both independent roots;
filtered `test-units` retains the compiler root and still rejects no matches.
The two independent roots use authenticated producer metadata covering executable
bytes, exact sources and embedded data, optimization mode, interface/ABI, and
the inherited build/Guardian/tool context. Missing or incompatible metadata keeps
the whole-artifact fallback. Other reviewed artifact selectors retain their
existing conservative source contracts. An unchanged wire schema alone never
authorizes replacement producer reuse.

The report's `action_budgets` evaluates the current request diagnostically. The
[budget evaluator](verification-budgets.md) combines archived compatible reports
and reevaluates advisory targets without executing tests. A single measurement
cannot establish a calibrated target. Failures, reused results, incomplete logs
and ambiguous timing rows do not become fresh samples. Hard limits remain opt-in
command controls, and no per-action deadline is enabled by calibration.

Remaining work includes native/guest individual timing, calibrated action limits,
qualified ordinary-edit latency, broader useful boundaries and full self-hosting. The
[DL1–DL8 plan](../audits/selka-development-loop-plan-2026-10-11.md) and
[bootstrap handoff](../audits/selka-development-loop-bootstrap-handoff-2026-10-11.md)
define the larger work and ownership. The active self-hosting branch owns compiler
porting; this tooling pass preserves its completion and performance requirements.
