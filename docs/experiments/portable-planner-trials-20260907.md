# Portable planner maintenance trials — 2026-09-07

Nine fresh exploratory participants implemented an input-boundary repair, a
priority contract change, and cycle-group reporting in `.selka`, Python and Zig.
The [launcher and library preparation](portable-planner-preparation-20260907.md)
was completed, tested, reviewed and frozen before any application clock started.
These are maintenance trials on existing small applications, not new application
construction or the planned scored pilot.

| Task | `.selka` seconds | Python seconds | Zig + Guardian seconds | Private draft groups |
| --- | ---: | ---: | ---: | ---: |
| Input-limit repair | 95.0 | 70.1 | 155.9 | 14 / all passed |
| Job priority | 132.6 | 110.7 | 288.0 | 7 / all passed |
| Cycle groups | 147.5 | 100.5 | 97.6 | 8 / all passed |


Application seconds include source discovery, editing, authored tests, public
checks, failures and retries after practice. No active clock was paused/reset.
Library/tooling preparation, practice, private grading and independent source
review are excluded from those numbers and retained separately. Preparation
included 21 passing harness tests, real relocated/isolated launcher execution,
review of pinned standard-library capabilities and a generic signed composite
ordering fixture on the installed VM. No compiler/library implementation change
was needed. The first added transport fixture had an incorrect schema expectation;
its failure and the corrected complete rerun remain in preparation evidence.

All nine sealed submissions passed their original private packs. The repair pack
contained 14 request groups producing 131 manifest results plus eight whole-request
errors; priority had seven groups producing 138 results plus four whole-request
errors; cycles had eight groups producing 136 results plus four whole-request
errors. Groups and generated manifests are not independent statistical samples.

The cycle trio also passed all five supplemental limit groups: 128-job ring,
128-job dense graph, 128 independent self-loops, a two-job cycle with 126 downstream
jobs, and 64 manifests of 128-job rings. These 68 additional manifests were frozen
before any cycle participant started, with independently constructed expected
groups checked against the coordinator oracle. They used the same adapters and
resource limits for all languages. The separate protocol/results preserve the
original draft pack rather than rewriting its denominator.

## Quality and observed iteration

The independent reviewer received only public requirements, sealed source and
baseline-to-sealed patches. No clocks, private cases or grading outcomes were
provided. The review identified no independent correctness defect in any of the
nine implementations. Each received clarity/consistency/testing scores of 2/2/2
under the frozen coarse rubric. These are source observations, not a proof of
bug absence or a sensitive general code-quality ranking.

Concrete coverage differed. `.selka` used Kosaraju traversal with repeated whole-edge
scans, O(VE); its authored tests included dense and ring graphs at 128 jobs plus
192 generated graphs. Python used Tarjan and exhaustively tested the 512 directed
three-job graphs. Zig used positive-length transitive closure and mutual
reachability; its added tests covered semantic cycle boundaries but lacked a new
maximum-size cyclic case. No participant authored a full 64-case maximum cyclic
batch. The separately frozen limit suite supplies runtime evidence for those
bounds without attributing coordinator coverage to participant-authored tests.

| Task / language | Practice seconds | Task commands | Public attempts | Failed public attempts |
| --- | ---: | ---: | ---: | ---: |
| Input-limit repair / my | 27.9 | 8 | 1 | 0 |
| Input-limit repair / python | 29.9 | 5 | 1 | 0 |
| Input-limit repair / zig | 58.5 | 7 | 1 | 0 |
| Job priority / my | 31.9 | 10 | 2 | 0 |
| Job priority / python | 25.4 | 8 | 1 | 0 |
| Job priority / zig | 60.7 | 11 | 3 | 2 |
| Cycle groups / my | 27.2 | 9 | 1 | 0 |
| Cycle groups / python | 24.8 | 7 | 1 | 0 |
| Cycle groups / zig | 56.5 | 6 | 1 | 0 |


These are gateway command/public-check counts, not model turns. A command can
contain several operations; failed local experiments may be intentionally used to
reproduce a defect. Exact model identity, model turns, token use, compute cost,
cache effects and complete preparation/adoption cost are unavailable. Unknowns
are null in evidence, never zero. This run cannot support a fewer-turns or total
adoption-cost claim.

Guardian remained enabled for Zig's main workflow, with its original protected
policy and root wrapper. The priority participant had two failed public attempts:
initial stale/duplicate specification links, complexity 27 against limit 25, and
long test strings; a later specification-link cleanup was also required. The
participant extracted job parsing, corrected the single requirement link and used
multiline fixtures. The final gate passed all 88 checks. Those failures are gate
findings, not private application defect detections. Report-only line lengths
were retained. Other gate observations and retries appear in the evidence.

## Design and limits

All three blocks used the same frozen library readiness, optimized `.selka` tools,
Python 3.14.4, Zig `0.17.0-dev.1683+5ceec001b`, 20-minute practice and 30-minute
application budgets, namespace command gateways and suite build reuse. Baseline
authors/reviewers were not reused as participants. Participants began from each
task's own v1 baseline, so changes were not cumulative. The repair mutation
changed only the `.selka` application's input-limit argument, leaving stdlib frozen.
Each task pack used a fresh private seed; original drafts were already exposed.

Dispatch was sequential with fixed cyclic language order: Python/`.selka`/Zig for
repair, `.selka`/Zig/Python for priority, Zig/Python/`.selka` for cycles. This rotates
position but is not randomized; shared-host and scheduling effects remain.
Commands were namespace-isolated, but whole-agent host access was limited by
instruction rather than enforced confinement. Exact model identity/settings
could not be independently attested. There is one participant per language/task;
no population productivity, defect-rate or causal library-effect claim follows.

Historical rotation inputs, sealed submissions and reported times were not
modified or pooled. Their readiness receipt remains a historical identity;
updated baseline launchers intentionally require this cohort's new receipt.
There are now 21 direct exploratory sessions overall (nine in this cohort),
including 12 library-prepared sessions. Scored pilot sessions remain zero.

## Continuation

These small tasks now show a ceiling in acceptance and the coarse source rubric.
Python completed all three observed tasks sooner than `.selka`; Zig was slower on
the repair and priority tasks and slightly faster than Python on cycle groups.
These observations do not establish a general ranking or fewer defects. There
is no evidence here that `.selka` is faster than Python, and tool counts do not
establish fewer agent turns.

The next preparation target is a reviewed medium-size maintenance workload with
cross-module repairs and contract changes, plus follow-up maintenance on the same
application. First inventory its required Python/Zig library facilities, implement
missing reusable `.selka` equivalents, and validate/migrate all baselines outside
application clocks. Preserve this cohort as small-task calibration. Before calling
new runs scored, add verifiable exact model/turn/usage capture and enforce the
participant boundary; freeze unseen tasks and budgets after that validation.
Until then, label further direct-agent runs exploratory and retain failures.

[Machine-readable evidence](../../experiments/application_comparison/evidence/portable-planner-trials-20260907.json)
retains clocks, outcomes, metrics, hashes, reviews and limitations. Complete frozen
inputs, protected task guides, sealed attempts, source-review bundles and grading
records remain under
`/home/epentland/ai/canopy/application-trials/portable-planner-20260907`.
