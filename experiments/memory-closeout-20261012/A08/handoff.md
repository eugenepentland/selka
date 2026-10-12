# A08 — cache safety, compiler scaling, and component source migration

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Worktree: `/home/epentland/ai/canopy/mylang-memory-20261012-A08`.
Branch: `codex/memory-closeout-20261012-A08`.
Proposed commits: this commit contains the tested comprehension metadata fix, component source migrations, and baseline qualification harness/evidence. No final candidate has been measured.

Owned production files: `src/core/{lowering_cache,optimization_cache,emission_cache}.zig`,
`src/{semantic_store,semantic_copy}.zig`. No production cache changes required by
source audit so far. Coordinator additionally reserved `src/sema_collections.zig`
for the concrete managed-comprehension metadata defect; a source element must
retain `LocalOrigin.iteration` after receiving its user-visible name. Coordinator additionally reserved
`selfhost/components/{test_index,cache_plan}/` source directories for minimal
migration that preserves protocols and compilation by the immutable RC seed.
No seed or packaging recipe changes belong to A08.

Frozen C0 compiler: A09 complete installation at
`../mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang`.
SHA-256: `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
Compiler mode: Debug, for correctness only. A09 froze a complete ReleaseFast C0 installation at
`../mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0-releasefast/bin/mylang`,
SHA-256 `78ac31605c7505c7cb330d41bdf2d3a232043e032f487e599f454b3bc6f2bd37`.
Matched final ReleaseFast candidate measurements remain pending; Debug harness
elapsed times are not throughput claims.

## Evidence

- `compiler-identity.log`: **passed**, registered runtime/compiler identity
  qualification (`scripts/build-slot.sh build python3 -B tests/compiler_identity_cache.py
  --zig "$ZIG"`). Frontend/Core/runtime edits change identity; test-only edits do
  not; sharing a Zig local cache across distinct worktrees refuses.
- `cache-audit.md`: source audit of compiler, runtime, mode, lowering, canonical
  fact, emission, native and whole-build identities. Whole-build replay is available;
  lazy/demand body restoration is disabled for ownership-checked compilation.
- `qualify.py`: reproducible CLI mode alternation, invalid edits, dependency edits,
  source relocation, whole-build replay, C0-to-candidate map ABI, and generated
  match/field/recursive/module/generic compilation families. Never writes historical
  experiments. Per-command build admission is default; `--admission held` requires
  one outer admission. `/usr/bin/timeout` is inside admission so queue wait cannot
  become a false compiler timeout.
- `c0-cache/`: superseded pilot, deliberately stopped between builds after one
  successful RC case. Its elapsed time includes queue wait and is not a measurement.
- `c0-cache-v2/`: **21/21 passed**. Three-mode isolation, source refusal after
  RC cache population, changed dependencies, relocation and ordinary/map whole
  replay were observed. Zero mode first access lowered 2/reused 0 functions;
  warm access lowered 0/reused 2. Whole replay reported `program=replayed`.
- `c0-scaling-smoke/`: **25/25 passed**, size-8 generated-source smoke over
  five families and cold/warm/receipt/replay/edit states. These are correctness
  checks; Debug elapsed times are not exclusive throughput measurements.

Measured compiler stage reports separate frontend (with nested/inclusive subphases),
lowering, optimization, emission, native compilation and linking. GNU time records
the maximum child process RSS, not a summed process-tree peak. Correctness harness
elapsed times are not exclusive timing measurements. Cold scaling cases use private,
empty guest caches; the shared Zig toolchain cache remains warm and is identified
as such. A09 owns final exclusive timing windows and machine-noise qualifications.

## Coordination and remaining work

- A10 command review: deferred canonical-fact reuse is ABI-safe after eager full
  source ownership validation. Raw keys include compiler identity and both modes;
  snapshot layout and canonical callee/body identities do too. Execution lowers
  separately. Requested warm zero-RC and shadow/reference equivalence coverage.
- A01 map helper signature meaning changes require old-artifact invalidation;
  `qualify.py --abi-only --candidate ...` exercises a managed parallel map with the
  same populated C0 caches and checks fresh candidate lowering.
- A07 owns the concrete component refusal: `with try fs.open(path, "rb") as file`
  is rejected because provider lookup does not unwrap propagation. Borrowed named
  `fs: Filesystem` is valid. Do not inline/remove `try` and change propagation.
- Coordinator must include existing 64-level nested owned-match hashing regression
  and three-mode cached/uncached oracle test in final focused/full verification.
- Final compiler, fresh scaling timings, default-command rerun, and C3 old-artifact
  test remain pending. Source namespace invalidation makes gratuitous semantic
  wire-format bumps unnecessary; final-artifact evidence is still required.

## Additional baseline evidence and concrete defects

- `c0-rf-{matches,fields}-*`: exclusive CPU 10 ReleaseFast measurements.
  Matches 16/64 and fields 16/64 passed every cold/warm/receipt/replay/edit phase.
  Matches 128 is an explicit parser refusal (`E_NESTING_LIMIT`, more than 256
  indentation levels); all five refusals remain in the denominator. These are
  baseline observations, with no candidate comparison or speedup claim.
- `c0-rf-scaling-schedule.log`: sequential per-family/size timing leases, separated
  by ordinary admission barriers. Stopped between leases after fields 64 at the
  coordinator's request to prioritize the component compiler defect. No compiler
  or active measurement was terminated.
- `component-seed-compatibility.json`: both real component mains build with the
  immutable seed, preserving protocol behavior. Test-index passed 19 malformed
  frames and 100 independent random graphs; cache-plan passed 408 incremental
  batches and 102 independent graph oracle cases, plus malformed/error paths.
  Native oracle elapsed output is incidental, not controlled timing evidence.
- `component-unit-rc-control.json`: both complete component test collections pass
  using C0 ordinary RC. The new retained-index independence regression is included.
- `component-scope-free-c0-v2.json`: disposable source copies remove filesystem
  acquisition only to expose later ownership diagnostics; these are source checks,
  **not component qualification**. Test-index passes, cache-plan refuses the scalar
  comprehension over `bytes[]` at `incremental.my:206` before and after source
  migrations. The frontend iteration-origin patch passes all three focused tests in `comprehension-focused-v2.log` (debug and verified release execution, direct cleanup, clean LLVM, and negative source checks).
- `reproducers/byte-repeat.my`, `byte-repeat-{c0,typed}.log`: C0 refuses the ordinary
  expression `b"a" * 32` with `E_SINGLE_OWNER_LOOP`; typed expansion appends the same
  owned bytes temporary inside a generated loop. Sent to A07/A04 for ownership-safe
  repetition lowering. This blocks component tests that use byte repetition.
- `component_qualify.py`: current component source/protocol qualification harness,
  plus explicit scratch-only scope-free diagnostic mode; records original source
  hashes independently of transformed scratch sources. Run inside outer admission.
- Superseded probes are retained as harness corrections: `component-modules-before`
  hit C0's library-check main requirement (A10 fix); `component-migration-probe`
  used invalid `assert try` positioning; v2 exposed real repetition refusal;
  `component-scope-free-c0` retained an unused capability, corrected in v2.

Source migration in cache-plan makes codec_v2's cursor scalar-only and passes the
input bytes as a borrowed parameter, reads adjacency directly, and explicitly
copies retained groups and returned topology. Tests explicitly copy borrowed
arguments and verify retained indexes survive input replacement. Both immutable
seed compilation and protocol behavior remain intact; zero-RC main qualification
awaits integrated A07 scope propagation and the comprehension fix. No installed
package or bootstrap RC-free claim is made.

The focused command was `scripts/build-slot.sh build "$ZIG" build test-core
-Dtest-filter='zero RC A08' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"`.
Its v2 run exited 0, with all three tests passing. The first run's sole failure
was an invalid fixture filter position, corrected without production changes.
A07 reviewed the iteration-origin fix. Coordinator supplied and authorized the
`src/core/root_test.zig` registration. The `src/sema_collections.zig` reservation
has now transferred to A01 for pending-result list work.

`components-support.json` uses interim source
`4c4c1663680fa4c290691867107eee24b504604d`, compiler SHA-256
`ac4ddfad53c1f096c91ba799810ca08b4713c36b62ff957ae326e24cf32407e5`.
This is not C1: test-index advances past scope checking but refuses the unaudited
`myl_core_stream_write_bytes` runtime helper; A05 audited the synchronous borrowed
payload path and sent the registry contract to A07. Cache-plan still refuses the
comprehension in that older binary. Real zero-RC component protocol qualification
remains pending an integrated compiler containing both fixes.
