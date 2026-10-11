# Advisory verification budgets

`verification_budgets.py` evaluates saved coordinator reports without running
verification or changing its success receipts. It preserves the existing guest
limits and explicit command deadline behavior. Hard deadlines default to `null`;
no recommendation enables enforcement.

```
python3 scripts/verification_budgets.py --inventory zig-out/verification/inventory.json \
  /path/to/archived-run-1.json /path/to/archived-run-2.json
```

Pass `--policy policy.json` to reevaluate existing observations against separately
named expected, regression and hard targets. Policy maps inventory action IDs to
`expected_seconds`, `regression_seconds` and `hard_deadline_seconds`. Each target
is a positive finite number or `null`; every result remains report-only. Changing
these advisory targets does not change execution or semantic evidence identity.
A policy hard target is descriptive metadata, not a command watchdog setting.

The coordinator API is `calibrate(reports, inventory, policy=None, context=None,
action_keys=None)`. `collect_report(report, inventory)` extracts advisory samples
and rejection reasons; `calibrate_observations(samples, inventory, ...)` evaluates
those saved samples. These functions never authorize reuse or publish success.

Samples require a successful overall report, a successful admitted gate, fresh
selected action evidence, and complete available untruncated logs whose parser
reports no malformed summary rows. Exact unique inventory member labels identify
the action. Cached summary rows, reused actions, duplicate labels or rows,
timeouts, cancellation, missing provenance and capture errors remain unknown.
Reports must prove `inputs_stable: true` and carry `action_metadata` matching the
provided inventory; changed membership or original member meaning remains unknown.
Reports need `budget_context` and action `action_key` SHA256 identities. The
inventory declares unique member labels in its top-level `action_metadata`.
Provenance retains the report digest, action contract, execution context, source
and observation index. Repeated reports contribute only one sample per member.

Only matching execution contexts and action contracts share a cohort. Callers may
choose the current context and contract keys explicitly; otherwise the last
accepted report selects the context and each action's last matching contract.
Different contracts are never pooled to reach a sample threshold. Input report
order expresses archive order; this helper makes no timestamp or freshness claim.

The report gives each named member's sample count, minimum, maximum and median.
Fewer than five unique compatible observations produce `insufficient_samples`;
no observations produce `unknown`. Five observations permit a
`report_only_candidate`: the observed median as an expected-cost suggestion and
1.5 times the observed maximum as a regression review suggestion. This is a
simple descriptive review policy, not a statistical confidence estimate or a
qualified latency guarantee. Shared-host operational samples do not establish
isolated performance acceptance. No percentile estimate is produced, regardless
of sample count; hard deadline recommendations stay `null`.

Member execution durations can overlap or nest. They are never summed, and full
action elapsed time remains explicitly unknown. Regression policy thresholds are evaluated against each named member
separately, with observed exceedance counts and an explicitly advisory status.
This does not evaluate whole action elapsed time. Missing CPU,
aggregate memory or work-count measurements are not inferred from elapsed time.

Input files and outputs are bounded to 2 MiB; at most 128 reports, 1,024 actions,
4,096 named members, 64 retained samples per member and 1,024 total retained
samples are supported. Samples beyond the retention limit keep the most recent
archive entries. Excessive or malformed inputs fail diagnostic evaluation rather
than executing work or altering verification status. Rejection reasons are capped
at 64. The standalone CLI returns 2 when evaluation is unavailable; the coordinator
must treat that diagnostic failure as unknown while preserving its real verdict.
