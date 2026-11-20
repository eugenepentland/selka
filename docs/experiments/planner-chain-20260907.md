# Two-stage planner maintenance experiment — 2026-09-07

The two completed steps test a new contract change followed by maintenance of the
resulting code. Each step has three fresh participants, one per language. This
extends the existing small planner; no medium-size workload claim is made.

1. **Dependency lags:** accept string prerequisites or explicit ID/lag objects,
   preserve duplicate/missing/cycle validation, and propagate delays through
   earliest timing. Parsing, identifier resolution, graph handling and reporting
   must stay consistent. Legacy string-only requests retain exact behavior.
2. **Latest starts and slack:** fresh agents start from the corresponding sealed,
   accepted lag implementation. They add backward timing constraints and sorted
   critical-job reports while preserving all lag behavior. This tests follow-up
   work on another agent's implementation instead of restarting from v1.

Before clocks start, fill comparator-standard-library gaps, validate the library
and all original baselines, review/freeze capability readiness and task packs,
and independently check the scheduling oracle. Integer min/max helpers and
empty-default slice reductions are preparation; domain scheduling remains timed
application work. Python has built-in min/max; pinned Zig has @min/@max and
std.mem.min/max. Local graphlib/sched and Zig stdlib inspection found no weighted
project scheduling/latest-start facility to supply as a language library.

An independent bounded reference enumerates feasible schedules and derives the
optimal deadline and each job's earliest/latest start from those schedules. It
checks oracle timing/slack without reusing its forward/backward DAG algorithm.
Frozen private cases also cover transport/schema errors, error precedence,
representation mixing, permutations, maximum lags/job counts and request batches.

Freeze both tasks' public/private packs before the first stage starts. Run
participants sequentially, with order Zig/Python/`.my` for dependency lags and
Python/`.my`/Zig for slack. Use the existing 20-minute practice, 30-minute task,
60-second command limits, namespace gateways and suite-build-reuse policy. Keep
Zig Guardian and its protected policy/root wrapper. No participant gets hidden
feedback or coordinator implementation advice. All attempts/retries remain timed.

Grade and independently review the first stage before preparing the second.
Use each language's accepted sealed source as its second-stage baseline, replacing
only the protected task guides. Bind predecessor source hashes and a new readiness
receipt to these chain baselines. If a predecessor fails, retain its failure and
record any separate untimed baseline recovery explicitly before stage two; never
claim that repaired baseline was the original timed result. Do not reuse its
author as the next-stage participant. Compare second-stage results with this
baseline inheritance in view; implementation differences are part of the chain.

Report all six outcomes, clocks, command/public-check counts and timing-blind
source reviews, alongside preparation and limitations. Exact model/turn/token/cost
telemetry and whole-agent enforced confinement remain unavailable, so all runs
are exploratory. Do not pool these new tasks with earlier times to claim a causal
speedup or a language-wide defect-rate difference. A six-session chain can expose
failure modes and inform larger workloads; it cannot estimate rare bugs reliably.

## Completed results

All six sealed implementations passed private grading. Each task pack contained
19 request groups: 244 manifest results and nine whole-request errors, including
maximum-size, dense, cyclic, mixed-representation and batch cases. Independent,
timing-blind source review found no application defects; each implementation
received 2/2/2 for clarity, consistency and testing under the existing rubric.
These are bounded acceptance and review results, not proof of a zero defect rate.

| Stage | Language | Application seconds | Working commands | Public checks / failed | Private groups passed |
| --- | --- | ---: | ---: | ---: | ---: |
| Dependency lags | my | 182.3 | 11 | 2 / 0 | 19/19 |
| Dependency lags | python | 134.5 | 8 | 1 / 0 | 19/19 |
| Dependency lags | zig | 326.5 | 18 | 3 / 1 | 19/19 |
| Slack / critical jobs | my | 188.3 | 9 | 3 / 1 | 19/19 |
| Slack / critical jobs | python | 169.2 | 9 | 2 / 0 | 19/19 |
| Slack / critical jobs | zig | 325.9 | 13 | 2 / 1 | 19/19 |

