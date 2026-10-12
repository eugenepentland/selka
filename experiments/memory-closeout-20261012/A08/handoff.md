# A08 — cache safety, compiler scaling, and component source migration

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Worktree: `/home/epentland/ai/canopy/mylang-memory-20261012-A08`.
Branch: `codex/memory-closeout-20261012-A08`.
Proposed commits: the A08 sequence contains tested comprehension/copy fixes,
component source migrations, bounded phi cleanup, and cache/scaling evidence.
No final candidate has been measured. The latest Support6 cache-plan qualification
resolves the earlier Support5 component blocker; historical failures remain intact.

Owned production files: `src/core/{lowering_cache,optimization_cache,emission_cache}.zig`,
`src/{semantic_store,semantic_copy}.zig`. The tuple staging addition now changes
the semantic cache wire version and validates persisted unpack storage.
Coordinator additionally reserved `src/sema_collections.zig`
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

## Support6 component qualification

Compiler source `5167c588be79dd43d21d5013c36db15110bf239b`, compiler SHA-256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`.
The exact installation boundary is recorded in `support6-compiler-identity.json`:
its libexec artifacts are staged historical components, so this is not an
installed-package qualification.

The real migrated cache-plan source builds with checked ownership and passes its
complete native protocol oracle: **560 counted executions**, comprising 523 normal
returns, 36 handled error returns, and one expected hard output-error trap.
Coverage includes 408 incremental cold/retained/warm batches, 102 independent
graph oracles, 100,000-node chains, malformed frames, and bounded-work rejection.
All observed RC events are zero. Every normal/handled-error return has zero managed
bytes live at exit and no resource leakcheck report. LLVM and symbols contain no
RC helper references. The hard trap remains in the denominator and is not used
to claim return-path cleanup.

The prior `close_group` ownership refusal is resolved by A07's scalar forwarding
fix, integrated into this compiler. Binary SHA-256:
`44cf164990de93468addf576e18af792ebcbd593f95748aa8059b388e1766f7f`.
`components-support6-cache_plan.json` retains exact commands, source hashes,
oracle identity and per-execution counts/statuses;
`support6-cache-plan-summary.json` adds the LLVM hash and concise conclusions.
The oracle's instrumented, nonexclusive elapsed times are correctness telemetry,
not compiler or runtime performance comparisons.

Test-index also passes all **128** counted protocol executions on this same
compiler: 106 normal returns, 21 handled errors, and one expected output-error
trap. Its binary SHA-256 is
`1734efefa37d2f17678dca227d51401c269a5028b4e6867bf91535989e79c28a`.
RC events, normal/error cleanup, and structural LLVM/symbol checks pass with the
same scope as cache-plan. `components-support6-test_index.json` contains the full
evidence; `support6-components-summary.json` records the paired **688-execution**
result and exact LLVM/source/compiler/oracle identities. This completes the
source/protocol prerequisite for a separate independently pinned owned component
build; it does not qualify the install's historical staged libexec artifacts.

The independent numeric-object cache probe passes **four builds** and every
structural/behavioral check. It seeds a private store with the preserved C0 object,
observes a distinct candidate object, verifies receipt/replay, and deliberately
replaces only the private candidate object with C0 bytes. The compiler repairs
those stale bytes before linking and retains the Unicode oracle
`ééé1.25ééé\n10 é\n`. The original shared C0 object remains byte-identical.
The candidate object is 409,160 bytes, SHA-256
`0fa3619e922e68e6418d487417de4b127281abe2618947cc023277dc7746c03c`;
its content-addressed filename uses digest
`bd0241774a18a2a0902c60c1feb7b476c478ec9b2282fc23a4704160bb555cc9`.
`support6-numeric-object/{results.json,object-audit.json}` retains exact source,
compiler, object, command, cache-state and behavioral evidence. This proves
candidate invalidation/repair, not old C0 execution of the Unicode fixture.

`pending-contract-reviews.md` separately records A07's borrowed-selection marker
review and A01's complete tuple-unpack cache review. They remain proposals under
implementation. A07 committed the bounded traversal and always-on marker validation
plus the central optimization-cache restoration guard as `ba273f041`. Its focused
tests and Guardian pass; A08 cached-corruption/replay qualification is still pending.

## Independent source-pinned compiler qualification

The independently provisioned ReleaseFast compiler from the exact Support6 source
`5167c588be79dd43d21d5013c36db15110bf239b` repeats all **688** counted component
protocol executions successfully. Compiler SHA-256 is
`29cfbd13390692757ce3add9cf61d8398eff283760d16cedb3c5b9addaa03e26`; its provisioning
receipt and source archive are pinned in
`owned-pin-support6-provisioning-snapshot.json`. The immutable historical seed was
not modified. This is a separate fresh build against the new compiler, not a
relabeling of the earlier Debug compiler's result.

`components-owned-pin-support6.json`, its compressed per-process counter/status
records, and `owned-pin-support6-summary.json` retain source, compiler, native
binary, LLVM and protocol-oracle identities. The 560 cache-plan and 128 test-index
runs pass with the same success/handled-error/hard-trap cohorts described above.
All observed RC events are zero, normal and handled returns have zero managed
exit-live bytes, and generated LLVM/linked symbols pass the RC audit. The two
counted binaries are byte-identical to their prior Support6 Debug-compiler outputs;
this is an observed artifact identity, not a compiler throughput claim.

A10 independently owns installed uninstrumented binaries and their package/native
qualification. Those binary hashes differ from these counted executables. The
provisioning snapshot records its creation-time state and is not amended to claim
later tests. This Support6 source is an intermediate qualification, not C1, a
default promotion, or legacy RC retirement. Final compiler/package changes require
fresh affected qualification.

## Complete-unpack persisted storage

The coordinator-authored optional `typed.Store.unpack` field and the semantic
wire change to **semantic-cache-v8** are included atomically. Both local and
portable shared typed-body keys inherit the new version. The codec/copy/hash
reflection already carries optional field-slot slices; copied scopes preserve
their function-local IDs.

Ordinary and specialization load/publication now reject metadata outside an
initialization, element stores, nonhidden or still-available original slots,
out-of-range RHS/local IDs, mismatched whole-value types, duplicate/aliased fields,
and visible field destinations. Validation allocates one lazy seen-slot array and
clears only actual bound fields: O(locals + total unpack fields), with no claimed
measured compile-time improvement.

Commit `3bbff3a61db91c4f8105749cefc1652159a2d162` includes the shared declaration
and v8 change atomically; Guardian passes all 88 checks. Four focused tests pass
in the existing semantic-store/copy modules, including
14 malformed metadata cases, a prior-version image with a valid checksum,
specialization publication/load, and independent relocated field-slot storage.
`tuple-cache/results.json` pins source hashes and commands; both the corrected
passing log and the initial fixture type-spelling compilation failure are kept.
These tests validate storage, not a complete guest program. A07 must additionally
validate exact tuple arity/types against the live catalog before Core unpacking;
A01's source producer and combined cold/warm/native tests remain dependencies.

The command is `scripts/build-slot.sh build python3 -B
experiments/memory-closeout-20261012/A08/component_qualify.py --compiler COMPILER
--compiler-revision 5167c588be79dd43d21d5013c36db15110bf239b --zig "$ZIG"
--work NEW --output NEW.json --components cache_plan --counted`. Final compiler
and installed component builds must consume or repeat this evidence explicitly.

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

## Managed sorting and list constructor follow-up

The coordinator reserved `src/prelude_builtins.zig` to A08 after the initial
comprehension commit. Unkeyed `sorted(values)` and `list(values)` now lower to
the existing explicit deep-copy operation instead of a generated full slice
whose append attempted to move borrowed managed children. The output remains
independent, and input storage stays borrowed. A07 reviewed the two replacements.
The existing keyed gather path is unchanged.

Two registered regressions cover bytes, empty/singleton lists, ascending/reverse
order, stable equal-key records, managed keys, nested children, input replacement,
and input destruction. `sort-focused.log` passes all five A08 tests using Debug
and verified release guest execution, leak checking and clean LLVM checks.
`sort-ordinary.log` passes all eight selected sorting tests, including existing
ordinary-mode alias/ordering, Unicode/bytes, NaN and signed-zero coverage.
`sort-ordinary-v2.log` repeats all eight successfully after the pending-Result
guards were added.

A01's expanded Result-list work requires implicit `list(...)` and `sorted(...)`
to reject pending elements with `E_RESULT_OPERATION`; these prelude guards are
included. A01 owns the Result-list negative integration cases because the C0
frontend in this worker still refuses Result-list construction itself.

Additional ReleaseFast baseline-only measurements now include accepted match
depth 96, field count 128, and recursive depth 16/64/128. Each passes all five
cold/warm/receipt/replay/edit cases. Match depth 128 remains an explicit parser
refusal. The schedule stopped before its unadmitted modules-16 timing lease
during the coordinator's exploratory gate; no active measurement was killed.
`c0-rf-modules-16.log` is only that cancelled queue, not timing evidence.

`c0-rf-memory-fields64` is a separate memory-only run using A09's 10 ms sampled
process-tree RSS wrapper. Cold peak summed RSS is 181,264,384 bytes; warm peak is
12,357,632 bytes; edited-source peak is 137,072,640 bytes. Sampling can miss short
peaks and summed process RSS double-counts shared pages. Replay finished before
the sampler observed its compiler and its sampled peak is invalid; GNU time's
individual-child high-water remains separate. These instrumented durations are
not compile timing measurements and no candidate comparison exists yet.

## Component field iteration and native protocol qualification

The additional cache-plan migration changes three field-row loops into captured-
length range loops with immediate scalar reads. Order, work accounting and failure
propagation are preserved without copying rows. Current checked ownership borrows
an entire record; reading one field through a live iterator while updating another
is an explicit unsupported boundary. The coordinator and A07 approved this local
source migration. `component-field-iteration-migration.json` records original and
migrated hashes; `component-migrations/incremental-before-field-iteration.my`
preserves the original source. Support3 source checking passes. Support4 still
refuses lowering at `incremental.my:241`, `closures.group_seen[group] = generation`,
with `E_ZERO_RC_LOWERING`; A07 owns the remaining production fix. Rerun the real
protocol after integration of the phi cleanup and its ownership-pass invocation.

`components-support4-test_index.json` passes the complete actual test-index
protocol under zero-RC using support4 source
`66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA-256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
The counted binary is
`28b9ed1b8007ef700013eee67ff45c35fcb2df39a58f43e1b24565b1d2b6a906`.
All 128 observed runs have zero RC events: 106 succeed, 21 return handled errors,
and one is the expected output-failure trap. All normal/error returns have zero
managed exit-live bytes and no handle leak diagnostic. The output trap is reported
separately, with observed exit-live zero. LLVM and linked symbols are RC-clean.
The oracle includes malformed requests, reply limits, missing input, output
failure, 100 independent random graphs and larger graph cases. Raw compressed
counters and per-run exit status/request hashes are retained in
`components-support4-test_index-counts/`. Instrumented oracle elapsed output is
incidental and is not a performance measurement. This interim result qualifies
that component/compiler pair, not the final installed package.

