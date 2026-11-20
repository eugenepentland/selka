# M2 token-envelope calibration (replay of M1b evidence)

**This calibrates the envelope's arithmetic and how binding each candidate cap is on trajectories observed under NO token budget.** Every charge below is a per-call `outputTokens` value really produced by the M1b participant sessions, replayed against `budget.Envelope` at caps 0, 2,000, 5,000, 10,000 and effectively unlimited; none of those agents was told a budget, so this is not evidence about how agents behave when told one — that requires real sessions, which this does not run. Captured 2026-09-19T17:43:32.300336+00:00.

## What this does not measure

The replay charges an envelope over trajectories produced when the agent was NOT told any token budget. It therefore cannot show whether telling an agent its budget changes how it spends, whether an agent paces itself, or whether a refused call changes the next one: a budget-aware agent is a different system from the one that produced these calls. That behavioural question needs real sessions on the four dev cases (4 cases x 3 caps x 2 policies = 24 sessions); none was launched for this calibration, and the dev cases are not replayed here because no participant session has ever run on them.

## What was replayed

- Source: `experiments/diagnostic-feedback/cohorts/m1b` — 112 measured cells (4 arms x 14 cases x 2 repetitions), cohort `m1b`, model `deepseek-v4-flash`, reasoning effort `max`.
- The 14 cases are the **test split** the M1b cohort measured. The four dev cases have no observed trajectories, so nothing is replayed on them and no dev result is claimed.
- Per-call usage recovered from the harness session logs: 112/112 cells matched a session log, and 112/112 recovered per-call sums reproduce the run's own aggregate usage exactly (`inputTokens`/`outputTokens`/`reasoningTokens`/`cacheReadTokens`).
- Pool for the headline tables: every measured M1b session for the case (all four presentation arms, both repetitions), repetition first and the M2-matching `text` arm first inside a repetition — 112 sessions total, 8 per case.
- Sensitivity pool: the M1b `text` arm only — the M2 treatment match: the checker's plain-text output with no suggestion — in repetition order — 28 sessions total, 2 per case. Both pools are replayed at every cap; neither is described as anything but what it is.
- Missing or unrecoverable cells: 0.
- Machine-readable form: `experiments/diagnostic-feedback-m2/cohorts/calibration/calibration.json` — every cap x policy aggregate, the per-task rows behind it (including which candidate was selected for each task) and the 112 recovered trajectories.
- Observed outcomes come from each cell's `record.json` (`public_acceptance`, `hidden_acceptance`, `events.metrics.failed_compiler_invocations`); those sessions were also bounded by the M1b invocation limit of 20 compiler invocations, a different limit from the token cap replayed here.
- The measured sessions spent a median of 1 failed compiler invocation(s) (p90 2, max 9) while repairing — the loop the envelope is meant to bound, before any token cap.

## What the caps mean: measured generated tokens per call

| scope | calls | min | median | p90 | p99 | max | mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| headline pool (all) | 1,228 | 40 | 240 | 978 | 4,152 | 19,853 | 496.6 |
| sensitivity pool (text) | 299 | 40 | 222 | 1,015 | 4,151 | 9,849 | 476.5 |
| every measured session | 1,228 | 40 | 240 | 978 | 4,152 | 19,853 | 496.6 |
| family: bool-int | 135 | 52 | 219 | 506 | 1,068 | 1,595 | 285.2 |
| family: checked-result | 522 | 40 | 304 | 1,436 | 6,491 | 19,853 | 732.2 |
| family: generic-requirement | 439 | 40 | 221 | 798 | 2,331 | 5,023 | 365.7 |
| family: variant-coverage | 132 | 72 | 182 | 351 | 680 | 768 | 216.4 |

A whole measured session spends a median of 3,247 generated tokens (p90 9,820, max 82,040, mean 5,445.1, n=112). How many of the 112 measured sessions fit whole inside one envelope, by cap:

| cap | sessions that fit whole | share |
| --- | ---: | ---: |
| 0 | 0 / 112 | 0.0 |
| 2000 | 20 / 112 | 0.2 |
| 5000 | 82 / 112 | 0.7 |
| 10000 | 101 / 112 | 0.9 |
| unlimited | 112 / 112 | 1.0 |

## Replay results

Headline pool — every measured M1b session for the case (all four presentation arms, both repetitions), repetition first and the M2-matching `text` arm first inside a repetition:

