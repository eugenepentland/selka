# A04 handoff

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (C0).
Branch: `codex/memory-closeout-20261012-A04`.

Coverage commit `d36558ac3e18ef1ba5547b67d9e14c7101998ab1` adds executable coverage and release inventory. Its required Guardian hook passed all 88 checks after correcting a duplicate primary spec tag to `spec-case`. It makes no
production allocation-policy or runtime change. The 80 public functions and five
public types in JSON, strings, path, base64, hex and byte_builder remain in scope;
none is silently excluded. Every function has direct fixture call coverage in
`inventory.json`.

Owned files: `src/stdlib/{json,strings,path,base64,hex,byte_builder}.my`,
`src/core/runtime/core_text.c`, associated fixtures and this A04 evidence.
New durable regression: `tests/lang/a04_memory_library_contracts.my` contains six
public tests and an executable main for zero-RC qualification before guest-test
mode support lands. The existing `NEW-CORE-ZERO-RC-LIBRARY-1` spec contract applies.
No shared-file edits were made. No helper whitelist additions were requested.

The supplemental tests retain outputs across dynamic input replacement and local
input destruction; exercise Unicode scalar boundaries, invalid UTF-8, codec
padding/errors, nested JSON, split/join/path operations, repeated calls and builder
snapshots. Separate fixtures prove borrowed view copies remain independent and
require exact diagnostics for owner replacement, mutation and local-owner escape.

## Executed evidence

Frozen compiler:
`/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0/bin/mylang`.
Compiler SHA-256:
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
Source commit is C0, rebuilt on this host by A09 with the pinned toolchain and
complete installed component layout.

- `mylang fmt tests/lang/a04_memory_library_contracts.my --check`: passed.
- `qualify.py --inventory`: passed, zero uncovered functions.
- C0 release pilot: ownership supplement and positive views passed, plus all three
  negative view cases. Both counted runs have zero emitted/runtime RC events and
  zero managed bytes live at exit; LLVM and symbol audits pass.
- Raw commands, compiler/source/binary/LLVM hashes and counters:
  `c0-pilot/results.json` and `c0-pilot/raw/`.
- C0 baseline qualification passed all 12 requested lanes and all three exact negative diagnostics. Every one of the eight fixtures runs in release; the six-test public ownership supplement also runs in unoptimized debug, verified release, optimized debug and release without facts. All counted runs have zero RC and zero managed exit-live bytes; LLVM/symbol audits pass. Raw evidence is in `c0/`, with compact totals in `c0-summary.json`. The coordinator approved this baseline scope because A04 makes no production change; the integrated candidate still requires the full 40-lane matrix.

The harness owns shared admission for each lane and reuses an authorized bounded outer build lease. The final ten baseline lanes used one lease after coordinator approval; individual observed compiles had been 0.17–1.21 seconds. It preserves validated completed lanes when resuming an interrupted phase, archives exact source inputs, and refuses to overwrite completed reports. It
imports historical helper functions without invoking their old report writers.
Build elapsed times are operational observations, not controlled performance
measurements. Managed counters are not RSS. No allocation reduction is claimed.

## Integration and remaining work

The coordinator should include the new guest test in normal auto-discovery and
rerun this matrix on the frozen integrated compiler, then on changed default and
retirement artifacts. C0 evidence cannot qualify a different compiler. The
coordinator owns the full registered gate and final Guardian check.

No production correctness failure was found in the complete C0 baseline library qualification. Active RC remains at
C0; this handoff does not claim rollout or retirement. `core_text.c` has two
legacy alternatives to remove only after stage approval: the uniqueness check in
`core_text_append_bytes` and the retained alias in `myl_core_text_encode`.
The selected zero-RC paths already copy static append sources and return an
independent bytes owner from text encoding. A07 has this retirement inventory.

## Additional guest migrations and repetition repair

The coordinator subsequently reserved 19 existing text/codec guest files to A04.
Commit `fe582983f` keeps all 133 public tests, exact originals and migration burden
in `migrations/`. Interim A10 support-compiler execution passes all 74 runnable
ordinary tests and 72 checked-ownership tests; two native-lowering refusals and
five source-refused files remain explicit. See `migrations/README.md` for owners
and reproducers. These sources need an integrated-compiler rerun.

