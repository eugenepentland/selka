# A09 handoff — preparation checkpoint

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Owned files: this evidence directory and its measurement harness only.
Initially evidence-only. The coordinator later reserved `src/core/version.zig` and
`src/core/a09_version_test.zig` for a concrete migration blocker; root registration
and SPEC changes were supplied by the coordinator. No old reports were overwritten.

Fresh complete C0 Debug installation built successfully at
`/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0`.
Compiler SHA-256:
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
All six installed files and package manifests are pinned in
`C0-installation.json`; raw build output is `C0-build.log`.
Installation is frozen and shared read-only with all ten workers.

Build command, run with the shared environment sourced:

```sh
scripts/build-slot.sh build "$ZIG" build \
  -p "$PWD/.tmp/memory-closeout/A09/C0" \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Build passed Guardian's 88 diff-scoped checks and exited zero. This is not
complete final verification. The harness passes CLI, output/exit validation,
per-process wait4 usage and timeout smoke checks. Guest baseline timing builds
are queued. No before/after timing or memory improvement is claimed yet.

`manifest.json` pins nine initial guest cases: enlarged JSON array/object lookup,
owned record unpack, and A01's same-source cheap/expensive maps at 1/2/8 workers.
Expected checksums are calculated independently. See `methodology.md` for the
fixed two-warmup/nine-measured alternating-pair procedure, affinity, noise review,
RSS limitations, compile-cache states and timing schedule.

`build-memory-observation.json` is a 16-second observed process-memory envelope
used by the coordinator for its centrally approved two-build-slot trial. Its
148,948 KiB maximum sum is **not a full-run build peak**. It double counts shared
pages and may include same-name unrelated processes. It is not RSS evidence for
compiler performance or memory savings.

Outstanding: frozen integrated candidate/default/retirement identities; A06
qualified uninstrumented application binaries; final matched measurements;
A03 allocation/RC/managed-memory results; A08 cache/scaling results; A01 scheduling
and A02 policy evidence. Final performance conclusions depend on those artifacts.

Preparation followup: `measure.py run --cases ID --cpu 10` supports bounded
per-case timing windows and appends only if both artifact sets still match.
The coordinator approved CPU10 after CPU0's sibling was observed busy. Another
session's `mylang-dl-closeout-20261012-S10` ReleaseFast build was observed outside
our admission locks; this limits host isolation. `host.json` records the actual
allowed affinity, sibling set, cgroup and lack of delegated cgroup writes.
JSON inputs were extended again to 4,000,000 lookups in distinct `_long.my`
files after a first-array correctness smoke completed below 100 ms. The earlier
source/artifact remains preserved; it is not used for throughput conclusions.
The C0-guest-v2 preparation restarted with the centrally approved two-slot env
only while its old child wrapper was queued and unadmitted.

Additional preparation: compiler scaling uses a distinct ReleaseFast C0 build
(required by repository policy), never Debug smoke timings. `tree_rss.py` provides
separate memory-only sampled descendant RSS; its two-process/16 MB smoke passed.
The wrapper does not claim cgroup accuracy and its instrumented elapsed time is
excluded from primary results. A06's four application timing entrypoints are
recorded in `applications-manifest.json` and baseline plain builds are queued.
All four application shapes already passed A06's C0 release correctness checks;
those counted results remain A06 evidence, not A09 runtime measurements.

`schedule.json` records approved timing windows and observed limits. A02's first
native policy comparisons are very noisy. The deterministic five-element-list
allocation regression supports retaining the current capacity policy; no native
policy throughput improvement is claimed. The first two windows' sources and
binaries belong to A02's controlled C0 policy experiment, not an integrated final
compiler. Final C1/C2/C3 measurement dependencies remain outstanding.

C0 ReleaseFast is now built and frozen. Compiler SHA-256:
`78ac31605c7505c7cb330d41bdf2d3a232043e032f487e599f454b3bc6f2bd37`.
Its complete installation is `.tmp/memory-closeout/A09/C0-releasefast`; manifest
and raw build log are committed. Nine C0 guest and six A06 application timing
entries are built; exact identities are in `raw/C0-guests.json` and
`raw/C0-applications.json`. Final candidate paired comparisons remain pending.

A09 completed A02's remaining replacement/buffer/reserved native policy timings
on the same verified binaries, using longer workloads with two warmup and nine
alternating measured pairs. All samples/checksums/RSS are preserved in `raw/`.
The growth policy remains unchanged; no runtime or RSS saving is established.
The broad-noise buffer median triggers review but does not establish a repeatable
regression; the list-capacity edit does not change the byte-buffer growth path.
See `README.md` and machine-readable `results.json` for scope and precise metrics.

An A01 prototype map binary was built only for workload calibration. An attempted
cancellation of the queued no-op barrier did not prevent the shell's subsequent
pilot command: it later admitted and completed all 21 one-shot rows. The earlier
statement that calibration never ran was incorrect. `raw/workload-pilot.json`
preserves those actual observations as calibration only, not paired performance
results. No compilation was interrupted and no data was lost. No A09 timing lease
or request remains while the coordinator's critical component fix is underway.

The pilot identifies record unpack and several applications as too short, and
prototype cheap-map cases need more repetitions. Expensive-map one-shot timings
are slower in the prototype, but unrestricted hybrid P/E CPU selection is a
material confound. Final qualification will pin the same comparable CPU topology
on both arms and use the required alternating pairs before interpreting it.


Coordinator-requested correctness fix: ordinary-mode migration of `index_return`
exposed a loop-duplication graph bug. An inlined early-return join is included in
`members()` but also has a predecessor outside the cloned region. Copying that
predecessor creates an edge the outside block does not branch to. `duplicate()`
now declines regions with any outside entry except preheader to header, before
allocating cloned blocks. This is an optimizer eligibility restriction; the
program remains supported with the same semantics.

Before the fix, the focused regression suite passes its positive single-entry
optimization control and fails the early-return fixture with InvalidIr. After
the guard, both tests pass, including three leak-checked native runs across
trusted/verified pipelines and the empty-input path. The first after-run exposed
only an incorrect lowercase Boolean expectation, now corrected to `True`;
that failed log remains preserved. `raw/version/results.json` pins source,
compiler and raw evidence. The source change invalidates compiler cache namespaces
through build_identity (confirmed by A08). This focused fix still requires the
coordinator's final full gate and integrated artifact qualification.


Version fix committed as `714ae7645b0315a38eb152e27b8a8b0bb44b79b6`; Guardian
88/88 passed after extracting the eligibility predicate to meet the complexity
limit. The coordinator owns integration and final full verification.

Current measurement preparation: calibrated manifests, 15 immutable C0 case
records and six experimental map rows are ready. `compare.py` runs one case per
timing lease with ordinary barriers and preserves completed evidence on resume.
The final input-sizing pilot is not enqueued: its owning shell was terminated
while only an ordinary no-op barrier was queued, before any timing wrapper
existed. Waiting for the coordinator's gate-release notice. Final C1 Debug and
ReleaseFast installations remain required before paired runtime/scaling results.