| cap | policy | tasks | selected | cand. started | fit | overshoot-ended | unstarted | mean spend | median spend | mean spend / cap | public ok | hidden ok |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | repair | 14 | 0 | 0 | 0 | 0 | 14 | 0.0 | 0.0 | - | 0/14 | 0/14 |
| 0 | independent | 14 | 0 | 0 | 0 | 0 | 14 | 0.0 | 0.0 | - | 0/14 | 0/14 |
| 2000 | repair | 14 | 2 | 14 | 2 | 12 | 0 | 2,258.1 | 2,204.0 | 1.1 | 2/14 | 2/14 |
| 2000 | independent | 14 | 2 | 15 | 2 | 13 | 1 | 2,300.7 | 2,204.0 | 1.2 | 2/14 | 2/14 |
| 5000 | repair | 14 | 11 | 14 | 11 | 3 | 0 | 3,459.6 | 3,054.0 | 0.7 | 11/14 | 11/14 |
| 5000 | independent | 14 | 11 | 28 | 15 | 13 | 1 | 5,552.5 | 5,319.0 | 1.1 | 11/14 | 11/14 |
| 10000 | repair | 14 | 12 | 14 | 12 | 2 | 0 | 4,428.1 | 3,054.0 | 0.4 | 12/14 | 12/14 |
| 10000 | independent | 14 | 12 | 46 | 32 | 14 | 0 | 10,618.1 | 10,247.0 | 1.1 | 12/14 | 12/14 |
| unlimited | repair | 14 | 14 | 14 | 14 | 0 | 0 | 4,932.1 | 3,054.0 | - | 14/14 | 14/14 |
| unlimited | independent | 14 | 14 | 112 | 112 | 0 | 0 | 43,560.9 | 31,343.0 | - | 14/14 | 14/14 |

Sensitivity pool — the M1b `text` arm only — the M2 treatment match: the checker's plain-text output with no suggestion — in repetition order. The same replay on the like-for-like pool is the check that the headline numbers are not an artefact of pooling four presentation arms:

| cap | policy | tasks | selected | cand. started | fit | overshoot-ended | unstarted | mean spend | median spend | mean spend / cap | public ok | hidden ok |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | repair | 14 | 0 | 0 | 0 | 0 | 14 | 0.0 | 0.0 | - | 0/14 | 0/14 |
| 0 | independent | 14 | 0 | 0 | 0 | 0 | 14 | 0.0 | 0.0 | - | 0/14 | 0/14 |
| 2000 | repair | 14 | 2 | 14 | 2 | 12 | 0 | 2,258.1 | 2,204.0 | 1.1 | 2/14 | 2/14 |
| 2000 | independent | 14 | 2 | 15 | 2 | 13 | 1 | 2,296.3 | 2,204.0 | 1.1 | 2/14 | 2/14 |
| 5000 | repair | 14 | 11 | 14 | 11 | 3 | 0 | 3,459.6 | 3,054.0 | 0.7 | 11/14 | 11/14 |
| 5000 | independent | 14 | 11 | 25 | 16 | 9 | 0 | 5,036.1 | 5,056.0 | 1.0 | 11/14 | 11/14 |
| 10000 | repair | 14 | 12 | 14 | 12 | 2 | 0 | 4,428.1 | 3,054.0 | 0.4 | 12/14 | 12/14 |
| 10000 | independent | 14 | 12 | 26 | 22 | 4 | 0 | 7,187.4 | 6,788.5 | 0.7 | 12/14 | 12/14 |
| unlimited | repair | 14 | 14 | 14 | 14 | 0 | 0 | 4,932.1 | 3,054.0 | - | 14/14 | 14/14 |
| unlimited | independent | 14 | 14 | 28 | 28 | 0 | 0 | 10,176.2 | 6,788.5 | - | 14/14 | 14/14 |

`public ok` / `hidden ok` count tasks whose *selected* answer passed the public examples / the sealed hidden checks; a task with no selection counts against both. Spend is per task (one envelope), charged in real generated tokens. At the unlimited control the spend/cap column is meaningless and shown as `-`.

### Reading the headline table, cap by cap

