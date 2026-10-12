# Wave 2 S05 handoff

## Fixed source

B0 is `c1857310e0bf623545380c8de24515f1b9970021`.
The worker implementation commits, in order, are:

1. `6031bf862634ca7d5bc2b1f0d4ff23a502a65303`: authenticated bounded long
   execution, profile-v2, tests, source fixture and coordinator/registration requests.
2. `9d93b8c4af60dbc19633f4f3e9814d7ca09db982`: fixed native Juice recipes,
   no dynamic provider imports, exact parse→capture output binding and limits.
3. `005dd40f96128d7d8c38de944c825d7c50876a5c`: separately bounded large
   executable validation, unchanged raw/aggregate/blob limits, explicit fresh-only
   handling and boundary/alias/publication regressions.

Own changes: verification_profiles.py/tests, new verification_qualification.py/tests,
test/fixtures/long-qualification/cases.my, Juice adapter/tests, and the specifically
transferred juice_evidence.py/tests/test_juice_evidence.py. Common coordinator,
CLI/session, build registration, source pins and docs were never edited here.
Root has integrated the first two commits and applied the exact third delta while
preserving canonical identity changes. This handoff/evidence follows separately.

## Supported path and authentication

The helper exposes `qualify(root, cache, compiler, zig, context, snapshots,
targets=None, max_actions=4, action_timeout=300, fuzz_steps=8)` and a context-managed
`QualificationRun`. `qualified_names(run, context, required)` accepts only that
live request handle, exact context and fixed obligation inventory. Serialized JSON
success booleans, stale contexts, missing/edited output files, lost input authority,
closed handles, and reduced obligation inventories cannot grant completion.
Profiles consume the handle through `qualification_run`/`qualification_context`;
legacy serialized successes are rejected. Diagnostic JSON is never a receipt.

The fixed mandatory obligation set is fuzz, scaling, work-counters,
juice-instructions, wall-clock-performance and bootstrap. Long keeps every complete
gate requirement. Supported work now executes real approved existing runners:

- Incremental differential fuzz: one shard, eight steps by default, maximum sixteen
  admitted misses, explicit per-action deadline, existing corpus/receipt store.
- Duplicate scaling: all six original cases and nine compiler CLI invocations,
  existing correctness/determinism assertions, actual algorithm work counters.
- Compiler/driver counters: two fresh checks and four forced guest tests, exact
  completed names/counts, compiler work-report-v1 and once-per-provider key work.
- Native Juice: fresh perf records for compiler check and forced test driver,
  three repetitions each, existing output oracle and exact raw evidence validator.

`max_actions` limits attempted obligations, not compiler subprocesses. Explicit
finite deadlines apply after each admitted command starts and exclude admission
queues. Fuzz and Juice coordinators own their admission; they are never wrapped in
another slot. Scaling and direct compiler work use ordinary build admission.
Source counts and instruction counts have different scopes and cannot satisfy a
wall-clock ratio. Physical records remain report-only and fresh. Provider closure,
matched cache-tier regression and wall-clock/bootstrap requirements remain visible.
S09 diagnostics never grant a full-bootstrap capability; root must guard any adopted
external bridge's actual loaded code/source, rather than dynamically importing it
through an unreviewed path. This helper has no such dynamic import.

`coordinator.patch`, `registration.patch` and `canonical-identity.patch` are exact
reviewable requests. Root has adopted CLI controls `--qualification-target`,
`--qualification-max-actions`, `--qualification-timeout`,
`--qualification-fuzz-steps`, common/session guard and registration wiring.
Root applies S08's canonical loaded-code helper/format identity and verification-v2
namespace migration. Worker operational evidence before adoption uses the guarded
B0 marshal implementation; it does not claim final canonical-session acceptance.

## Real evidence and limits

