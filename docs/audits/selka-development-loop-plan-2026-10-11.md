# Selka development loop improvement plan

Date: 11 October 2026. Status: implementation started with DL1 instrumentation,
DL2 command-deadline plumbing and the first reviewed DL3 test boundary.
Full calibration, broader dependency splits and later waves remain open.
Baseline: local `main` at `e935448025873afc0740b345acf77b7e4f09dda3`.

Make ordinary compiler edits cheap to build and verify, keep expensive checks
bounded and visible, and carry those improvements into the self-hosted compiler.
Start with measurement and test dependencies while the other branch completes
self-hosting. Integrate its compiler stages as they become qualified; this
roadmap does not start a second compiler port.

The completed [cache roadmap](selka-toolchain-cache-plan-2026-10-10.md) remains
the foundation. These are **development loop waves DL1 through DL8**, distinct
from cache Waves 1 through 11. Each wave should deliver an independently useful,
reviewable change with an explicit acceptance report.

## Current costs and boundaries

The [Wave 11 qualification](../../experiments/cache-wave11-20261011/REPORT.md)
recorded 575.739 seconds of gate execution on its first request and 35.898 seconds
on the unchanged repeat, which reused 32 groups and selected 11 fresh groups.
The first request already had Zig/native build artifacts available. These are
operational cold/warm observations, not an isolated before/after benchmark.

The [execution log](../../experiments/cache-wave11-20261011/session-verification.log)
includes a 44-second component qualification, 41-second golden test, and several
roughly minute-long native test shards. The warm language release/fact/leak action
took 18 seconds. These are initial profiling candidates, not additive durations
or guaranteed savings.

Current implementation details explain why source edits remain expensive:

- [Test input lists](../../build_test_inputs.zig) bind broad source and fixture
  trees. Core inherits the unit inputs and adds entire test, example and benchmark
  directories. Execution shards are not independent implementation boundaries.
- [Compiler identity](../../build_identity.zig) covers all production sources,
  the toolchain and optimization mode. Test-only files are already excluded.
- [Verification](../../scripts/verify_cache.py) supports selected artifact
  dependencies, but also keys common inventory, configuration, environment,
  implementation and tool identities. Splitting a fixture list alone cannot
  remove every source of broad invalidation.
- [Affected test selection](../../scripts/affected_tests.py) is an approximate
  developer aid. Its source-name heuristics are not a proof for skipping required
  verification. Native test executable changes still invalidate their evidence.
- The retained cache session preserves input snapshots. It does not retain a
  compiler AST, and shared executable lookup still follows frontend work.

## Coordination with the self hosting branch

The user confirmed `codex/selka-bootstrap-20261011` as the active self-hosting
branch. It was inspected for this plan at `8aae33ef3`, in
`/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang`.

That branch has progressed well beyond the original pilot briefs. Its current
references are `docs/audits/selka-incremental-selfhost-parallel-work-2026-10-10.md`,
`docs/audits/selka-body-wave-integration-2026-10-11.md` and
`docs/tooling/selfhost-performance-budget.md`. Read those files from the branch;
the versions on this plan's main baseline do not describe all that work.

Its stated completed-compiler acceptance requirement is at most **1.5 times the
Zig reference for both median and p95 of every required workload**, including
compiler operations, testing and generated runtime. Existing component results
have not satisfied that requirement. Preserve it unless the user changes it;
neither feature completion nor an instruction-count proxy establishes acceptance.

| Owner | Scope |
| --- | --- |
| Self-hosting workstream | Language coverage, semantic ownership, Core/LLVM and driver port, component schemas, seed qualification and staged bootstrap |
| Development loop workstream | Cost reports, test budgets, verification inventory, fixture and artifact dependencies, invalidation explanations, test execution overhead and Juice integration |
| Joint integration changes | Producer identities, build wiring, native runner controls, adoption of compiler stages and any shared source touched by both branches |