- **Cap 0**: `repair` keeps 0/14 answers with mean spend 0.0 (- of cap); `independent` keeps 0/14 answers after starting 0 candidates, mean spend 0.0 (- of cap).
- **Cap 2000**: `repair` keeps 2/14 answers with mean spend 2,258.1 (1.1 of cap); `independent` keeps 2/14 answers after starting 15 candidates, mean spend 2,300.7 (1.2 of cap).
- **Cap 5000**: `repair` keeps 11/14 answers with mean spend 3,459.6 (0.7 of cap); `independent` keeps 11/14 answers after starting 28 candidates, mean spend 5,552.5 (1.1 of cap).
- **Cap 10000**: `repair` keeps 12/14 answers with mean spend 4,428.1 (0.4 of cap); `independent` keeps 12/14 answers after starting 46 candidates, mean spend 10,618.1 (1.1 of cap).
- **Cap unlimited**: `repair` keeps 14/14 answers with mean spend 4,932.1 (- of cap); `independent` keeps 14/14 answers after starting 112 candidates, mean spend 43,560.9 (- of cap).

### Termination and binding

| cap | policy | end states (tasks, headline pool) | candidates ended by overshoot |
| ---: | --- | --- | ---: |
| 0 | repair | unaffordable: 14 | 0 |
| 0 | independent | unaffordable: 14 | 0 |
| 2000 | repair | complete: 2, overshoot: 12 | 12 |
| 2000 | independent | overshoot: 13, unaffordable: 1 | 13 |
| 5000 | repair | complete: 11, overshoot: 3 | 3 |
| 5000 | independent | overshoot: 13, unaffordable: 1 | 13 |
| 10000 | repair | complete: 12, overshoot: 2 | 2 |
| 10000 | independent | overshoot: 14 | 14 |
| unlimited | repair | complete: 14 | 0 |
| unlimited | independent | pool-exhausted: 14 | 0 |

Binding, cap by cap — **0**: 0/112 headline-pool sessions fit whole (0.0); repair was cut short or unable to start on 14/14 tasks and independent ended 0 candidates by overshoot with 14 never started; **2000**: 20/112 headline-pool sessions fit whole (0.179); repair was cut short or unable to start on 12/14 tasks and independent ended 13 candidates by overshoot with 1 never started; **5000**: 82/112 headline-pool sessions fit whole (0.732); repair was cut short or unable to start on 3/14 tasks and independent ended 13 candidates by overshoot with 1 never started; **10000**: 101/112 headline-pool sessions fit whole (0.902); repair was cut short or unable to start on 2/14 tasks and independent ended 14 candidates by overshoot with 0 never started; **unlimited**: 112/112 headline-pool sessions fit whole (1.0); repair was cut short or unable to start on 0/14 tasks and independent ended 0 candidates by overshoot with 0 never started. A cap is binding exactly when the measured per-session spend (median across all 112 measured sessions 3,247, p90 9,820) does not fit inside it; the low caps bind on the long tail of sessions only, because the median call is small.

### Who loses the answer when a cap binds (headline pool)