The repetition reproducer required additional coordinator reservations:
`src/repetition.zig`, `src/sema_idioms.zig`, `src/core/build_values.zig` and
`src/core/runtime/core_values.c`. Repetition now remains a typed binary operation;
text/bytes use the existing borrowed-input, fresh-output runtime helper without a
gathered list. List repetition copies each managed child before moving it into the
output, as `PY-REPEAT-1` already requires. Named `*=` rebinds the independent result.
Empty lists bypass the count loop, and the octet size guard includes its terminator.
A07 approved the static ownership/cleanup review and owns the two explicit helper
contracts. The coordinator extended `SPEC.md`; A04 did not edit shared contracts.

The nested/wide list fixture passed counted execution in all five modes on A04's
compiler SHA256 `077aa182f221694ed29e1757a1a6f249bdd8196018804f8e459747c8c193dff8`.
Every lane reports zero RC, zero managed exit-live bytes, and clean LLVM/symbol
audits (`repetition/lists-01/`). This is a prototype source-diff artifact, not C1.
Full text/byte native qualification must consume A07's helper-contract additions;
earlier unaudited-helper refusals are retained in `repetition/initial-02.json`.
Nested-place `holder.values *= count` remains the existing `E_TYPE` boundary in
both modes; mutable parameter and field arguments retain positive coverage.
`repetition/ordinary-01.json` also passes the 17 existing Python expression guest
tests and the new complete fixture; both oversized nonempty repetition probes
trap `R_MEMORY_BUDGET` under the explicit 8 MiB ceiling. No runtime/RSS speedup or
allocation reduction is inferred from these correctness probes.

## Borrowed rendering and expanded fixture migration

Commit `b63b5ae80454708f05d91409dac4d31a0fd0efee` replaces rendering's temporary
owning box with a synchronous borrow of canonical stack storage. The coordinator
reserved `build_render.zig`/`emit_render.zig`; A07 authored and audited the shared
`emit_llvm.zig` hook and exact generated-helper contracts. The coordinator applied
SPEC/root registration. Five focused tests and Guardian's 88 checks passed. The
frozen prototype also passed all five native counted modes with zero RC/leaks and
clean LLVM/symbol audits; its ordinary/replay/control evidence is still running.
See `rendering/` for exact identities, source diff and raw results. The equivalent
A01 driver dependency is `1120bde6a` on this branch and `38dc781a` in integration;
do not merge both. No allocation/runtime saving is inferred from removing the box.

The coordinator also assigned 14 more `test/core` fixtures. All 42 public tests,
including intentional traps, and every existing value assertion are preserved.
`additional-migrations/` records original bytes/hashes, 43 extra copy calls, 43
added/removed lines, source checks and remaining reproducers. Twelve of fourteen
source checks pass; A07 owns the conditional-result and optional-loop failures.
Native qualification and registered exact diagnostic oracles remain required.
The 19 earlier guest sources now admit 18 files under support4; only borrowed
tuple destructuring remains source-blocked. `first_word` now explicitly copies a
borrowed generic string return, with source burden recorded separately.

## Completed support4 and renderer evidence

