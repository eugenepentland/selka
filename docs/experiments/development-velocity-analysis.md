# Matched development-velocity analysis

`experiments/development_velocity/analysis.py` analyzes immutable matched-cohort
records. It does not launch participants, grade programs, inspect private packs,
infer telemetry, or alter the study decision journal. Run:

```sh
python3 -B -m experiments.development_velocity.analysis cohort.json report.json
python3 -B -m unittest discover -s tests/development_velocity -p test_analysis.py
```

The output path must not exist. Python callers can use `analyze(document)`;
validation failures raise `ValueError`. `canonical_hash(value)` and
`registration_hash(registration)` produce SHA256 over compact, sorted-key UTF-8
JSON (`ensure_ascii=False`, no NaN/Infinity). Hash strings use lowercase hex.

## Pre-registration and input

Version 1 accepts exactly these top-level fields; version 2 adds `arm` to every
attempt and `arms` to the configuration, as described under Registered arms:

```text
{
  schema_version: 1,
  registration: {
    study_id: string,
    candidate_id: string,
    phase: "development" | "confirmation",
    look: integer,
    frozen_at: UTC_ISO_TIMESTAMP,
    configuration: object,
    configuration_hash: SHA256(configuration),
    analysis: {
      version: "development-velocity-analysis-v1" | "development-velocity-analysis-v2",
      seed: integer,
      bootstrap_samples: integer in [1000, 1000000],
      speed_margin: 1.0,
      quality_margin: 0.0
    },
    prior_variant_hashes: [SHA256, ...],
    tasks: [{
      task_id: string,
      variant_hash: SHA256,
      family: FAMILY,
      kind: "feature" | "bugfix",
      budget_seconds: positive finite number,
      pair_ids: [string, ...]
    }, ...]
  },
  registration_hash: SHA256(registration),
  attempts: [{
    task_id: string,
    pair_id: string,
    language: "my" | "python",
    arm: string,                        // registered arm label; v2 only
    attempt_id: string,
    participant_id: string,
    registration_hash: SHA256,
    configuration_hash: SHA256,
    variant_hash: SHA256,
    started_at: UTC_ISO_TIMESTAMP,
    ended_at: UTC_ISO_TIMESTAMP,
    clock: {
      boot_id: string,
      started_monotonic_ns: nonnegative signed-64 integer,
      ended_monotonic_ns: nonnegative signed-64 integer
    },
    status: "sealed" | "failed" | "timed_out" | "abandoned" |
            "infrastructure_failure",
    behavior_pass: boolean,
    verification_pass: boolean,
    review: "approve" | "approve_with_nits" | "reject" | "pending",
    telemetry: null | object
  }, ...]
}
```

This is a schema sketch, not literal JSON. `telemetry` is optional; omission
becomes `null` in the output. `clock` may be omitted/null for legacy development
records only; confirmation requires it. Other missing/extra schema fields reject. Unknown
model identity, tokens, queue time and cost belong as `null` in the configuration
or telemetry, never invented zeros. Telemetry objects are opaque raw observations;
the analyzer does not classify their contents or derive model reasoning time.

## Registered arms

`configuration.arms` is optional and records the compared pair:

```text
arms: {comparator: {label, language: "my" | "python", interface: "files" | "store"},
       candidate:  {label, language, interface}}
```

Labels are distinct and name the attempt directories. When `arms` is present the
registration is `development-velocity-analysis-v2`: each attempt carries `arm`,
its `language` must equal that arm's language, expected identities are
task/pair/arm label, per-task, family and aggregate values use `candidate_*` and
`comparator_*` keys, the speed ratio is candidate cost over comparator cost, both
gates read candidate against comparator, and the report echoes the arm
definitions under `arms`.

When `arms` is absent the registration stays `development-velocity-analysis-v1`
and every output is byte-for-byte what it was: identities are task/pair/language,
values keep `my_*` and `python_*` keys, the ratio is `.my` over Python, and no
`arm` field is accepted on an attempt. Old evidence therefore keeps validating
against its hashes; old records are never rewritten. A cohort of two `.my` arms
is expressible only in the v2 form.

Families match the corpus catalog: `data-text`, `configuration`,
`stateful-collections`, `binary-codecs`, `filesystem-path`, and
`multi-module-maintenance`. The development plan starts with twelve tasks
(eight features, four bugfixes), one pair each, followed by repeated fresh cohorts.
The analyzer accepts smaller development subsets for diagnostic work; their
reports cannot authorize stopping. The frozen task roster records the intended
feature/bugfix balance; the coordinator enforces the study's planned balance.

Each registered task/pair must have exactly one attempt in each language, or in
each registered arm under v2. Missing attempts, duplicates, unexpected attempts
and reused participant identities reject.
Each context is fresh; register a sequential maintenance sequence as **one task
cluster**, rather than treating stages sharing a participant as independent tasks.
Tasks and variant hashes must be unique within a cohort. Confirmation variants
must not occur in `prior_variant_hashes`; the coordinator must supply the complete
exposure history, including earlier development and confirmation cohorts.

Timestamps are ISO UTC strings ending in `Z`, such as `2026-09-08T12:30:00.123Z`.
Freeze must precede every start. `started_at` is coordinator begin before dispatch;
`ended_at` is immutable submission seal or recorded terminal failure/timeout.
Durations use the supplied monotonic nanosecond difference and include handoff and
uncovered wall time. `boot_id` identifies the common host boot for both readings;
the coordinator must verify boot continuity. Monotonic end must not precede start.
UTC timestamps remain unmodified provenance; wall-clock adjustment may make their
delta disagree with monotonic time, even negative. Reports retain that raw
`utc_elapsed_seconds` separately and mark `duration_source:"monotonic_ns"`.
Do not synthesize UTC end timestamps to match monotonic duration. Legacy development
records without `clock` use UTC difference and are labeled `duration_source:"legacy_utc"`.
Sealed attempts require positive duration. Both languages share the task's budget.
An unfinished registered attempt
must acquire an explicit terminal disposition before the cohort can be analyzed;
silently omitting it is forbidden.

