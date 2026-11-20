# Random stream copy migration — 2026-09-26

The corrected mutable-reference liveness analysis exposed stale shared-stream
assertions in the standard random fixture and documentation. `Random` already
stores its state in a value record containing `list[u64]`. Under value
semantics, copying that record snapshots the stream position; subsequent
draws on either copy advance only that copy. The old assertions expected the
shared-list behavior retained only by `--legacy-sharing`.

This change migrates the fixture, executable example, both standard-library
guides, module comments, and `STANDARD-TIME-RANDOM-1`. It preserves the Random
layout, SplitMix64 implementation, pinned numeric vectors, range sampling,
and capability behavior. Public signature summaries now include the existing
`mut` parameters. An explicit legacy regression still checks the shared
stream in normal execution and GC stress.

The only embedded standard-module delta is three changed comment lines in
`src/stdlib/random.my`; its nonblank, noncomment source is byte-identical to
`178d43dc` (SHA-256
`adb63c19ad24046daef27d6de83c24c4082db331f90a67bad8292f7031fbace9`).
There are no compiler or runtime implementation changes. The separately
installed Debug compiler is `.tmp-random/install/bin/mylang`, SHA-256
`31bf2ae018160071c1395b00b7b056e3f1e9d0c0d81e578e3ef4e77f6786b0a0`.

## Why this is a migration, not a new generator defect

Controls use two frozen Debug compilers from `codex-d9-stage3f-prep`:

| Compiler | SHA-256 |
| --- | --- |
| Before corrected reference liveness, `.tmp-stage3f/install-indexed/bin/mylang` | `cdd9bed601bb0ade5705c5af8c962e7d10c55463128bba7fb57c915b271ac5cd` |
| Corrected default at `178d43dc`, `.tmp-stage3f/install-rootlive/bin/mylang` | `52ddd1337b4998b2a22184cac58af5ae4b0f4bc465dd449cfae3271c7451575d` |

The trace draws once from a generator, copies it, then draws from the copy,
the original, and the copy again. For seed 42, successive SplitMix64 words
A, B, C, D are `13679457532755275413`, `2949826092126892291`,
`5139283748462763858`, and `6349198060258255764`.

| Compiler/mode | Original trace | With an ordinary state read after the copy |
| --- | --- | --- |
| Old, value semantics | A B C D | A B B C |
| Corrected, value semantics | A B B C | A B B C |
| Old, legacy sharing | A B C D | A B C D |
| Corrected, legacy sharing | A B C D | A B C D |

The ordinary read changes no generator state. It merely kept the original
local live after the copy in the old compiler. Without that read, the old
missing `ref_local` use let the copy be treated as a last-use move, incorrectly
preserving sharing even though the original was subsequently passed as `mut`.
The corrected compiler consistently gives independent value snapshots.

The unchanged fixture/example return 0 on old value semantics and both
legacy compilers, but return 3/5 on corrected value semantics, matching the
failed default gate. The migrated fixture/example reverse the value-mode
result: old compiler returns 3/5 and corrected compiler returns 0. The fixture
therefore remains a meaningful regression for the future-mut-reference case;
it was not made green by accepting arbitrary output. Its third-word checks
also verify both snapshots continue independently from their copied position.

## Validation

- Focused Zig filter `standard time random`: 15/15 passed, including normal
  and explicit GC-stressed execution of both the value fixture and the legacy
  regression.
- Frozen corrected compiler: migrated fixture and example, plus the legacy
  regression, all pass explicit native GC stress on QBE Debug and LLVM
  ReleaseFast with optimization 3 and full LTO (six executions).
- Frozen old compiler: both migrated value programs fail at the intended
  snapshot assertion under explicit GC stress (two negative controls).
- Full isolated default gate: `test` 94/94 steps, 2,125 executed tests;
  `test-qbe` 51/51 steps, 428 tests; `test-qbe-build` 29/29;
  `fmt-check` 2/2. Both affected guides pass (3 time/random examples and 16
  standard-library examples). Guardian passes all 88 checks with no ratchet
  growth. No main checkout or shared preparation worktree was edited.

Full commands, compiler hashes, source text/hashes, and output are in
[the evidence JSON](evidence/d9-random-value-migration.json). Private scripts
and logs live under `d9-random-value-fix/.tmp-random/`:

```sh
scripts/build-slot.sh build python3 .tmp-random/check-controls.py
scripts/build-slot.sh build python3 .tmp-random/check-migration.py
flock ../.d9-closeout-gate.lock bash .tmp-random/gate.sh
```

The gate script uses a private on-disk `TMPDIR` and Zig cache, builds a Debug
compiler, and serializes `test`, `test-qbe`, `test-qbe-build`, and `fmt-check`.
The formal 43-workload measurement can retain frozen compiler `52ddd…`:
this migration changes comments, specifications, examples, and tests, with no
production algorithm or lowering change.
