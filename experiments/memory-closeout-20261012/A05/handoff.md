# A05 handoff (qualification in progress)

Base is `fbfcaa7a923186a8e773c3760f81c10aa345a432`; worker branch is
`codex/memory-closeout-20261012-A05`. No peer merges, pushes, default promotion,
legacy-RC deletion or Guardian feedback edits were performed.

## Current status after the first Support6 matrices

All 95 functions and 25 type/resource declarations have at least one labelled
intermediate counted fixture reference. This is not common-C1 qualification.
Support5 source `a1f19edf255c8c0886731d8d7cce450d5f657720` passes the four affected
storage/scoped-capability/setdefault cases in all five modes (20/20), with RC0,
managed exit-live0 and clean LLVM/symbol audits. The earlier scalar-copy,
dictionary-snapshot, network acquisition, returned-file and callable-authority
blockers described below are resolved in labelled interim evidence.

Support6 source `5167c588be79dd43d21d5013c36db15110bf239b`, compiler SHA256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`, passes
nested provider records and explicit managed-get copies in all five modes
(10/10 runs, RC0/live0 and clean LLVM/symbol audits). All ten aggregate negatives,
the ambiguous-get view and the simultaneous mutable-child negative refuse as
specified. Complete provider tuple unpack still refuses `E_SINGLE_OWNER_BORROW`;
mandatory capability-field tests still refuse `E_ZERO_RC_LOWERING` at their
constructor. Both remain qualification blockers. General noncopy managed-get
lowering remains a separate check-pass/build-refusal boundary, with no execution.

Remaining work is both aggregate fixes, the frozen common C1 suite, and affected
ordinary-command C2/C3 reruns. `boundaries/dictionary_get_readonly.my` keeps the
exact readonly check/build probe. Same-root simultaneous mutable child loans are
an intentional source refusal with an explicit-copy migration, not a compiler bug.

Commit `172629acf` carries the latest 20-run evidence. Commit `443478167` is the
isolated C2 documentation draft (26 executed examples and six expected refusals);
`d4d6c50f2` and `6a0516d8e` add the standard-library draft (23 executed examples).
These documentation commits must be held for default promotion. Runtime retirement patches remain prepared
and unapplied. Support5's legacy-built libexec is not owned-package qualification.
No release milestone is complete from A05 evidence alone.

## Scope and inventory

Owned remaining 13 standard modules and their corresponding fixtures, runtime
`core_dict.c`, `core_sort.c`, `core_io.c`, `core_host.c`, `core_durable.c`.
Coordinator additionally reserved `src/core/durable_test.zig` and the seven
resource/persistence guest fixtures listed in `migrations.json`. The export inventory contains all 120 public
 declarations (95 functions, 25 types); every function has at least one explicit
source reference in the fixture map. A source reference is not execution proof.
`exports.json` preserves C0 signatures/source hashes and records ownership
contracts; `inventory.md` gives module totals.

## Commits and proposed implementation

- `27737ea037cec92ee7b722c0d6f15354dd78e4df`: borrowed provider lifetime marker,
  a no-op lifetime use with no count/storage ownership. Requested and approved by
  coordinator/A07 for dependent-resource cleanup. Guardian 88 checks passed.
- `278538395`: library snapshot migrations, fixtures, inventory and C0/overlay
  evidence. Guardian 88 checks passed; source resource/scalar blockers remain.
- `a34f073ef`: registered owned durable native fixture. Guardian 88 checks passed.
  The focused registered test passed 1/1; raw log is retained in evidence.


`memo` now copies retained keys/values, returns independent hit values, and copies
borrowed error details. `persistent_memo` copies values retained in temporary
record/entry lists. `durable` copies persistent record fields and state snapshots,
and validates its borrowed output path in a helper without an intermediate copy.
These preserve existing independent-snapshot semantics under checked ownership;
no allocation reduction is claimed. Dynamic error-message functions allow
managed allocation through their derived ceiling because independent text can allocate;
the redundant explicit annotation was removed after the compiler flagged it.

Current pool/time/random and registered memo fixture aliases use explicit
`.copy()`. The pool mutation argument is bound before the mutable loan. Original
and migrated source hashes are recorded in `migrations.json`.

`durable_test.zig` adds an owned-ABI variant of the registered native fixture.
The ordinary fixture is retained. Owned fixture adaptation transfers acquired
lock pointers out of their result box, transfers root providers, and uses direct
destruction. The existing fault/SIGKILL/directory-ownership scenarios are preserved.

## Evidence recorded so far

C0 full installation was rebuilt by A09 on this host. Compiler:
`../mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang`, SHA256
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.

- `evidence/C0-check.json`: deterministic env/filesystem/file/clock/entropy source
  checks pass; memo borrowed message and network generic acquisition refuse.
- `evidence/C0-independent-check.json`: cache record/hash checker passes;
  denied network acquisition still refuses.
- `evidence/overlay-check.json`: migrated memo and cache record checker pass;
  durable scoped fallible lock is refused. Overlay is labelled explicitly and is
  not an integrated compiler qualification.
- `evidence/native-durable.json`: the owned native runtime passes all existing
  short/zero-write, fsync/uncertain-publication, path/listing, actual SIGKILL,
  concurrent-writer and lease cleanup checks. Runtime hash
  `d5c393bd561ad2ca363d983209b187d4d823e5f2de7e13312a7f6ce6f960f36e`, binary hash
  `a7a002f173899fdc1365ecbd838726592cc32c8ca7eb1352115a7f008df949e8`.
  Leak checking is clean and no legacy RC symbols occur. This is native evidence;
  it does not qualify source resource lifetimes.

Fresh release runs pass for all five remaining mandatory migrated standard
fixtures: sort, math, integer_extrema, pool, time_random. Expanded math, cache-record,
container replacement/pop/copy/set, deterministic filesystem/environment/clock/entropy,
and migrated managed-value memo samples also pass. Every counted passing run has
zero RC events, zero exit-live managed bytes and no legacy LLVM/symbol entries.
The exact binaries, source files, counters and compiler identities occur in
`evidence/*release*.json` and `evidence/C0-independent*.json`; raw counters are
preserved under `evidence/raw`. These are baseline/overlay results, not C1.

The library-only guest fixtures now have generated main adapters preserving their
public zero-argument test assertions; the two provider-argument tests receive
explicit deterministic stand-ins. `guest-overlay-check.json` retains all refusals.
An earlier direct-check probe in `guest-migration-C0.json` encountered E_MAIN on
library-only sources; it is not counted as an ownership defect.

Raw guest outputs/counters/LLVM/binaries are under `.tmp/memory-closeout/A05/`.
No historical reports are overwritten. Initial per-case admission runs were
canceled only while queued and resumed in bounded batches; canceled missing cases
are not counted as source failures. Final C1/mode qualification remains pending.

## Defects reported earlier in the run (historical snapshots)

- A07: `list(values.keys())` and `list(values.items())` compile through a borrowed
  frontend field extraction and refuse. `samples/containers.my` is the reproducer;
  A07 fixed this in the interim integrated compiler; full `containers.my` now
  passes. A02 later found a scalar-key synthetic-copy panic in its broader
  unchanged `rc_dictionary_views.my`; A07 owns that follow-up.
  `containers_core.my` independently exercises
  replacement/pop/copy/set cleanup without dropping the refused snapshot case.
- A07: `network.connect` reaches `acquire_resource` at standard network line 71
  and refuses. `samples/network.my` includes read/write/close and bounded local
  loopback provider cleanup; `network_denied.my` is the minimal deterministic
  acquisition failure. Source resource ownership must be handled before native
  helpers are admitted.
- A07: `durable.run` / `persistent_memo.call` lexical `with try lock_directory`
  needs provider-lifetime propagation and audited `myl_core_durable_access`
  admission. `samples/storage.my` reproduces. `runtime-contract-audit.md` records
  complete native contracts and limitations; no helper whitelist was added here.

- Coordinator: generic scalar `.copy()` inside a record constructor aborts the
  compiler at `sema_expressions.zig:1109`. `samples/scalar_copy.my` is the 10-line
  minimized reproducer; full stack is `evidence/scalar-copy-C0.stderr`. This is
  resolved in coordinator support2: scalar-copy and the full mandatory memo
  fixture pass all five modes (ten counted runs), zero RC/live bytes and clean
  structural checks. See `evidence/support2-memo.json`; final C1 remains pending.
- A07: compiler-generated byte repetition loop refuses `b"a" * 1` in the original
  application-cache hash oracle. `samples/byte_repeat.my` preserves the minimal
  case; confirmed refusal is in `evidence/byte-repeat-C0.json` and the original
  parent fixture refusal is in `evidence/guest-overlay-check.json`.
- A07/coordinator: capability-field aggregates and returned TextFile Results in
  `tests/lang/capability_fields.my` / `rc_contract_results.my` remain exact C0
  originals and explicit blockers. They were not weakened or rewritten away.

All owned library exports and these API failures remain in the release inventory.
Correctness refusals are blockers, not measured tradeoffs. Integrated C1 and its
five requested build modes remain required; any C2/C3 changes must be requalified.

## Reproduction

Source the shared development environment. `qualify.py --admit` owns admission
per compilation. For source-only probes, run the harness under one build slot
without `--admit`. `native_runtime.py` owns admission for its native compilation.

```bash
python3 -B experiments/memory-closeout-20261012/A05/qualify.py \
  --compiler "$COMPILER" --zig "$ZIG" --output "$OUTPUT" --admit \
  --modes release debug verified optimized-debug no-facts
python3 -B experiments/memory-closeout-20261012/A05/native_runtime.py \
  --zig "$ZIG" --output "$NATIVE_OUTPUT"
scripts/build-slot.sh build "$ZIG" build test-core \
  -Dtest-filter='zero RC durable native' -j"$MYLANG_DEV_JOBS" \
  --maxrss "$MYLANG_DEV_MAXRSS"
```

The complete coordinator verification and Guardian checks remain required on
final inputs. No final milestone is claimed by this in-progress handoff.

## Guest migration integration

The separate guest migration changes borrowed payload returns to explicit copies,
independent cache/pool/builder aliases to `.copy()`, and dependent capability
locals to lexical scopes. Application numeric formatting binds its temporary
before encoding. The simulated-clock shared-reading assertion uses an ordinary
borrowed helper (coordinator-approved), because capabilities are not copyable.
Every original test assertion is preserved; capability aggregate and returned-file
fixtures remain unchanged. `migrations.json` records C0/current hashes, copy counts
and changed-line counts for all seven assigned files and two stdlib fixtures.

The source-only generated-main batch still refuses at library/compiler blockers;
these source migrations are integration inputs, not guest pass claims.

## Interim integrated feedback

Coordinator support-install source `4c4c1663680fa4c290691867107eee24b504604d`,
compiler SHA256 `ac4ddfad53c1f096c91ba799810ca08b4713c36b62ff957ae326e24cf32407e5`,
is an interim compiler, not C1. Full container keys/items snapshot case passes
with zero RC/live bytes and clean LLVM/symbols. Source persistence now passes
lexical lock checks. Copying retained journal suffix elements explicitly preserves
snapshot semantics; the next block is the generated `function_digest` helper's
audit contract. Generic network resources still refuse.

`export-status.json` maps passing fixture references to public declarations while
keeping final qualification pending. Stream binary and buffer helpers have been
audited with A07; their executable regression is prepared and awaits the helper
contract. These open helper/source boundaries remain rollout blockers.

Dynamic error messages from memo/persistent_memo/durable survive replacement of
their error owner in all five requested build modes, with zero RC/live bytes and
clean structural checks (`evidence/support-errors.json`). This uses the interim
support compiler and labelled library overlay, not final C1.

Coordinator support2 identity: source `245e892f8518943ee44a0cc6009ab4b4fa6bca43`,
compiler SHA256 `3e9f7f2cd7e1ff7dc13b342dc812cb64b340cddc02b8b2b4b1ae8008cb203c7c`.
Full memo assertions and minimized scalar-copy now pass all five modes against
this compiler. No old failure was removed from the raw evidence.

## Retirement preparation requested by coordinator

`retirement/` contains exact unapplied runtime and native-fixture patches, source
hash manifests, applicability checks, and a passed scratch native durable preview.
No production runtime retirement was applied. The preview runtime removes the A05
counted branches/legacy sort entrypoint while preserving owned layouts, native
provider storage and direct drops. Its README states the A02/A07/header/emission,
fixture reservation, cache and installed-component dependencies. Actual Stage4
qualification remains mandatory after C2 approval.

The expanded public-value constructor/copy fixture passes release on support2
(`evidence/support2-public-values.json`): direct public Cache/Entry/Lookup, generator
state, duration/instant, persistent options/value and durable Step/Request/Report
construction all preserve snapshots. It calls no resource/digest helper and closes
previously indirect public-type coverage while those helpers are pending.

Coordinator support3 identity: source `0d17e4e130706639c0f49e78b60502bfb2151ebc`,
compiler SHA256 `7b911f91acefccc9dbfd0d1bcfee46e1ec5acc7f47a7ca5954481d44393c7de7`.
Ten cases, including storage, all network paths, binary stream output, byte
repetition and the original application/cache/resource migrations, now reach
native linking. All ten fail there because the driver removes an uncacheable
staged object before linking (`FileNotFound`). This is the independently reproduced
baseline driver defect owned by A01, not a language refusal or an executable pass.
`evidence/support3-native-link-failure.json` preserves every exact invocation,
generated source identity and diagnostic. Native retries await the integrated fix.

The harness now accepts `--ordinary-command` for later C2/C3 requalification; it
omits the experimental selector and records that choice. Existing invocations
remain explicit zero-RC requests. No default promotion or retirement is implied.

## Additional registered fixture migrations

The coordinator reserved thirteen more `test/core` and `test/fixtures` sources.
All thirteen pass source checking on support3; executable qualification awaits
the native driver fix and the final registered suite. `additional-migrations.json`
records each original C0 identity, migrated hash, line burden and explicit copies.
The checked commands and diagnostics are in `evidence/additional-support3-check.json`.

Dictionary snapshots and retained keys now copy explicitly. Capability narrowing
uses lexical `with` scopes, including recursive network handles and trapped cleanup.
The attenuation fixture delegates the read operation inside nested directory/read-only
scopes, so its provider remains live through cleanup. Application persistence keeps
its original assertions/output protocol and transfers the complete fresh Step value.

The coordinator explicitly approved replacing only `v_capability_arrays.files()`
with two named providers and the same writes/reads (`a`, `b`, `a`) and return value.
Its Stream/Host array, record and union tests remain unchanged. The exact original
C0 source is retained as `negative/capability_array.my`, and refuses with
`E_ZERO_RC_UNSUPPORTED`; owning capability arrays remain an explicit boundary.
This does not replace the separate capability-field method contract or claim that
owning capability aggregates are supported.

Support4 source `66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`, fixes native
object lifetime. Seven of ten release cases pass: useful network computation,
deterministic acquisition denial, error descriptions, exact binary stream writes,
byte repetition, application-cache assertions and migrated value-semantics stdlib.
Every passed case has zero RC events/exit-live bytes and clean LLVM/symbol checks.
Network read/write wrappers consume their Connection, and all three loopback
connections close; the binary stream fixture preserves the exact embedded-zero/
non-UTF8 output after input replacement. See `evidence/support4-libraries.json`.

Three failures remain in that ten-case denominator. Persistence returns a miss
where the fixture requires reuse: both generated callable-digest helpers return
empty text while native toolchain authority is unavailable, so no receipt is
created. The expected hit remains unchanged. Two capability fixtures expose the
same checker bug: `with fs.read_only()` falls through to the unscoped-capability
rejection because the scope switch omits `restrict_resource`; A07 owns the fix.
The public inventory now has 118/120 declarations with counted passing fixture
references; only `durable.run` and `persistent_memo.call` need their full storage
contracts. These counts mix labelled interim revisions, never final C1.

The direct Connection/Chunk/Failure fixture passes release on support4
(`evidence/support4-network-values.json`). Extracting the scalar error code consumes
the affine Failure carrier and drops its resource child; the loopback peer observes
EOF, with zero RC/live bytes and clean LLVM/symbols. The initial probe attempted a
second discard after that field access and correctly refused; its separate receipt
is retained. The original owning capability-array source also refuses as expected
through the qualification harness. Its ordinary-command option can rerun this
negative at C2/C3. Source refusals remain distinct from admitted guest execution.

The unchanged original `rc_contract_results.my` separately passes counted release
on support4 (`evidence/support4-file-results.json`), including managed success/error
postconditions and forwarded `Result[TextFile, str]` under `with try`. It has zero
RC events/managed exit-live bytes and clean LLVM/symbol checks. The earlier
returned-file blocker is resolved; capability-field aggregates remain separate.

The coordinator subsequently approved bounded provider ownership in ordinary
record/tuple fields, with whole-aggregate lifetime pinning and no capability
copies. A05 prepared the corresponding `capability_fields.my` migration: all
field-method and value assertions remain, dependent narrowing uses lexical scopes,
and an ordinary borrowed helper preserves the alias observation. Its three owned
payload returns copy explicitly. `migrations.json` records the new source pair;
qualification awaits the coordinator's aggregate-root implementation. Owning
capability arrays/lists/dictionaries/variants/boxes remain outside this contract.

The expanded managed-dictionary default contract is a separate blocking API:
`get(key, default).copy()` passes source checking but native lowering rejects
`E_ZERO_RC_LOWERING` on support4. Its fixture keeps eager fallback effects and
independent result storage after both possible roots are replaced. The matching
view invalidation reproducer currently passes checking, then refuses at lowering;
it was never executed. A07 owns explicit-copy branch lowering and ambiguous-borrow
source rejection. See `evidence/support4-dictionary-defaults.json` and
`evidence/support4-get-view.json`; this failure is not hidden by the public
standard-library export count, which excludes these builtin dictionary methods.

`aggregate-providers.md` and its fixtures are prepared qualification inputs for
the coordinator's bounded provider-root implementation. Three positives cover
existing capability-field methods, nested record providers and tuple providers;
six source-only negatives cover root invalidation, copying, partial moves,
aggregate-parameter resource origin, and the exact original capability array.
They have not yet qualified on that implementation. The harness records expected
refusals separately from guest execution.

The prepared aggregate positives now pass ordinary frontend syntax/type checks on
support4 (`evidence/aggregate-input-syntax.json`); this is not checked-ownership
qualification or execution. That preparation caught and corrected a shadowed
constructor name and replaced unsupported tuple indexing with complete tuple
unpack. `dictionary_setdefault.my` also passes that frontend check: it exercises
managed hit/miss copies, eager fallback effects, independent results after clear,
and five sizes with and without deleted entries. Native qualification awaits
A07's integrated setdefault lowering. The get-default view regression is wired
into the source-only harness with its intended `E_ZERO_RC_VIEW_ESCAPE` diagnostic.

Support5 source `a1f19edf255c8c0886731d8d7cce450d5f657720`, compiler SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`, passes
all 20 affected runs: persistence/durable storage, both named restricted-capability
guest fixtures and dictionary setdefault, each in release, unoptimized debug,
verified release, optimized debug and release without facts. Every admitted run
preserves its assertions, has zero emitted/executed RC and managed exit-live
bytes, and passes LLVM/symbol audits. Storage now verifies the required second-call
cache hit and reused journal chunks with restored callable digest authority.
Raw counters and all artifact/source/compiler hashes are retained under
`evidence/support5-*.json` and `evidence/raw/support5-*`.

All 95 public functions and 25 public type/resource declarations now have at least
one labelled intermediate counted fixture reference. `export-status.json` keeps
final common-C1 qualification pending. Aggregate-field providers and managed
get-default copies/views remain separate compiler work; installed Support5
`libexec` remains legacy bootstrap-built and is not owned-package qualification.

The coordinator reserved `docs/sets.md`, `docs/value-semantics.md` and
`docs/records-and-unions.md` for an isolated C2 ownership migration. The revised
pages remove current RC/COW claims and teach explicit independent copies, moves,
ordinary borrows and direct destruction. All executable fences pass actual
Support5 `doctest --experimental-zero-rc`: 26 run and six expected refusals, with
no skips or failures. `doc-migrations.json` pins original/proposed document and
executable-fence identities plus raw command reports. These documentation changes
must be promoted with C2, not mistaken for a changed default in this branch.

The existing simultaneous mutable-child example is an intentional conservative
whole-owner boundary, confirmed by the coordinator and A07. Its original source
is preserved as `negative/disjoint_mut_fields.my` and an expected refusal in the
page. The positive migration adds six explicit child copies and six ordered
writebacks while retaining the exact output. The callee only sees the independent
child arguments, never their enclosing record/list/dictionary; the manifest records
that justification and source burden. No disjoint-field inference or hidden copy
was added to the compiler.

The additional standard-library C2 draft executes all 23 runnable fences on the
same Support5 compiler. Four explicit copies preserve independent borrowed
returns/persistent payloads. Network acquisition has a lexical scope, and dynamic
decimal encoding uses a named temporary. The final prose describes A01's actual
parallel contract: one read-only callback argument, independently owned result,
non-Unit elements, mandatory joins, and explicit acknowledgement of Result lists.
Only scheduling wrappers have a bounded count; output and temporary chunk result
slots still scale with input length. `standard-library-doc-migration.json` retains
the initial failure, fixed passing receipts and exact source/fence hashes. These
changes remain held for C2 alongside the other three documentation pages.

Four additional aggregate-provider boundary probes preserve unsupported list,
dictionary, variant and recursive-box shapes. Their ordinary source baseline is
labelled separately from checked-ownership qualification. Lists/dictionaries and
recursive providers already refuse in the frontend; the variant admits ordinary
mode and must refuse checked ownership. General noncopy managed-get use has a
separate source/check-build probe under `boundaries/`, without an execution claim.

`qualify_exports.py --stage C1 --reports ... --output ...` combines explicit
candidate receipts only. It requires one compiler revision/hash, current input
hashes, five-mode execution references for each export, no overlay and the
correct command selector for C1 versus C2/C3. A partial Support5 smoke check stays
at 12/120 declarations; a mixed Support4/Support5 check refuses qualification
entirely. The older `summarize.py` continues to report labelled interim references.
This export report never substitutes for package, ABI, performance or full-gate
qualification. Support5 readonly managed-get source check passes but native build
refuses `E_ZERO_RC_LOWERING`; `evidence/support5-get-readonly.json` records both
phases and explicitly records no execution.

The first Support6 matrices contain ten executed positives across all five modes,
twelve expected source refusals, and two required positive build failures. The
failures remain in the denominator: A01 owns complete provider tuple unpack;
coordinator/A07 own named provider-record transfer into an enclosing record.
`capability_fields.my` retains all assertions and fails at its named Ports value
construction. Twelve separate compile-only probes isolate that direct five-field
construction/return and inline nesting compile, while named Ports-to-App transfer
does not. No source workaround or execution claim is applied to those probes.
The readonly managed-get probe still passes check and refuses build on Support6.
All reports preserve exact source/compiler hashes; passing runs retain raw counters.

The additional `pool_managed.my` public contract also passes all five Support6
modes with RC0/live0 and clean LLVM/symbol audits. Dynamic text and nested bytes
remain independent after seed destruction, pool replacement, slot removal/reuse,
and destruction of both original/copied pools. Handles exercise valid, removed
and regenerated slots. Release traffic is 119 allocations/7360 bytes, with managed
peak 2560 bytes; these are current whole-program counters, not timing or RSS.
Removing a pool slot still retains its old value storage until reuse or pool
destruction, as the existing generic slot representation requires. No retention
saving or production policy change is claimed. The coordinator received the C2
SPEC.md correction request for the stale shared-pool wording.

Exact coordinator-owned C2 replacement request (do not apply before promotion):

> [STANDARD-POOL-1] A standard pool hands out copyable generational handles into a reusable slot store. Removing a slot advances its generation so every earlier handle stops matching; a stale or out-of-range handle reports absence and no handle traps, and released slots are reused before the store grows. An assignment can move a pool owner; `.copy()` creates an independent pool, including independent managed element storage. A handle names a slot and a generation rather than a pool, so callers keep it with the appropriate pool value.

Coordinator requested a read-only audit of A10's original borrowed entry Context.
`borrowed-entry-context-audit.md` records the exact source/receipt and a proposed
parameter-only local borrowing contract, with matching source/Core/ABI/cache and
native authority/cleanup requirements. This is a design request to coordinator/A07,
not implemented support or an added helper whitelist. It preserves actual entry
providers and leaves ordinary owning provider records unchanged. No production
file was edited for that audit; the original checked-source refusal remains.

The borrowed-entry audit now has a concrete, tested proposal in
`borrowed-provider/README.md`. New helper/tests are reserved A05 files; eight
shared consumer changes are supplied as `borrowed-provider/shared-hooks.patch`
for coordinator application, with captured input hashes. A07 reviewed ownership,
ABI/home and inlining behavior; root approved the exact cost/noalloc contracts.
The final private overlay compiler SHA is
`0fdd1d8afa9e7e833d5508888b3da0065b89935dbee4d6bb3aafb47e7254bc24`.
Eight named focused tests (including corrupted persisted provider roots) pass;
wrapper, owned-provider regressions and exact entry authority all pass five-mode
native coverage; nine source negatives and seven cache/edit/relocation cases pass.
Raw receipts retain the preliminary new-fixture syntax error and its corrected
reruns. A07's verifier scratch leak was exposed and fixed; final compiler output
is clean. This is ready for integration review, not a qualified common C1 or
completed rollout/retirement. Test-root registration and the exact shared SPEC
request are included in the proposal README.

The final implementation is delivered in an evidence-only commit: apply
`borrowed-provider/new-files.patch`, `shared-hooks.patch` and
`registration.patch` together on integration; their exact bytes/hashes and the
full private-overlay reproduction delta are recorded. The first failed worker
production commit gate and corrected style findings remain in evidence. The
older worker tree intentionally has no orphaned new production source files;
root owns the complete registered implementation commit and final gate.