Refresh the branch head and confirm exact file ownership in DL1. Agree contracts before changing
shared files; use one integration owner for each such change. Do not independently
port a lexer, checker or backend that the other branch already owns. If the full
port lands first, apply the same dependency contracts directly to that compiler.

## Performance and correctness policy

Initial targets apply to named workloads and hardware, after server admission.
Record queue time separately; exclude AI time from this roadmap. Include planning,
validation, build, setup, execution and reporting in the developer-loop total.
Report elapsed critical-path time separately from summed work across processes.

| Scope | Initial target | Initial watchdog proposal |
| --- | --- | --- |
| Small unit test execution | Usually below 100 ms; investigate above 1 second | 5 seconds |
| Focused integration test execution | Usually below 2 seconds | 30 seconds |
| Cold build, bootstrap, large corpus or stress check | Named measured budget and reason | Per action, with measured headroom |
| Ordinary warm edit loop | Useful completed check within 5 seconds; p95 completion within 15 seconds | A separate command deadline; do not derive it from the 15-second target |
| Unchanged complete verification | Reduce the observed 36-second floor | Establish a supported target from DL1 measurements |

These are proposals to calibrate, not immediate global timeout changes. Existing
guest defaults remain 60 seconds, one million steps and 1,024 frames until a
qualified change deliberately alters them. Track build and setup separately from
test execution. Cold bootstrap and broad semantic edits have their own budgets.

A timeout yields an incomplete or failed result, never a pass or a reusable
success. Missing coverage cannot be hidden by moving work to a slower category.
Quick feedback, complete verification and long-running qualification must report
exactly what they covered. Required qualification still runs before finishing.

Instruction/work budgets complement wall-clock deadlines and memory limits.
Juice instructions per completed unit are not elapsed time; its runtime predictor
remains advisory. Use real timing for latency acceptance and valid work counters
for stable regression signals. Avoid collecting expensive profiles for every
small unit test.

## DL1 Measure the edit loop and establish ownership

**Outcome:** a reproducible baseline showing why each edit rebuilds or reruns work.

Extend existing coordinator reports rather than introducing another scheduler.
Record action/test identifiers, phase start/end times, build and setup duration,
execution duration, available CPU time and memory observations, cache state,
executed/reused counts, and changed dependencies. Keep unavailable measurements
explicit; process peak RSS is not aggregate concurrent memory. Bound report size
and keep diagnostics out of semantic cache identities.

Store structured dependency summaries so misses can distinguish a test edit,
fixture edit, compiler identity change, environment/tool change, inventory change,
forced run, eviction and required freshness. An old result lacking explanation
metadata remains conservative rather than receiving an invented cause.

Freeze an edit matrix: unchanged repeat; test-only edit; fixture addition/removal;
documentation edit; tooling-only edit; pure compiler helper; semantic rule; runtime;
Selka component implementation; protocol/schema change; and compatible second
worktree. Include a revert and an edit during execution. Separate Debug developer
builds from ReleaseFast compiler timing, and distinguish warm caches, missing
verification receipts, missing project artifacts and cold bootstrap.

Refresh the confirmed self-hosting branch and exchange producer/output identity
and timing contracts. Save raw operational evidence; acquire timing isolation for numerical
claims. Do not represent a few observations as a stable p95.

**Acceptance:** every required action appears in the report, overlapping phases
are not double-counted, and each edit has a reproducible invalidation explanation.
Telemetry preserves outputs, selected tests and reuse behavior. Archive the exact
baseline and branch ownership before structural changes.

## DL2 Add calibrated budgets and reliable cancellation

**Depends on:** DL1.

Add budget metadata to the existing action inventory, with stable test IDs where
individual measurements are available. Separate expected cost, regression target,
hard deadline and memory/work ceiling. Start legacy actions in report-only mode;
new tests select a justified category, and expensive exceptions name their reason
and review point. Do not classify or move a test automatically because it is slow.

