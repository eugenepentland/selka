# A02 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Production commit: `ac4e945c5` (capacity arithmetic safety).
- Owned production files: `src/core/runtime/core_rt.c`, `core_bytes.c`.
- New regressions: `src/core/a02_capacity_test.zig`, `a02_capacity_fixture.c`.
- Shared edits: coordinator authored the `OWNED-CAPACITY-BOUNDS-1` SPEC bullet
  and `src/core/root_test.zig` import directly in this worktree and authorized
  inclusion in the production commit. No outstanding shared-file request.
- A07 reviewed the complete safety diff and approved it; no ownership, layout,
  helper-signature, or source-language contract changed.

The fix rejects negative capacities/sizes, overflow in element-byte products,
header or alignment addition, and signed list doubling before allocation or
copying. C0 reproducers and exact source fingerprints are committed. Zero-sized
elements, normal growth, snapshots, cleanup and memory-budget diagnostics are
covered.

Validation: `scripts/build-slot.sh build "$ZIG" build test-core
-Dtest-filter='A02 capacity' -j"$MYLANG_DEV_JOBS" --maxrss
"$MYLANG_DEV_MAXRSS"` exited 0; the one registered test passed all 22 native
scenarios across zero-RC and legacy control builds. The precommit whole-tree
Guardian gate passed all 88 checks. No Guardian FEEDBACK entry was written.
Exact test/compiler details: [safety-validation.json](safety-validation.json).

Policy decision: **measured tradeoff, retain the existing policy**. Start-one
reduces retained singleton capacity but increases five-element-list allocation
count by 2.5× and bytes by 2.125× without lowering peak; 1.5× growth increases
reallocations and can have larger final capacity. Existing reserve hints avoid
byte-buffer growth. All 28 native counted runs preserved checksums, used no RC,
and ended with no managed bytes live. See [README](README.md) and [raw evidence](raw/).

The runtime policy artifacts reconstruct exact C0 from Git and use the recorded
Zig hash, independent of the safety-patched working tree. Plain and counted
binaries have separate identities. Native timing samples are preliminary and
noisy and are not guest compiler qualification or a speedup claim. Actual
historical JSON guest reproduction is delegated to A03's
`owned-payload/json_nested` case (expected `121000`), avoiding duplicate builds.

Remaining integration responsibilities: rerun the registered safety test and
the complete verification coordinator on the integrated final compiler; A09
requalifies affected guest runtime/peak/RSS paths under the final compiler
identity. Remaining native timing/RSS cases are queued for A09's measurement
schedule after the smoke-build backlog. No unresolved correctness defect is
known in the A02 change. This evidence does not claim default promotion or
legacy-RC retirement.

## Managed list mutation follow-up

`insert`, `reverse`, indexed `pop`, and `remove` now operate on zero-RC lists of managed children. Insert appends the new owner and rotates it into place; indexed removal rotates the selected owner to the final slot and uses the existing pop transfer/destruction path. Reverse swaps slots. The consuming runtime helpers preserve the list header, capacity, layout descriptor and every child owner, with bounded byte scratch and no allocation or deep copies. Ordinary RC lowering is unchanged at this stage. A07 reviewed the complete helper and lowering path.

The registered `A02 list methods` test passes release, unoptimized debug, verified release, optimized debug, and release without facts. Every mode checks 100 nested-list, wide-record and recursive-union trials (output `500`), independent snapshots, clamped insertion, discarded pop, removed-child cleanup and four failure paths. Counted runs have zero exit-live bytes, clean RC symbols/LLVM, and exact indexed-pop error metadata for -3/2, 2/2 and 0/0. `remove` of a missing element reports `R_LIST_VALUE`. Exact compiler, source, binary and LLVM hashes and complete counter/trap results are in `raw/list-methods/`. No runtime-speed or RSS claim is made for this API completion.

The test uses a read-only equality helper for nested comparisons: direct nested-list equality followed by mutation currently produces an unrelated ownership phi retain. A07 received the full IR reproducer at `.tmp/memory-closeout/A02/list-methods-ir.txt`; this remains a separate support issue, not a passed general equality claim.

Reproduction: `scripts/build-slot.sh build "$ZIG" build test-core -Dtest-filter="A02 list methods" -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"`; durable native matrix: `scripts/build-slot.sh build python3 -B experiments/memory-closeout-20261012/A02/list_methods.py --compiler COMPILER --output NEW_DIRECTORY`. The integrated candidate must rerun this registered test. Coordinator authored SPEC/root registration and approved A07 contract edits in this worktree.

## Managed list slice and extension follow-up

Slices and extensions now make independent copies of managed children in checked ownership mode. Syntactic bounded slicing uses the existing explicit-copy operation for aggregate children; Core stepped slicing and extension use the existing deep-copy lowerer. Ordinary RC Core lowering is unchanged. No append/store behavior is relaxed. Self-extension reads the finite original prefix from the current owner after each growth. The output copy is required by the existing independent-value contract.

A07 approved the source and ownership review. The registered list test and separate native matrix pass in all five modes: nested bounded/stepped/empty slices, destination mutation with source preservation, source destruction, nested self-extension from 20 to 40 elements with outer reallocation, managed union payload copies that create control-flow, zero-size children, scalar duplicate removal, and all existing mutation/trap cases. Output remains `500`; admitted counted runs have no RC events or managed exit-live bytes, and LLVM/symbol audits pass. Exact source/compiler/artifact hashes and results are under `raw/list-copying/`. The registered test printed PASS and the build command exited 0; Zig additionally printed its test-runner command, preserved verbatim in the log.

Pending-result and resource slices remain rejected. This worker compiler refuses the negative fixtures before the newly explicit slice guard (`E_GENERIC_REQUIREMENT` for the pending generic list; `E_ZERO_RC_UNSUPPORTED` for resource-list parameters). These are recorded as earlier boundary refusals, not coverage of A01's subsequent pending-list admission. The integrated compiler must rerun them alongside A01's obligation regressions. No runtime-speed or RSS improvement is claimed.

## List-copy arithmetic follow-up

`myl_core_list_copy` now rejects negative lengths and `INT64_MAX` before evaluating `len + 1`. The maximum length is testable with a zero-sized element payload. Before the fix, signed-overflow trap instrumentation terminates scenario 11 with SIGILL; the malformed negative-length scenario 12 is incorrectly admitted. After the fix both report the existing fatal out-of-memory message and status 1. All 26 registered capacity scenarios pass across owned and ordinary control runtimes. A07 approved the guard.

`raw/list-copy-overflow/` records exact source/native hashes and logs. The first UBSan link attempt lacked the handler runtime, so the successful reproduction uses compiler-supported trap instrumentation explicitly; no full UBSan runtime availability is claimed. The new guard preserves the existing capacity policy and is separate from the unapplied Stage 4 preview.
