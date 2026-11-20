# B1 / D2 / S1 review and next-stage decision — 2026-09-16

## Decision

**Accept B1 as closed and move into the performance stage. Correct two S1
interpretations before using its priority list to commission implementation.**
The measured latency target failures are real. The assertion that retention size
is the dominant time cost is not supported by a controlled budget experiment,
and the assertion that managed specialization bodies never replay is incorrect.

**Next:** repair performance telemetry and locate the remaining whole-project
checking cost; make C4 selective preparation/lowering the next substantial test
pipeline feature. Defer a large retention-format redesign until profiles justify
it. Self-hosting frontend work can continue independently on a pinned compiler.

## Scope

- Reviewed `5eaa4051..763eb386`, including B1 source, its boundary tests, D2
  reconciliation, S1 harness, report, and low-load raw measurements.
- Re-ran the two original standalone B1 assertions against current sources.
  Both pass: the 1,400-byte cache retains zero entries, and allocator-tracked
  ownership exactly matches the 1,598-byte report in the accounting fixture.
- Recomputed low-load p50/p95 from the saved samples. No summary discrepancies;
  the only failed/timed-out sampled invocation was the documented 100k native
  test timeout. These checks validate the saved statistics, not host isolation.
- Fresh-process probes used a private copy of the exact S1 ReleaseFast compiler:
  executable SHA-256
  `58a39d625369491cc696f9585d002aac4d6e9265afb2d5458b425d92cc61f57f`.
- A separate ReleaseFast probe imported the reviewed compiler modules and varied
  only semantic retention capacity. It used the S1 ordinary-100k source and
  private, in-memory body edits; no repository implementation was changed.
- Full repository/Guardian gates were not rerun. No Guardian gate was exercised.

[Raw review evidence and reproducer sources](development-velocity-b1-d2-s1-review-2026-09-16-probes.json).

## Findings

### S1R1 — P2: retention misses do not establish the dominant latency cost

Location: `docs/audits/velocity-implementation/s1-corrected-report-2026-09-16.md:357-364`,
also the opening summary and `final-status.md` scale limitation.

The report correctly observes the 16 MiB cap and the resulting body misses. It
then attributes most edit latency to those misses and makes retention redesign
the first priority. Work counts alone do not establish that timing attribution.

The controlled in-process experiment gives the following medians, with five
body-edit samples after a seed request at each budget:

| Semantic budget | Fresh / reused bodies per edit | Retained bytes | Total measured time | Semantic check/cache phase |
| --- | ---: | ---: | ---: | ---: |
| 0 MiB | 33,475 / 0 | 0 | 1,000.2 ms | 711.7 ms |
| 16 MiB | 24,202 / 9,273 | 16,776,636 | 954.9 ms | 669.5 ms |
| 32 MiB | 14,911 / 18,564 | 33,554,386 | 926.9 ms | 641.5 ms |
| 64 MiB | 2 / 33,473 | 60,639,212 | 886.6 ms | 601.3 ms |
| 128 MiB | 2 / 33,473 | 60,639,212 | 885.7 ms | 600.7 ms |

Fitting the entire body set reduces fresh checks from 24,202 to two, but saves
only about **68 ms / 7%** versus 16 MiB in this path. The full-reuse semantic
phase alone still exceeds 500 ms. Source loading, indexing/parsing and merging
add roughly another 285 ms. A larger cache helps; it does not remove the main
remaining elapsed time in this experiment.

**Limits:** this is a direct, in-process diagnostic comparison, with the same
syntax cache and compiler path at every budget. It excludes persistent store
I/O, CLI policy/receipt/report work, and final project destruction. It is not a
replacement S1 p95 result or proof of the exact fresh-process benefit. Its
16 MiB counters match the reported session workload, and its timings are close
to those session measurements. A fresh-process budget sweep still belongs in
the next measurement package.

**Correction:** describe retention as a demonstrated cause of extra work and a
measured modest session benefit, not the established dominant wall-time cost.
Do not infer that all remaining check time is body checking merely because
lowering/emission counters are zero. Interface construction, dependency keys,
tree replay, whole-graph passes, warnings and cache maintenance also execute.

### S1R2 — P2: measure specialization body replay with its own counter

Locations: `s1-corrected-report-2026-09-16.md:365-370` and
`scripts/profile_large_project.py:768-778`.

`instantiated_specializations` counts concrete functions in the checked program;
`src/main.zig:1151-1156` sets its reused field to zero. It does not distinguish
freshly checked specialization bodies from replayed bodies. The current harness
drops `specialization_bodies` and `symbolic_templates` from timed samples.

An independent fresh-process seed followed by the same managed-100k private-body
edit yields:

