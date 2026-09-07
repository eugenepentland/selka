# Application maintenance comparison: .my, Python and Zig

Status: continuing evaluation plan, updated 2026-09-07. Standard-library parity
preparation is required before new timed application cohorts. This document
specifies the protocol; dated calibration reports retain earlier observations.
The [comparison coordinator](../../experiments/application_comparison/README.md)
tracks infrastructure acceptance separately from exploratory participant results
and the pending scored study. Native compilation of `.my` remains outside this
experiment: freeze the installed bytecode interpreter.

## 1. Decision and scope

Determine whether adopting `.my` reduces the total effort and cost of delivering
correct changes, especially as applications grow and several agents edit them.
Compare against Python and Zig separately. A win against one is not a win against
both, and a small-program result does not establish large-project usefulness.

The principal application outcome is independently accepted changes per unit of
application-development effort and cost after library parity preparation, with
final defect rate and independently reviewed code quality reported alongside it.
Report total adoption effort, including library development, as a separate outcome.
Compiler rejection counts, lines of code, number of tests and an agent's confidence
are explanatory evidence,
not standalone measures of success.

Run a small calibration/pilot before building a large benchmark. Extend only when
the protocol works and the initial evidence or a specific fix warrants the expense.
Keep baseline construction, compiler/stdlib development, agent familiarization,
application maintenance and verification infrastructure costs in separate ledgers.
All contribute to an adoption decision; setup is not silently treated as free.

## 2. Fairness contract

### Application dependencies

Only each language's standard library, compiler/runtime and application source
are allowed. Before timing application work, inventory the general-purpose
facilities available in the pinned Python and Zig standard libraries that the
planned workload needs, and implement any missing equivalents in `.my` first.
Freeze the reviewed `.my` standard-library/runtime inventory before scored tasks
and participant sessions. The parity process below defines this prerequisite.

- Python may use its actual standard library, including `json`, `dataclasses`,
  `enum`, `typing`, `collections` and `unittest`. No pip dependencies, mypy,
  Pyright, Pydantic, pytest or borrowed third-party implementations.
- Zig may use `std` and its built-in testing/build facilities. No fetched packages
  or external domain libraries in the application dependency graph.
- `.my` may use its frozen runtime, source facilities and audited basic I/O
  bridge. No Zig/Python helper may perform its parsing, geometry, graph algorithms,
  validation, rendering or other application business logic.
  General-purpose compiler/runtime intrinsics exposed through the frozen standard
  library (such as ordinary JSON parsing) are allowed, just as comparator standard
  libraries may use native implementations. The raw byte bridge must not add
  application-specific parsing, schema validation or algorithms.
- If a needed general-purpose facility is supplied by the pinned standard library
  of either comparator, `.my` must provide a tested, reusable equivalent before
  application timing starts. Do not charge its initial implementation as `.my`
  application work. Application-specific logic remains timed. Do not force Python
  or Zig to duplicate `.my`'s allocation model, module layout or error syntax.
  Use idiomatic, reviewed code.
- No vendoring, foreign-function escape hatch, external command used as a domain
  library, or network service may evade the dependency restriction. The evaluator
  and agent tooling are separate from the application, not callable shortcuts.

