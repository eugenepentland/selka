# Velocity iteration v1 results — 2026-09-08

All six language/tooling improvements are implemented. The eight application
retests all passed, but their summed delivery time increased **11.6%**. Recorded
commands fell **71 to 67**, failed commands **8 to 3**, and failed trusted checks
**1 to 0**. This cohort does not establish an overall developer-speed improvement
or a reduction in shipped bugs.

## Implemented changes

| Improvement | Delivered behavior and evidence |
|---|---|
| JSON/schema convenience | Extended the existing `std_json_view` typed-node API with immediate-child cursors, required/default fields, inclusive bounds and allowed-field checks. Defaults apply only to absent fields. Parser strictness and quotas remain intact. |
| Borrow syntax | Whole initialized `[..]` views and grouped independent loans preserve aliasing, lifetime and cleanup rules. |
| Application baseline migration | EDA/planner use checked schema helpers and direct literal output. Planner owners fell from 8 to 6 and borrow nesting from 8 to 1; planner `.selka` lines fell 661 to 619. These are structure measurements, not speed evidence. |
| Borrowed callback context | Synchronous explicit readonly context for generic callbacks; reusable heapsort, lower-bound and filter algorithms. No escaping captured context or borrowed callback return. VM/native and allocation-failure checks cover changed paths. |
| Combined project feedback | `scripts/project.py` combines checked source context and declared verification with compiler/source/test identities and exclusive per-attempt reports. Seven of eight agents used it; eight direct calls were recorded. Per-command caches/reports are retained but not reused across commands. |
| Export diagnostics | `E_EXPORT_PLACEMENT` explains the required declaration position and has a tested repair. The export grammar is unchanged. |

Implemented in commits `3edb3b4`, `a402ed1`, `3ed0d15`, `ce7c821`, `bf7b197`,
`1745a98`, `b0471ae`, `8048512` and `b6776e7`; readiness was committed in `eb05e80`.
The first three worktrees split JSON, borrow and callback work, with independent
integration reviews. The already-existing typed JSON API was extended, not invented anew.

## Validation and retained observations

The frozen compiler passed **57/57 build steps and 1,089/1,089 Zig tests**, plus
the default Python acceptance drivers. All **185 application-harness tests** passed.
The eight timed application sources passed **90 fresh and 90 historical private
case groups**, all eight full declared test manifests, and five additional historical
cycle limit groups. Twelve maintenance stages passed **1,920 fresh and 1,920
historical field observations**. All 20 application/maintenance source reviews
found no application defect.

Two generated Python test drivers could silently skip truncated results. Their
separate, untimed followups add strict result counts and complete timing membership;
positive regressions and deliberately truncated-response checks passed. Original
timed source, clocks and review findings are preserved in the evidence archive.

The first six maintenance stages used automatic first-check clock starts, whereas
historical clocks began before coordinator handoff. The audit found 15–27 seconds
of historical pre-command delay. Those runs remain supplemental, with no headline
speed percentage. Six fresh stages repeated the original handoff method. Their
sum was **266.336 versus 284.339 seconds (6.3% faster)**; all source files match the
historical and autonomous solutions. That small timing difference does not measure
adoption of the new syntax or libraries.

Concurrent VM optimization work (`53f1ed5` and subsequent local edits) appeared
after tool freezing. These trials used compiler SHA-256
`5c867506161594bbd489d481703da73a1fde4861fc1ef4719a776c09f76ed830` throughout;
the 1,089-test acceptance belongs to that frozen version. Concurrent host activity
was recorded and no elapsed times were corrected.


Across eight main tasks, recorded delivery time changed from 1150.759s to 1284.712s (+11.640%). This provides no aggregate speed improvement.

Working commands: 71 → 67; failed commands: 8 → 3; trusted-check failures: 1 → 0. Captured output bytes: 450366 → 2129057. These are not model turns or proven bug counts.

| Main task | Old seconds | New seconds | Fresh / historical accepted | Declared tests | Review |
|---|---:|---:|---|---|---|
| eda-clearance-boundary | 89.632 | 104.426 | True / True | True | approve_with_nits |
| planner-input-boundary | 95.026 | 90.867 | True / True | True | approve |
| eda-pin-roles | 198.711 | 183.832 | True / True | True | approve |
| planner-priority | 132.638 | 147.379 | True / True | True | approve |
| eda-rotation | 116.665 | 155.139 | True / True | True | approve |
| planner-cycle-groups | 147.458 | 205.704 | True / True | True | approve |
| planner-dependency-lags | 182.303 | 191.217 | True / True | True | approve |
| planner-slack | 188.326 | 206.147 | True / True | True | approve_with_nits |