| cap | policy | family | tasks | overshoot-ended | public ok | hidden ok | mean spend |
| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0 | repair | bool-int | 2 | 0 | 0 | 0 | 0.0 |
| 0 | repair | checked-result | 5 | 0 | 0 | 0 | 0.0 |
| 0 | repair | generic-requirement | 5 | 0 | 0 | 0 | 0.0 |
| 0 | repair | variant-coverage | 2 | 0 | 0 | 0 | 0.0 |
| 0 | independent | bool-int | 2 | 0 | 0 | 0 | 0.0 |
| 0 | independent | checked-result | 5 | 0 | 0 | 0 | 0.0 |
| 0 | independent | generic-requirement | 5 | 0 | 0 | 0 | 0.0 |
| 0 | independent | variant-coverage | 2 | 0 | 0 | 0 | 0.0 |
| 2000 | repair | bool-int | 2 | 1 | 1 | 1 | 1,945.0 |
| 2000 | repair | checked-result | 5 | 5 | 0 | 0 | 2,483.6 |
| 2000 | repair | generic-requirement | 5 | 5 | 0 | 0 | 2,260.0 |
| 2000 | repair | variant-coverage | 2 | 1 | 1 | 1 | 2,003.0 |
| 2000 | independent | bool-int | 2 | 2 | 1 | 1 | 2,243.0 |
| 2000 | independent | checked-result | 5 | 5 | 0 | 0 | 2,483.6 |
| 2000 | independent | generic-requirement | 5 | 5 | 0 | 0 | 2,260.0 |
| 2000 | independent | variant-coverage | 2 | 1 | 1 | 1 | 2,003.0 |
| 5000 | repair | bool-int | 2 | 0 | 2 | 2 | 2,172.0 |
| 5000 | repair | checked-result | 5 | 3 | 2 | 2 | 4,925.6 |
| 5000 | repair | generic-requirement | 5 | 0 | 5 | 5 | 3,043.6 |
| 5000 | repair | variant-coverage | 2 | 0 | 2 | 2 | 2,122.0 |
| 5000 | independent | bool-int | 2 | 1 | 2 | 2 | 5,054.5 |
| 5000 | independent | checked-result | 5 | 5 | 2 | 2 | 5,894.2 |
| 5000 | independent | generic-requirement | 5 | 5 | 5 | 5 | 5,617.0 |
| 5000 | independent | variant-coverage | 2 | 2 | 2 | 2 | 5,035.0 |
| 10000 | repair | bool-int | 2 | 0 | 2 | 2 | 2,172.0 |
| 10000 | repair | checked-result | 5 | 2 | 3 | 3 | 7,637.6 |
| 10000 | repair | generic-requirement | 5 | 0 | 5 | 5 | 3,043.6 |
| 10000 | repair | variant-coverage | 2 | 0 | 2 | 2 | 2,122.0 |
| 10000 | independent | bool-int | 2 | 2 | 2 | 2 | 10,131.0 |
| 10000 | independent | checked-result | 5 | 5 | 3 | 3 | 11,242.4 |
| 10000 | independent | generic-requirement | 5 | 5 | 5 | 5 | 10,359.0 |
| 10000 | independent | variant-coverage | 2 | 2 | 2 | 2 | 10,192.5 |
| unlimited | repair | bool-int | 2 | 0 | 2 | 2 | 2,172.0 |
| unlimited | repair | checked-result | 5 | 0 | 5 | 5 | 9,048.8 |
| unlimited | repair | generic-requirement | 5 | 0 | 5 | 5 | 3,043.6 |
| unlimited | repair | variant-coverage | 2 | 0 | 2 | 2 | 2,122.0 |
| unlimited | independent | bool-int | 2 | 0 | 2 | 2 | 19,249.0 |
| unlimited | independent | checked-result | 5 | 0 | 5 | 5 | 76,446.2 |
| unlimited | independent | generic-requirement | 5 | 0 | 5 | 5 | 32,112.8 |
| unlimited | independent | variant-coverage | 2 | 0 | 2 | 2 | 14,279.5 |

### Repair with each measured session in turn

The headline `repair` row charges the first pool member only (M2-matching arm, repetition 1) because `repair` is one session per task. Replaying each measured session of the headline pool as the one repair session, so no session is hidden behind that choice:

| cap | replays | overshoot-ended | selected | public ok | hidden ok | mean spend |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 112 | 0 | 0 | 0 | 0 | 0.0 |
| 2000 | 112 | 92 | 20 | 20 | 20 | 2,385.1 |
| 5000 | 112 | 30 | 82 | 82 | 82 | 3,584.5 |
| 10000 | 112 | 11 | 101 | 101 | 101 | 4,363.0 |
| unlimited | 112 | 0 | 112 | 111 | 111 | 5,445.1 |

## Acceptance is near the ceiling in this evidence

111 of 112 measured M1b sessions ended in hidden acceptance, and public and hidden acceptance coincide in every measured cell, so the public/hidden split cannot separate the policies on this evidence. What the replay does separate is how often a cap cuts a session short: an overshoot-ended candidate is incomplete and cannot be selected, which is where a binding cap costs a task its answer.

## Missing or unrecoverable observations

None: every scheduled cell produced a record and a matching session log.

Attempt directories that exist without a `record.json` (a discarded attempt, kept visible rather than dropped): `json_fix/bool-b/1`.

No cell had a per-call/aggregate mismatch or a malformed log line: the per-call values are the ground truth for spend here, never a session-total estimate.

## Reproduction

```console
python3 experiments/diagnostic-feedback-m2/m2_usage.py --selftest
python3 experiments/diagnostic-feedback-m2/envelope_replay.py --selftest
python3 experiments/diagnostic-feedback-m2/envelope_replay.py \
    --json experiments/diagnostic-feedback-m2/cohorts/calibration/calibration.json \
    --markdown docs/audits/m2-budget-calibration-2026-09-19.md
```

Selftest at capture: usage reader 10/10, envelope replay 10/10 property checks. The replay launches no session: it reads sealed evidence and charges it.
