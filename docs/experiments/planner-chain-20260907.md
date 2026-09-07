# Two-stage planner maintenance experiment — 2026-09-07

The next two steps test a new contract change followed by maintenance of the
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

RESULTS_PENDING
