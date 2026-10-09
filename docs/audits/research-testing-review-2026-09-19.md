# Research proposal and mylang testing review

Reviewed 2026-09-19 against the working tree at HEAD
`70447f376f621b8ca5716d0c886c0196ea7464f1`. The cascade and elegance-metrics
directories and their results were already present as untracked work; this review
includes them. Historical measurements below belong to their recorded compiler
and environment, not necessarily today's native-only language.

**Assessment:** mylang already has substantial correctness infrastructure and
exploratory agent evidence. It has not established that its abstractions improve
agent productivity or held-out generalization. The cascade experiment is relevant
and worth retaining, but its measurement instrument needs repair before another
large run. The propagation experiment tests one proxy against session cost; it
does not falsify MDL, all measures of elegance, or the broader language hypothesis.

**What has actually been tested**

| Area | Existing evidence | What it establishes / leaves open |
| --- | --- | --- |
| Language and runtime | Zig checker/diagnostic/invalidation tests; native QBE and C runtime tests; guest tests; migrated language tests run with GC stress; executable documentation; seeded integer laws | Broad implementation coverage. Passing these does not establish better agent authorship. Current counts vary with ongoing test migration. |
| Python familiarity | `velocity/suites/idioms/manifest.json`: 110 probes at the September 17 snapshot: 67 CPython-oracle, 34 mylang-only, 9 deliberately rejected. 36 accepted overall; 23 agreed with CPython; one silent mismatch recorded. | Concrete surface/semantic friction, not agent solve rates. These are historical manifest results, not fresh measurements. |
| Real program size and behavior | S-expression port: 1,013 module lines versus Zig's 1,702; 79 guest tests; 17 independent Zig printer goldens; Python differential census. | A useful concrete size reduction with bounded behavioral evidence. It is not corpus MDL or a controlled productivity comparison. Include tests and support code when comparing total size. |
| Cross-language maintenance | Planner/EDA feature and repair blocks with Python, mylang, Zig + Guardian, common private grading and source review. Rotation: about 117 s for mylang/Python, 214 s for Zig + Guardian. | Feasible application work. Small, mostly single observations; historical runtime/library differences and workflow overhead prevent a language ranking. |
| Sequential maintenance | Two fresh participants, three owner/generic stages each, all edited submissions accepted; 960 private observations. | A working longitudinal harness, but tiny tasks, identical final solutions, and no comparison treatment. |
| Workflow iteration | Velocity v1: eight main tasks, aggregate 1,150.759 s → 1,284.712 s, +11.640%; failed commands 8 → 3. | No aggregate speed improvement. Several things changed together; command failures are not defect counts or model turns. |
| Architectural leverage | Cascade: B/P1/P2; 63 original independent maintainer runs; 9 chained stages; 2 designers; 6 prediction probes. All maintainer changes verified. | Neither redesign recovered its upfront cost on this pack. P1's single chain was about 14% cheaper; replication is absent. |
| Propagation score | Saved analysis of the 72 original maintenance records: within-task reported blast-radius/cost correlation −0.139; mean propagation cost favors P2. | This implementation of a graph proxy does not validate as an agent-cost predictor. Instrument defects and limited sampling narrow the conclusion. |

Evidence: [language tests](../../tests/lang/README.md),
[guest tests](../../tests/guest/README.md),
[idiom manifest](../../velocity/suites/idioms/manifest.json),
[port](../../experiments/sexpr-port/README.md),
[rotation](../experiments/stdlib-parity-rotation-20260907.md),
[maintenance](../experiments/direct-agent-maintenance-20260907.md),
[velocity v1](../../experiments/velocity-evidence/v1/report.md),
[cascade results](cascade-experiment-results-2026-09-19.md), and
[propagation results](../../experiments/elegance-metrics/findings-2026-09-19.md).

The new velocity loop remains partly planned: `velocity/score.py`, `solve.py`,
and `gen_project.py` are absent, and lane A's baselines in `goal.json` are null.
The prepared twelve-task, six-family development corpus is useful expansion
material; its preparation is not a timed experiment result.

**Measurement defects to fix before spending more agent runs**

The first, third, fourth and fifth findings below were reproduced with read-only
scoring or small temporary-directory probes. Other findings follow directly from
the cited code and recorded data. None required a new participant session.