| Counter | Performed | Reused |
| --- | ---: | ---: |
| `instantiated_specializations` | 128 | 0 |
| `specialization_bodies` | **64** | **64** |
| `symbolic_templates` | 0 | 2 |

Thus the report's zero-specialization-reuse claim is false, even though its
copied `128/0` counter is accurate. `not-ordinary-body` records an ordinary-store
miss before specialization lookup and does not by itself prove fresh checking.

**Correction:** preserve the complete work report in samples; use
`specialization_bodies` for body replay; expose exact specialization miss reasons
before prioritizing a repair. Investigate the remaining 64 misses and dense
remapping separately. Sparse remapping may reduce allocation/copy work; it does
not by itself make missing nested specialization identities replayable. Update
the report and status text, including the stale blanket statement that concrete
specializations are fully rechecked.

## Test measurement boundary

The 100k timeout is honestly recorded, but the attempted warm-up never completed.
Its following forced run is therefore not evidence of a successfully warmed
100k test pipeline. The harness also measures forced runs rather than an edit
followed by affected-test selection, and does not include cached-test states in
this matrix. The three-sample 10k p95 is the maximum of three observations.

The implementation does perform whole-project preparation emission for changed
snapshots and builds a whole selected-provider library when execution is needed.
That supports pursuing C4. However, linking happens when an uncached selected
case needs an executor, not before test selection in every invocation. Fully
cached unchanged selections already skip emission/build. Keep these paths
distinct in the report and in future timing results.

## Next work, in priority order

### 1. Measurement correction and warm-check profiling

This is the immediate package. It should produce a defensible optimization
choice without changing language semantics.

- Preserve full work reports, retention totals/per-kind counts/evictions and
  exact specialization miss reasons. Keep invalid/timed-out runs out of success
  summaries and require successful warm-up before labeling native samples warm.
- Add separate timings for source/header loading, syntax replay/parse,
  declarations/interfaces, source merge, dependency-key preparation, ordinary
  and specialization replay, fresh body checking, effect/origin passes,
  warnings, and retention/durable I/O. Avoid double-counting nested timers.
- Repeat 16/32/64/128 MiB comparisons for both sessions and fresh processes;
  keep build mode, source workload and other cache budgets fixed. Measure peak
  memory and allocation/copy volume as well as p50/p95. Retain a no-cache control.
- Identify the largest costs after nearly all bodies replay, then assign a
  bounded optimization to the measured hot path. Preserve mandatory correctness
  passes unless a separately validated incremental design replaces them.
- Use at least 20 successful samples for acceptance comparisons, a pinned
  ReleaseFast binary, recorded host load, and private caches/fixtures. OS `perf`
  was unavailable to this review (`perf_event_paranoid=4`); explicit phase timers
  can supply the needed evidence without changing host settings.

**Exit:** corrected reports plus phase/allocation evidence that identifies what
still costs roughly 600 ms inside checking despite near-total body reuse.

### 2. C4 selective preparation and lowering

This is the next substantial implementation package and can proceed independently
of profiling the check path.

- Produce checked schema and test dependency facts without emitting the full
  project. Preserve declaration-first provider validation and source/key binding.
- Select cases and validate their receipts before lowering. Compute the union
  of reachable functions needed by uncached selected tests, including required
  adapters, concrete specializations and runtime support. Use explicit
  conservative handling where indirect calls prevent an exact closure.
- Lower, emit, compile and link that closure. Keep one shared preparation/library
  per canonical provider graph and preserve isolation between distinct graphs.
- Keep full required validity checks: an invalid project must still reject before
  cached green results, and fake-versus-unfinished-production behavior must remain
  correct. Preserve `--force` refresh and `--no-cache` no-durable-I/O contracts.

**Exit:** warm unchanged and wholly cached unaffected selections emit/build
nothing; a used-helper edit executes only dependents and compiles only required
work. Measure first build, warm cached, forced, used/unused-helper edit and provider
edit separately at 10k/100k, with lowering/emission/link/execution counters and
cold/no-cache result equivalence. Do not substitute forced execution for the
affected-edit objective.

### 3. Evidence-driven follow-ups and final acceptance

- Choose retention compaction, configurable budget defaults, sparse specialization
  remapping, nested specialization recipes or other checking changes based on
  the corrected profiles. A budget increase is a measurable memory/time tradeoff,
  not a demonstrated solution to the latency target.
- Add realistic specialization/provider churn to measure eviction and re-admission;
  the stable 128-specialization workload does not cover it.
- Re-run S1 against the final compiler, reconcile remaining D2 statements, and
  conduct the controlled productivity trial. Functional gate success remains
  separate from speed and comparative-productivity acceptance.

No new language-correctness blocker was found in this review. The remaining
findings concern measurement interpretation and the resulting priority order.