`repetition/support4-01/` passes ten counted lanes plus three required negative
cases on source `66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
The compiler includes approved helper contracts and byte-kind preservation.
Zero-RC counters, leak checks and structural LLVM/symbol audits pass throughout.
The source-commit argument is now mandatory in the repetition harness, keeping
external compiler identity distinct from the fixture checkout's revision.

`rendering/prototype-02/` completes five counted zero-RC modes and ordinary release.
The two replay checks fail their reuse requirement despite successful links, since
the changed host native tool closure is unqualified. The immutable C0 ordinary
control fails on the old native-object lifetime bug. These three failures remain
in the report and block a cache/baseline qualification claim; the coordinator and
A08 own the host approval and integrated rerun. No paired savings are claimed.
The complete public-export matrix and migrated guest executions are still running
against support4 and will be recorded separately. Their final-candidate rerun is
required after integration, default promotion and retirement as affected.

The full support4 public-export matrix is now complete: `support4-public/` records
40/40 native lanes and 3/3 exact negative diagnostics, with all 80 functions and
five public types retained. Counted execution has zero RC and zero managed exit
bytes; LLVM and linked-symbol audits pass. The source-matched twelve C0 baseline
lanes have unchanged allocation/reallocation/peak counters in
`c0-support4-counter-comparison.json`. This is preserved behavior, not an
allocation saving, RSS result or timing comparison. Support4 remains an interim
artifact; the final integrated compiler must consume the full matrix again.

The harness now batches each fixture's five modes under one build lease, validates
completed sources before admission when resuming, and checks the three negative
fixtures in one bounded lease. Completed native lanes were preserved across
queued-only checkpoints when adopting the coordinator's shared build budget.
No active compilation was interrupted during these support4 checkpoints.

The support4 migrated-guest run is also complete: all 128 admitted ordinary tests
pass; zero-RC passes 124, retains two native-lowering failures in
`rc_plain_update_paths.my` and two unsupported `myl_core_format_float` repr tests
in `python_text_surface.my` (A07 owns both). The separate five tests in source-refused
`tuples.my` keep the full 133-test / 19-file denominator visible. Raw test receipts,
forced execution commands and diagnostics are in `migrations/execution-support4.json`.
The helper file is exercised by its importing formatter fixture.

The resource audit adds `repetition/affine_resource.my`: both ordinary and
support4 checked source compilation refuse a list containing a record that owns
a generic resource with `E_LIST_ELEMENT`, before repetition could duplicate its
owner. A07 is adding registered negative coverage; future repetition harness runs
include this fourth negative separately from the completed three-negative report.

The support5 renderer rerun (`rendering/support5-01/`) now passes six native lanes
and both release/debug receipt/replay checks on source
`a1f19edf255c8c0886731d8d7cce450d5f657720`. The five counted ownership modes have
zero RC/leaks and clean structural audits. A08 separately verifies the transition
from preserved C0 partial rendering stages; C0's old failed native link remains an
explicit limitation. This does not qualify support5's historical installed RC
components or claim C1/default/retirement completion.

Numeric formatting ABI repair is committed as
`92edc7a99e6ca2c03928586bc66f6f563a93b3b2` after Guardian88.
The prebuilt Zig adapter now treats the first eight bytes as opaque and updates
ASCII metadata through the selected C layout. `formatting/abi-04/` records the
actual old/new objects under ordinary and checked ABIs: old checked fails the
Unicode metadata oracle, both ordinary controls and the repaired checked object
pass with no live managed blocks. Earlier harness attempts are retained and
classified in that README. Five counted guest modes plus ordinary pass; two
prototype cache replay requirements remain unqualified on the worker's old host
closure. A08 owns integrated numeric-object invalidation/replay. Exact audited
format_float/format_number/round_float contracts were authored by the coordinator
and reviewed by A07. The harness now pins its old source to C0 so committing the
repair does not silently turn the old control into the new implementation.

Slice lifetime repair is committed as `36e1afc91`, Guardian88. Four focused IR
tests pass, including preserved read-only fusion. New native regressions pass all
five modes; original s1_reads passes five checked modes plus ordinary. Five
s1_views checked lanes remain refused at an earlier sorted/list-copy path absent
from this older worker compiler, while its ordinary control passes. All refusals
remain in `slices/prototype-01/`; the full integrated rerun is required. The
production pass follows borrowed parents and bidirectional phi aliases, retaining
materialized snapshots across owner transfers or updates. Analysis remains
O(nodes + edges) per candidate query. A07 reviewed the alias and consuming-operand
contracts. No workaround changes either original S1 source.

The additional14 support5 native survey plus targeted corrected reruns now covers
12/14 cases; two S1 slice failures remain assigned to the optimizer repair. The
benchmark-provider failure was harness misuse of --link with an object instead of
C source, preserved in the initial results and corrected in a separate phase.
Two missed copies in the scalar comparison list are now explicit without changing
assertions; the source burden is 44 line pairs / 45 added copy calls. See
`additional-migrations/sources-support5.json` and both native result directories.
Borrowed tuple decomposition migrations await the integrated tuple.copy frontend
fix (A01 eccea1cc) and are not yet counted as qualified.

Support6 source5167c588 / compiler SHA256bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4
now completes two integrated follow-ups. Numeric formatting passes all six
native lanes and both release/debug receipt-replay checks; the stored object
SHA2560fa3619e922e68e6418d487417de4b127281abe2618947cc023277dc7746c03c
is recorded separately from the earlier prototype. A08 owns old-object repair.
Slice qualification passes all17 lanes, including both full original S1 fixtures
with their existing output assertions. All15 counted checked slice lanes are
RC0/live0 and structurally clean. See formatting/support6-01 and slices/support6-01.
These results remain intermediate; Support6 retains historical RC installed
components and is not the final C1/default/retirement artifact. The19-source
migration survey still refuses the optional tuple unpack at found.copy(); A01's
complete-unpack fix is excluded from Support6. Forced native tests for the
admitted subset are underway and will retain all19 sources/133 tests in evidence.