| Priority | Finding | Required regression / correction |
| --- | --- | --- |
| P0 | `cascade/score.py:45` loads every numeric run file. It mixes cache-fixed `B/T2/4.json` with the original three B/T2 runs. | Freeze an explicit cohort manifest with run IDs and hashes, compiler, runner, prompt, model/effort and normalized environment policy. Adding an unrelated follow-up must leave the old report byte-for-byte stable apart from report-generation metadata. |
| P0 | `cascade/run.py:88` and `:604` identify chained working copies and records by step, omitting repetition. Repeating a chain with `--n 2` reuses `chain-1`, etc. Existing working copies are removed; same-verdict records overwrite without preservation. | Key storage by cohort, arm, chain repetition, step and attempt. Test that two chains and two attempts retain distinct workspaces, records and parent source hashes. Fix this before replicating the 14% lead. |
| P1 | `propagation.py:58` caches by entry path and `main.my` mtime. Editing an imported module leaves the cached graph valid according to this key. | Include source closure contents, compiler identity and graph schema/policy. A temporary test indexed once, edited `helper.my`, then indexed again: compiler-call count stayed 1. |
| P1 | `propagation.py:162` labels an ablation `without_uses_type`, but removes `uses_type`, `accepts`, `returns`, and `contains_type`. Its edge set is exactly identical to `calls_and_fields`. | Test each advertised edge set explicitly. Remove only the named kind in that ablation. The existing three-row table contains only two distinct edge policies. |
| P1 | `propagation.py:199` iterates only files in the final project and intersects new-side lines with final declarations. A wholly deleted module produces no changed ranges. | Index both snapshots and handle deleted files/declarations, renames and pure-deletion hunks. A temporary deleted-module probe returned `{}`. Use the pre-change graph for prospective impact prediction. |
| P1 | `propagation.py:120` can include the start node through recursion/cycles, despite describing the denominator as other nodes. Five nodes in each cached arm include themselves. | Define diagonal treatment consistently; test isolated, recursive, cyclic, empty and singleton graphs. Keep any revised normalization versioned. |
| P1 | `propagation.py:319` pools raw within-task ranks without removing different task means. Tasks with a chain have 12 observations, others 9. Chains also are not independent repetitions. | Analyze independent runs separately; center ranks within task or use a specified task-controlled model. Cluster longitudinal inference by whole chain. |
| P1 | `cascade/run.py:295` sets `first_green_ms` on the first text containing `, 0 failed`. The prompt requires running the unchanged baseline first. | Record structured check events tied to source hashes and task requirements. Distinguish baseline-green, public candidate-green and sealed hidden acceptance. A baseline success must never become time-to-solution. |
| P1 | `cascade/score.py:87` uses successful runs for median cost; `decide()` does not require its `solved` flag. | Test failures, missing usage, timeouts, missing cells and incompatible configurations. Gate on success rate and report all-attempt cost under a fixed budget. This did not affect the original all-green cohort, but matters for harder tasks. |
| P1 | `cascade/arm_gate.py:67` accepts any positive test count. Its census tolerates missing inputs; large fixtures can be omitted if absent. | Pin required test IDs/counts and fixture hashes. Missing required coverage must fail; an explicitly smaller gate needs a different identity. Historical receipts do show 79/79/127 tests and six census fixtures, so this is a repeatability risk rather than evidence those runs skipped coverage. |

Fresh execution of `python3 experiments/cascade/score.py` produced P1 pack gain
−33,425 and R = −360,733. Restricting to the original three independent runs per
cell reproduces the published −28,816 and −356,124 exactly. The difference comes
from cohort mixing, not an unexplained arithmetic discrepancy.

On the saved 72-row propagation data, centering ranks within task changes the
blast-radius correlation from −0.139 to −0.211. Restricting to the 63 independent
rows gives −0.249 with the existing rank function. These checks do not rescue the
metric; they show why the reported statistic needs a precise definition.

There is also report drift: the cascade result's no-edit P1/T7 discussion quotes
74,350 / 91,701 / 101,345 tokens, while its actual independent P1/T7 records are
149,690 / 129,948 / 104,769, each with an empty diff. Generate examples as well as
tables from the frozen records.

Audit token normalization before interpreting the measure as cost. For B/T2/1,
`totalTokens == inputTokens + outputTokens + cacheReadTokens`; the scorer adds
`reasoningTokens` again and excludes cache reads. Verify the logger/provider's
field definitions to establish whether reasoning is already part of output.
Retain raw fields, normalized token totals and billed cost separately. An explicit
reasoning-weighted research score is possible, but should not be labeled a
standard token total. This review did not establish the provider field semantics.

