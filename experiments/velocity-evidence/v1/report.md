# Velocity v1 evidence report

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