Apply deadlines to build/setup and complete actions as well as guest execution.
Use monotonic time and start execution deadlines after admission. A command may
separately have a user cancellation deadline. Account for profiler overhead and
shared-host variability when choosing hard ceilings.

Terminate owned process trees, reap children and release claims, temporary files
and admission resources. Cancellation of one request must not terminate shared
work still required by another subscriber. Reuse the existing ownership model;
do not add a second set of claims. Execution-affecting limits participate in action
identity. Report-only targets and Juice thresholds may reevaluate compatible
evidence without rerunning it; missing required measurements require execution.

**Acceptance:** exercise a CPU loop, blocked child, grandchild, interrupted build,
timeout during publication and cancellation with another subscriber. No success
receipt is published for incomplete work, and the next invocation can recover.
Calibrated normal workloads pass without raising ceilings to hide regressions.

## DL3 Split test boundaries and declared dependencies

**Depends on:** DL1; coordinate budget metadata with DL2.

Start with the expensive roots and broad input lists identified in DL1. Separate
pure unit tests, compiler integration, CLI packaging and cold-bootstrap checks
where they genuinely have different implementation and fixture dependencies.
Create independent test executables where a single executable's digest would
otherwise invalidate every subgroup. Merely adding more shards does not solve this.

Keep groups large enough to avoid rebuilding duplicated compiler code or creating
excessive process startup. Measure that tradeoff. Move eligible value-behavior
tests to Selka according to the existing test-layout rules, coordinating any files
owned by the self-hosting branch; preserve diagnostic/trap/host assertions.

Refine per-group source, fixture and prepared-artifact dependencies. Extend
provider declarations for tools, environment and generated inputs only when
complete dependencies can be established. Split group-local contracts from global
inventory coverage so adding an unrelated group need not invalidate every success,
while discovery still requires every current action. Changes to actual common
execution semantics must continue to invalidate all affected groups.

Negative lookups, directory membership, added tests, embedded files, transitive
imports and generated inputs remain dependencies. File traces and import analysis
help audit declarations; an observed run is not proof that an unvisited path is
irrelevant. Unknown or incomplete dependencies retain broad invalidation.

**Acceptance:** a fixture or test-only edit reruns the responsible groups and
preserves proven unrelated evidence. Added/deleted/renamed tests and fixtures are
discovered. Exact test inventories and behavior match independent full execution.
Measure both warm edits and full cold preparation to reject harmful oversplitting.

## DL4 Introduce qualified producer identities

**Depends on:** DL3 and the shared producer contract with the self-hosting branch.

Keep the whole-compiler identity as the default. Introduce narrower identities
first for an independently built tool or component with a complete implementation
closure. Cover source/import closure, generated code, seed/build recipe, relevant
runtime/ABI, flags, tools and protocol. A manually maintained version number or
source-directory label is insufficient.

Separate each cached result's producer implementation, interface/schema and
consumed data dependencies. A compatible wire schema does not make a changed
checker equivalent. A semantic producer change invalidates what it produces;
consumer reuse requires the existing qualified artifact/content contracts.

Allow compiler stages to opt into narrower identities one at a time. Zig test
receipts still bind their executable unless independently compiled boundaries or
another qualified proof establish independence. Do not promote the heuristic
affected-test script to a correctness authority or promise function-level Zig
test reuse without such a proof.

Carry the same identities into compilation, test successes, fuzz evidence and
performance captures. Include indirect calls, specializations, effects, constants,
layouts and embedded inputs. Unknown relationships widen the affected set.

**Acceptance:** a genuinely independent tooling/component edit preserves unrelated
artifacts and results, while semantic/runtime/ABI changes invalidate consumers.
Inject a transitive edit that turns a cached pass into a failure and prove it runs.
Qualify reverts, old schemas, second worktrees and incomplete dependency metadata.
Retain conservative fallback and version the changed cache namespaces/contracts.

