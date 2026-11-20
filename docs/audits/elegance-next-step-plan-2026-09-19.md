# Next experiment: make correct changes require fewer decisions

Date: 2026-09-19. Status: proposed implementation plan.

Working hypothesis: a useful design states a rule once and supplies its
consequences, reducing what an agent must rediscover while preserving behavior.
The next step is to test that mechanism with trustworthy measurements. A
compression score is not needed for this experiment.

Build on [diagnostic-feedback](../../experiments/diagnostic-feedback/README.md),
its [initial results](../../experiments/diagnostic-feedback/findings-2026-09-19.md),
and the [testing review](research-testing-review-2026-09-19.md).

**Implementation order**

| Milestone | Deliverable | Exit condition |
| --- | --- | --- |
| M0 | Reliable invocation accounting, immutable cohorts, stronger acceptance | Harness regressions pass; historical recount published with its limitations |
| M1 — immediate next experiment | Text/JSON × suggestion/no-suggestion comparison | Frozen pilot and scored cohort completed; per-family results and uncertainty reported |
| M2 — separate experiment | Repair versus independent sampling at common budgets | Actual budget enforcement demonstrated; success-versus-budget curves produced |
| M3 — structural follow-up | One project-aware command for invocation mistakes | Same semantics and acceptance; fewer avoidable invocation failures on unseen projects |

Implement M0 and M1 first. Keep M2 and M3 separately selectable; the default
command must not launch every milestone. Language-level changes to module identity,
MDL scoring, abstraction discovery and a new decoder remain later decisions.

**M0: repair the measurement instrument**

1. Replace the transcript-wide regex in `diagnostic-feedback/run.py` with one
   event per actual compiler process. Instrument the compiler wrapper before
   rendering either text or JSON, so measurement is identical across treatments.
   A shell command containing three compiler invocations must produce three
   events; one invocation containing three diagnostics must produce one event.
   Assistant prose and echoed historical output must contribute no events.
2. Record events through a coordinator-owned collector outside the candidate
   source tree. Preserve participant stdout/stderr unchanged except for the
   assigned rendering treatment. The event collector must not expose hidden
   cases, expected answers or acceptance results to participants.
3. Snapshot source content before each invocation and check identity afterwards.
   Use relative paths and hashes of the complete candidate source inventory,
   including additions/deletions. Record source changes during execution as
   invalid measurements. Keep caches and reports outside that inventory.
4. Have the coordinator grade an immutable final snapshot using its frozen
   compiler and verifier, independent of the participant's editable files or
   wrapper. Preserve all failed, timed-out and interrupted candidates.

Suggested event fields:

```json
{
  "schema": "compiler-invocation-v1",
  "cohort_id": "...",
  "attempt_id": "...",
  "invocation_id": "...",
  "command": "check",
  "argv": ["check", "project/main.my"],
  "cwd": "...",
  "source_sha256": "...",
  "compiler_sha256": "...",
  "started_monotonic_ns": 0,
  "finished_monotonic_ns": 0,
  "exit_code": 1,
  "outcome": "source_error",
  "diagnostic_codes": ["E_TYPE", "E_TYPE"],
  "source_stable": true
}
```

Also retain raw stream hashes and paths, termination reason, missing-event flags,
and observed suggestion IDs. Outcomes must distinguish source rejection, runtime
failure, public-test failure, successful check, invocation misuse and infrastructure
failure. Do not infer an outcome from finding the word `error` in arbitrary output.

Use explicit metric names:

| Metric | Definition |
| --- | --- |
| Failed compiler invocations | Completed compiler processes rejected for source or invocation errors; infrastructure failures separate |
| Failed checks on changed source | Failed check/build/run invocations whose source hash differs from the initial snapshot |
| Failed candidate versions | Distinct changed source hashes with a failed check; repeated checks on unchanged code count once here |
| Repeated diagnostic | The same diagnostic identity on distinct failed invocations; report raw code counts separately |
| First compiler green | First successful compiler check on a recorded snapshot; compilation alone is not task completion |
| First public acceptance | First snapshot passing the common public behavior checks |
| Hidden acceptance | Final selected snapshot passing all private requirements after sealing |