The primary comparison measures application development with the required
standard-library capabilities already available. It concerns language + prepared
stdlib + allowed tools, not a perfectly isolated estimate of syntax or type-system
quality. Differences in library investment remain in the separate adoption ledger.
Python annotations alone do not enforce types at runtime; do not report them as a static checker.
See the [Python typing documentation](https://docs.python.org/3/library/typing.html).
Allow normal runtime validation and strong tests rather than an intentionally weak
Python implementation.

### Standard-library parity before application timing

This rule applies to bug repairs, features, refactors and any future application
construction trials, including exploratory calibration. It covers the union of
needed capabilities supplied by **either** pinned comparator's standard library;
it does not require cloning every Python and Zig module before any experiment.
Verify availability against the actual pinned toolchain documentation/source.
Third-party packages remain outside the comparison.

1. **Inventory before tasks.** From the language-neutral workload contract and
   baseline dependency review, create a capability matrix listing the Python/Zig
   API and version, required behavior and limits, `.my` API or gap, implementation
   commit, documentation, independent acceptance evidence and readiness status.
   Include routine parsing/serialization, text/formatting, collections, sorting,
   general graph utilities where applicable, files/paths, time/random and testing
   support. Required semantics, not matching function names, determine parity.
2. **Implement missing library facilities first.** Build general-purpose `.my`
   modules and any necessary compiler/runtime support outside application clocks.
   Put reusable operations in the real standard library, with public contracts,
   examples, boundary/error tests and ownership/resource cleanup coverage. Use
   unrelated fixtures and an independent review; library authors must not receive
   hidden tasks, graders or task-specific solutions. EDA rules, planner policies
   and benchmark-specific wrappers cannot be relabeled as standard-library work.
3. **Prove workload sufficiency.** Check required input sizes, Unicode/number
   behavior, capacity, failure semantics and resource authority. A bounded API
   qualifies only if it covers the agreed workload. For example, the current
   256-byte hash keys and bounded decimal float parser require explicit review;
   their existence alone does not establish parity. Do not silently narrow the
   common contract to make an unsupported `.my` operation pass.
4. **Prepare and freeze.** Review all baselines for idiomatic use of their allowed
   libraries; replace baseline-local `.my` substitutes with the new APIs where
   appropriate. Count that migration as baseline preparation, not timed maintenance.
   Re-run common conformance and regression checks. Freeze library/compiler/bridge
   hashes, baseline snapshots, guides, build/cache policy and the capability matrix.
   Only then author/seal fresh scored tasks and launch fresh participants. Runtime
   implementation can differ, but application business logic stays in its language.
5. **Handle a newly discovered gap without editing the stopwatch.** Record the
   affected attempt and all matched attempts under that cohort's frozen rules.
   Do not pause a timed `.my` session, build a library, resume and subtract the time.
   Close the affected matched block as a parity-incomplete protocol observation,
   retain it in assigned-attempt accounting, implement and validate the gap, then
   launch a separately identified fresh matched block in all languages. Use unseen
   equivalent tasks and new participants; report restart cost and never pool its
   timing with the interrupted block. A library defect likewise requires a new
   library version and cohort; runtime defects remain reliability evidence.

Keep separate ledgers for **library/compiler preparation**, **baseline construction
and migration**, **agent familiarization**, **timed application work**, and
**independent grading/review**. Each records wall time, agent turns, tokens/compute
cost and human effort where observable; unavailable telemetry is unknown. The
primary application result excludes the first two ledgers. Also publish the full
adoption total and any amortization over an explicitly stated number of accepted
changes. Python/Zig's historical library investment is not reconstructed or charged
to their application clock; `.my` preparation is reported transparently rather
than treated as nonexistent.

The capability matrix and `parity_readiness.py` now check declared readiness and
bind its reviewed evidence to tools, libraries, all comparator baselines and
contracts. The direct exploratory setup verifies this receipt before preparation.
This is not automatic semantic proof; full scored-cohort binding remains pending.
Exploratory launch still requires the retained readiness review. Existing
calibration results keep their original library/build conditions and cannot be
retroactively presented as parity-prepared measurements.

### Developer tools and study arms

The user selected **Guardian for Zig in the main trial**. Freeze its policy and
binary, require a clean baseline, and count its time and required refactoring.
Agents cannot weaken gates, acceptance tests or contracts to finish a task.

| Arm | .my | Python | Zig | Interpretation |
| --- | --- | --- | --- | --- |
| Main workflow | Compiler checks, bundled navigation/quality tools, VM and declared-suite verification | Standard-library development/testing tools | Compiler/tests plus Guardian | Which permitted workflow is worth using? |
| Language-focused control | Compiler/VM; optional navigation/quality reports disabled | Same stdlib-only baseline | Compiler/tests; Guardian disabled in this separate trial | How much survives without the extra quality/navigation tools? |
| Tool removal experiments | Remove navigation or shared verification reuse, one at a time | Replay comparable verification conditions | Remove Guardian or shared verification reuse, one at a time | Which tool contributes, and what does it cost? |

Git, text search, the same shell/editor access and the coordinator are common tools.
The `.my` navigation client is development tooling, never an application dependency.
Do not add a third-party language server or Python type checker to one arm midway.
The control and tool removal experiments are separate matched cohorts, not a way
to subtract two unrelated averages and declare a causal language effect.

Freeze the model version, reasoning configuration, context limit, prompt scaffold,
agent permissions, OS, hardware allocation and all executable hashes per cohort.
The currently available runtimes are Python 3.14.4 and pinned Zig
`0.17.0-dev.1683+5ceec001b`; record the actual versions at launch. Use the ReleaseFast
`.my` VM with its ordinary checked language semantics. Zig should retain checked
application arithmetic/ownership expectations, normally through Debug tests and
ReleaseSafe application runs. Do not compare safety-disabled Zig with a checked VM.

Build language tools once before participant work. Ordinary `.my` edits load from
disk and must not rebuild Zig or run Guardian on the language implementation.
Application Zig compilation and its Guardian gate remain inside the measured
workflow. No compiler, standard library or trusted bridge changes during a scored
cohort; a necessary fix ends that version's cohort and starts a separately reported
one. Missing language features remain visible product limitations.

## 3. Applications and baseline construction

Build two useful applications from language-neutral behavioral contracts. Start
small and grow the same product through reviewed releases. Use existing EDA work
as a starting point, but do not mechanically translate its architecture.

| Application | Initial behavior | Growth that creates real maintenance work |
| --- | --- | --- |
| EDA project inspector | Parse a bounded schematic/board description, resolve IDs/units, validate nets and constraints, emit reports and SVG | Hierarchical subcircuits, multiple rule families, import/export versions, shared constraints, diagnostics, deterministic layout, incremental report invalidation |
| Workflow/dependency planner | Parse job manifests, resolve a dependency graph, reject cycles, produce a deterministic plan and report | Resource limits, dependency policies, artifact identities, version migration, cache invalidation, cancellation/retry states and multiple report consumers |

The planner operates on modeled jobs; executing external tools is not a shortcut
for implementing its algorithms. The second workload reduces the chance that an
EDA-specific design or prior knowledge determines the whole result.

Each language owns input parsing, validation, algorithms, state transitions and
serialization. A `.my` host bridge may only supply documented basic operations
such as raw byte I/O. Freeze and audit it before the trial; retain its source,
marshalling costs and tests. Do not feed `.my` prevalidated rich objects while
charging Python and Zig for parsing and validation in the same comparison.

The existing board trial's Zig rectangle callback must be implemented in `.my`
for this stdlib-only comparison. Do not time its existing dual-language runner as
though the host contribution were free. The old repair harness also documents
unequal per-input and rebuild overhead; those paths must be replaced.

Construct each baseline with separate agents/sessions that see the same contract
but not another language's implementation. Have reviewers familiar with each
language improve idioms and obvious performance problems before freezing. Match
observable behavior, input limits, failure semantics and conceptual subsystems,
not source text. A second independently constructed baseline for a promising large
workload is a useful confirmation against architecture/author bias.

Preflight real input sizes and supported features. If the agreed application cannot
be implemented without a forbidden helper or compiler change, record the gap and
cost before reducing scope. Do not quietly make every task fit `.my`'s strongest
features. The feasibility result is itself relevant to adoption.

## 4. Testing the effect of codebase size

Use three snapshots per application. These ranges are planning envelopes, not
quotas, scoring criteria or permission to manufacture redundant code.

| Tier | Approximate conceptual/module scale | Typical source envelope | What it tests |
| --- | --- | --- | --- |
| Small | 10–20 meaningful modules | 2–5k lines | Whether the workflow works and fixed overhead dominates |
| Medium | 40–70 meaningful modules | 8–20k lines | Finding owners and changing contracts across subsystems |
| Large | 100–180 meaningful modules | 25–60k lines | Wider dependency graphs, unfamiliar features, handoffs and concurrent changes |

Actual physical files/lines will differ by language. Match product capabilities
and conceptual dependency graphs, and report actual source bytes, symbols, public
contracts, graph depth, fan-in/fan-out and task impact. Python should not be padded
because its stdlib makes an implementation shorter. Existing `.my` defaults cap
projects at 256 modules, 4096 imports and 16 MiB of source; feasibility must verify
all budgets rather than promising an arbitrary million-line project.

Grow with exercised features and real cross-module relationships. Separate a
synthetic generated stress test from application-maintenance results; thousands
of unrelated helper functions are insufficient evidence of maintainability.
Input-data size is a separate axis: small/representative/stress fixtures must not
be confused with source-codebase size.

Use two kinds of matched changes:

1. **Stable local changes:** retain the same target behavior and similarly sized
   necessary patch across all tiers while surrounding real features grow. This
   isolates the cost of finding and understanding the relevant code.
2. **Contract changes:** evolve a shared concept with deliberately increasing
   numbers of real consumers. This tests detecting and repairing the wider impact.

Include both a reused root area and an unfamiliar subsystem. Most maintenance
participants start with a fresh context; a smaller longitudinal track retains
project history. Neither case alone represents how all ten-agent teams work.

## 5. Task corpus

Write issue descriptions and independent acceptance criteria before observing
language results. Use a mixture of EDA-backed requests and neutral workload
requests. Match requirements and failure modes; the language-specific patch may
legitimately differ. Do not require every task to seed a compiler-detectable bug.

| Family | Example | Evidence sought |
| --- | --- | --- |
| Local bug/input boundary | Inclusive rectangle edge; duplicate manifest key; an invalid ID | Navigation cost, diagnostic repair, meaningful input rejection |
| Shared schema/state evolution | Add a net category or job cancellation state used by validation, storage and reports | Missing consumers, exhaustive handling, behavioral regressions |
| Feature extension | Add an inherited constraint and visible SVG annotation; add a scheduling policy | End-to-end delivery, API reuse, clear boundaries |
| Cross-module rule refactor | Centralize an actual repeated eligibility rule, then change its meaning | Whether independent consumers stay consistent; follow-up cost |

Vary malformed input, units, identity, ownership and allocation/budget edges
within those families. Preserve already passing behaviors as well as testing the
new request. Use reasonable integer/input bounds in the contract; do not invent
fixed-width overflow requirements merely to disadvantage Python.

For discovery tasks, give the issue and entry point, not the answer's filename.
For implementation-only controls, supply the relevant locations to all languages.
Keep the task domain equally explained. Use no misleading names or deliberate
obfuscation added only to make navigation look valuable.

The corpus must also contain mundane parsing, formatting and collection work
where Python's standard library may be advantageous. Failure to represent these
would make the result a selected safety-feature demonstration.

## 6. Participant and grading protocol

1. Complete and retain the standard-library parity review, then freeze clean,
   fully accepted baselines, tool identities, task variants, budgets,
   public development tests and the hidden grader/generator before the cohort.
2. Create a matched three-language block for each task, tier, application and
   repetition. Randomize dispatch order and machine/time slots. Fresh participants
   receive the same model/settings and equivalent same-language documentation.
3. Give `.my` concise language examples and every language a comparable API/tool
   guide plus the bounded warm-up specified below. Count familiarization separately. Model prior
   exposure to Python/Zig cannot be equalized; it is a real adoption limitation,
   so record it rather than claiming equal experience.
4. Use isolated checkouts with all application source editable; the old one-file
   repair restriction is unsuitable. Contracts, graders, policies and trusted
   adapters are read-only. Permit necessary new files and application tests.
5. Record model/tool events, source snapshots and every submitted check. A check
   after each candidate produces a source identity and a response. Preserve raw
   diagnostics rather than trusting an agent's claimed reason for failure.
6. Seal the final submission on completion, timeout, abandonment or a budget hit.
   No hidden grading feedback returns to participants. Freeze one hidden case set
   per matched block and run it against all three sealed submissions.
7. Grade in a fresh environment with a full check on the exact final source and
   merged dependency set. Development cache receipts cannot certify hidden tests.
   Return separate behavioral, policy, performance and infrastructure outcomes.

Use actual filesystem/process isolation for participant tools: mount only their
worktree, approved toolchains/docs and public fixtures, excluding hidden tests,
other implementations, reference answers and coordinator state. Instructions or
ordinary worktrees alone do not provide blinding. New sessions must not inherit
this design conversation, earlier patches or a sibling's hidden results.

Proposed pilot limits are 30 minutes of participant elapsed time per task, with
identical model/context settings. Before launch, use unscored calibration to set
one common token/spend ceiling per task family and publish it in the manifest.
The larger study may use 45-minute tasks if calibration shows that is appropriate;
freeze that decision before scored runs. Time includes checks and normal waits.
Log provider outages, coordinator delay and human pauses separately. An outage
policy must be preset; rerun a whole matched block when needed and retain originals.
An unsupported feature, compiler defect, slow check, or exhausted normal budget
counts against product usability and is not erased as generic infrastructure noise.

### Timing and allowance for a new language

Time every session, but treat elapsed time as one outcome alongside correctness
and cost. The time limit is a common resource ceiling, not an instruction to rush
a patch. Calibrate a generous ceiling on unrelated tasks before scoring. If almost
everything times out, the study cannot distinguish much; change the next cohort's
budget for all languages rather than extending only `.my` after seeing results.

Use explicit clock boundaries. Library parity and baseline migration must be
complete before either familiarization or task work begins:

- **Library preparation:** starts at capability inventory/implementation and ends
  at reviewed library readiness; includes compiler fixes, tests and documentation.
  Baseline migration has its own ledger. Neither is application-development time.
- **Familiarization:** starts when the agent receives the language/tool guide;
  ends when it finishes the practice exercises or reaches the preparation cap.
- **Task work:** starts before the agent can read the scored issue or repository;
  ends when the final candidate and required development checks are submitted,
  or at the common task budget. Reading source/docs, navigation, coding, builds,
  Guardian, testing and ordinary queue waits all remain on this clock.
- **Independent acceptance:** log subsequent grading/review and any allowed
  delivery-stage recovery separately. Publish delivery elapsed time as well as
  participant time, so expensive validation does not disappear from the result.

Propose up to **20 minutes of preparation**, with a concise reference, runnable
examples and three unrelated exercises: import/call a module, handle a fallible
operation, and repair a representative diagnostic. Offer the same preparation
ceiling to every language; completion can be earlier. Freeze equivalent conceptual
exercises and language-appropriate examples before the study. The scored issue,
repository and hidden tests remain unavailable during preparation. Adjust this
provisional cap only through unscored calibration before the cohort is frozen.

Record practice correctness, actual time and tokens. Keep participants that fail
the warm-up in the assigned cohort and report that outcome; selecting only the
agents that mastered `.my` would hide an adoption cost. Practice improves access
to the rules, but cannot establish equal prior language familiarity.

The proposed 36 pilot sessions use this preparation phase followed by the same
30-minute task ceiling. Report both **post-preparation development** and
**onboarding-inclusive cost/time** from those same sessions. These are two views
of a guided workflow, not a causal cold-versus-warm experiment. An actual no-practice
first-use control requires additional fresh, randomly assigned sessions on a
preselected subset and an explicit additional budget.

Keep the guide and that participant's practice history available during its scored
task. A new independent session needs its own guide/preparation; prior sessions
must not be assumed to have permanently taught the model. A fixed reusable language
cheat sheet is allowed, with its version, construction cost and prompt tokens
recorded. It must contain no study-task solutions or information from earlier
scored attempts. Larger longitudinal trials may retain authorized project context
and amortize preparation across the actual sequence, reporting context resets.

Do not discount `.my` time by an arbitrary percentage, pause the task clock for
syntax questions, or grant selective extensions after failures. This provides
room to learn while keeping recurrent learning effort, documentation quality and
the cost of onboarding ten fresh agents visible to the adoption decision.

The grader combines independent reference algorithms, known boundary cases,
metamorphic properties and old-behavior regressions. For example, identity renaming
and translating a board should preserve the specified rules; SVG XML must preserve
connectivity and geometry regardless of irrelevant attribute order. Multiple tests
exposing one root cause count as one defect, not hundreds of independent bugs.

Validate the grader with correct alternative solutions and deliberately wrong
ones. Hidden tests may reject only behaviors prohibited by the written contract.
Review ambiguous outcomes while blinded to aggregate scores, and apply a revised
rule to every affected language/run. This follows the useful separation between
frozen candidate patches and reproducible evaluation environments in the
[SWE-bench evaluation protocol](https://www.swebench.com/SWE-bench/guides/evaluation/);
its task corpus and dependencies are not being adopted here.

## 7. Measures and attribution

| Measure | Definition and interpretation |
| --- | --- |
| Acceptance within budget | Fraction of all assigned tasks whose final patch passes independent behavior, agreed contracts and the arm's required gates |
| Defective final submissions | Fraction with independently established root-cause defects; separate severity, observed misses and ungradable timeouts |
| Cost per accepted change | All API/tool compute expenditure across assigned runs divided by accepted changes, with human time reported separately; undefined if none succeed |
| Time to an accepted submission | Elapsed time to the submitted candidate later verified correct; summarize alongside failures, not only successful runs |
| Delivery throughput | Accepted changes per fixed experiment wall-time window or human oversight hour, especially for concurrent waves |
| First repair after a diagnostic | First edited submission following that specific diagnostic passes its target and regression tests; distinguish repeated unchanged checks |
| Agent turns and repair loops | Count participant model responses in the task phase, tool calls separately, and edited candidate/check cycles to independent acceptance; report failures and missing turn telemetry, not just successful attempts |
| Reviewed code quality | Predeclared rubric for API clarity, cohesion, duplication, error/resource handling and test relevance; independent reviewers inspect sealed source, then follow-up tasks test maintenance cost |
| Library parity preparation | Missing capabilities, implementation/review time, defects, migration cost and frozen readiness evidence; separate from application speed and included in adoption accounting |
| Navigation effort | Search/read commands, source/context bytes and tokens, irrelevant files opened, and time to first recorded relevant location |
| Verification delay | Actual check execution, queue wait, repeated work, cold/warm cache hits, stale hits rejected and dependency-selection misses |
| Maintenance disruption | Necessary versus unrelated edits, duplicated decision rules, weakened contracts, special-case workarounds and downstream edits needed |
| Runtime suitability | Latency, startup/reload time, CPU and peak memory on common inputs; interpreter speed is a separate product constraint |

Define a set of valid relevant locations per task, allowing alternative designs.
Opening a file does not prove understanding: navigation measurements are proxies,
confirmed by subsequent edits and grading. Reviewers should be blinded to tool
condition and aggregate results where practical; language syntax prevents full
language blinding. Subjective quality ratings support behavioral evidence, not
replace it. Shorter source and lower complexity scores are not automatic wins.

Do not infer bugs prevented from a compiler rejection alone. Classify findings as
actual defects, useful review, intentional changes, false positives or uncertain,
using the patch and independent behavior. A compiler may prevent a defect from
executing, but it may also enforce a convention with no behavioral benefit.

Record tool intervals and their overlap. Never add parallel command durations to
estimate human waiting or team elapsed time. Log human interventions and API
input/output/cached token usage directly; missing telemetry is unknown, not zero.
METR's [2026 productivity-study update](https://metr.org/blog/2026-02-24-uplift-update/)
describes selection and concurrent-agent timing problems, which motivates fixed
assigned tasks and direct event logging here rather than self-reported speedups.
It does not predict the outcome of this language comparison.

Require a declared runtime latency/memory envelope for each real application
before scoring. A VM can be slower than Zig and still suit the intended workload;
missing the agreed envelope is a product limitation even if editing is faster.

## 8. Longitudinal and ten-agent trials

First use independent frozen tasks for an interpretable baseline. Then test actual
maintenance through a sequence of accepted features, schema changes and repairs.
Hand the resulting branch to a fresh agent for an undisclosed, preselected follow-up.
This is where a seemingly tidy abstraction may create extra work later.

Select follow-up task families before observing which language succeeds. Carry
failed initial submissions forward as failed chains or count the recovery effort;
do not discard them and compare only the cleanest surviving branches. Report chain
completion, cumulative cost, recurring defects and review time. Fixed accepted
checkpoints can also support a separate controlled handoff comparison, but those
results must not be mixed with naturally accumulated branch quality.

For concurrency, begin with deterministic replay of matched changes. Apply the
same logical edit sequence to ten worktrees per language under cold, equivalent
warm and post-main-update cache states. Use repeatable CPU/RAM quotas, randomized
condition order and no competing language wave on the same allocated machine.
Replay measures verification infrastructure, not how fast agents can invent code.

Then run live ten-agent waves with a fixed backlog containing independent edits,
shared-schema changes, competing rule edits and changes that interact only after
merge. Include a main update during the wave. Every language gets the same resource
budget and task mix. Use a neutral merge coordinator and record its repair effort.

The common suite driver can schedule/cache all three languages' declared suites;
`.my` may additionally use its existing compiler dependency receipts. Zig's own
cache and Guardian remain enabled in its main workflow. Use conservative declared
closures for other implementations, never unsound guesses to make their checks
look faster. Report manifest authoring/maintenance as a tooling cost. Development
subset selection is checked against a full final combined-candidate gate.

Measure accepted combined changes per wall hour, queue delay, work coalescing,
CPU/RAM peaks, merge conflicts, semantic merge regressions, repeated checks and
stale-result rejection. Verify the exact combined candidate, not the independent
branch heads; hidden evaluation stays fresh. Keep failures and wasted work in the
denominator. Existing merge-certificate tooling does not itself merge branches.

A ten-agent wave needs ten real isolated sessions. Our current four-slot agent
setup cannot establish live ten-agent throughput; use a separate launch facility
or label a smaller run honestly. Fixed-patch replay is possible earlier, but must
never be presented as ten live agents developing concurrently.

## 9. Staged sample and analysis

| Stage | Proposed scope | Exit condition |
| --- | --- | --- |
| 0. Library parity, feasibility and calibration | Inventory needed comparator stdlib facilities; implement/test missing `.my` equivalents; migrate/review six small baselines | Reviewed capability matrix, common conformance, frozen libraries/guides/build policy, working isolation and calibrated budgets; unresolved gaps block timing |
| 1. Pilot | Six new small/medium task blocks × three languages × two independent attempts = 36 sessions | Reliable telemetry/grading, task difficulty calibration and explicit failure review; exploratory results only |
| 2. Main maintenance study | Two apps × three tiers × four task families × three languages × two repetitions = 144 sessions | Matched results with uncertainty, size/impact breakdown and separately reported Python/Zig comparisons |
| 3. Follow-up maintenance | Eight preselected medium/large task chains × three languages × two repetitions = 48 additional sessions | Whether early patches reduce or increase later change cost |
| 4. Team workflow | Fixed-patch replay, then two ten-agent waves per language = 60 live sessions if warranted | Combined-change throughput and merge correctness under measured resource limits |

The pilot and main study total 180 sessions, not 180 independent task designs.
The optional maintenance/team stages add 108. Do not launch all stages at once.
Pilot task wording/answers never enter the main study. Run a small separately
budgeted matched tool-removal cohort when needed to explain a promising or harmful
result; it is additional work, not already included in these totals.

Budget model: baseline authoring + harness/isolation work + number of sessions ×
measured pilot cost + review/grading + compiler/stdlib maintenance. Quote launch
cost from actual pilot API usage and elapsed compute; do not invent a currency
estimate without a selected model, pricing and resource allocation.

The main design has 24 task blocks, with two attempts in each language. Repeated
attempts on the same task and thousands of hidden inputs are not independent
samples. Report paired differences by block, both workloads and all tiers. Use
block-clustered intervals for completion, defect and cost differences; show
success-only timing separately and retain budget failures in primary outcomes.
Do not invent a completion time for an unfinished task. A declared capped-time
summary can assign the budget for ranking, but is labeled a penalty, not observed
time-to-success. If uncertainty is wide, collect additional task blocks rather
than merely rerunning a favorite task more often.

Estimate the change in the `.my` advantage from small to large, separately for
stable local tasks and increasing-impact changes. A larger benefit only on a
larger, unrelated task is not evidence that codebase size caused it. With two
applications, conclusions remain limited to these workloads and this model/tool
cohort. Replicate a promising result on another model and an independently built
baseline before making broad claims; existing model exposure is not controlled away.

## 10. Decision rules to agree before scoring

These are proposed investment thresholds, not guarantees or statistically derived
sample-size claims. Keep behavioral acceptance and practical cost separate.

- **Promising productivity result:** around 20% lower cost per accepted change on
  medium/large work, with no material degradation in acceptance, defects or runtime
  suitability, against each comparator separately.
- **Promising reliability result:** around 30% fewer defective final submissions
  with no more than roughly 10% extra delivery cost, at comparable completion and
  task mix. If defect counts are too low, mark this question unresolved.
- **Strong large-codebase evidence:** the advantage survives realistic shared
  contract changes and fresh-agent follow-ups, and is not explained only by warm
  caches, a poor baseline or one compiler-friendly task family.
- **Continue with a targeted fix:** a specific recurring cost, such as unclear
  diagnostics, a missing stdlib primitive or excessive navigation output, explains
  otherwise promising outcomes. Record implementation cost and test a new cohort.
- **Pause or narrow scope:** larger tasks repeatedly fail on language limits,
  advantages disappear against the stronger baseline, or compiler/stdlib/tooling
  investment outweighs maintenance savings. A good EDA-specific result can justify
  a narrower language without claiming a general replacement for Python or Zig.

Require the predeclared quality guardrails and interval estimates before calling
an observed threshold a demonstrated win. An exploratory point estimate supports
another experiment, not certainty. Define material acceptance/defect margins using
product risk and pilot feasibility before the main study; do not pick them after
seeing which result is favorable. Rare severe defects need specific tests/review,
not a claim of absence from a small sample.

For investment accounting, report the estimated break-even number of accepted
changes as additional adoption/toolchain cost divided by savings per accepted
change, using the same units and explicit labor valuation. If measured savings are
nonpositive, there is no measured break-even yet. Keep human minutes, compute cost
and total team elapsed time separate unless a conversion is explicitly chosen.

## 11. Implementation sequence and deliverables

1. Add a v2 comparison coordinator beside the existing repair study. Reuse its
   source snapshots, tool hashing, sealing and resumable grading patterns. Replace
   fixed guest/Zig pairs with language adapters and matched three-language blocks;
   allow multi-file edits/new files and capture actual model/tool telemetry.
2. Implement process/filesystem isolation and a minimal audited `.my` byte-I/O
   bridge. Add harness acceptance for timeout, tampering, changed tools, interrupted
   grading, source races, hidden-data access, stale receipts and unequal dispatch.
3. Use the two contracts and dependency manifests to review the capability matrix.
   Implement and independently test missing `.my` standard-library equivalents
   first, then migrate/review the six small baselines and run common conformance.
   Move shared native business logic into the language implementations. Freeze
   library readiness and all source/tool identities before selecting scored tasks.
4. Register the six pilot tasks, common budgets and outcome schema. Run 36 fresh
   sessions. Publish every attempt and failure class, costs and protocol deviations.
5. Use the pilot to decide whether building the medium/large releases is justified.
   If proceeding, freeze new tasks, expand the corpus and run the 144-session study.
6. Run selected follow-ups, tool-removal controls and concurrency replay/live waves
   only where they answer an unresolved investment question.

Proposed artifacts:

- `experiments/application_comparison/contracts/`: behavior, dependency rules,
  resource envelopes, task families and acceptance predicates.
- `experiments/application_comparison/study-plan.json`: versioned cohort design,
  randomization, frozen identities, budgets, metrics and stopping rules.
- A versioned capability matrix and library-readiness receipt, linked to API docs,
  commits, independent acceptance and separately recorded preparation costs; cohort
  validation must reject unresolved required gaps before scored launch.
- A stdlib-only coordinator/adapter/reporting package and public acceptance tests;
  grader data, answers and sealed participant artifacts stored outside worker mounts.
- A report with raw per-run records, paired comparisons, uncertainty, size/impact
  trends, longitudinal outcomes, tool attribution and adoption-cost accounting.

The original planning phase did not launch participants. Current implementation
and calibration status is recorded in `study-plan.json` and the dated experiment
reports; draft fixture validation and exploratory sessions are distinct from the
scored pilot.


## Next continuation: evaluate after library preparation

The [standard-library expansion](../standard-library.md) is implemented and its
[combined acceptance receipt](../../experiments/validation/stdlib-20260907/receipt.json)
records 73/73 build steps and 1071/1071 Zig tests, plus native/application suites.
That validates implementation coverage; it does not establish workload parity or
faster application development.

1. Audit the existing EDA/planner baselines against the expanded library and make
   the capability matrix. Fill remaining comparator-stdlib gaps before any new
   timed application block; retain costs and migrate reusable baseline helpers.
2. Refresh the installed trial compiler/byte host, guides, dependency inventories
   and frozen environment receipts to the reviewed version. Revalidate isolation,
   public/private graders and the same suite-build-reuse policy for every language.
3. Run fresh matched bug-fix, shared-contract and feature blocks with the same
   model/settings and common budgets. Previously exposed planner/EDA tasks may
   calibrate the harness, but scored tasks and variants must be unseen. Keep the
   planned 36-session pilot provisional until this readiness review is complete.
4. Report acceptance, root-cause defects/severity, application time, turns/repair
   loops, compute cost and independent quality review together. Keep preparation
   and total adoption results beside them. Compare Python and Zig separately;
   preserve failed, interrupted and parity-incomplete attempts.
5. Only after usable pilot evidence, grow medium/large workloads, repeat the
   capability review before freezing each cohort, and run follow-up maintenance
   and concurrent-agent trials. New application construction can be a separate
   matched study with the same library-first rule; do not mix its times with
   maintenance sessions or silently add it to existing sample totals.

## Direct coding-agent calibration (2026-09-07)

At the user's request, run the initial exploratory trials with fresh coding
subagents in the current session. This route requires no API key. The API
coordinator remains an optional execution route, not a prerequisite to testing.

The first matched block is `planner-priority`: one independent participant each
for `.my`, Python, and Zig, with standard-library-only application dependencies.
Use Guardian for the Zig main arm and the installed compiler/navigation tools for
`.my`. Give every participant the existing practice exercise (20-minute maximum),
then the feature task (30-minute maximum). Record actual preparation and task time
separately, with no language-specific discount. Public checks precede freezing;
common private grading follows only after all three submissions are sealed.

Participants are instructed to perform every source read, edit and execution
through the namespace-isolated gateway. The coding-agent runtime still has broad
host tools: this is instructional whole-agent separation, not enforced
whole-agent isolation. Record shared-host contention, exact-model-ID and
token/cost telemetry gaps, draft task coverage, and the single repetition as
limitations. Do not count these runs as scored pilot sessions or infer a language
ranking. Use their failures and tool friction to decide the next matched blocks.

Retain configurations, source snapshots, phase clocks, public checks, gateway
command logs, private grading, and protocol deviations under
`/home/epentland/ai/canopy/application-trials/direct-20260907`. Publish a concise
report in the language repository after grading.

Completed result: [direct agent calibration report](direct-agent-calibration-20260907.md).
All three participants passed private grading; scored pilot sessions remain zero.

Follow-up completed: [suite build reuse and EDA repair trial](direct-agent-clearance-20260907.md).
The new repair block passed private grading for all three languages; keep timing
separate from the earlier priority block, which used repeated cold builds.

Third exploratory block completed: [pin-role shared-contract results](direct-agent-pin-roles-20260907.md).
All three participants passed private grading; nine direct-agent sessions now
have results, with no scored pilot or productivity advantage claimed.

## Library-prepared rotation checkpoint (2026-09-07)

The capability audit, five additional reusable modules and both baseline migrations
are complete for current v1 workloads. The [fresh rotation trial](stdlib-parity-rotation-20260907.md)
passed private grading for all three languages. `.my` and Python each took about
117 seconds of application work; Zig with Guardian took 214 seconds. Library
preparation was excluded and recorded separately. This fixed-order exploratory
block has no established productivity/defect-rate advantage and is not pooled
with older calibration. The [portable planner follow-up](portable-planner-trials-20260907.md)
now adds nine fresh repair/shared-contract/feature sessions: all private packs and
prelaunch cycle limit checks passed. Preparation and application clocks remain
separate; there are 21 exploratory sessions overall and zero scored sessions.
Next prepare a medium-size maintenance workload with the same library-first rule;
verifiable model/turn/usage telemetry and enforced participant confinement remain
prerequisites for scored claims.
