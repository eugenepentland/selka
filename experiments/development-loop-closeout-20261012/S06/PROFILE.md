# S06 baseline fresh language work

Base C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Frozen Debug compiler comes from S10; its SHA and pinned Zig SHA are recorded in
`baseline-manifest.json`. Native preparation used the shared build-admission
queue, a private local Zig cache, worktree-local disk TMPDIR and shared global
cache. Nine registered actions were captured twice without filters. `--jobs 4`
is explicit, so these operational durations do not reproduce the unrestricted
registered gate's concurrency. Cold means a new private guest cache only; it
does not mean a cold shared Zig global cache or cold compiler construction.

| Suite | Tests per action | Debug cold/warm seconds | Unoptimized cold/warm seconds | Release facts+leaks cold/warm seconds |
| --- | ---: | ---: | ---: | ---: |
| lang | 1,552 | 45.105 / 3.217 | 34.654 / 3.246 | 60.559 / 29.956 |
| value_semantics | 140 | 2.429 / 0.357 | 2.202 / 0.204 | 4.432 / 3.262 |
| ported | 98 | 2.614 / 0.803 | 4.370 / 0.328 | 11.032 / 4.448 |

All 18 commands exited 0. Every cold action executed all selected tests.
Debug/unoptimized warm lang executed three and reused 1,549; the other two
suites reused all selected tests. Every release/facts/leaks cold **and** warm
action executed all tests, with `MYL_CORE_LEAKCHECK=1`, and no cached test verdicts.
Names and counts agree across tiers. No test inventory was reduced.

These are single operational observations under build admission alongside
other cooperating work, not isolated latency medians, p95, speedups or target
acceptance. Action time includes process startup, collection, JSON parsing and
raw report writing. Admission queue time is outside the action interval and
appears in the admission log; a separate numerical queue observation is not
available. Peak/aggregate RSS is not captured. Source mutation/crash/isolation
behavior of a new production implementation is not qualified by this capture.

The existing supported `cache.work` report exposes counts for key preparation,
canonical facts and lowering. `work-summary.json` extracts those counts without
adding nested durations. Warm fact/leak lang still executes 1,552 tests while
its recorded canonical work computes 856 facts fresh and reuses 3,217; lowering
reuses 3,217 bodies. Reused preparation does not waive fact assertions or leak
checks. Absent root-work telemetry is explicitly unknown. This report cannot
attribute full discovery/startup/frontend/native compile/link/execution phases;
`runner-patch-request.md` describes the joint instrumentation contract.

The independent RF control fixture executes cold/warm/force/no-cache/facts+leaks,
then changes a helper to make one test fail, forces that failure, and reverts.
The edited command returns 1 with exactly one failure and one unrelated cached
success; forcing executes both tests and returns 1; reverting returns 0 and
reuses both successes. Force/no-cache/facts+leaks report zero cached verdicts.
These eight controls use the unchanged frozen C0 RF compiler, so they establish
baseline contracts and a reproducer, not candidate compiler qualification.
