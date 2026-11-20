# Independent registered-shape release review

Frozen source: `c13be022aa4a5260d15b002c377de15c5abb4480`, reviewed in the
exclusive `codex-next-registered-release-review-20260930` worktree. The parent
runtime lane owns source integration and performance acceptance. This review
contains source and native behavioral evidence only; it makes no hardware,
corpus-performance or final-gate claim.

## Source finding

No actionable regression was found in the narrow patch. The production changes
are one collection caller, a private-header declaration/comment and extraction
of the old public release body. A programmatic comparison proves the new
`myl_rc_registered_edges_release` body is byte-identical to the old
`myl_rc_edges_release` body after removing its single shape registry lookup.
The public wrapper still checks heap/RC/traversal depth before its original
lookup, then delegates to the helper. The helper retains the same heap/depth,
nonnull-shape, extent-overflow and address checks and the complete old pointer,
shallow and generic O/H traversal, slot clearing and death order. The entire
`native_collections.c` file is equal to the baseline apart from the one
`rc_elements_release` call replacement. The observed pre-freeze production and
fixture hashes exactly match the committed freeze.

The helper's admitted internal input is a shape already held by a binding from
the same heap. An arbitrary raw shape passed directly to this private helper is
outside its internal contract. The public raw/source API retains its identity
lookup and refusal; no user-facing raw API is relaxed.

## Provenance and lifetime

Dynamic registration's `build_batch` copies the root and child shape graph and
rewrites both descriptor and child references into that retained batch. Dynamic
descriptor registration likewise resolves its shape before publication. Image
registration validates a closed immutable entry graph, copies mutable bindings
into a heap-owned batch, and borrows the image graph under its existing lifetime
contract. `index_commit` publishes canonical self identities. Registry growth
replaces index arrays, not the retained binding or graph allocations. Batches
are freed only during heap teardown; borrowed images remain immutable and alive
until their participating heaps are destroyed.

The changed collection caller obtains its binding through the existing type
lookup and already used that binding's registered shape for the preceding depth
test. Release-path queuing/draining is unchanged. `drain_one`, its registering
finalizer, its post-callback binding reacquisition and every other public/source
release caller remain untouched. This includes resource hooks and dynamic
child graphs. No new metadata field/cache, alias authority, unchecked counter or
static native ID is introduced.

## Independent execution

`growth-controls.c` includes the frozen 13-case owner fixture and adds two
independent cases. Each added case retains a depth-four H child graph, one
dynamic and one image-backed, while an unrelated dying object's finalizer
registers a new 64-deep graph and 64 descriptors. Assertions require actual
shape-map and binding-map growth and replacement of the traversal frame array.
They verify that the old binding/root/each child identity and O/H counts survive
that callback. The dynamic case erases the original root and source-field
metadata before the callback. Both then clear the original collection, require
both slots empty and H zero/O one, and finish with zero live objects, frames,
queued deaths and heap bytes.

The included owner fixture provides six dynamic/image O/H traversal cases, one
registering-finalizer case, and six expected SIGABRT refusals: public unknown
source identity, missing heap, missing address, extent overflow, active walker,
and null canonical shape. Assertions remain active with `-UNDEBUG`. Native
runtime code is compiled at `-O2 -DMYL_NATIVE_RC=1` with UBSan and
`-fno-sanitize-recover=all`.

The control is the unchanged `5535e5a3` runtime. A documented compile-only
macro maps the new private helper name in the candidate fixture to the old
public API; baseline production sources remain unchanged. Thus the same
behavioral fixture can execute on both implementations without inventing a
baseline helper. Each compiler/arm run is individually admitted through
`scripts/build-slot.sh build taskset -c 0`; the compile and native execution both
remain on CPU 0, outside the reserved timing pool. The receipt records exact
admission and compiler commands, versions, environment, source identities,
statuses, outputs and executable hashes. Per-arm receipts are the authority for
the completed results; the final summary requires all four arms to pass.