**How to improve the experiment design**

1. **Calibrate the instrument in the actual participant environment.** Before
   starting clocks, exercise check, test, build and run from the sandbox using
   both pinned local/global caches. Freeze cold/warm policy. Record infrastructure
   failures separately from source errors and wrong answers. The original run set
   encountered cache-path failures throughout; one corrected B/T2 run cost 79,332
   against 108,484–193,521 previously. One repeat cannot estimate the causal
   saving. A shared bug is not necessarily equal overhead across arms: P2 has
   more tests and agents make different numbers of compiler calls.

2. **Keep total delivery cost as an outcome and decompose it.** Reading and
   assessment are real maintainability costs. Do not remove them simply because
   they dominate or make an abstraction look worse. Add request-to-first-edit,
   diagnosis, editing, repair and verification phases, plus production declarations
   changed and unrelated production modules touched. Count required test updates
   separately: T4 changing printer tests is not evidence that presentation logic
   leaked into another production concern. Use a common mandatory acceptance suite
   and report additional arm-owned test work explicitly.

3. **Use randomized task blocks and uncertainty estimates.** Run each treatment
   on the same task with fresh contexts, frozen model/effort/budgets and randomized
   order. Pair by an actual block identity, not merely matching `run` integers.
   Separate task variability from repeated-run variability. Replace the criterion
   “median gap exceeds observed max-minus-min” with a prespecified effect size and
   confidence interval; ranges can grow as more samples are added. Use a pilot
   to size the study rather than inferring a required run count from three samples.

4. **Test future maintenance through repeated chains.** After fixing chain
   storage, repeat T2 → T3 → T7 across all three designs under the corrected
   environment. Preserve the distinction between evolving source and an agent's
   retained conversational context. Use whole-chain cost, success, repair rounds,
   affected production modules and cumulative regression checks. Keep independent
   fresh-start tasks as a separate estimand. Add a second application family before
   claiming a general architectural effect.

5. **Replace the transfer probe with actual held-out work.** The current
   `probe.py` asks for exact printer bytes while withholding the printer; its
   expected outputs come from each arm itself. That measures reconstructability
   from a partial contract, not whether learned abstractions help solve new tasks.
   Freeze the abstraction/library using training tasks, then ask fresh agents to
   implement unseen features or clients using it, with an independent oracle.
   Split by task family, not just input seed. Once a holdout informs design changes,
   it becomes development data and needs replacement for a confirmatory claim.

6. **Make failures and observation coverage first-class results.** Report
   compile-first-try, hidden solve rate at the budget, cost across all attempts,
   conditional successful cost, regressions and infrastructure exclusions. Include
   a source-preserving no-op task as a calibration control. Do not infer the
   fraction of all session cost spent assessing from one no-op task alone.

The [toolchain-noise finding](../../experiments/cascade/findings-2026-09-19-toolchain-noise.md)
provides the original environment evidence. The
[prepared development corpus](../experiments/development-velocity-corpus.md)
offers stateful collections, codecs, configuration and multi-module maintenance
for expanding beyond the S-expression reader.

**The next research tests, in priority order**

| Experiment | Treatments and acceptance | Why it is informative |
| --- | --- | --- |
| Diagnostic feedback | Same seeded faults and compiler, comparing current text, structured diagnostics, and structured diagnostics with a concrete alternative/fix. Randomize fresh sessions; hold budgets and available documentation constant. Primary: hidden solve rate and repair rounds. Secondary: total cost, wrong edits, repeated identical error. | Directly tests whether the existing checker helps agents. Merely populating `fix` or `alternative` fields is a coverage measure, not proof of useful feedback. |
| Repair versus resampling | Compare the best feedback treatment with independent generation at the same total inference budget on suitable synthesis tasks. Selection sees only the same public checker, never hidden answers. Count all generation, feedback and checking costs. | Tests whether a loop is worth its budget, rather than comparing one attempt with many attempts. |
| Repeated architecture chains | Corrected B/P1/P2 cohorts, repeated chains and a second application family, common acceptance and source-pinned receipts. | Follows the one promising cascade observation without claiming it is replicated already. |
| MDL and transfer | On a bounded pure corpus, compare no extraction, ordinary manual/helper extraction and compression-guided extraction. Count normalized program AST plus library definitions, parameter/call overhead and dependencies; freeze costs before evaluation. Gate with independent behavior checks; evaluate unseen tasks. | Tests the paper's compression mechanism directly. It has not been tested by line counts or the propagation experiment. Stitch integration can follow a small scorer/extractor pilot. |
| Metric gaming | Include dead leaf declarations, helper fragmentation, minification/renaming, dispatch indirection, lookup-table memorization and moving work into libraries. Compare with SLOC/AST baselines and blinded human pair judgments. | Exposes whether a score rewards accounting changes rather than simpler future work. Keep components separate until predictive validity is established. |