Keep initial diagnosis attempts visible. A fix suggested on the first check and
applied successfully has one initial failed invocation and zero failed checks on
changed source. Do not call both quantities “repair rounds.” Use stable semantic
diagnostic identities where possible; a shared broad `E_TYPE` code alone does not
identify the same underlying error.

**Preserve cohorts and historical evidence**

- Add a frozen cohort manifest listing every eligible case, treatment, repetition
  and attempt, with source, oracle, prompt, wrapper, compiler, runner and model
  identities. Normalize cache configuration by policy rather than absolute path.
- Store evidence as `cohorts/<id>/runs/<arm>/<case>/<repeat>/<attempt>/`.
  Refuse an existing destination. A retry is a new attempt with a reason and a
  link to its predecessor; it never silently replaces a failure.
- Score only manifest-listed records. Adding a follow-up run elsewhere must not
  change a published cohort's numbers. Generate Markdown and JSON from the same
  aggregation, including every selected arm; the current scorer omits `oneshot`
  from its condition summaries.
- Write a separate historical recount. Parse only matched tool-call/result
  events; deduplicate repeated delivery by event identity. Count exact invocations
  only when boundaries and outcomes are reconstructable. Otherwise report
  “tool results containing diagnostics,” with missing coverage, rather than
  retroactively inventing exact compiler events.
- Retain the original 108-session study, including its defective-task attempts
  where available. If overwritten raw evidence cannot be recovered, document the
  gap. The corrected task belongs to an explicit revision.

Required regression cases: assistant quotes a diagnostic; one process emits
multiple diagnostics; two compiler calls share one shell command; successful
check has empty output; a failed process emits non-diagnostic stderr; repeated
reads of a result; missing/truncated event; timeout; source changes during a
check; baseline green is not task acceptance; adding a follow-up cannot alter
an old score; retries cannot overwrite; incompatible manifests cannot be pooled.

**Make the behavior oracle discriminating**

The present tiny tasks often grade one known stdout value. Before expanding the
study, make each task require behavior on several inputs and reject shortcuts.
For example, bool/int checks need true and false cases; result handling needs
success and error paths; a generic repair needs more than one valid use; module
tasks must preserve the helper and exercise multiple consumers.

Each case must have: a failing initial source, a reviewed reference repair that
passes, public examples, independent hidden cases, and deliberately wrong
repairs that the oracle rejects. Include returning the advertised constant,
deleting a required helper, bypassing error handling and weakening a signature
in ways the contract forbids. Give any structural requirement explicitly in the
public task; do not hide an architectural preference in the grader.

Preflight both the faulty and reference versions through the actual isolated
participant command path. Check expected stdout/exit semantics, local/global
cache paths and the verifier itself before starting a cohort. This catches the
wrong-expected-output defect that invalidated the original pilot case.

**M1: separate actionable advice from its presentation**

Hypothesis: an applicable remedy reduces unsuccessful work on result handling
and generic requirements, across more than the examples used to write that remedy.

Run this complete factorial design:

| Arm | Diagnostic representation | Remedy |
| --- | --- | --- |
| `text` | Existing text | None |
| `text_fix` | Same text | Appended suggestion |
| `json` | Structured fields | None |
| `json_fix` | Same structured fields | Identical suggestion content |

Implement the suggestion once and render it both ways. Preserve the underlying
code, location, message, source context and notes across representations. The
initial prompt, command examples, documentation, tools and acceptance checks
must be identical in every arm. Do not give only one arm usable invocation
instructions. Verify treatment delivery from the emitted events, including
cases where no suggestion matches; retain those cases in the assigned arm.

Freeze remedies using development cases. The existing `dev`/`test` split holds
out examples within the same families; it does not hold out entire error families.
Create fresh confirmatory examples with different control flow, call sites and
error paths. Keep their task briefs and hidden cases away from remedy tuning.

Recommended bounded first cohort:

| Cases | Arms | Fresh repetitions | Sessions |
| --- | ---: | ---: | ---: |
| Development pilot: one case from each of four families | 4 | 1 | 16 |
| Checked-result: five fresh variants | 4 | 2 | 40 |
| Generic-requirement: five fresh variants | 4 | 2 | 40 |
| Controls: bool/int and variant coverage, two fresh variants each | 4 | 2 | 32 |
| Main cohort total, excluding pilot | | | 112 |