## DL5 Reduce the cost of checks that must execute

**Depends on:** DL1 and DL3; proceed alongside DL4 where ownership permits.

Profile the expensive component, golden, native shard and release/fact/leak
actions from DL1. Optimize their measured dominant phases: repeated compiler
startup, duplicated fixture preparation, small build/link invocations, redundant
discovery, serialization or actual algorithm work. Use existing batch APIs and
immutable prepared fixtures where appropriate; retain fresh mutable state for
cases testing isolation, cold behavior, corruption, bootstrap or crash recovery.

Split pure Juice/report/codec tests from live collector qualification when their
dependencies allow it. Preserve live host/effect checks and explicit fact/leak
execution. Reduce validation and metadata work in retained sessions without
weakening source-change detection or one-shot correctness.

Profile frontend work before a shared-program hit. If material, qualify an earlier
lookup against a complete project/producer/effect contract. Retained compiler
state is a separate measured option: coordinate it with the self-hosted driver's
design, and do not require a daemon, C ABI or worker service to finish this wave.
Avoid optimizing a temporary component transport that the active port is removing.

**Acceptance:** selected expensive checks show reduced executed work and isolated
latency with equivalent coverage. Report cold, warm and edited cases separately.
No improvement may come solely from skipping cold-cache controls, leak checking,
malformed-input cases or required end-to-end assertions.

## DL6 Provide fast feedback and qualified regression budgets

**Depends on:** DL2 and the useful boundaries from DL3 through DL5.

Extend the supported verification/session entry points with explicit quick,
complete and long-qualification profiles. Keep one authoritative action inventory
and dependency model. Quick mode schedules relevant inexpensive checks first and
reports remaining required work; complete mode accounts for every required action
through valid evidence or execution. Long qualification runs named bootstrap,
scaling, stress, fuzz and timing workloads. Moving a required action into that
profile does not remove the finishing requirement.

Use sound dependencies for certified reuse and label heuristic selection as
partial feedback. Give broad semantic changes a visible larger plan rather than
silently forcing them into the ordinary-edit target. Integrate the retained session
as a supported developer option while preserving correct one-shot commands.

Add small representative compiler and test-driver workloads to the existing Juice
coordinator. Check outputs, completed units, artifact and environment identity,
and stable repeatability before evaluating work-regression thresholds. Reuse
compatible captures for threshold-only changes. Keep fresh timing requests fresh
and keep the self-hosting runtime ratio gate based on actual timing.

Bound fuzzing by explicit cases/work/time and retain only completed evidence.
An exhausted campaign budget reports partial coverage, not a completed full run.
Performance regressions with noisy or insufficient evidence remain uncertain.

**Acceptance:** ordinary named edits meet the calibrated feedback targets or have
a retained, explicit unmet result. No new fast path weakens complete verification.
Budget regressions are visible, report-only rollout precedes enforcement, and
unchanged runs preserve eligible cross-worktree and session reuse.

## DL7 Integrate self hosted stages into the measured loop

**Depends on:** the other branch's qualified milestones and DL4 identities.
Begin contract reviews during DL1; do not wait for DL6 to exchange changes.

Adopt qualified stages from the existing port in its chosen dependency order.
For each adopted stage, wire producer manifests, action membership, budgets and
cache evidence into the same tooling. Reuse its parity and bootstrap harnesses;
do not create a rival implementation or redefine completion as a collection of
partially hosted components.

Prove the useful edit boundary: changing the Selka implementation rebuilds the
affected component/functions with an existing qualified seed while preserving
unrelated host and component artifacts. Measure current behavior rather than
assuming the self-hosted compiler supports every desired incremental case.
Seed refresh and stage-to-stage bootstrap have explicit separate cold budgets.

For compiler stages, compare accepted/rejected programs, diagnostics, emitted
behavior, facts/leaks and cache decisions with the qualified reference. Keep
unsupported cases visible and selected routes free from silent native fallback.
Installed commands and source builds retain their Python-free contract; optional
developer reporting can remain Python.