Begin diagnostic testing with representative real error families: bool/int
confusion, module/invocation mistakes, checked-result handling, variant coverage,
generic constraints and effects. The cascade transcript review reported 91
invocation/entry diagnostics and 70 bool/int diagnostics among 180 occurrences;
these are repeated occurrences, not 161 independent bugs. Separate CLI guidance
from type-system feedback and judge transfer on new faults, not only those used
to author diagnostic wording.

Full type-constrained decoding is a later, separate treatment. Typed holes and
compiler feedback do not implement it. It needs a model interface that can enforce
prefix/type constraints; a hosted API's tool schema alone is insufficient. First
measure what fraction of remaining failed attempts type constraints could address,
then compare unconstrained, syntax-constrained and type-constrained generation.

**Strengthen correctness gates alongside the research tests**

- Generate well-formed and malformed S-expressions and compare full normalized
  trees, spans and numeric values with an independent implementation. The current
  census of counts and value sums can miss swapped subtrees or compensating wrong
  values. Retain exact goldens, add boundary mutations and shrink counterexamples.
- Add broader metamorphic cases: parse/render normalization, permitted whitespace
  and comments, unit equivalence, nesting/width boundaries, and dialect differences.
  Guard properties by their actual preconditions; input spelling and source spans
  are not invariant under every transformation.
- Extend existing cache/invalidation coverage with generated edit sequences:
  incremental versus fresh check/build/test must agree on verdicts, outputs and
  diagnostics after body, signature, type, effect and imported-module changes.
  Include a forced full check so incorrectly reused green receipts cannot certify
  the experiment itself.
- Use mutation sensitivity to test the oracle: wrong unit scale, off-by-one column,
  lost literal spelling, wrong dialect comment handling and corrupted tree shape
  should each fail an appropriate independent check. Existing seeded bugs and
  sampled laws are useful groundwork, not exhaustive semantic verification.

**How to read the supplied research proposal**

The proposal usefully separates behavior preservation, compression and future
change cost. It is a research synthesis and a proposed metric, not evidence that
their weighted sum is validated. I would retain the existing language and test
those mechanisms here; restarting as a Racket/Haskell DSL is unnecessary for
answering these questions with the compiler and corpus already available.

Stitch's objective is corpus compression with a specified cost function; the
size-times-reuse description is intuition, not the complete accounting rule.
It does not demonstrate cheaper agent maintenance on mylang.
[Primary paper](https://mlb2251.github.io/stitch.pdf).
LILO combines library compression with documentation and downstream synthesis;
that motivates testing transferred task-solving benefit as well as source size.
[Primary paper](https://arxiv.org/abs/2310.19791).

Type-constrained generation was evaluated with a TypeScript implementation and
HumanEval tasks. Its reported reduction in compilation errors is useful motivation,
not a guaranteed mylang threshold or proof that stronger types alone cause better
generation. [Primary paper](https://arxiv.org/abs/2504.09246).
The self-repair paper explicitly compares with equal-budget independent sampling;
that is the appropriate control for a repair-loop experiment.
[Primary paper](https://arxiv.org/abs/2306.09896).

Felleisen's macro-expressibility formalizes relationships between language
constructs under restricted translations. It is not an automatic pass/fail test
that an arbitrary application refactor is elegant, nor a substitute for a behavior
oracle. [Primary paper](https://www.sciencedirect.com/science/article/pii/016764239190036W).
Likewise, model naturalness is an unvalidated proxy here: familiar Python-like
code can be wrong mylang. Test that regularizer before rewarding it.

**Review validation:** read implementation, manifests, raw run summaries and saved
results; reran the read-only cascade scorer; reconstructed the original-cohort
gains; reproduced graph/cache/deletion and rank-pooling issues using temporary
fixtures and saved data. No compiler gate, full acceptance run or paid model
experiment was executed. Guardian was not exercised, so no Guardian feedback
entry is required. This note proposes changes; experiment implementations and
historical artifacts have not been edited by this review.
