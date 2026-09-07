# Rotation trial after standard-library preparation — 2026-09-07

All three fresh participants passed the same seven private groups: 138 EDA boards
and four malformed requests. `.my` and Python took about 117 seconds each; Zig
with Guardian took 214 seconds. This is one small exploratory feature task, not
evidence of a general productivity advantage or a reduction in defect rate.

| Language/workflow | Familiarization | Application including checks | Public submissions | Failed public submissions | Private acceptance |
| --- | ---: | ---: | ---: | ---: | --- |
| `.my`, optimized VM | 25.5 s | 116.7 s | 2 | 0 | 7/7 |
| Python | 22.1 s | 117.3 s | 1 | 0 | 7/7 |
| Zig + Guardian | 56.5 s | 214.0 s | 2 | 1 | 7/7 |

All participants passed the same 21-case practice suite. Common ceilings were
20 minutes for practice and 30 minutes for application work. Application timing
starts before task/repository access and includes source reading, coding, builds,
tests and ordinary tool waits. Independent grading and review follow sealing.
The 0.6-second difference between `.my` and Python is not a meaningful established
ranking. Zig's observation includes its required Guardian workflow; it does not
isolate compiler, language or gate causality.

## Preparation completed before application clocks

The [capability matrix](../../experiments/application_comparison/stdlib-parity.json)
maps required Python/Zig standard operations to `.my` APIs and their limits.
Both `.my` baselines now use the standard JSON parser, text I/O/formatting,
character-class matching and range-key ordering. The planner additionally uses
standard dependency readiness. New `std_order`, `std_graph`, `std_ascii`,
`std_counter` and `std_iter` modules bring the embedded library to 34 modules.
Library implementation, compiler builds and baseline migration were completed
before participant preparation; none are charged to application time above.

The [preparation receipt](../../experiments/validation/stdlib-parity-20260907/receipt.json)
records six-baseline common conformance, 12 planner CLI groups, maximum-size graph
checks, and the EDA stress suite including 57,692,813 output bytes. Three focused
Zig tests and six native library fixtures passed, including 3,568 injected
allocation-failure positions. Native checks validate library implementation; the
measured `.my` application used the VM. Normal build/commit Guardian gates passed
all 88 checks without policy changes. An initial Debug-host stress timeout remains
recorded separately; the final optimized run passed unchanged input bounds.

Preparation was not free: its complete developer time, turns, tokens and compute
cost were not instrumented. The matrix retains the first explicit clock capture
and readiness completion, with the earlier unmeasured work disclosed. Verification
logs are not a substitute for full development-cost accounting. A total adoption
cost or break-even point cannot yet be calculated.

The [readiness receipt](../../experiments/application_comparison/evidence/stdlib-parity-readiness.json)
binds the reviewed matrix to actual compiler/host binaries, standard-library
sources, both comparator runtimes, all six baselines, contracts and evidence.
It verified before setup and before grading. Full runtime/tool configurations
also verified before and after grading; coordinator source identity was unchanged.
This checks declared coverage and input identity, not mathematical equivalence.
No participant reported a missing standard-library capability during this task.

## Change and quality evidence

The task adds optional component rotations of 0/90/180/270 degrees, preserving the
top-left occupied-box anchor. Width/height swap only at 90/270. Boundaries,
clearance, centers/net spans and SVG must agree, while invalid types/angles,
extra fields and validation precedence retain the specified behavior.

All three implementations centralize occupied dimensions: Python uses a named
rectangle helper, `.my` a shared dimension helper, and Zig normalizes its component
representation once during parsing. An independent reviewer inspected exact sealed
sources against the public task and predeclared rubric without timings, private
cases or execution. No rotation correctness defect was identified. Each scored
2/2 for clarity, consistency and test relevance, with concrete evidence retained
in the [review](../../experiments/application_comparison/evidence/stdlib-parity-rotation-review-20260907.json).
These equal, subjective scores do not establish one language's code is better.

Python added seven tests and reported 27 passing unit tests. `.my` retained its
CLI assertions and added explicit geometry/schema checks plus 128 paired fixtures.
Zig reported 12 passing Zig tests and an expanded ReleaseSafe stdin suite. Tests
include independently specified boundary/span/SVG expectations; metamorphic cases
supplement those expectations. Counts are coverage descriptions, not quality ranks.

Zig's first public check was blocked by `test-no-conditional` (three top-level
loops in one test) and `repeated-string-literal` (`rotation`). Splitting tests and
extracting `rotationKey` resolved both. Independent source comparison found the
protected policy and root wrapper unchanged. These were test/maintenance repairs,
not demonstrated application defect detections. A premature practice finish also
hit the gateway lock until its running check completed.

`.my` adapted a checkout-dependent test-driver path to `/tools/byte_io` in `/work`.
That time remains charged in this attempt. Portable test launching should be part
of preparation before another cohort; do not retrospectively discount this clock
or edit its sealed sources. Python reported no comparable friction.

## Interpretation and continuation

Task command counts were `.my` 5, Python 6 and Zig 7; public checks were 2, 1 and 2.
Commands may contain multiple actions. These are not model-turn counts: exact
turns, token/cost telemetry, precise model ID, relevance and cache/queue attribution
remain unavailable. There is no supported fewer-turns claim from this block.

Fresh-thread capacity forced sequential dispatch: Python, then `.my`, then Zig.
The deviation is retained separately from the frozen initial protocol. No baseline
author was reused as a participant; no active clock was paused or reset. This
fixed-order block is not randomized. Commands ran through namespace-isolated
gateways, but whole-agent host access was limited by instruction, not enforced
confinement. Shared-host effects remain possible. These limitations keep the run
exploratory and scored pilot count at zero.

Earlier calibration used different tasks, library/baseline versions and sometimes
different build policies. Preserve those results without pooling them here or
claiming the library caused a before/after speedup. The new result establishes
feasibility with prepared libraries; it does not answer the larger-codebase or
rare-defect questions.

Next: make test launching portable, retain exact model/turn/usage telemetry for
scored work, and repeat fresh matched repair/shared-contract/feature blocks under
one frozen policy. Then use pilot evidence to decide medium/large and follow-up
maintenance work, repeating library capability review before each new workload.

[Machine-readable results](../../experiments/application_comparison/evidence/stdlib-parity-rotation-20260907.json)
retain clocks, outcomes, observed tool metrics, source hashes, review and deviations.
Full frozen inputs, sealed sources, patches and private results remain under
`/home/epentland/ai/canopy/application-trials/stdlib-parity-20260907-rotation`.