The immutable seed accepts the latest migrated source but now fails native linking
on this host (`component-field-iteration-seed.json`). Earlier seed protocol results
remain valid only for the earlier source/host state. `/etc/ld.so.cache` changed
while the session was running; `native-runtime-approval.json` records the exact
old/new hashes while all five reviewed runtime ELF files and resolved paths stayed
unchanged. This correctly disables native cache reuse and exposed an existing
uncached staging-file lifetime bug. A01 fixed the candidate driver in
`38dc781a897182ffbf1fff0906ec319a007a9154`; coordinator authorized this worker's
corresponding dependency cherry-pick `7005ad4a37c4ba3d1ef3927ebc81951bcb699714`.
The immutable C0 compiler and seed remain untouched. The coordinator owns reviewed
host closure refresh and the independent component compiler packaging decision.

C0 ReleaseFast modules16 and modules64 consequently fail all five build states
with missing native objects. `c0-native-link-failures.json` classifies all ten as
compiler failures rather than language refusals. No successful whole-build timing
ratio can be computed for those C0 cases. Raw failures and partial stage timings
are retained; remaining scaling work is paused pending the integrated candidate.

## Phi identity cleanup dependency

`5b4245c7d2bc7fa927dfe1101001e25c15908c16` adds a bounded iterative phi-only SCC
cleanup helper and four registered regressions. `phi-cleanup.md` and
`phi-cleanup-validation.json` give the contract, operation-count scaling through
16,384 phis, exact native test binary identity and raw logs. All four focused tests
pass, including an irreducible managed-value graph, native output, LLVM checks and
leak checks; Guardian passes 88 checks. A07 reviewed the algorithm. The helper
requires A07's separate ownership-pass invocation before it fixes production
lowering; the helper commit alone is not completion of that defect.