The initial invocation attempted a nonexistent standalone `clang` PATH command
and failed in the harness before C compilation. Both setup failures are retained
separately. The corrected Clang arm uses the installed pinned `zig cc` driver;
no production or fixture behavior changed. This setup failure is not classified
as a product/native test failure. Guardian was not exercised by the direct
native compiler runs.

## Completed result

All four admitted runs passed: Zig Clang/control, Zig Clang/candidate,
GCC/control and GCC/candidate each completed 15/15 cases with exact identical
stdout and empty stderr. That is 60 case executions: 36 positive executions
and 24 expected SIGABRT refusals, with zero UBSan diagnostics or native failures.
The candidate remains byte-identical to the frozen production source.

## Durable evidence

The self-contained raw archive is `evidence/wp-b3-registered-release-independent-20260930/raw.tar.gz`: 3,798,449 bytes, SHA256 `c728d5834f40a51908eb1d7c2ac949edf21b21dfc14274b53637dcfba3ff7282`, 150 raw members plus the manifest. Every member length and hash was independently verified after archive construction.

Summary receipt SHA256 `98825d0f855fbbbf0f361d9d6a955ca68e767e95fa6d6db14b982d2330eec631`; manifest SHA256 `48d9e4ecbb0ab8afe2d7c299d0b3dc47849ab8c569021d3fa779e2e427446de6`. The archive contains all four native executables, runtime/header snapshots for both arms, complete compiler commands/versions/admission identities, source/body proof, fixture, stdout/stderr and the two retained harness-only setup failures.

## Frame-address assertion refinement

After the original 60-case run, the independent fixture was tightened to save the old frame allocation address as `uintptr_t` before callback-driven replacement and compare integer addresses afterwards. The two added growth cases alone were then rerun under Zig Clang and GCC against both unchanged control and candidate: eight additional positive executions passed, with exact stdout and empty stderr. The earlier native archive and results remain immutable; these follow-up results are additive. No production or owner-fixture source changed.

Follow-up archive `evidence/wp-b3-registered-release-independent-20260930/followup.tar.gz`: 3,121,376 bytes, SHA256 `5d0a49ded9793e7c6bde678d5478a5e4a0cc842cb919365375cefc938026b216`, 54 raw members plus manifest, all member lengths/hashes verified. Growth receipt SHA256 `d96a6a8cddd8844d776746e1faffef2ef807e870b4bd18aedf3d28057e25d494`. It contains the revised fixture, four growth-only native executables and logs/commands, the read-only comparison inputs/verifier/receipt, and the full Guardian log/receipt.

## Read-only combined performance check

The integrator's `5347c9c0d1c63965b687561a11f458c1ecc3361c` comparison was independently recomputed from the original candidate, approved A5 and fresh pinned A5 JSON files. All 258 unique row records and comparison columns agree; all 58 candidate executable hashes and all ten measurement-receipt member hashes match. Dev and full each have 43/43 absolute RC/GC caps per backend and no instruction regression over 1% against either control. Smoke retains six movements over 1% and its existing absolute cap misses (37/43 LLVM, 39/43 QBE within 1.3), with zero new cap misses against either control. LLVM text_ops's three size-labelled instruction counts differ by 56. This verifier performs file/hash/arithmetic checks; it does not execute new hardware samples or rerun the 258 outputs. The root harness records all 258 matching outputs.

Performance-review receipt SHA256 `78b91d367c710fec8d4d481ed378246549bd82215ca7a5e987dc00700aea0e16`. No samples were selected or replaced: the comparison uses each original per-size observation. The final integration gate remains required.

## Guardian and source scope

A full whole-tree `guardian-check all . --full`, admitted through the gate slot, passed 88/88 checks before this docs-only commit. The only remaining additions are audit/evidence files; production, fixtures, SPEC and build wiring remain exactly at frozen c13. Guardian feedback is coordinated through the parent integrator to avoid concurrent feedback-log writers.