All native work sourced /home/epentland/.config/mylang/dev-env.sh: pinned Zig,
private local cache/on-disk TMPDIR, shared global cache and unchanged admission.
The immutable original ReleaseFast compiler SHA-256 was confirmed as
`75935fabfbde64f8045d0aaba92122b304d344bee06839699b7b21563dcae9b1` at
/home/epentland/ai/canopy/mylang-dl-closeout-20261012-integration/.tmp/frozen-final-release/bin/mylang.
Native compiler sources match B0; these worker changes affect Python tooling.

`fuzz-observations.json` records a real completed two-step, one-shard differential
action. `scaling-observations.json` records all six real compiler work observations:
header-index sizes 128/512/1024 and banded-distance sizes 50/100/200. The largest
banded case performed 4,070,419 units under its 4,100,000 ceiling. Header work and
the original deterministic pair assertion remain intact. Queue time and printed
two-run elapsed observations are operational, not isolated latency claims.

The encompassing development request was correctly rejected when this worker
edited its helper while later work was queued. `development-mutation-rejection.*`
and `live-qualification.log` preserve that behavior. These native action observations
do not certify final long-request authority, the final source candidate, or a full
fuzz campaign. Source fixing was prioritized over keeping an earlier request alive.

S10's exclusive availability probe proved hardware events can be counted. The
subsequent real compiler Juice capture used the native CPU-specific PMU selector,
not the generic hybrid probe. It produced three complete, fully counted
cpu_core/instructions/u samples: 474,904; 474,866; 474,906. Median 474,904; observed
spread 0.00008422754914677493. Exact empty output and completed one-check units were
validated for each native repetition. `raw-instructions/compiler-check/` retains the
original record and raw perf/stdout/stderr files; `validated-instruction-recovery.*`
records expected identity, executable SHA, metrics and read-only validation.

The first adapter attempt conservatively refused the 68,298,936-byte compiler
because the old generic artifact bound was 64 MiB. `live-instructions.*` preserves
that partial refusal. The repaired adapter validated the already completed original
record read-only; **zero measurements were repeated after the failure**. Executables
now have a separate 256 MiB bound, raw files remain 64 MiB, aggregate evidence remains
1 GiB and the reusable blob store remains 64 MiB. A digest used by both raw and
executable evidence still obeys the stricter raw bound in direct and document reads.
Oversized fresh compiler captures cannot publish a reusable alias/blob; the adapter
labels them fresh-only. No shared-store size or retention policy was changed.

Test-driver instructions were not captured after the first refusal. Root also found
a distinct uncacheable native-object cleanup defect after ld.so.cache changed from
its approved pin; the owner fix requires joint authorization. No repeated known
failing native test/capture was launched here. Instruction regressions, external
provider closure, matched cold/warm cache tiers, latency/p95 and wall-clock ratios
remain unqualified. Raw counter repeatability is an observation, not regression
enforcement or complete performance acceptance.

## Tests, integration and remaining work

Focused logs report 13 profile, 11 qualification, 31 raw-evidence and 43 Juice
adapter tests passed, all exit 0. These cover fabricated serialized authority,
source ABA, output mutation before/after capture, closed/context-mismatched handles,
partial commands/work caps, exact case inventories, distinct executable/raw limits,
shared-digest classification, aggregate ceiling and refusal before blob publication.
Each source commit ran its normal Guardian hook: 88 checks passed; size/length/ABI
observations remain report-only. Guardian feedback was not modified.

`validation.json` records exact source SHA-256s, fixed implementation SHAs, native
compiler hash, counter meanings and unavailable fields. The required complete gate,
formatting, canonical runtime/session acceptance and final inventory/configuration
review belong to root/S10 on the frozen integrated candidate. No redundant full
gate, timing window, main merge, push, bootstrap takeover or memory rollout was run.

Root should preserve canonical identity/input closure changes when integrating the
large-artifact delta, then prepare its repaired compiler after source freeze. Run
the actual supported long cohort and complete gate on that exact candidate. Attach
authenticated S09 diagnostics and S10's explicitly scheduled timing adapter only
under their reviewed source/producer contracts. Unsupported wall/bootstrap and
unqualified machine-regression obligations must keep long qualification partial.
