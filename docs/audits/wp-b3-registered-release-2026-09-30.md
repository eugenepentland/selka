# WP-B3 canonical collection release — 2026-09-30

The collection element walker now uses the canonical shape already retained by
its registered descriptor. The public source-shape API still validates the heap
and idle traversal, resolves the source identity, and rejects unknown shapes.
There are no metadata/cache fields, ABI version, counter, or admission changes.

Source is frozen at `c13be022aa4a5260d15b002c377de15c5abb4480`, from
`5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f`, in owned branch
`codex/next-runtime-registered-release-20260930`. Root composed this source with
its independent test repairs as `5347c9c0`; final integration and quantitative
acceptance are the integrator's responsibility.

## Implementation and authority

The new internal `myl_rc_registered_edges_release` is the exact old traversal
body after removal of its shape lookup and a signature rename. It retains heap,
walk-depth, nonnull-shape, extent multiplication, and storage address guards.
Pointer clearing, O/H drops, shallow/deep traversal and drain order are unchanged.
Only `native_collections.c:rc_elements_release` selects it; public slot/source
callers and `drain_one` finalizer/reacquisition/fallback remain unchanged.

Dynamic registration rewrites descriptors and child graphs into retained batches
(`native_rc_shapes.c:512–527`); descriptor registration resolves canonical shapes
(`:784`). Image admission validates descriptor/source correspondence and copies
mutable bindings while borrowing the immutable graph (`:685–716`). Identity
indexing adds canonical self-keys (`:175–176`); table/frame growth cannot move the
batch graph. Only heap teardown frees batches (`native_rc.c:95–103`). This removes
a redundant lookup, without introducing new registration authority.

## Executed validation

| Check | Actual result |
|---|---|
| New native UBSan primary suite | 13/13 |
| Existing native collections | 47/47 |
| Existing native contract | 25/25 |
| Existing native image | 15/15, including six host-allocation and six budget failure points |
| Tagged reachable Zig primary | 1 named + 12 unconditional unnamed imports = 13/13; named test executes all 13 C cases |
| Install/compiler, fmt, input coverage and focused steps | 28/28 steps |
| Whole-tree Guardian | 88/88; no waivers or baseline changes |
| Fresh actual text_ops guests | LLVM O3/full-LTO + QBE ReleaseFast, 2/2 exact frozen-control outputs |
| Source proof | Exact old walker minus lookup; exactly one trusted collection call changed |
| Production C O3 assembly | Both original walker branches call canonical helper; flat and other public paths retained |

The primary suite covers dynamic/image registered shapes, O/H depth 1/2/4,
repeated aliases, public source/canonical identity resolution, retained dynamic
copies after source overwrite, empty release, cleared slots, registering finalizer
metadata growth and subsequent reuse of the original binding. Six subprocesses
must abort on unknown public source, invalid heap, null nonempty storage,
overflowing extent, active traversal, or null canonical shape.

The compiler and QBE digests were unchanged at source freeze and final packaging:

- mylang: `0d02371c065d586a350ce1504dba44be1c2c51b17755c70c3629130571b80570`
- QBE: `93ec0b70f28762cbe5557d672c758fb621342399d4d59318b5b8c436a54ac0e4`

The install prefix and raw scratch remain frozen at
`.tmp/registered-release/{compiler,native,...}`. Every build/native/guest job used
a build slot, owned caches/TMPDIR and nonreserved CPUs; no hardware timing was
performed. The full compiler/backend/guest/performance gate belongs to root's
combined checkpoint, and is not claimed here.

## Address variability evidence and limits

All twelve predeclared ASLR probe trials completed with the exact frozen 5535
output. The first six sampled 100 initial release entries and saw the fixed image
key `0x100b618` with zero occupied misses. Six trials gated at the first text split
sampled a later heap key: five saw zero misses, one saw one miss for all 100 calls.
The copied ET_EXEC bytes were unchanged; live breakpoints were restored before
completion. All outcomes and the initial copy-mode setup error are retained.

The captured low profile has 399,999 public release calls with zero occupied
misses; its occupied-miss cycle has ten instructions. One extra miss for all calls
would cost 3,999,990 instructions, near root's observed 3,999,976 difference, but
the later key's full-run frequency was not measured. The exact 2–4M variability
mechanism remains unproven. `native_heap.c:pool_hits` is used by tracing `mark`,
not this RC release path. No instruction savings or corpus acceptance are claimed
until the integrator measures the frozen combined source.

## Durable evidence and feedback

`experiments/wp-b3-layout-20260929/registered-release/` contains a receipt,
106-member digest manifest, verified 3,521,823-byte compressed artifact bundle,
README and reproduction scripts. It includes raw logs, native/guest executables,
outputs, assembly, source snapshots and the complete ASLR experiment. Wrong
initial developer command spellings and the initial assembly-extraction assumption
are preserved separately; they are not counted as runtime or Guardian failures.

Guardian feedback was centrally appended and committed as
`3a466a498125575d8aedc4e27853b3f26a5b1bcc`. The entry records the executed primary
coverage, whole-tree 88 checks, input declarations and formatting, with combined
quantitative/final gate acceptance explicitly pending.