The sample size is a bounded initial allocation, not a claim of statistical
power. Prefer varied programs over ten repetitions of one program. Include both
local repairs and a few two-function repairs so all outcomes are not at ceiling.
If the pilot shows an uninformative workload or broken measurement, revise it
before freezing the main manifest; do not repeatedly tune against main results.

Use a block for each `(case, repetition)`. Randomize treatment order within each
block and shuffle blocks with a recorded seed. Fix model/version, reasoning
effort, documentation, 900-second session deadline and a maximum of 20 compiler
invocations across arms. Enforce limits in the runner, not only in the prompt.
An invocation-limit failure is an unsuccessful attempt, not an excluded row.
Use one active participant at a time for this first cohort to simplify latency
interpretation; record cache policy and provider/cache telemetry regardless.

Primary outcome: hidden acceptance within the common limits. Conditional on
acceptance, compare failed checks on changed source and total failed invocations.
Also report failures separately, all-attempt output tokens, steps, wall time,
distinct failed candidate versions, infrastructure incidents and public/hidden
disagreements. A failed run with zero checks is not a fast repair.

Report the suggestion effect separately in text and JSON, the format effect
separately with and without suggestions, and the interaction. Give each case
equal weight within its family. Show every variant and paired block difference;
use a specified paired analysis with uncertainty, clustering repeated runs by
case. Do not treat individual diagnostics as independent observations. With
only five target variants per family, any broad transfer claim remains limited.

Predeclare a practical target: at least one fewer failed compiler invocation
per successful repair on average in each responsive family, with no observed
hidden-acceptance regression. Treat that as an engineering signal, not a
statistical guarantee of equal correctness. If intervals include both meaningful
benefit and harm, label the result inconclusive and define a new replication
cohort. Control-family regressions call for narrowing the remedy's applicability.

Interpretation:

- Both suggestion arms help: implement actionable remedies in the compiler;
  choose rendering for the consumer's needs.
- Only one rendering helps: inspect preserved information and the interaction
  before attributing the difference to JSON itself.
- Fewer failed checks but unchanged end-to-end cost: claim a repair improvement;
  keep the total-cost result visible.
- No repeatable benefit: revise or retire the remedy; do not redefine the metric
  until it rewards the treatment.

**M2: compare strategies at actual matched budgets**

Use the same faulty projects, initial information, public checks and final hidden
oracle. Compare text-feedback repair against independent one-attempt candidates
first. Keep fix suggestions out of this first strategy comparison so it isolates
adaptive feedback; add the chosen suggestion treatment in a later cohort.

Both strategies receive the same coordinator-generated initial diagnostic and
command documentation. In repair, subsequent public failures can inform edits.
In sampling, each candidate starts in a fresh context from the initial source,
with no earlier candidates or feedback. The coordinator may check each candidate
and select the first passing public acceptance. If none passes, select the final
complete candidate under a predeclared rule. Hidden acceptance is used only
after selection and must never choose the winning candidate.

Define a budget envelope per task and repetition, not per generated candidate.
Within it, charge every model call, feedback processing, discarded candidate and
selection call. A repair strategy may restart only if that policy is declared
in advance and charged to the same envelope. Record compiler/check work separately
and apply identical wall/tool limits.

First verify provider usage semantics: input may exclude cache hits; reasoning
may already be included in output. Keep raw fields and a versioned normalization.
Report cached plus uncached input as input volume when confirmed disjoint,
generated tokens with reasoning counted exactly once, and billed cost separately.
Output-token budgets are acceptable if labeled precisely; they do not establish
equal total inference cost. Do not describe all token measures as unusable
because uncached input varies with prefix-cache warmth.

Pilot candidate output budgets of 2k, 5k and 10k generated tokens on development
cases, then freeze the useful range before evaluation. These are proposed caps,
not current runner capabilities. Implement per-call remaining-budget limits and
stream cancellation or another demonstrably enforceable provider mechanism.
Test deadline/cap termination, hidden reasoning accounting and overshoot. Never
select a candidate completed after a hard budget cap. If the interface cannot
enforce the chosen budget, report observed consumption and defer the matched-budget
claim; polling completed sessions alone is insufficient.

