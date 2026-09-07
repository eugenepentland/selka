# Interrupted attempts and recovery

This protocol applies to fixture and unscored calibration attempts now. New coordinator v2 receipts freeze this protocol alongside coordinator source and
runtime identities. Before scored launch, review the frozen protocol and validate
the adjudication workflow described below. Scored launch remains
disabled. This document does not authorize retries or certify an interrupted run.

## Preserve the assigned attempt

An assigned attempt remains in the cohort denominator after a transport failure,
worker termination, environment drift, timeout, or invalid model response. Keep
its reservation, initial source, working tree, captured submissions, requests,
responses, phase reports, launch output, and interruption records. Do not delete
or overwrite an attempt, rename a replacement as the original, or edit its saved
configuration to make it resumable.

A public check failure is an ordinary participant outcome. Rechecking and repairing
within the original active phase and budget is permitted. An exhausted phase
budget or token threshold is an outcome, not an infrastructure retry opportunity.
An unfinished model response or missing usage is recorded by its actual stop
reason; it does not automatically qualify for a replacement attempt.

## Establish whether execution has stopped

First inspect the actual launch process/session handle. Poll a confirmed live
handle; an output timeout alone does not establish termination. Saved PID files,
locks, and old status messages alone do not prove that a worker is alive or dead.
PID reuse must be excluded before taking action against a process. New launch records include kernel start ticks, boot ID, and PID namespace. Use
those identities for read-only liveness observations. Legacy PID-only records
remain insufficient for unattended recovery or process termination.

If the coordinator was killed, verify that its child execution has stopped before
reviewing final artifacts or scheduling competing work. Existing parent-death and
process-group cleanup reduce orphan risk, but do not replace checking the actual
process state. If identity or liveness cannot be established, classify recovery as
unresolved; do not launch a duplicate or kill an unrelated process.

## Review the retained evidence

Record the assigned session ID, cohort hash, launch directory, phase, observed
stop reason, and hashes of the evidence used. Separate observations from attributed
causes. A RuntimeError alone does not establish provider failure, and a rejected
program does not establish a language defect. Mark uncertain causes as unknown.
Never include credentials in review notes.

Use these review categories:

- `participant-outcome`: ordinary completed, abandoned, public-check or budget result.
- `transport-interruption`: evidence establishes a failed or interrupted model request.
- `harness-interruption`: evidence establishes a coordinator or isolation failure.
- `environment-invalid`: source, tool, runtime, or configuration drift invalidates the attempt.
- `unknown`: retained evidence cannot establish a narrower category.

Keep behavioral acceptance, observed termination, and human attribution separate.
Review attribution must not overwrite grades or alter the all-assigned denominator.

## Timing, usage, and grading

Do not pause or extend a running phase clock after seeing a failure. Do not resume
a stopped model loop with extra turns, a fresh transcript, or a reset token limit.
The current implementation intentionally refuses silent restart; it has no supported
mid-phase model resume operation.

Retain completed preparation time even if the task later fails. Report tokens from
completed phase receipts separately when no final driver report exists. Missing
request usage and unfinished task time remain unknown; do not infer zeros or billable
cost from them. Partial observations do not establish complete attempt totals.

Hidden grading is a separate operation. It may resume only through an existing
supported grading entry point that validates unchanged source, inputs, adapters,
and identities. A rejected resume must remain visible. The fresh scheduled grading
wrapper currently refuses an existing output directory: lower-level resumability
does not imply that the outer wrapper supports recovery. Do not bypass frozen
configuration or provenance checks to finish grading an interrupted driver.

## Further attempts

For unscored calibration, a new practice run can be useful after the cause is
understood and fixed. Preserve the original run and use a newly declared schedule
or cohort when the original reservation is already consumed. Identify the new run
as additional calibration. Never use it to erase the first run's time or failures.