Measure the port's required per-workload median and p95 against the frozen Zig
reference, and maintain a matched main comparison for development-loop changes.
Do not reset a slow baseline to make the 1.5-times requirement pass. Preserve the
full workload denominator and report instrumentation/cache modes identically.
If the branch delivers the full compiler at once, apply this wave as integration
and qualification rather than restarting the port in stages.

**Acceptance:** the adopted boundary has parity evidence, correct invalidation,
bounded recovery, measured rebuild/test cost and an explicit performance verdict.
Full self-hosting acceptance additionally requires the port's complete language
and driver ownership and qualified seed-to-stage1-to-stage2-to-stage3 bootstrap;
component rebuilds alone do not establish it.

## DL8 Qualify the combined loop and prevent regressions

**Depends on:** DL1 through DL6; repeat the matrix as DL7 milestones land.

Run the frozen edit matrix on the integrated main candidate, including cold,
unchanged, edited, reverted and compatible multi-worktree cases. Compare against
forced independent execution, isolating lower cache tiers where the test requires
true cold code generation. Exercise corruption, eviction, cancellation, crashes,
new tests, negative lookups, source mutation and transitive behavioral failures.

Archive exact source/toolchain identities, command receipts, required test counts,
cache states, per-phase timings, work counts and memory observations. Report
end-to-end latency, aggregate work and reuse separately. Timing comparisons obey
the existing admission/isolation rules and keep deferred results visibly deferred.

Turn demonstrated targets into regression checks. Prefer deterministic work-count
checks in ordinary tests; use repeatable Juice evidence and isolated latency
qualification for performance. Retain periodic full/reference comparisons as an
explicit qualification procedure; scheduled automation requires a separate request.

**Acceptance:** no missing required coverage, correct stale-result rejection,
improved representative edit loops and no unexplained cold-build or memory
regressions. Publish a table of achieved targets, remaining slow cases and approved
exceptions. Record the self-hosting acceptance verdict separately from loop gains.

## Delivery order and useful stopping points

1. **First implementation pass: DL1 and DL2.** Establish ownership, measurements,
   explanations and calibrated watchdogs. This is useful before either compiler
   implementation changes further.
2. **Largest structural opportunity: DL3 and DL4.** Reduce work invalidated by a
   small edit. DL5 profiling/optimizations can proceed on independent files.
3. **Daily workflow: DL5 and DL6.** Make unavoidable execution faster and expose
   quick feedback without weakening complete verification.
4. **Self-host integration: DL7 as qualified milestones arrive.** The other branch
   can proceed throughout; this roadmap does not require it to wait.
5. **Closeout: DL8.** Qualify loop improvements before the full port if necessary,
   then repeat against the self-hosted compiler when it is ready.

Each implementation wave should include its code, focused correctness checks,
required complete verification, raw performance evidence where available, and a
short report with tested commits, counts, limitations and the next handoff. Use
the existing admission coordinator and private Zig local caches. Guardian feedback
entries are not required. Timing unavailability does not justify an unsupported
speed claim or block independent correctness work.

## Primary references

- [Cache roadmap and correctness matrix](selka-toolchain-cache-plan-2026-10-10.md)
- [Verification and worktree operation](../tooling/many-agents.md)
- [Runtime budgets](../tooling/runtime-budgets.md)
- [Juice contracts and evidence](../tooling/juice.md)
- [Test layout and migration rules](../tooling/test-layout.md)
- [Independent component build and seed contract](../tooling/selfhost-components.md)
- [Existing parallel self-hosting brief](selka-incremental-selfhost-parallel-work-2026-10-10.md)

Reconcile historical test-layout prose and self-hosting briefs with live build
registration and the confirmed active branch before implementation. The ownership
and bootstrap continuation on the confirmed branch supersede its original pilot
task assignments where they differ.
