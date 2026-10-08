# Integrated benchmarks and reviewed performance baselines

> **Removed 2026-10 (new core S5-D6).** `mylang test --bench*` and
> `mylang bench-promote` were dropped with the old test runner and are refused. This
> plan is kept as a record.

Status: partially implemented September 16, 2026. Guest benchmark discovery,
sampling, candidate reports, baseline/policy comparison and reviewed promotion
ship in `mylang test` and `mylang bench-promote`; a blocking CI performance
status and the compiler benchmark adapter (`zig build bench`) remain follow-ups.

Add benchmarks alongside tests, with repeatable measurements, versioned baselines,
and limits that block a change until its performance improves or a maintainer
approves the regression. Ordinary correctness tests remain fast; performance
checks run explicitly and as a separate required CI job.

## Scope

Start with benchmarks written in MyLang and executed by `mylang test`. The current
runner already provides exported-function discovery, typed JSON inputs and
expectations, provider fixtures, native compilation, bounded subprocesses, and
JSON reports. Extend those facilities rather than create a second test framework.

Design the report and comparison engine so a later Zig benchmark executable can
use the same baseline and approval workflow for compiler internals. Timing a
whole `zig build test` run is not a substitute for measuring specific operations.
That second adapter is a follow-up, not a prerequisite for guest benchmarks.

## Proposed developer workflow

These commands describe the intended interface; they do not exist yet.

```sh
# Existing correctness tests.
mylang test app/main.my

# Correctness tests followed by selected benchmarks.
mylang test app/main.my --bench '*' --mode ReleaseFast

# Produce measurements for inspection or a proposed baseline update.
mylang test app/main.my --bench '*' --mode ReleaseFast \
  --bench-output perf/candidate.json

# Enforce the approved baseline and its policy.
mylang test app/main.my --bench '*' --mode ReleaseFast \
  --bench-baseline perf/baseline.json --bench-policy perf/policy.json
```

Discover exported `bench_` functions beside `test_` functions. One invocation of
a benchmark function represents one operation; the harness owns repetition.
Reuse `--cases` for typed arguments, expected results, and provider substitutions.
Allow named input sizes so one function can cover small, medium, and large data.
Boolean results can default to `true`; other results require an expectation.

Keep test filtering and benchmark filtering independent. In benchmark mode,
correctness tests run first and must pass before measurement. Provide an explicit
benchmark-only option for local iteration. A required CI job must select the
complete configured benchmark suite, regardless of local filtering options.

## Measurement contract

- Build once using an explicit optimization mode. Reuse compilation artifacts,
  but never reuse cached performance results as evidence of a fresh measurement.
- Measure inside the native subprocess with a monotonic clock. Exclude compiler
  execution, process startup, library loading, fixture preparation, and report
  serialization from guest-operation timing.
- Initially measure the complete native copied-value call, including its codec
  and runtime costs. Label this boundary in the report. A future direct-call
  benchmark mode needs a separate measurement identity and baseline.
- Warm up, calibrate the iteration count to a target batch duration, and collect
  multiple independent batches. Initial tuning candidates are 9 batches of about
  250 ms each; validate these against actual noise before freezing defaults.
- Time batches rather than putting two clock reads around every tiny operation.
  Validate results outside timed regions and ensure results remain observable so
  optimization cannot remove the workload. Define and test how mutable state is
  reset between operations; setup/reset costs must have an explicit boundary.
- Run timing batches sequentially, including directory suites. Compilation may
  run in parallel, but benchmark workers must not compete with each other.
- Retain per-operation execution limits and a separate bounded batch/run timeout.
  Traps, incorrect results, timeouts, and invalid outputs fail the run.
- Report raw batch durations and iteration counts, median ns/op, spread, and
  sample count. Preserve raw measurements for investigation. Add bytes/op and
  allocations/op later when runtime counters can measure them accurately.

## Baselines, policy, and comparability

Store three distinct artifacts:

| Artifact | Purpose |
| --- | --- |
| `perf/baseline.json` | Approved measurements, benchmark inventory, and provenance |
| `perf/policy.json` | Default and per-benchmark limits, required cases, runner profile |
| Run report / candidate | Fresh measurements, comparison, failures, and proposed changes |

Version their schemas. Reject malformed data, unknown schema versions, duplicate
benchmark IDs, invalid numbers, and nonpositive timing baselines. Never replace a
baseline while checking it. Candidate writes must be atomic and clearly indicate
whether every required test and benchmark completed successfully; incomplete
reports cannot become an approved baseline.

Each measurement needs a stable benchmark ID, workload version, fixture identity,
measurement-boundary version, optimization mode, sampling configuration, and
runner profile. Record source revision, compiler/toolchain versions, OS, CPU,
and relevant environment settings as provenance.

Compare only compatible runs. A mismatched workload, runner profile, optimization
mode, or measurement boundary requires investigation or a new baseline. Ordinary
implementation changes and compiler revisions remain comparable within that
contract: they are precisely the changes whose performance needs checking. Do
not key baseline eligibility on the code-under-test implementation hash.

