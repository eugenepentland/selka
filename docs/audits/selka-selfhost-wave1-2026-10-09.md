# Selka progressive self-hosting: first wave qualification

Base: `main` at `0689d3407c17df34915aeb2a92e309af3a04921c`.
Branch: `codex/selka-selfhost-wave1`. This wave implements milestones 0–2 of
[the interop plan](selka-zig-interop-plan-2026-10-09.md).

## Delivered boundary

`selfhost/component-seed.json` pins the pre-component compiler and Zig version.
`selfhost/components.zig` is the native build/install coordinator. It provisions
the source archive and records the qualified executable, runtime/source and Zig
library identities. It streams SHA-256 hashing through bounded buffers for the
toolchain executable, library inputs, seed and component artifacts. The builder installs
content-named component executables and atomically selects a manifest. A fresh
component-only rebuild checks byte reproducibility; malformed or corrupted cache
entries fail explicitly. Interrupted seed builds recover under the builder lock.

`selfhost/components/test_index/` contains the Selka graph library, bounded binary
codec, native entrypoint and pure tests. The graph preserves cycles, discovery
order, duplicate test roots and direct-edge multiplicity. Function names stay
native: the algorithm needs only integer indices. The shared empty-frame golden
covers unsigned identity bytes; host tests cover Unicode and zero bytes in names.

The Zig adapter supplies explicit process/file services. It verifies manifest
and executable digest, creates a private request directory, uses a fixed deadline
with bounded stdout/stderr, validates reply identity and releases temporary files.
It races native `std.process.spawn`/`MultiReader` execution against a deadline
covering the complete child lifecycle. Timeout cancellation kills and reaps a
child even when it closes both output streams and ignores SIGTERM; a dedicated
regression covers this case. Importing the Core module's private spawn
implementation from the frontend would violate Zig's module ownership rules.

Production `tests-for` (checked and syntax), lint, interface listings and
`context` use the component. Reference/shadow modes are explicit. The embedded-only
`reference` command keeps its pure renderer to preserve its no-filesystem contract.
Missing components fail without silent fallback. No actual test-skipping or Core
cache-key algorithm moved in this wave.

## Bootstrap and test integration

Default install includes `bin/mylang` and the component package under
`libexec/mylang/components`. `zig build components` executes one builder step and
has no host compile dependency. The relocated package works from an unrelated
working directory without environment overrides.

Source builds compile and run the native Zig coordinator for component provisioning.
Python remains a test-only dependency for blackbox coordinator and protocol/oracle
qualification. The installed host and component remain interpreter-free; the
existing empty-PATH contract is retained. The test-only drivers accept the compiled
coordinator through `--builder`; they do not import a Python production coordinator.

The historical stage-0 pin is unchanged. D6 describes the current Core/LLVM
boundary; D7 now explicitly permits independently seeded component profiles,
while retaining the full compiler's release-delay rule. `component-v1` is a
qualified profile, not a claim of a compatibility release.

`zig build test-components` and the main test target include builder regressions,
pure Selka tests in debug/release with fact verification and leak checking, and
native protocol/oracle tests. Cached test steps hash the installed manifest in
addition to source inputs, so a changed artifact, seed or toolchain cannot retain
an old test verdict merely because the Zig host stayed identical.

## Historical acceptance results: Python coordinator baseline

The measurements in this section predate replacement of the Python coordinator
with the native Zig coordinator. Builder timings are the Python coordinator
baseline and are preserved as historical evidence; they do not measure the
current native provisioning path. Measurements are local development measurements
on a shared machine, not a controlled benchmark. The edit demo used an isolated copy of component source,
the shared builder and the installed host. A deliberate graph-body mutation
removed the root's self-reachability; the normal `tests-for` command changed from
`reached-by (1)` to `reached-by (0)`. Restoring source restored the original
artifact and answer. The mutation was never applied to the delivered component.

| Check | Result |
| --- | --- |
| Installed host SHA-256 before/after component edit | Identical: `a88917b6abcc2476589e8704d50844e28362bc53ec15b0317d6868ff9158006b` |
| Python baseline: new graph-body compile/install | 4.80 seconds |
| Python baseline: unchanged component build/install | 1.55 seconds |
| Python baseline: uncached rebuild of unchanged inputs | 4.55 seconds; identical artifact digest |
| Warm small `tests-for`, 15 samples | Reference median 4.33 ms; component 8.49 ms; shadow 8.42 ms |
| Relocated host + component, working directory `/` | Correct result with no component environment override |
| Relocated installation, empty `PATH` | Check/build/run/test/fmt/docs/navigation/context and LLVM release build/run passed without a component override |
| Native 1,000-node/100-test/10,000-edge graph | Debug median 15.17 ms, release 6.75 ms; 44,472-byte request and 412,068-byte reply |
| Protocol and graph oracle | 19 malformed frames, output overflow, missing input, failed output and 100 deterministic random graphs passed |
| Focused Zig adapter suite | 10 named tests passed (17 including unconditional root blocks) |
| Focused CLI component suite | 2 named tests passed (5 including unconditional root blocks) |
| Python coordinator builder regressions | 10 passed, including corrupt uncached artifacts, installation permissions and interrupted seed recovery |
| Pure Selka suite | 6 debug and 6 release tests passed, zero replayed results |
| Guardian install gate | All 88 checks passed at the changed-source scope |

