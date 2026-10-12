# A04 handoff

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (C0).
Branch: `codex/memory-closeout-20261012-A04`.

The first commit adds executable coverage and release inventory. It makes no
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
- Full eight-fixture, five-mode C0 matrix is running; `c0/` records partial output.
  It is not yet claimed as passed in this initial handoff.

The harness owns shared admission for each lane, writes raw evidence only under
the specified phase directory, and refuses to overwrite existing results. It
imports historical helper functions without invoking their old report writers.
Build elapsed times are operational observations, not controlled performance
measurements. Managed counters are not RSS. No allocation reduction is claimed.

## Integration and remaining work

The coordinator should include the new guest test in normal auto-discovery and
rerun this matrix on the frozen integrated compiler, then on changed default and
retirement artifacts. C0 evidence cannot qualify a different compiler. The
coordinator owns the full registered gate and final Guardian check.

No production correctness failure was found in the pilot. Active RC remains at
C0; this handoff does not claim rollout or retirement. `core_text.c` has two
legacy alternatives to remove only after stage approval: the uniqueness check in
`core_text_append_bytes` and the retained alias in `myl_core_text_encode`.
The selected zero-RC paths already copy static append sources and return an
independent bytes owner from text encoding. A07 has this retirement inventory.