An unbaselined new benchmark or a removed/skipped required benchmark must produce
an explicit incomplete-coverage result, not a successful gate. Local filtered
runs may compare a subset but cannot approve or replace the whole-suite baseline.

## Regression rules and noise

Support a default relative limit with per-benchmark overrides, plus absolute
ceilings. An initial policy might allow 10% growth, with a small absolute delta
floor to avoid failing on negligible changes. Those are configurable starting
values, not promises that all machines can reliably detect 10% differences.

For lower-is-better timing metrics, let `B` be the baseline median and `C` the
current median. Flag a relative regression when both hold:

```text
(C - B) / B > allowed_growth_percent / 100
C - B > minimum_meaningful_delta_ns
```

An independent `max_ns_per_op` ceiling applies even if relative growth is small.
Equality with a limit passes. Zero percent tolerance is valid. Display baseline,
current value, percentage change, limit, spread, and the reason for failure.

Use a controlled runner profile for blocking comparisons. If measurements exceed
a defined noise budget or the result is near a limit, perform at most one
predefined confirmation run and evaluate all its samples together. Do not retry
until one run passes. Unresolved noise is inconclusive and needs a rerun or runner
repair; it does not silently turn the performance gate green.

Keep the approved baseline fixed until a reviewed change replaces it. Retain
baseline history so successive individually accepted regressions remain visible.
Do not automatically advance the baseline on every successful build, which would
allow small regressions to accumulate unnoticed.

## Approval and CI enforcement

1. CI reads approved policy and baseline from a trusted base revision or approved
   artifact, measures the proposed code, and uploads the comparison report.
2. An exceeded limit fails a required performance status check. The author can
   optimize the code or submit a baseline/policy change with its reason, measured
   impact, and candidate report.
3. A designated maintainer reviews that specific revision and measurement
   artifact. Approval must be bound to the candidate contents; a later code,
   policy, or candidate change invalidates the approval.
4. After approval, a controlled workflow promotes the candidate and records the
   approver, reason, revision, runner profile, and old/new measurements.

A local command that writes a baseline is not approval. A PR must not pass merely
by raising its own limits or replacing its baseline. Protect policy, baseline,
benchmark definitions, and the promotion workflow with the repository's review
rules. Benchmark deletion or workload reduction also needs review.

The existing CI matrix runs Debug and ReleaseFast tests on `ubuntu-latest`.
Introduce performance reporting there first, then enable blocking timing checks
on an explicitly controlled runner. If shared hosted runners must be used, measure
base and candidate on the same runner in alternating batches and validate the
noise policy before making that comparison required. Continue checking cumulative
performance against the approved baseline on a stable runner.

Keep correctness checks independent. Guardian should enforce the normal code,
test, and specification checks; the benchmark command supplies a separate
performance status. Avoid running expensive timings on every ordinary build.

## Implementation sequence

1. **Specify the contract and schemas.** Document discovery, execution boundaries,
   fixtures, filtering, exit statuses, comparison policy, and approval artifacts.
   Add SPEC coverage for the new externally visible behavior.
2. **Add opt-in discovery and execution.** Extend `native_test_options.zig`,
   `native_test_cases.zig`, and `native_test_command.zig`. Add a versioned benchmark
   protocol to `native_test_execute.zig` and `native_test_runner.c`, keeping ordinary
   test execution compatible. Cover directory discovery and sequential measurement.
3. **Add reports and comparison.** Put sampling statistics, baseline validation,
   policy evaluation, and JSON output in focused modules. Leave successful-test
   receipts separate from benchmark measurements.
4. **Ship examples and deterministic tests.** Add representative scalar,
   collection, and allocation workloads. Extend native-runner and CLI tests;
   update `docs/tooling/guest-tests.md` with the workflow and timing boundaries.
5. **Introduce CI reporting, then enforcement.** Measure noise and overhead first;
   establish approved baselines; configure the required status and approval
   promotion workflow only after the runner is reliable.
6. **Extend to compiler benchmarks.** Add a `zig build bench` adapter for parsing,
   checking, lowering, and incremental rebuild workloads. Reuse the comparison
   format and approval policy, with distinct benchmark IDs and timing boundaries.

## Acceptance criteria

- Existing tests, filters, fixtures, caching, and default CLI behavior still work.
- Benchmarks always execute freshly; startup and compilation do not contaminate
  the declared operation timing; repeated operations remain observable.
- Deterministic unit tests cover exact thresholds, overrides, zero tolerance,
  absolute ceilings, noisy/inconclusive runs, malformed baselines, incompatible
  metadata, and missing/removed cases. Use synthetic samples, not real-clock
  assertions, to test comparison decisions.
- End-to-end tests exercise real native timing, traps, incorrect results,
  timeouts, candidate writes, and a reliably forced regression. A failed check
  leaves the approved baseline byte-for-byte unchanged.
- Directory runs have collision-free case identities and sequential timing.
- CI demonstrates that an ordinary passing change succeeds, a deliberate
  slowdown fails, a self-raised limit cannot bypass the gate, and a reviewed
  candidate can be promoted with a recorded reason.
- Baseline and policy formats can serve both guest and compiler benchmarks
  without requiring a second approval system.
