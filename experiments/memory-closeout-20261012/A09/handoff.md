# A09 handoff — prepared runtime matrix, frozen baselines and versioning fix

Base C0: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Worktree: `/home/epentland/ai/canopy/mylang-memory-20261012-A09`.
Evidence and scratch remain private to A09. Historical reports were not overwritten.

## Changes and commits

A09's preparation commits are `077400f76`, `4a700cb52`, `35bab5be4`,
`e41f9fd61`, `e5fb737d3` and `d64d01fec9eeb29a7e182cbad3b6d0494377f1b8`.
They provide frozen installations, runtime/RSS harnesses, calibrated sources,
raw controlled capacity experiments and explicit methodology/host limitations.

The coordinator temporarily reserved `src/core/version.zig` and new
`src/core/a09_version_test.zig` for a migration blocker. Fix
`714ae7645b0315a38eb152e27b8a8b0bb44b79b6` includes the coordinator's root test
registration and SPEC amendment. Those production reservations are now released.
No other production files were edited by A09, and no shared-file requests remain.

## Frozen installations

Both installations are complete, with `bin/`, `libexec/` and `tools/` together:

- Debug: `.tmp/memory-closeout/A09/C0/bin/mylang`, SHA-256
  `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
- ReleaseFast: `.tmp/memory-closeout/A09/C0-releasefast/bin/mylang`, SHA-256
  `78ac31605c7505c7cb330d41bdf2d3a232043e032f487e599f454b3bc6f2bd37`.

`C0-installation.json` and `C0-releasefast-installation.json` pin every installed
file and tool. Both compilers were freshly built here from C0 production inputs,
under shared admission. Their build logs are retained. The ReleaseFast source
comparison against C0 was empty for compiler/build/docs inputs; only A09 evidence
commits differed. The compiler's Debug mode does not imply Debug guest binaries:
all primary runtime timing binaries are uninstrumented Release builds.

Installed C0 components still derive from the historical component seed; this
baseline package is not claimed entirely RC-free. These frozen installations were
not rebuilt or modified by the later versioning fix.

## Tests and evidence

The versioning defect was ordinary-mode `index_return` migration: loop members
included an inlined early-return join also entered from outside via the normal
loop exit. A clone copied that outside predecessor while the outside block still
branched to the original join. `duplicate()` now rejects such a region before
allocating clones; the sole permitted outside edge is preheader to header. The
source program remains supported with unchanged semantics.

Before the fix, the two-test focused suite passes the positive optimization
control and fails the reduced source with InvalidIr. After the guard, both tests
pass, including three leak-checked native executions in trusted/verified pipelines
and the empty-input path. The positive single-entry fixture still unswitches.
A first after-run had an incorrect lowercase Boolean expectation, corrected to
`True`; its log is preserved. Guardian initially rejected cognitive complexity;
extracting `singleEntry()` resolved it, and the final gate passed all 88 checks.
`raw/version/results.json` records exact commands, compiler/source/test-binary
hashes, before/after logs and the original optimized IR. A08 confirmed the source
change invalidates optimization/emission/native/replay cache namespaces through
build_identity. The coordinator still owns integrated verification.

Native capacity-policy continuation is complete: two warmup and nine alternating
measured pairs each for lengthened replacement, growing buffer and reserved
buffer workloads, CPU 10, exact frozen baseline/start-one binary hashes. All
samples/RSS/checksums are in `raw/capacity-*-long.json`. No runtime or RSS saving
is established. A02 retains current growth based on deterministic allocation
tradeoffs; the broad-noise buffer median is reviewed as an unchanged-path noise
control, not a repeatable regression. See README/results.json for separate metrics.

The final runtime matrix has 15 prepared C0 cases: nine JSON/record/map entries
and six entries covering four application shapes, including parallel 1/2/8 workers.
`calibrated-manifest.json` and `calibrated-applications-manifest.json` freeze source
paths, local module hashes, runtime arguments, checksums and CPU affinity.
`raw/C0-calibrated-guests.json` and `raw/C0-calibrated-applications.json` pin binaries.
Recalibration reused verified artifacts; only record unpack needed a new source
with one million iterations. Earlier sources and evidence remain preserved.

The final-input pilot passed all 21 exact-output checks (15 C0 and six A01
prototype map entries), UTC 2026-10-12 01:38:38.742775–01:39:05.456624. Admitted
elapsed time was 26.71 seconds; its 15-second queue wait is excluded. The shortest
sample was 158.1 ms. `raw/workload-pilot-final-inputs.json` retains every observation.
A01's prototype is solely a sizing control, not C1 or final performance evidence.
Earlier all-CPU and fixed-topology pilots also remain preserved.

## Running final qualification

Use an exact frozen integrated Debug installation to build candidate timing
artifacts through `measure.py build`; it owns build admission, so do not nest it.
A06 timing source files currently resolve through its separate worktree using
`--source-root`. After integration the same hashes can resolve in the coordinator
checkout. The default/retirement selector may change, but paired guest inputs,
arguments, environment, workers and affinity must remain identical.

`compare.py --before BUILDS.json --after BUILDS.json --output NEW_DIRECTORY`
checks compiler/binary identities, runs one case per exclusive timing lease, and
uses an ordinary admission barrier between cases. It preserves completed cases
on resume, rejects changed artifacts and stops on failure. Do not wrap this
orchestrator in admission. Each case uses two warmup and nine measured alternating
pairs. `measure.py run --cases ID` supports manual per-case scheduling as needed.

Use the separate frozen ReleaseFast compiler pair for A08 compilation scaling.
A08 owns cold/warm/receipt/replay/edit cases and their phase metrics. Its
representative sampled tree RSS run is separate from timing; the very short
replay sample missed the compiler and is explicitly invalid as replay tree RSS.
`tree_rss.py` documents sampling/shared-page limitations; cgroup peak is unavailable.

Final workers use CPU 10 for one worker, CPUs 8/10 for two, and CPUs 0–11 for eight.
The last set is six physical P cores with twelve logical CPUs. Cheap-map iteration
counts differ across worker cases to bound the slower baseline windows, so raw
wall times across those worker counts are not a scaling claim. Each paired case
uses identical work. All input preparation is now complete.

## Limits and outstanding work

A09 has zero final-candidate runtime pairs. C1 Debug/ReleaseFast installations and
final A03/A06/A08 qualification remain dependencies owned by the coordinator and
those agents. A03's original30/pinned81 census remains separate from timing-input
supplements; metrics with different input sizes are not mixed. Default promotion
and RC retirement require fresh affected artifacts/reruns. Earlier binaries will
not be relabeled as C1/C2/C3. None of the three closeout milestones is claimed here.

Shared timing admission drains cooperating jobs, not the whole host. Unrelated
builds and historical unadmitted Guardian hooks are disclosed in schedule.json.
A09's earlier commit ending 00:46:58 overlaps A02's noisy nested-five window;
its hook admission is not established by preserved metadata. Future A09 commits
explicitly use shared gate admission. The initial 16-second process snapshot is
only an observed envelope, not a full-run build RSS peak. Managed counters, child
RSS high-water marks, sampled descendant RSS, allocation traffic and wall time
are reported separately.


## Counter audit follow-up (before C1)

Coordinator reserved `src/core/count_runtime.zig`, `src/core/count_test.zig` and
subsequently `src/core/ce_lists_test.zig` to A09. The migrated counter fixture is
A03 commit `17a70623b` (copied temporarily for qualification, not owned or committed
by A09). Driver dependency `38dc781a` was explicitly authorized and cherry-picked
as `47d600345`; preserve coordinator registrations when integrating only the A09
counter change.

Eight Support4 configurations and sixteen normal/trap runs pass, with exact
separate ordinary and checked counters in `raw/counters/README.md`. A missing
runtime hook undercounted descriptor-driven recursive list-copy traffic; the
list-only anchored hook fixes that count without instrumenting box shells or
counting ordinary helper copies twice. Registered focused tests pass 2/2, including
five checked pipelines and debug/release recursive-box copying. Command:
`zig build test-core -Dtest-filter='zero RC count' -j4 --maxrss 8589934592`
under shared build admission. `raw/counters/hook-build.json` pins source/compiler
identities. This is a focused qualification, not the final integrated gate.

`retirement/count-runtime-retirement.patch` is deliberately unapplied until C2
qualifies and the coordinator dispatches A02 runtime retirement. It removes only
five obsolete count-helper anchors, preserves all allocation/copy/growth/free
instrumentation and retains zero-valued historical telemetry fields. A03 knows
the v1 schema remains strict. `retirement/ce-lists-review.md` records necessary
optimization oracle migrations; A06 source hashes and exact checked IR must guide
that work. A prepared patch/review is not completed retirement.