Autonomous maintenance remains supplemental because its clock started at first check. The matched repeat uses explicit begin before handoff; gaps remain part of delivery time.

| Matched maintenance | Old seconds | New seconds | Old / new begin gaps | Fresh / historical accepted | Identical old / autonomous source |
|---|---:|---:|---|---|---|
| a-stage1 | 49.786 | 49.675 | 27.189 / 26.676 | True / True | True / True |
| a-stage2 | 39.737 | 37.849 | 14.682 / 11.616 | True / True | True / True |
| a-stage3 | 43.800 | 46.877 | 15.859 / 18.464 | True / True | True / True |
| b-stage1 | 50.971 | 53.537 | 27.309 / 22.954 | True / True | True / True |
| b-stage2 | 49.587 | 40.447 | 23.234 / 14.673 | True / True | True / True |
| b-stage3 | 50.459 | 37.950 | 24.824 / 11.365 | True / True | True / True |

Two review followups strengthened test completeness separately; timed sources and clocks remain unchanged.

Preparation validated 1089 language tests and 185 harness tests. The recorded preparation interval was 23:41:57–00:29:22 UTC, approximately 47.4 minutes wall time, not summed CPU time.

No aggregate application delivery speed improvement if elapsed total increases; command/failure reductions are observed proxies, not proven fewer bugs or model turns.
Background concurrent VM work was observed; elapsed results include scheduling interference and uncontrolled agent/dispatch variation.
Main trials changed syntax, standard library, baseline structure, workflow and test workload together; no individual feature effect or causal attribution.
Autonomous maintenance is excluded from historical speed comparisons because its clock began at first check.
Matched maintenance retains begin-to-first-command gaps without correction; identical small program solutions do not establish general development advantage.
Exact model identity, model turns, tokens and cost are unknown. Gateway output bytes are captured output, not model context.
Separate followup test repairs do not alter timed submissions, acceptance or clocks.

Next experiments:

- Repeat matched tasks with multiple fresh contexts, identical declared verification workload and randomized order.
- Separate syntax/library changes from workflow changes in controlled arms.
- Implement and independently test required standard-library mechanisms before freezing baselines or starting application clocks.
- Add a medium-size application with cross-module changes and meaningful error-handling requirements.

The JSON report contains complete cohort observations and source-file hashes/raw evidence references. Private case contents and seeds are omitted.

## Continuing the experiment

[Machine-readable results](../../experiments/application_comparison/evidence/velocity-v1.json),
[reviewed sources and coordinator snapshots](../../experiments/velocity-evidence/v1/README.md),
and the [append-only iteration index](../../experiments/application_comparison/evidence/velocity-iterations.jsonl)
retain this iteration. Complete private packs, sealed sources, per-attempt stdout/stderr,
cache reports and configuration receipts remain under
`/home/epentland/ai/canopy/application-trials/velocity-v1`.

Read-only completeness verification is `python3 -B final_report.py --check` from
that raw directory. Historical replays use `reporting/replay.py replay TASK` and
resume only matching completed receipts. An unfinished execution requires an
explicit retained recovery, never deletion and silent retry. Existing publications
are not overwritten; `final_report.py --output NEW_DIRECTORY` creates a new report.
Coordinator snapshots in the repo are provenance copies, not launch directories.

For v2, create a new raw directory and ledger, pin this iteration's evidence hashes,
freeze fresh private packs before participant access, and keep every failed attempt.
Inventory Python/Zig standard-library requirements first, implement/test missing
`.selka` facilities, review parity, migrate baselines and freeze tools before timing.
Use fresh contexts, identical verification requirements across compared arms, and
explicitly identical clock placement. Separate syntax/library and project-workflow
treatments; repeat before making aggregate claims. Extend to a medium-size maintenance
application after these controls are stable. Record preparation separately, preserve
null turn/token/cost fields when telemetry is absent, and append the next result to
the index rather than replacing this record.

Captured command output rose from 450,366 to 2,129,057 bytes, with one input-boundary
run contributing 1,450,467 bytes. This is output volume, not model-token telemetry.
A useful next tooling experiment is bounded default feedback with full reports retained;
it should be evaluated separately from mandatory-test workload changes.
