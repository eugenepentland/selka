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