Configuration should pin compiler/runtime, standard library, baselines, task and
grading contracts, public verification obligations, documentation, gateway policy,
model settings, clock policy and analysis-source identities. The analyzer validates
the configuration and registration hashes plus every attempt's matching references.
The coordinator must verify those hashes against the actual frozen files and
seal receipts. Self-consistent hashes alone cannot prove historical immutability,
truthful timestamps, identical execution environments, or heldout isolation.

Do not retrofit new pair IDs into a registration after outcomes or rewrite old
attempt references. Repetitions/reruns use a new frozen cohort and new pair/context
IDs, or pairs fully declared before the original freeze. The study journal retains
all original attempts/cohorts, including infrastructure failures. A rerun is not a
replacement for the failed pair; both languages receive a fresh matched pair.
The primary analysis has no infrastructure-exclusion path.

## Outcomes, weights and uncertainty

A qualified completion requires status `sealed`, delivery within the inclusive
budget, both behavioral and declared verification checks passing, and a timing-blind
review of `approve` or `approve_with_nits`. The review rubric must define nits as
nonblocking before launch. Pending review does not qualify and is never dropped.
Use an append-only superseding analysis after a pending review finishes; it is the
same cohort/look, not a new confirmation opportunity.

The primary per-attempt cost is delivery seconds for qualified completion and the
**entire task budget** otherwise. Fast failures therefore cannot create artificial
speedups. Deadline overruns retain their actual observed elapsed time but receive
the budget cost and do not qualify. Every attempted/qualified count and terminal
status remains visible. Successful-only timing is reported per task as secondary;
it is `null` when no attempt qualifies and never determines a decision.

For each language or registered arm, average all registered attempts within a
task, then average tasks equally within each family, then average families equally.
The speed statistic is the ratio of these two weighted mean costs, `.my / Python`,
or candidate over comparator under v2, **not** the mean of task ratios. Completion
rates follow the same hierarchy. Extra repetitions do not increase a task's weight,
and extra tasks do not increase a family's weight.

Speed uncertainty resamples whole task clusters with replacement independently
within each family, preserving paired language data and every repetition within
the selected cluster. It uses a deterministic seed and the predeclared number of
draws. The reported one-sided upper percentile is the nearest-rank quantile at
`1 - 0.00625`. This is an approximate bootstrap interval, not a finite-sample exact
guarantee. Fewer than three task clusters in a family produce a small-sample flag;
three participant pairs do not repair the shortage of independent tasks. Very
homogeneous or small samples can yield a degenerate bootstrap interval; interpret
that as a limitation of this corpus, not proof of no population variance.

The separate population quality assessment uses task-level completion differences
`d_t` in `[-1,1]` and weights `w_t = 1 / (family_count * tasks_in_family)`:

```text
quality_lower = max(-1,
    weighted_difference - sqrt(2 * log(1/alpha) * sum(w_t**2)))
```

This conservative one-sided weighted Hoeffding bound assumes independent task
clusters. It reports uncertainty without pretending that all-pass samples prove
identical population defect rates. At observed zero difference its lower bound is
negative for every finite cohort. Population inference requires a defensible task
sampling design; handpicked tasks support a corpus claim only.

## Stopping decisions

Development has `look:0` and always returns `parity_criterion_met:false`.
Confirmation requires at least two distinct task clusters in **each of six families**
and at least three fresh pairs per task. A confirmation look is an integer 1..4.
Before the first confirmation outcome, freeze all four allowed looks and the
analysis policy. Each gate has one-sided alpha `0.00625` at each look, giving
`4 * 2 * 0.00625 = 0.05` total allocation. The conservative allocation does not make
the approximate bootstrap exact, and the empirical quality gate has no statistical
false-positive guarantee. No unregistered fifth look or relaxed margin is accepted.

Two distinct conclusions are reported:

* `parity_criterion_met`: confirmation only; speed upper bound **<=1.00**,
  **all** `.my` attempts qualify, and its observed weighted completion is no worse
  than Python's. This is the predeclared operational **heldout corpus-level parity**
  gate. It does not assert equal population defect probabilities.
* `population_quality_noninferiority_demonstrated`: confirmation only; the
  conservative quality lower bound is >=0.00. This may remain false even when the
  empirical corpus gate passes. The zero quality margin is never weakened.

Publish task/family regressions, preparation costs and all development cohorts even
when the corpus gate passes. Aggregate speed does not imply every task is faster.
Failure to meet the gates within the allotted looks/budget is reported as parity
not demonstrated. After inspecting heldout failures, those tasks become development
evidence; a revised candidate requires a new frozen cohort with fresh variants.
The caller's append-only decision journal must prevent repeat look use, selective
publication, or resetting the four-look allowance under new candidate IDs. This
stateless analyzer cannot enforce history it has not received.

## Output

Reports include source-analysis version, input/registration/configuration hashes,
phase/look, every attempt with raw telemetry and capped cost, task summaries,
family summaries, total attempt/qualified/status counts, weighted aggregates,
uncertainty methods/seeds/bounds, small-sample flags, both decision types and scope
limitations. Reports are new artifacts: the CLI refuses an existing output path.
Root orchestration owns preparation records, raw evidence retention and the study
decision journal. No build or Guardian gate is required to run these Python tests.