The local qualification budgets were under 50 ms for the medium debug exchange
and under 25 ms of added median latency for the small warm CLI fixture. Both passed.
The cold source-qualified ReleaseFast seed build took several minutes and is
outside the component edit loop. The pinned source archive has no Git metadata;
its recipe builds the established `affected-compiler` target. Current project
implementation checks still run the normal Guardian gate.

## Historical regression validation before native coordinator replacement

`zig build test fmt-check -j2 --summary all` completed every suite and reported
2,335 passing Zig test executions and one failure. The sole failure was the
empty-PATH integration fixture: it invoked the uninstalled compiler from Zig's
build cache, which had no adjacent component package. The fixture now stages a
complete `bin`/`libexec` installation, verifies the copied component digest, and
runs the staged compiler without any component-directory override.

After that fixture-only change, `zig build test-cli install fmt-check -j2
--summary all` passed all 261 CLI tests, formatting, installation and all 88
diff-scoped Guardian checks. The targeted empty-PATH test also passed separately.
The other test roots and implementation did not change after the full run;
their successful results include all 600 Core tests, frontend/unit shards,
incremental/interface/cache-isolation drivers, debug and release language/value
suites, doctests and the component qualifications above. The queued redundant
aggregate rerun was canceled before execution because other benchmarks held
the shared gate slot; the complete changed CLI root was rerun using the
repository's supported focused build target instead.

No full ReleaseFast host test matrix was run locally. The native Selka component
and guest-language suites were qualified in both debug and release modes with
fact verification and leak checking. Guardian feedback was appended and
committed separately in `guardian-zig` as `37959d0`.

## Native coordinator qualification

The native coordinator compiled successfully, and its blackbox harness passed
all 15 tests against the final rebuilt coordinator. The harness
uses native shell fixtures for the pinned toolchain and seed compiler, so it
exercises coordinator behavior without compiling a host for each case. Coverage
includes unchanged cache hits; source, embedded-input, qualified-seed and Zig
library invalidation; missing/corrupted cache artifacts including `--uncached`;
installed artifact corruption; failed-build preservation of the selected manifest;
uncached byte reproducibility; manifest/artifact/receipt modes under `umask 077`;
interrupted seed recovery;
and concise failure for malformed receipts or invalid archive/seed digests.

Before the final CPU-identity and coordinator-target corrections described below,
`zig build test-components test-cli install fmt-check -j2 --summary all` passed
27/27 build steps and 268/268 Zig tests: all 262 CLI tests and six native support
tests. It also passed the 15 blackbox regressions, six pure Selka tests in each
of debug and release modes, and the malformed-protocol/random-graph oracle in
both modes. All 88 diff-scoped Guardian checks and formatting passed. The new
CLI regression builds and installs a real component with an empty `PATH` and an
already qualified seed. The native support tests cover fixed-buffer hashing of
an 8 MiB file, canonical Unicode JSON, archive safety and source tree identity.

This run covers the changed coordinator, build integration and entire CLI root;
it does not claim another complete Core/frontend aggregate run. The production
Zig host remains byte-identical to the historical acceptance digest above.

A fresh cache was provisioned with a verified `--seed-source` archive, an
absolute Zig path and an empty `PATH`. Native extraction, the full ReleaseFast
seed build, component compilation and installation succeeded without Python,
Git or an external tar program. GNU time reported 385.64 seconds and 4,310,528
KiB peak RSS (about 4.11 GiB), including child processes and excluding the
build-slot wait. This measurement predates the coordinator's baseline-CPU
workaround below and is not a new cold timing for the final executable.
This cold cost is dominated by the optimized compiler seed;
it is separate from the component edit loop. The existing qualified seed was
also reused unchanged under recipe key `99a0c5875f1543cbb9c55694eb744328012fd1454b83a451ea11c6b2f96963fc`.

### Final corrections and validation

Reading `/proc/cpuinfo` using a stat-sized allocation returned no data because
procfs reports a zero file size. The coordinator now streams its first record
through a bounded 64 KiB buffer. Two additional support tests cover real procfs
and record/size boundaries; the blackbox harness also asserts that stored Linux
CPU identities contain actual model/features. Seed and component keys retain the
native CPU identity rather than the coordinator's compilation target.

The pinned Zig compiler's accelerated SHA-256 code produced expensive AVX/SSE
transitions on this machine. A CPU-pinned seed-verification run took 31.89 seconds
and recorded 591,717,827 SSE/AVX-mix assists. Compiling only the coordinator with
baseline CPU instructions reduced that verification to 1.60 seconds on the same
CPU. This was the initial workaround; the LLVM ReleaseSafe/native-CPU follow-up
below supersedes it. Both workarounds use the standard SHA-256 implementation
and leave the installed toolchain and seed/component recipes unchanged.