The observed 3.3× ratio is descriptive. Since one independent attempt consumed
more output than a repair session, it cannot justify assigning three independent
samples to each repair session. Let the common cap determine how many attempts
each strategy can afford. Plot hidden success versus budget, with actual spend,
uncertainty and per-family results. Distinguish selected-candidate success from
oracle pass-at-k, which assumes access to hidden answers for selection.

**M3: test one structural simplification of invocation**

First classify the module-family transcripts into command/root confusion and
actual source defects. `E_MODULE_NAME` or `E_MODULE_READ` alone does not prove
the command was wrong. A project wrapper must still reject an incorrect module
header, missing dependency or nonexistent import.

Prototype one project-aware entrypoint that takes root, entry and public checks
from a single explicit project description. Reuse
[scripts/project.py](../../scripts/project.py) and
[its workflow](../experiments/project-workflow.md) where applicable. Keep the
compiler, language semantics, public verification workload and rendered feedback
fixed; isolate automatic command/root selection from other navigation or
verification features of that script. It must not rewrite source, infer hidden
requirements or manufacture a passing output.

Compare three arms: existing commands; existing commands with an exact
task-independent invocation hint; the project-aware entrypoint with the same
hint. Give all arms access to the same project metadata. Only the third arm
derives the invocation automatically.

Use new projects exercising changed working directories, nested modules and
test/library entries. Include negative controls with genuinely invalid headers
and imports; all arms must still diagnose those and require a real repair.
Freeze a small pilot first; set main repetitions using its observed variability.

Measure hidden task acceptance, avoidable invocation failures, first useful
check latency, source edits made solely to accommodate invocation, and total
delivery cost. Count work removed rather than commands hidden inside the wrapper:
retain its underlying compiler invocations and report both levels.

Success supports the narrow claim that a single source of project configuration
reduces repeated decisions across workflows. If eliminating header/path duplication
is still warranted, propose a separate compiler experiment with explicit semantics
for roots, renames and collisions. Do not silently introduce that language change
into the wrapper comparison.

**Implementation map and completion checks**

| Location | Planned change |
| --- | --- |
| `experiments/diagnostic-feedback/conditions.py` | Separate canonical diagnostic data from rendering; add `text_fix`; log compiler invocations before rendering |
| New `events.py` / `cohort.py` in that directory | Event validation/aggregation; immutable manifests, identities, attempt paths and compatibility checks |
| `experiments/diagnostic-feedback/run.py` | Use event collector; enforce limits; seal source; independent verification; preserve unsuccessful outcomes |
| `experiments/diagnostic-feedback/sweep.py` | Launch frozen block schedule; explicit cohort and case IDs; no overwrite; retries recorded separately |
| `experiments/diagnostic-feedback/score.py` | Read manifest only; include all arms; produce matching JSON/Markdown, coverage flags and paired comparisons |
| `experiments/diagnostic-feedback/faults/generate.py` | Version cases; multiple behavior inputs; faulty/reference/wrong-repair preflight; keep confirmatory cases separate |
| New `tests/diagnostic_feedback/` | Focused event, rendering, cohort, oracle, accounting and budget regressions |
| New cohort-specific findings files | Original study, recount, M1, M2 and M3 results remain distinguishable |

Implement a dry-run that prints the entire frozen schedule and maximum session
count without launching a model. Add a fixture-only smoke mode that exercises
collection, sealing, verification and reporting using deterministic fake sessions.
All M0 acceptance must pass before spending on the 16-session M1 pilot.

Completion of M1 requires the frozen manifest, all scheduled outcomes or explicit
missing/infrastructure statuses, raw invocation events, sealed source identities,
oracle receipts, reproducible tables, and a decision for each hypothesis. The
report must distinguish improvement, observed harm and insufficient evidence.
It must not claim a validated elegance score or a general language advantage.

For implementation validation, run the focused harness tests and the real small
wrapper/project smoke checks. Run relevant compiler gates only when compiler
code or its integration changes. Any task that exercises Guardian must append
the required feedback entry to `~/ai/canopy/guardian-zig/FEEDBACK.md` and commit it
there, following the repository's global instructions.
