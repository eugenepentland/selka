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