Final C1/C2/C3 cache ABI, application, component and performance qualification
remain pending. The support5 results below supersede the earlier unexecuted
cache-transition status, without qualifying the final candidate.


## Support5 cache and component checkpoint

Compiler source `a1f19edf255c8c0886731d8d7cce450d5f657720`, executable SHA-256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`, is an interim
integration compiler, not C1. Its `bin/mylang` lives under the coordinator's
`.tmp/memory-closeout/coordinator/support5-install/`. Its staged `libexec/` still
contains the explicitly labeled older support4 components; this checkpoint does
not qualify the installed package.

The following correctness runs pass, with exact arguments, source/compiler hashes,
stdout, reports and refusals in each `results.json`:

| Evidence directory | Cases | Result |
| --- | ---: | --- |
| `support5-fresh-cache` | 21 | RC/zero-RC/single-owner alternation, invalid edit, dependency change, relocation, generic/map replay pass |
| `support5-retained-cache` | 9 | Existing successful C0 generic/map caches invalidate; old RC-admitted invalid source refuses cold/warm; new receipts replay |
| `support5-result-cache` | 7 | C0 Result-list refusal retained; new nested Result program and replay pass; unhandled edits refuse cold/warm |
| `support5-render-cache` | 3 | Copied C0 partial-stage rendering cache invalidates; new checked native fixture and replay pass |

`support5-fresh-cache/mode-audit.json` separately verifies fresh lowering on each
first RC/zero-RC access, mode-specific reuse, distinct LLVM and absence of retain/
release names in zero-RC LLVM. The single-owner compatibility path still emits RC
and has separate zero-valued lowering-session counters; it is not zero-RC.
`--emit-llvm` exercises whole-module emission, so these rows do not claim unit-
emission-cache counter coverage. Registered direct stage-cache tests remain a
separate gate requirement.

The retained C0 run snapshots the complete disposable baseline tree before using
its original paths; its source files are restored after the invalid edit. Old
artifact payloads stay unchanged; only locks, retention timestamps and stage
sequence bookkeeping change. `support5-cache-transition-summary.json` and the
per-run provenance record these differences. Rendering baseline source/LLVM and
its original failed-build report are archived under `baseline-partial/`. C0
rendering had failed native linking after the host closure changed, so this is
lowering/LLVM transition evidence, not an old native executable/receipt test. The
copied A04 cache also contains earlier prototype entries, explicitly recorded in
its provenance. Peer source and cache files were not changed.

Run reproduction uses `qualify.py --compiler SUPPORT5 --source-revision SHA
--zig "$ZIG" --work NEW_WORK --output NEW_OUTPUT --admission held --timeout 120`
inside one bounded `scripts/build-slot.sh build` lease. The default invocation is
the fresh matrix; `--result-only` supplies the A01 Result fixture pair and oracle,
and `--render-only --retained-render-root ROOT` copies the preserved rendering
baseline. `retained_cache.py` uses `--baseline-work` and `--baseline-report` for
retained generic/map artifacts. All outputs must be fresh paths. These Debug
compiler executions were correctness runs; their elapsed/RSS telemetry does not
constitute an exclusive performance comparison.

`components-support5-test_index.json` repeats all 128 real protocol runs using a
freshly counted zero-RC component: binary SHA-256
`77d7aa713eec891a9d59935b05a3a4476a34c2d2eb12f7ccba87ad14e3e3650f`.
All 106 successful runs and 21 handled error returns pass, with zero observed RC,
zero managed exit-live bytes and no handle-leak diagnostic. The one expected
output-failure trap remains separately classified. LLVM and linked symbols are
RC-clean; compressed counters/statuses are retained. This component/compiler pair
is qualified; final packaging and final compiler requalification are pending.

`components-support5-cache_plan.json` still refuses native lowering with
`E_ZERO_RC_LOWERING` at `incremental.my:241`, despite source checking succeeding.
Support5 includes the phi SCC cleanup invocation; that fix does not resolve this
nested parent mutation. A07 owns the pending prepared-parent/writeback fix.
`cache-plan-support5-facts-v2.ir` and its `close_group` extract show a retain on
`%45` feeding a real loop-carried mutation phi, not an identity SCC. No broader
phi rewrite is justified. `dump-ir --facts` succeeds as diagnostic Core generation;
that does not establish guest/runtime admission. The first attempted dump used a
typo path and was cancelled before admission; its empty output is excluded from
compiler evidence, and the corrected `v2` files are authoritative.

The aggregate-provider pin cache regression was contributed to the coordinator
for atomic integration with that feature. Its archived draft SHA-256 is
`24fb4db15c2997c8838a99e1e3f08e7090f76801dd3fd01fc985541056e9afda`.
No duplicate test-only commit is needed from A08. The physical-type identity audit
is in `cache-audit.md`; executable results await that integration.

## Prepared next qualification inputs

`diagnostic-sources.json` freezes six modules/generics cases at sizes 16/64/128
(214 source files generated from the pinned A08 generator). A09 approved a bounded
exclusive `diagnostic_scaling.py` run, but the no-op admission barrier was cancelled
before admission when the coordinator prioritized Support6. No timing wrapper or
compiler ran. This future command measures `dump-ir --facts`, including parsing,
checking, eager ownership validation, Core lowering, release passes and IR/facts
formatting. It excludes LLVM/native compilation/linking and does not establish
runtime admission. The command has no per-stage timing report; one exploratory
sample per case is explicitly distinct from whole-build timing. C0 native failures
remain in the existing denominator. Final paired inputs must match this manifest.

`numeric_object_cache.py` and `numeric-abi.my` prepare the final A04 numeric-header
ABI check. `C0-number-object-provenance.json` pins the exact old object and its byte
range inside the immutable C0 compiler, independently confirmed by A03/A09. The
harness copies the object privately, checks the new Unicode formatting/length/index
oracle, requires a different candidate object, and verifies repair after stale old
bytes are placed at the candidate's disposable object path. These inputs only have
Python parse/help checks so far; they await the integrated numeric fix and must not
be counted as completed qualification. No historical shared artifact is mutated.


## Cache-plan blocker reduction

`cache-plan-reduction/README.md` and raw reports reduce the support5 refusal to
`small-one-loop.my`, a 19-line mutable-record/scalar-capture/loop fixture. The
ordinary native control returns the expected result; zero-RC build still refuses.
Constant/argument controls remove the retain, while retaining the captured scalar
field reproduces it even without a generation update or `try`. A07 independently
identified scalar field forwarding as the cause and owns the narrow production
correction. These diagnostic variants are not component migrations. Full component
protocol qualification remains required on the corrected integrated compiler.


## Borrowed-selection cache validation

The A08 cache regressions run from the coordinator-created integrated validation
branch based on `006e2355a`. They require A07's strict restoration guard and the
always-on marker CFG/dominance wrapper. Three new registered tests cover debug
and verified-release cold/warm LLVM equivalence, earlier physical type discovery,
a checksum-valid wrong-root debug artifact rejected and repaired by fresh work,
and a selected phi with swapped incoming predecessor operands. Persistent and
live bodies are compared through canonical identities, so valid string-slot
relocation does not become a false failure.

The predecessor corruption reproduced a missing check in the initial local marker
proof. A07's `2cb87014c` adds general IR verification once per marker-bearing
function at ownership and cache restoration boundaries. The first integrated run
then exposed 192 compiler scratch allocations retained when ownership passed a
backing allocator; A07's `522e66671` gives the verifier its own temporary arena.
Both intermediate failures are retained under `borrow-selection-cache/`. These
were compiler cache validation defects, not measured guest leaks or performance
changes. The focused filter also includes A07's existing 64-level nested selection
case; four selected tests now pass without leaks.

`borrowed_cache.py` prepares twelve native command checks; `tuple_cache.py`
prepares eleven generic tuple source checks using A01's frozen source SHA-256
`bace27f035ed485fc988e7516c70e6747096ac55d70542eaf934cdad1b138275`.
Both harnesses currently have Python help/parse checks only. Actual command runs
wait for the combined compiler, and tuple runs require the producer plus Core
contract validation. `final-qualification-plan.json` records exact remaining
scaling, cache and rollout work. No timing window was started during this batch.


## Typed selection wire format

The coordinator-authored `typed.Node.borrow_selection` tag is committed atomically
with **semantic-cache-v9**. Ordinary and specialized load/publication validate
both operand IDs against the stored body and require them to precede the selection
node. Structural logical-type checks reject scalar first operands, differing
fallback/result types, and differing text-selection operand/result types. A single
node scan performs this storage check without allocations. Exact canonical string
and Optional payload schemas require A04/A07's always-on live-catalog checks.

Eight focused tests pass: the four existing tuple storage/copy tests plus four new
selection tests. The new tests cover 27 malformed images, valid ordinary and
specialized publication/decode, a prior-v8 image with recomputed checksum, and
relocation of both operand NodeIds and source spans. Optional scalar payloads remain
structurally representable; the current frontend's selection policy is qualified
separately. `selection-store-v9/results.json` records scope, exact source hashes,
commands and logs. Complete producer/native cold/warm qualification still requires
the combined compiler. Prepared borrowed/tuple CLI harnesses now require observed
frontend and lowering reuse for their warm rows; matching output alone is not a
cache-hit claim.

## Prepared combined-source qualification and retirement

The source-generated typed selection cache suite is prepared in
`selection_cache.py`: sixteen release build/refusal rows, using an exact copy of
A04's self-contained min/max/Optional fixture plus four cache refusal inputs.
It requires observed frontend/lowering reuse, a whole-program receipt replay,
relocation, and earlier physical record discovery. It has only Python help/parse
validation; actual execution waits for the combined Support7 compiler. The
borrowed-dictionary and tuple generic suites remain twelve and eleven rows.

`retirement/retirement.patch` and its manifest record an **unapplied, unqualified
C3 draft**. It removes mode booleans from A08-owned cache/native boundaries and
requires explicit nonzero OWN1 provenance in persisted payloads and native
receipts, with coordinated scope changes. The linker checks every guest unit
before native tool discovery. Only syntax formatting has run; external ABI,
runtime and caller migrations are listed explicitly in `retirement/README.md`.
No active compiler behavior changed and no default/retirement milestone is claimed.