For scored trials, any replacement rule must be specified before launch, including
eligible evidence, reviewer process, maximum replacement count, and analysis of
both original assignments and replacements. No such rule is currently enabled.
Changes to the model, toolchain, harness, task, or budget require a new frozen cohort;
do not pool it with an earlier cohort without reporting that change.

## Remaining implementation

The current artifacts preserve failure evidence and refuse overwrite, but automated
recovery is not implemented. The `adjudication` module now appends evidence-bound human review records outside
the participant session. Coordinator v2 now carries the full policy text and its hash into the cohort.
A reviewed rule for any scored replacements remains required if replacements are enabled. The read-only process identity helper supports liveness observations; it does
not authorize unattended recovery or process termination. Neither a document nor a green fixture test substitutes
for actual calibration and launch review.


## Recording a review

```sh
python3 -m experiments.application_comparison.adjudication \
  --session /absolute/attempt/session --directory /absolute/private/reviews \
  --category unknown --reviewer reviewer-name \
  --reason 'The recorded exception does not establish a root cause.' \
  --evidence /absolute/attempt/session/driver/interrupted.json
```

Repeat `--evidence` for additional files. Each record captures the session identity
and manifest hash, evidence file hashes, policy hash, review category, reviewer and
reason. Corrections append another record; the earlier classification remains part
of the history. Session source drift can be reviewed without certifying that source.

The API writes numbered records under a lock and verifies their hash chain before
appending. This detects accidental edits and internal gaps; it is not a digital
signature or protection against a trusted filesystem writer rewriting the entire
chain or removing its tail. Preserve review artifacts with the study exports.
Evidence files are referenced by hash, not copied: retain the original artifacts.
Review records do not alter grading, choose a replacement, reset budgets, or certify
that a process has stopped. Cohort reports can incorporate these labels with `--reviews`; see below.


## Including reviews in a report

Pass `--reviews /absolute/private/reviews` to `cohort_summary`. The reader verifies
the record chain and records its head hash in the report. For each assigned session,
it selects the latest review matching the cohort, session ID, session directory,
and record kind. It rechecks the session manifest and referenced evidence hashes.
A missing or changed artifact makes that review stale; no earlier label is silently
substituted. Review notes remain in private records rather than summary output.

Per-attempt fields are `review_status`, `review_category`, and `review_sha256`.
Language totals show category and status counts. Only current reviews contribute a
category; an explicit `unknown` category differs from an unreviewed attempt. With
no review directory supplied, status is `not-requested`. No label changes grades,
assignment denominators, costs, or paired comparisons. A current label means its
evidence matches, not that an independent reviewer has proved the attributed cause.


## Frozen policy identity

New coordinator receipts retain the complete UTF-8 policy text and its SHA-256.
The cohort stores that receipt, so policy content is recoverable even after the
working document changes. Runtime receipt verification checks the current policy
alongside code and Python identities before and after execution. A changed policy
requires a new frozen coordinator/cohort; it cannot silently alter a calibration.
The fresh calibration entry requires coordinator v2. Legacy v1 receipts remain
readable for historical fixtures and do not gain policy attestation retroactively.


## Read-only process observations

```sh
python3 -m experiments.application_comparison.process_identity \
  --record /absolute/launch/process.json
```

New launch records identify the process using PID, boot ID, PID namespace and
kernel start ticks. The helper reports `live`, `not-running`, `different-process`,
or `unknown`. Zombies count as not running; stopped processes remain live. Missing
identity, a different boot/namespace, or unavailable process context remains
unknown. No signal is sent, budget reset, or retry authorized. A successful helper
exit means an observation was made, not that recovery is approved; inspect its
status. Unknown observations exit with code 2.

Observations are point-in-time evidence. Do not use a prior observation as authority
to signal a PID later: the process can exit or its PID can be reused between calls.
A kernel process handle would be needed for an identity-safe signaling operation;
this helper intentionally provides no signaling or automatic resume operation.
