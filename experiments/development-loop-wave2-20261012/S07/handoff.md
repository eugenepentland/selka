# S07 scoped calibration and headroom

Base B0: `c1857310e0bf623545380c8de24515f1b9970021`.
Own branch `codex/dl-wave2-20261012-S07`; owned sources:
`verification_budgets.py/tests` and `verification_policy.py/tests`.
No shared build/configuration/cache-session/CLI, native runner, runtime, ABI,
Guardian implementation, or default execution policy files changed.

## Passed behavior

Policy v2 adds explicit observation clocks while v1 defaults remain unchanged.
S01 native intervals use `supported_runner_protocol_interval_including_reporting`;
they cannot satisfy the Python setup/body/teardown individual-test clock.
Different clocks have independent policy entries and are never added as wall time.
The adapter maps each validated `tests[]` row's actual `elapsed_scope`; unsupported
scopes remain unavailable. Supported Python legacy rows retain their existing
report-only evaluation, without gaining calibration evidence.

The existing `evaluate_scoped_policy` path now includes bounded per-entry
calibration reports. `calibrate_scope(entry, observations, cohort=None)` is the
standalone collector/evidence API. Rows match exact action/member/test/scope and
clock, and require fresh, complete, successful work with no timeout/cancellation,
incomplete or truncated flags. Calibration further requires SHA256 provenance:
`context`, `action_key`, `measurement_context`, `run_id`, `evidence_sha256`;
`measurement_kind` is `isolated` or `operational`, and `sample_role` is
`calibration` or `validation`. S10 agreed to this collector contract.

The measurement-context digest must cover exact source/tool/mode/cache tiers,
CPU placement, flags and collector clock protocol. Those digests describe
collector provenance; this module does not authenticate arbitrary supplied rows
or grant success/reuse authority. The caller must verify capture artifacts and
manifest identities before supplying rows. Existing normalized test telemetry
without those fields still evaluates current advisory observations, but cannot
become calibration samples.

The latest complete compatible cohort in caller order is selected explicitly in
the result; the caller may instead pass all four cohort fields (context,
action_key, measurement_context, measurement_kind). Duplicate run IDs count once.
Conflicting rows for one run are rejected entirely, including attempts to use a
training run as validation. Each role retains at most 64 distinct compatible runs.

Per-target results separate training from independent holdout: observed maximum,
remaining headroom, maximum/threshold ratio and exceedance count. Missing or
fractional byte/work measurements, mismatched work units, missing capture proof,
unresolved declared evidence, missing holdout and operational-only samples are
explicit gaps. Aggregate memory cannot be inferred from process RSS. No nested
elapsed durations are summed. Report serialization validates the observation list
once per public evaluation rather than once per policy entry.

Five compatible samples may provide a descriptive median expected cost. They do
not calibrate deadlines, tail safety or enforcement. Every calibration reports
`qualification=not_qualified`, `enforced=false`; enforced policy mode is rejected.
No hard deadline, memory or work limit is inferred from expected cost, regression
thresholds, the ordinary-edit 5-second goal or 15-second p95 goal. User-configured
ProcessLimits remain separate. Policy/advisory changes keep execution_identity={};
derived scoped-policy reevaluation cannot inflate legacy report sample counts.

## Actual evidence and explicit expensive exceptions

The two prior frozen C1 operational warm reports provide two compatible named-step
observations for each of 22 members. `legacy-evidence-audit.json` records original
report SHA256s; `legacy-operational-calibration.json` preserves collected values,
context/action keys and provenance. Every member remains insufficient_samples.
These are prior-closeout cohorts, not wave2 final compatibility evidence or
independent admitted-action clocks. Shared gate durations cannot be allocated to
individual groups. No isolated timing, hard limit or headroom acceptance is claimed.

`legacy-expensive-exceptions.json` archives seven named report-only exceptions:
core, broad units, golden corpus, authenticated native components, language modes,
doctest and guest checks. All five target types are explicitly null. Each exception
has a concrete reason and review criteria preserving cold/authentication/fact/leak,
complete test inventories, cache tiers and clock meaning. No action is automatically
reclassified. `legacy-scoped-evaluation.json` runs that policy through the real
adapter against a successful stable frozen warm report: seven admitted-action
scopes remain unavailable, because compatible individual admitted-action durations
were not captured. This is the truthful current verdict.

## Validation

- Focused policy tests: 19/19 passed; focused budget tests: 16/16 passed.
- Related existing verification Python suites: 192/192 passed before the final
  scoped calibration serialization/clock-identity refactor; the affected 35 focused
  tests were rerun afterward and passed.
- `git diff --check` passed. Raw outputs are the three `*-tests.log` files.
- Native builds/full gate/timing were not launched. Source/tool/cache environment
  initialized from `/home/epentland/.config/mylang/dev-env.sh`; normal commit hooks
  run under build admission with pinned Zig/private local cache/disk TMPDIR/shared
  global cache. No feedback log entries.

## Coordinator integration and remaining qualification

The existing budget adapter adopts these reports with no shared-file patch.
S01 confirmed elapsed_scope occurs on every validated tests[] row. S02 confirmed
worker_seconds runs after dispatch/admission validation through owned-lineage
closeout and queue time is separate; a multi-action shared gate still cannot
establish individual action elapsed time. S10 agreed to explicit current-context
capture/role provenance and independent holdout; whole guest CLI/output-validation
loops keep their own clock and are not relabeled as individual tests or admitted
policy actions.

Verdict: compatibility, held-out reporting, exact clock separation and rejection
controls PASSED in bounded meaningful fixtures; actual prior operational evidence
correctly remains NOT QUALIFIED. Current final compatible isolated captures,
independent holdout, aggregate concurrent memory/work, broad adverse headroom and
per-action scheduling remain required before any enforcement proposal. No hard
controls or graph serialization were proposed. S10 owns those measurements and
coordinator owns any later enforcement adapter/inventory/CLI changes.