After both corrections, `zig build test-components test-cli install fmt-check
-Dtest-filter='CLI component' -j2 --summary all` passed 27/27 steps and all 14
selected Zig tests (eight support tests and six CLI executions, including three
unconditional root blocks). All 15 blackbox regressions, the debug/release Selka
and protocol/oracle suites, formatting, and 88 diff-scoped Guardian checks passed
again. Together with the complete CLI run above, this qualifies the changed
paths; it is not a second full Core/frontend aggregate result.

An ordinary default `zig build --summary all` also passed all 12 steps with a
`PATH` containing only Git and Zig. It reused the qualified seed and cached host,
ran the native coordinator and passed Guardian without a Python executable on
`PATH`. The separate cold bootstrap above covers provisioning from source.

### Baseline-CPU component rebuild measurements

These are medians of three samples on the shared machine, reusing the qualified
seed and excluding build-slot waits. GNU time reports peak RSS including child
usage as the largest individual process, not the sum of concurrent processes.
The Python samples below are the repeated baseline measurements, distinct from
the earlier single-run acceptance figures above.

| Operation | Python coordinator | Native coordinator | Python peak RSS | Native peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Unchanged component check/install | 0.90 s | 1.65 s | 197.1 MiB | 37.7 MiB |
| Forced component rebuild/install | 3.78 s | 4.83 s | 197.0 MiB | 154.3 MiB |

The final native time ranges were 1.63–1.69 seconds unchanged and 4.80–5.33
seconds rebuilt. Peak memory fell about 81% and 22%, respectively. Time increased
by 0.75 and 1.05 seconds: removing Python does not itself make hashing faster,
and that coordinator used the portable SHA path to avoid the pinned toolchain
issue. The 64 KiB streaming buffers remove the whole-file allocation;
compilation remains the largest process during a rebuild.

A real graph-body edit in an isolated source copy rebuilt in 6.33 seconds and
changed normal `tests-for` output from `reached-by (1)` to `reached-by (0)`.
Restoring source restored the original manifest, artifact digest and answer.
All unchanged, forced and edited native measurements ran with an empty `PATH`.
The installed Zig host remained byte-identical throughout. Raw final measurements
are in the local `.mylang-cache/native-coordinator-qualification.json` report.

Guardian usage feedback for the native coordinator run was committed separately
in `guardian-zig` as `3639aac`.

### LLVM ReleaseSafe coordinator follow-up

The coordinator now explicitly uses LLVM, ReleaseSafe and the native CPU target
on the existing `0.17.0-dev.1683+5ceec001b` pin. This replaces the baseline-CPU
ReleaseFast workaround. The [toolchain comparison](../../experiments/zig017-toolchain-20261009/README.md)
found that LLVM ReleaseSafe avoids the hashing transition regression on this pin;
ReleaseSafe with Zig's native backend does not. The build therefore sets
`use_llvm = true`, requiring an LLVM-capable pinned Zig for this helper.

The integrated command `zig build test-components test-cli install fmt-check
-Dtest-filter='CLI component' -j2 --summary all --verbose` passed all 27 steps
and 14 selected Zig tests. Its compile trace confirms `-fllvm -OReleaseSafe`
with the native target. All 15 coordinator blackbox tests, six pure Selka tests
in each mode, and both Debug/Release protocol suites passed. Each protocol suite
covers 19 malformed frames, reply overflow, missing files, output failures and
100 randomized graphs. The CLI suite includes a real component rebuild and
installation with an empty `PATH`. Formatting and all 88 diff-scoped Guardian
checks passed; this was a focused qualification, not a full compiler aggregate.

Neither the Zig pin nor the seed pin/recipes changed. The installed host remains
byte-identical (`a88917b6abcc2476589e8704d50844e28362bc53ec15b0317d6868ff9158006b`).
The coordinator's changed executable digest intentionally creates a new component
cache key. Component reproducibility is checked within that key; the embedded
build paths can change the artifact digest between keys.

The installed helper was measured on reserved CPU 2 with an empty `PATH`, the
same qualified seed and warm filesystem caches. These are three-sample medians
after one warmup per operation, excluding build-slot admission. Other builds
could run on unreserved CPUs. Peak RSS is GNU time's largest individual process,
including children, rather than their combined memory.

| Operation | Time | Peak RSS |
| --- | ---: | ---: |
| Seed verification | 0.368 s | 38.3 MiB |
| Unchanged component check/install | 0.354 s | 38.3 MiB |
| Forced component rebuild/install | 3.202 s | 121.1 MiB |

All repeated installs and forced rebuilds reproduced the installed component's
digest for the new key. The earlier baseline-CPU measurements above were taken
separately, so they are historical comparisons rather than paired samples.
Raw measurements, commands, the measurement script and the integrated build log
are retained locally under `.mylang-cache/coordinator-safe-qualification/`.

Guardian usage feedback for this follow-up was committed in `guardian-zig`
as `8f67e8a`.
