# Uncached native unit lifetime repair

The native driver deleted each pending object's staging file when `unitObjects`
returned. With an approved cacheable tool, publication had already renamed the
partial into the store, so this cleanup was harmless. An unproved tool keeps its
objects in the request's private staging directory; deleting these files before
linking caused `failed to open object .../native-link-.../<key>.o: FileNotFound`.

The repair only removes per-unit cached partials at that boundary. Uncached files
survive the linker and remain owned by `linkWithScratch`'s existing staging-tree
cleanup, on both success and failure. Tool approval rules and trust digests are
unchanged.

The new multiunit regression uses an explicitly unproved test tool that checks
that every object exists when linking. Two successful links each compile both
units without reuse, and a failing link also leaves no private staging directory.
The existing unproved-tool cleanup regression also passes.

Focused command: `scripts/build-slot.sh build "$ZIG" build test-core
-Dtest-filter='A01' -Dtest-filter='linkNative refuses unproved'
-Dtest-filter='an unchanged build replays' -j4 --maxrss 8589934592`.
Raw output: `focused.log`. Four tests passed, including both driver lifetime tests
and the current Result-list semantic/Core checks. The ordinary cache replay test
failed its expected-replay assertion after native builds succeeded: this host's
current tool closure is not approved for caching. A08/coordinator owns the
remaining platform-approval investigation. The pinned Zig executable hash still
matches `approved_zig`; no trust exception was introduced to force reuse.

The same FileNotFound error was observed with immutable C0 in A08's modules-16
workload and with A05 API fixtures, independently of Result-list changes. C0
failures remain failures; the frozen baseline is not relabeled with this fix.

After extracting cleanup into a small helper to retain the driver's existing
complexity bound, both native fallback tests passed again (2/2), raw output
`final-focused.log`. A08 identified the cache-approval mismatch precisely:
`/etc/ld.so.cache` differs from the platform's reviewed digest while all five
reviewed runtime libraries and loaders match. See A08/native-runtime-approval.json.
