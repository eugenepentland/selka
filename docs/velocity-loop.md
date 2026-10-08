# The velocity loop: a closed loop that improves agent development speed

Status: design, 17 September 2026. Nothing here runs yet except the measurements
that seeded the baselines. The loop's own first iterations build the instrument.

## 1. The goal, stated so a machine can check it

The north star in [the plan](plan.md#design-goal-north-star) is "the language in which
an agent gets from a task description to a correct, working program in the fewest
turns and with the least repair". That sentence names the outcome but not a number.
The loop needs the outcome and its causes to be numbers with a direction, a baseline,
a target and a tolerance, so that a background agent can (1) measure, (2) pick the
change with the largest expected gain, (3) make it, (4) re-measure, and (5) keep it
only if the numbers moved the right way and nothing else moved the wrong way.

The numbers live in [`velocity/goal.json`](../velocity/goal.json). That file is
owned by the user. The agent reads it, reports against it, and may propose changes
to weights or targets in a commit that touches nothing else, but never edits it as
part of a language change. Everything the agent produces goes under `velocity/`.

The metrics are grouped into lanes. The research behind the ordering is summarised
in the 17 September assessment: comprehension time dominates change cost, feedback
latency has the strongest controlled evidence, static typing pays off as machine-
checked documentation and a bug filter, and consistency beats expressiveness in a
large codebase.

| Lane | What it measures | How often | Cost |
| --- | --- | --- | --- |
| A. Task velocity | What an agent actually experiences: turns, repairs, waiting, tokens to a verified solution | nightly | tokens |
| B. Loop latency | Edit-to-check, edit-to-run, edit-to-test at three project sizes | every iteration | seconds |
| C. Python fidelity | Does the language accept what an agent writes first, and does it mean what Python means | every iteration | seconds |
| D. Comprehension and navigation | Can the agent answer "who calls this" while red, read an interface with its effects, trust the formatting | every iteration | seconds |
| E. Gates | Correctness that is never traded for speed | every iteration | minutes |

Lane A is the outcome. Lanes B to D are the causes the language controls. Lane E is
the constraint. A change is accepted on B to D immediately and its effect on A is
read from the next nightly run.

## 2. The metrics

Each metric below has an id that matches `velocity/goal.json`. "Baseline" is the
value measured on 17 September 2026 on the installed binary at commit `237871a6`,
with the probe and the number recorded in the memory and audit files cited.

### Lane A: task velocity (outcome)

Measured by running **solver sessions**: a fresh headless agent, a task pack entry,
the installed compiler and the docs, nothing else. The solver never sees the
compiler source. The improver never sees the held-out tasks or the solver's task
text; it sees **friction records** (below).

| Id | Metric | Direction | Baseline | Target |
| --- | --- | --- | --- | --- |
| A1 | Solve rate within the turn cap | up | unmeasured | 0.95 |
| A2 | Median turns to a verified solution | down | unmeasured | 3 |
| A3 | Repair rounds per task: compiler or test failures before the first green verify | down | unmeasured | 0.5 |
| A4 | Seconds the agent waited on compiler, build and test calls per task | down | unmeasured | 5 |
| A5 | Tokens per solved task, input plus output | down | unmeasured | set after first run |

A task is a directory with `request.md`, a `verify.json` in the format
[`scripts/verify.py`](../scripts/verify.py) already runs, and hidden inputs the
solver cannot read. Three tiers: greenfield programs of 30 to 100 lines,
modification tasks on the corpus and the schematic guest with hidden tests, and
large-project tasks on the generated 50k-line project. Two thirds of the tasks are
held out under `../mylang-eval/tasks/heldout/`, outside the repository, with only a
hash manifest checked in; one third is public under `velocity/tasks/public/` so the
improver can reproduce a friction record by hand.

The solver runner records, per task: turns, tool calls to the compiler with their
wall time and exit, the diagnostic codes seen, the verify result, and usage. From
those it emits friction records:

```text
{"version":"friction-v1","task":"greenfield/042","phase":"check",
 "code":"E_SYNTAX","idiom":"chained-assign","count":2,"latency_s":0.03,
 "excerpt":"x = y = 21"}
```

The idiom classifier is a fixed table from diagnostic code plus a source regex to
an idiom name, kept in `velocity/friction/classifier.json`; unknown pairs get
`idiom: "unclassified"` and are the improver's first thing to read.

### Lane B: loop latency (cause)

Measured on three projects with a warm cache, three samples, median reported.
The projects are the schematic guest at 2,186 lines, the generated 50k-line
project from `velocity/gen_project.py` with a fixed seed, and, once B1 is under
five seconds, a generated 500k-line project. Every metric is a ratchet: a change
that makes any of them worse than the baseline by more than the tolerance is
rejected even if it improves another.

| Id | Metric | Direction | Baseline (2k / 50k) | Target (any size) |
| --- | --- | --- | --- | --- |
| B1 | One-line body edit to a running program (`run`) | down | 3.4 s / 74 s | 1.0 s |
| B2 | One-line body edit to a check verdict | down | 0.17 s / 3.9 s | 0.3 s |
| B3 | Warm unchanged build, nothing to compile | down | 3.3 s / 70 s | 0.2 s |
| B4 | Cold build seconds per thousand lines | down | 4.7 / 14.0 | 0.5 |
| B5 | Fraction of checked bodies reused after a one-line body edit | up | 0.99 / 0.0002 | 0.99 |
| B6 | Fraction of tests reused after an unrelated body edit | up | measured per run | 0.95 |
| B7 | Interface edit: seconds to the first diagnostic in the true dependents | down | measured per run | 0.5 s |

Why B5 is a metric and not a detail: on the 50k-line project every body was bypassed
with the `interned-record` reason because `list[int]` first appeared inside a body,
and even with that fixed the retention budget kept 1,100 of 4,800. Reuse that
silently collapses is the failure mode the ratchet exists to catch.

### Lane C: Python fidelity and silent wrong answers (cause)

The oracle is CPython. Every probe in `velocity/suites/idioms/` is a program an
agent wrote first; 76 of the 110 run under CPython, and 9 of those are Python the
language rejects on purpose, leaving 67 with a CPython oracle.
A probe passes when the compiler accepts it and the program's exit status and
stdout equal CPython's. A change that adds a language feature must add its probe.
The existing `zig build test-idioms` gate already runs 57 probes under
[`tests/fixtures/idioms`](../tests/fixtures/idioms) with hand-recorded baseline and
target outcomes and a `must_pass` ratchet. Lane C extends that gate rather than
adding a second one: V0 moves the 110 tagged probes beside it, adds the CPython
oracle as a third kind of expectation, and keeps `must_pass` as the lane E rule.

| Id | Metric | Direction | Baseline | Target |
| --- | --- | --- | --- | --- |
| C1 | First-try fidelity: probes with a CPython oracle that mylang accepts and agrees with | up | 23 / 67 = 0.34 | 0.90 |
| C2 | Silent wrong answers: accepted without an error whose output differs from CPython | down, gate | 1 (`round(2.5)`) | 0 |
| C3 | Rejections that name the alternative or carry a machine-applicable fix, over all rejections in the suite | up | 0.02 | 0.95 |
| C4 | Boilerplate lines per public declaration over the standard library and corpus: `module`, `export` and redundant `effects` lines | down | 1.1 | 0.1 |

C2 is a hard gate. A warning does not rescue a program from C2: the record
parameter write compiles, warns and exits 0 with the wrong count, and a pipeline
that reads exit codes never sees the warning. The remaining Python programs that
mylang rejects by design, such as exceptions and closures, are tagged
`# oracle: rejected-by-design` and count only toward C3.

### Lane D: comprehension and navigation (cause)

| Id | Metric | Direction | Baseline | Target |
| --- | --- | --- | --- | --- |
| D1 | Change-impact queries answerable on a project with one failing body: callers, callees, impact, tests-for, recompile set, boundary mentions | up | 0 / 6 red, 2 / 6 green | 6 / 6 |
| D2 | Exported functions whose `list-interfaces` row shows signature, effects, mutated parameters and a summary | up | 0.25 | 1.0 |
| D3 | `.my` files in the repository that pass the formatter's check | up | 0.0 | 1.0 |
| D4 | Diagnostic codes with an `explain` entry | up | 0 / 203 | 1.0 |
| D5 | Misleading diagnostics in the suite: the code names a construct the source does not contain | down | 4 known | 0 |

### Lane E: gates

Never optimized, always required: `zig build test`,
`fmt-check`, Guardian, doc-coverage, doctest, golden parity, the idiom suite's
CPython agreement for every probe that agreed before the change, and C2 = 0.

## 3. Scoring and acceptance

Each metric is normalized to 0..1 between its baseline (0) and its target (1).
Latency and count metrics normalize on a log scale, so 74 s to 7 s is worth as much
as 7 s to 0.7 s; fractions normalize linearly. A lane's score is the weighted mean
of its metrics and the composite is the weighted mean of lanes, with weights from
`goal.json`. The composite is for the trend chart only.

Acceptance of one change is a Pareto rule with a ratchet, not the composite:

1. Every lane E gate passes.
2. No metric in lanes B, C or D is worse than the current baseline by more than its
   tolerance, by default five percent of a latency and zero for a count or fraction.
3. At least one metric improved by more than its noise floor, or the change is a
   backlog prerequisite whose commit message names the metric it unblocks.

On acceptance the measured values become the new baseline in
`velocity/baseline.json`, and the run is appended to `velocity/history/`. On
rejection the attempt, its numbers and the reason are appended to history and the
worktree is discarded. History is append-only so drift is auditable.

## 4. The loop

One iteration is one candidate commit. The agent runs it from a worktree off `main`.

1. **Measure.** `zig build`, then `python3 velocity/score.py --lanes B,C,D` writes
   `velocity/current.json`. If any B-to-D metric is below the baseline beyond
   tolerance on a clean `main`, the loop's only job is to find and fix that
   regression.
2. **Pick.** Read `velocity/backlog.json` and the newest friction records. Choose by
   this rule, in order: any C2 silent wrong answer; any red ratchet; the backlog
   item with the highest `expected_gain / cost` whose prerequisites are done. Write
   the choice and the expected metric movement to history before starting.
3. **Change.** Implement with the repository's rules: a spec tag per behavioral
   line, a doc section with a runnable example for a new feature, an idiom probe
   with a CPython oracle for a new Python construct, focused tests while iterating.
4. **Gate and score.** Full gate, then `score.py` again. Apply §3.
5. **Record.** Commit with the before and after values of the metrics that moved in
   the message body. Append history. Update `backlog.json`: done, or failed with
   the numbers, or split into smaller items.
6. **Use.** Every fifth iteration, and every night, run lane A on the public pack
   with `python3 velocity/solve.py`, and once a week port one program from
   `velocity/dogfood.md` to mylang. Every stumble becomes a friction record, and
   every unclassified friction record becomes a backlog item with its count as the
   expected gain.

Stop rules: never commit red; at most one candidate at a time per checkout; a
token or wall-clock budget per day from `goal.json`; stop and report if the same
backlog item fails three times or if a gate fails on clean `main`.

## 5. Why this does not get gamed

- **CPython is the oracle for fidelity.** Accepting more syntax only scores when
  the accepted program means what Python means; accepting it with different
  behaviour is a C2 gate failure.
- **Ratchets on every cause metric.** A checker made faster by skipping reuse
  validation fails golden parity; a build made faster by dropping objects fails
  B5 or the gate.
- **Held-out tasks and blinding.** The improver sees friction records, not tasks;
  the solver sees the compiler, not its source. The held-out pack rotates
  quarterly and its hashes are in the repository so a substitution is visible.
- **Real and synthetic projects both count.** The synthetic generator is seeded
  and versioned, so its numbers are reproducible; the schematic guest and corpus
  keep it honest about shapes the generator does not produce.
- **Weights and targets are user-owned.** The agent cannot move the goalposts.
- **The heavy trial is separate.** The sealed-cohort comparison under
  [`experiments/application_comparison`](../experiments/application_comparison/README.md)
  remains the instrument for a comparative claim against Python or Zig. The loop
  optimizes the language; it does not certify it.

## 6. Bootstrap order

The first iterations build the instrument, each accepted by reproducing a number
already measured by hand:

| Iteration | Deliverable | Acceptance |
| --- | --- | --- |
| 0 | `velocity/score.py` for lanes B, C, D and the gate list, writing `velocity-score-v1` JSON | reproduces the baselines in `goal.json` within noise on the same binary |
| 1 | `velocity/gen_project.py`: seeded synthetic project at 50k and 500k lines | the 50k project reproduces B1 to B5 within noise |
| 2 | `velocity/solve.py`: solver runner with a command template for `dsh --profile headless` and `claude -p`, transcript metrics A1 to A5, friction records | one public task runs end to end and produces a friction record |
| 3 | Public task pack: 20 greenfield tasks seeded from the idiom suite, 10 corpus modifications, 5 large-project tasks; held-out pack written outside the repository | `solve.py` runs the public pack nightly |
| 4 onward | the backlog | §3 |

## 7. Files

```text
velocity/
  goal.json          metric definitions, weights, baselines, targets   (user-owned)
  backlog.json       ranked candidate changes with expected gains       (agent-maintained)
  baseline.json      last accepted measurement                           (score.py)
  current.json       last measurement                                    (score.py)
  history/           one JSON per iteration, append-only
  friction/          friction-v1 records from lane A and dogfooding, plus classifier.json
  suites/idioms/     the idiom probes with oracle tags
  tasks/public/      the public third of the task pack
  tasks/HELDOUT.sha256
  dogfood.md         programs to port, one per week
  LOOP-PROMPT.md     the prompt that starts an iteration
  score.py gen_project.py solve.py
```
