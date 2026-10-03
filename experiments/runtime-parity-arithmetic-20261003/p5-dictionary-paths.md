P5 native dictionary/set evidence
=================================

`dictionary-path-proof.py` compares the runtime dictionary source at `2af5d62a`
with the candidate source. It compiles each runtime translation unit with the
bundled Zig C compiler at `-O3`, then uses the host linker to wrap two public
publication helpers. Zig's integrated linker does not support `--wrap`.
The JSON records every command and the source, binary and assembly hashes.
This is an untimed diagnostic, not a replacement benchmark workload.

The diagnostic uses 512 varied full-width integer keys, a 128-element unit set,
4096 duplicate set additions, and 4096 dictionary get/update pairs. Observed
generic ownership transactions change from 512 to zero for scalar insertion
and from 128 to zero for unit-set insertion. Duplicate set calls to
`myl_rc_native_retain_replace` change from 4096 to zero. The existing get/update
pair already bypasses both helpers and continues to do so. The checksum
1085440, 32 allocations and 1074576 charged bytes match in both arms.

The old fixed eight-byte replacement path remains a fixed register copy.
Successful insertion now records its retained key as found. A live scalar
absence may supply its hash and empty slot after reservation and callbacks;
growth, deletion, compaction, reindexing and optional-index allocation refusal
continue to invalidate the cache. This patch adds neither a second lookup
cache nor a fixture-specific table or bounded-key bitmap.

Validation:

- Six new C cases exercise varied-key growth/deletion/reindex/clear history,
  keys borrowed from relocated entry backing, aliased setdefault input/output,
  duplicate narrow-key unit sets, injected invalid regions, optional index and
  mandatory backing allocation refusal, generation overflow, queued callbacks
  that alter source bytes and the last probe, and custom owning native-plain
  shapes with saturated owner counts.
- The existing 47 production collection cases and 27 runtime fast-path cases
  pass, alongside the new six cases (15 selected Zig test blocks total).
- The standalone collection suite passes all 53 cases with undefined-behavior
  instrumentation.
- Three guest cases pass on QBE, stress GC and LLVM: scalar map snapshots and
  deletion/update histories, unit sets with plain structural keys, and distinct
  equal text/view keys across growth.

Static helper code is larger because it contains guarded fast paths; its
assembly is saved for review. This evidence proves omitted helper calls and
unchanged outcomes/accounting for these cases, and makes no timing or parity
claim. Full frozen benchmark timing remains with the shared harness.