Observed application effort summed across this chain was **370.6 seconds for
`.my`, 303.7 for Python and 652.4 for Zig**. Python completed both steps sooner
in this run. This is one observation per language per task, with Zig Guardian
included; it does not establish a general productivity ranking or isolate the
cost of the language from its development workflow. Public checks and commands
are observable interactions, not model turns. Model turns, tokens, exact model
identity and compute cost remain unavailable.

## Preparation and integrity

Reusable integer `std_math::min`, `max`, `min_or` and `max_or` were implemented
before application timing. Slice fallbacks apply only to empty inputs. All eight
integer widths, extrema, mixed signs, ties and nonempty fallback behavior were
validated, alongside the existing floating-point API. Existing planner maxima
were migrated before freezing the first baseline. The standard library still has
34 embedded modules. No compiler implementation change was required.

The preparation build passed 12/12 steps and Guardian's 88 checks; the focused
three-test run includes one substantive fixture and two root/import tests. The VM
fixture returned 42, all 12 migrated planner CLI groups passed, 20 common harness
acceptance tests passed, and 11 oracle/task-pack tests passed. An additional
no-op rejection check passed. Independent feasible-schedule enumeration checked
216 fixed tiny scenarios and 96 randomized mixed-representation scenarios.
[Preparation evidence](planner-chain-preparation-20260907.md) remains frozen.

Both packs were frozen before the first participant clock. Stage two inherited
each language's accepted sealed lag implementation byte-for-byte, excluding only
the replaced protected task guides. No baseline recovery was needed. Fresh agents
performed each stage; clocks did not overlap, no scope violations were recorded,
and protected Zig policy/root-wrapper bytes remained unchanged. Both readiness
receipts verified after the runs. Library preparation, practice, private grading
and source review were outside application clocks; application retries were not.
The frozen tools and full trial artifacts remain under
`/home/epentland/ai/canopy/application-trials/planner-chain-20260907`.

## What the additional steps exposed

- `.my`'s first slack public check failed at compile time: an `export latest_start;`
  declaration appended after functions produced `E_SYNTAX: ... expected kw_fn`.
  Moving the export to the module header repaired it. This was a syntax repair,
  not a scheduling defect discovered in private grading.
- Zig's lag attempt initially failed Guardian on 25 test lines above the 240-character
  hard limit. Its slack attempt initially failed on four long expectations and a
  missing `PLANNER-CRITICAL` spec-to-test annotation. Both were repaired; final gates
  passed all 88 checks, with 29 and 37 report-only line-length findings respectively.
- The gateway rejected overlapping `.my` commands during the lag task. Changes
  after a successful snapshot also required rechecking before sealing (`.my` and
  Zig lag participants). These workflow costs remain in the application clocks.
- Slack authors added exhaustive feasible-schedule checks. Python's check uses
  the application's deadline; `.my` independently computes it, and Zig independently
  minimizes it. The reviewer recorded this difference without finding a production
  defect. Independent coordinator checks supply another oracle for all languages.

## Continuation

There are now **27 direct exploratory sessions overall, 18 after library parity
preparation, and zero scored sessions**. This adds a real two-stage agent handoff,
but both changes still belong to a small planner. Keep their raw times separate
from earlier task cohorts.

Next prepare a medium-size maintenance workload with multiple modules and a
longer change chain. Audit and implement comparator-stdlib facilities first,
then freeze tools and baselines before timing. A specific follow-up experiment
is clearer export-placement diagnostics with an actionable fix, or permitting
exports throughout the module; test that change in a new frozen matched cohort
without changing or retiming these results. Scored productivity and bug-rate
claims still require verifiable telemetry, enforced confinement and replication.

The [machine-readable evidence](../../experiments/application_comparison/evidence/planner-chain-20260907.json)
retains all six outcomes, timings, command/check counts, source hashes, predecessor
bindings, reviews, readiness integrity and repair observations. Exact total adoption
cost is not known; preparation evidence is retained separately rather than treated
as zero.
