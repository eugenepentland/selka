# A09 handoff — prepared runtime matrix, frozen baselines and versioning fix

Latest coordinated C3 request: `retirement/c3-counter-runtime/counters.patch`
targets four counter files at Support7 `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
It is unapplied and must accompany A02 runtime/A07 emitter retirement. Twenty
synthetic parser controls and twelve native scratch-runtime controls pass;
all anchors apply, allocation/growth/copy/direct-destruction telemetry remains,
and all native runs have zero managed exit-live bytes. Historical v1 RC columns
remain required explicit compatibility zeros, with no claim they observe RC
events after their hooks are removed. Structural proof is independently required.
Initial harness failures and their corrected interpretation are preserved in
the draft README and raw archive. No final guest/package C3 proof is claimed.

Latest preparation: `C1-schedule.md/json` distinguish 330 runtime launches,
90 separate RSS launches, 30 planned size-aligned counted configurations and
the independent 435-build/695-run census. The corrected RSS harness is commit
`268a77a3e`, with native parent-memory controls and Guardian 88/88. All 15 frozen
runtime inputs and both complete C0 installations were reverified unchanged.
The ordinary exact-sized counted C0 builds encountered eight native-link
failures; these remain in `raw/size-aligned-C0`. Root subsequently approved A10's
exact-source native adapter `44a9ccbbc`: all eight reconstructed native binaries
and 15 counted configurations pass, using the archived LLVM and compiler-verified
C0 runtime. `raw/size-aligned-C0-native-replay` records this separate method with
zero observed RC and no managed exit-live bytes. Final C1 must use the same
adapter and repeat normal/manual equivalence controls. The compiler/package
freeze remains outstanding, and no final timing pair has run.

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

The later RSS audit invalidated the RSS columns in all three guest pilot files:
outer `wait4` usage included launcher high-water memory. Raw files remain intact.
`raw/rss-qualification` reproduces the error and qualifies the corrected GNU-time
guest-child RSS path with 1/64 MiB native children and 0/256 MiB parent memory.
Final wall timing and RSS now use separate executions/results; no old pilot RSS
is evidence of guest memory use. Native capacity GNU-time reports are unaffected.

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


Post-hook raw confirmation is complete in `raw/counters/recursive-after-hook.json.gz`:
checked debug/release have exactly two copies/40 bytes, with every other total
unchanged from the Support4 reproducer (including mode-specific allocations and
peak608). No runtime/RSS claim is attached to these instrumented runs.

Host admission monitoring: `raw/three-slot-sample.json` observed at least18.70GB
MemAvailable over31seconds, but that interval covered light/drained work and is
not a heavy-build peak. The coordinator separately approved3 build slots with an
8GiB available-memory admission threshold. An external cooperating development-loop
session held timing admission for several minutes with all build slots idle;
its delay is queue time, not compiler/guest time. It was not interrupted.

The coordinator authorized continuation branch
`codex/memory-closeout-20261012-A09-continuation` at
`35e6f3cf333abe84937af1d2e4450885cf17a2f8`; original worker branch/evidence remain.
`measure.py` now explicitly selects opt-in C0/C1 versus ordinary C2/C3 commands,
records actual options, and supports a bounded enclosing build lease. Nine
existing calibrated C0 binaries were reused with exact hashes/options preserved;
negative selector/admission controls passed. These are harness checks, not final
runtime pairs. All final-candidate measurement dependencies remain open.


## Registered checked list oracles

The six registered `ce_lists_test` tests now pass on continuation production
inputs plus approved A07 safety/exact-slot dependencies. The oracle checks source
ownership, IR and emitted LLVM, preserving direct destruction while rejecting
actual RC. Four retained native fixtures pass all five affected pipelines with
unchanged outputs, normal leak checks and exact bounds/memory-budget diagnostics.
A06's final ce_cow migration is its owning commit `8c91c5091`; the source copy in
this worker was borrowed and excluded from the A09 commit. The coordinator owns
`build.zig`'s `core-test-binary` target and the SPEC change requested in
`retirement/ce-lists-c1-spec-request.patch`.

`raw/ce-lists-registered` contains exact compiler/test/source hashes and all failed
preparation logs. The first oracle incorrectly forbade Core `release`, which is
direct destruction under the owned ABI; the retirement review is corrected too.
The initial trap-line216 expectation was also wrong: two migrated lines moved
the historical names store215 to217; the preceding three-element scalar list
accepts index2. Full/reduced debug/release LLVM and runs confirm correct ordering.
No compiler diagnostic defect was found. The final selected registered run passes
6/6. It uses explicitly staged Support5 components and does not claim installed
package qualification, full verification or final C1 measurements.

The coordinator additionally reserved `docs/tooling/counters.md`. Its audited
update distinguishes legacy RC events from direct drops, counted traffic from
managed live storage and uninstrumented RSS, and current cost-summary labels from
strict raw-counter audits. It documents the recursive-list copy telemetry fix
without reinterpreting historical measurements. Current examples retain opt-in;
separate C2/C3 doc patches and the ce_lists default-command patch are unapplied.
Sequential patch/hash checks and relative documentation links pass. No production
code changed, and no unqualified default or package claim was introduced.

## Managed selection diagnosis (Support6)

Read-only diagnosis requested by the coordinator reduced seven current managed
min/max/unwrap_or refusals, with two admitted scalar controls and nine successful
ordinary typed dumps. `repros/managed-selection` preserves the exact Support6
compiler/source hashes, source/typed/Core evidence and an unapplied frontend
list-extrema patch proposal. List selection loses availability because its hidden
borrow changes read-site provenance at a same-root loop join; two-value extrema
and optional defaults also join different potential parents. Clearing joined
provenance would be unsafe and is not proposed. The list-only alternative carries
a scalar selected index, preserves the empty-list trap, and reads the selected
child at the end. Its hand-written lowering reference passes source checks;
the production patch remains unapplied and unqualified. Coordinator/ownership
owners retain the implementation and native safety work. No public failure was
removed from the release inventory, and no source workaround replaced a fixture.
