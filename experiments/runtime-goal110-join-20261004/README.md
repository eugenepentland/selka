# B2 join candidate

This candidate changes only the native text join implementation and its existing
native method suite. It starts at b1b0500e (production inputs source-730a86e6),
separate from the unintegrated equality candidate. Frozen benchmark sources,
contracts and reference settings are unchanged.

The existing LLVM helper calls libc memcpy for every nonempty part and every
separator. Joining many short pieces repeatedly pays call overhead and reloads
separator/list metadata. The candidate copies pieces up to 16 bytes with bounded
first/last loads and stores, using memcpy for unaligned access; overlapping
endpoints cover every short byte. Larger pieces retain bulk memcpy. It computes
separator byte/scalar totals once with a checked multiply, checks every part
addition, and hoists immutable lengths/payload metadata. One output allocation,
its index sizing, roots across its safepoint, publication and refusal behavior
are retained.

The existing native text method suite now exercises 12,480 joins using exact
payload allocation sizes, lengths 0–257, separator widths 0–65, empty/one/three
parts, interior NULs, Unicode and views at offsets 1–7. It verifies every output
byte and scalar count, ASCII flags, one output allocation, and restored roots.
A separate managed fixture forces collection at allocation and then refuses the
output allocation while keeping every input live. Overflow probes verify both
separator multiplication and part addition refuse before allocation.

Five native suites were checked with ASan/UBSan, cc -O3, and warnings as errors:
methods, views, index, dictionary and RC collections. The first methods attempt
found a fixture error: native_list_new(3) reserves capacity with length zero,
so directly inserted pointers were invisible to GC until the fixture set
length to three. The four other suites passed, and a focused methods recheck
passed after correcting that fixture. join-native-tests.log retains both the
failure and correction; no runtime failure was hidden. A preliminary compilation
also caught the test's const-qualified owner free, corrected with an explicit
cast for the synthetic allocation.

Reproduce the final suites with private disk-backed TMPDIR:

```sh
TMPDIR="$PWD/.mylang-cache/goal110-join/tmp" scripts/build-slot.sh build python3 experiments/runtime-goal110-join-20261004/native-checks.py
```

The coordinator owns serialized timing and acceptance; no timing claim is made
by this implementation commit. join-before-helper.asm records the original
source-730a86e6 LLVM helper for comparison with the eventual guest.

The official Debug compiler build and all 24 expanded ReleaseFast guests passed.
`join-validation-receipt.json` binds source, test/log hashes, actual compiler
receipt, guest manifest, and unchanged text fixture/contract hashes. The LLVM
helper uses a multiply/overflow test for separator sizing (no variable divide),
and emits bounded inline loads/stores on the short paths; the remaining memcpy
calls are guarded by sizes above 16. Both text guests pass 120 exact independent
checksums, six runtime-control failures and two artifact/backend records.
Finite step/frame controls refuse with their existing no-accounting errors,
and MYLANG_MEMORY_LIMIT=1 triggers R_MEMORY_BUDGET.

The first compiler attempt refused a copied local Zig configure cache belonging
to the equality worktree; an empty private local cache resolved that without
changing any checks. The initial guest probe included SIZE=1, outside the frozen
SIZE>=2 contract. It refused with exit2, and valid nearby SIZE=2 replaced that
probe. Both rejected attempts are retained; neither changed benchmark inputs
or implementation. No timing or acceptance is claimed by this receipt.

The exploratory six-arm screen passes 720 exact qualifications and records
240 samples (four cases, both sizes, five rounds and one warmup on CPU 2).
LLVM/current-fastest join is 1.05204 small (227.69 ns versus Rust 216.43 ns)
and 1.00000 large (LLVM 12641.88 ns is fastest). The same-session paired
comparison uses verified source-730a86e6 Debug-host guests before and
source-5a60ef10 Debug-host guests after, preserving identical calibration:
LLVM join after/before is 0.56298 small and 0.55530 large; QBE is 0.94280
and 0.90415. All equality/search/bytes controls at both sizes are within
0.994–1.006 of their paired before arm. Per-sample host/cgroup snapshots
and all observations are retained. This is exploratory evidence; official
ReleaseFast compiler policy and normal confirmation remain pending.

Pieces above 16 bytes retain the same bulk memcpy after one size branch.
The native suite covers those boundaries through 257-byte pieces and 65-byte
separators, while metadata work decreases. No special long-piece performance
claim is made. Equality is unchanged and remains above the 1.10 goal in this
screen (LLVM/current-fastest 1.3576 small and 1.1718 large).

`join-timing-evidence.json` binds each compressed report to its raw report
hash and distinguishes the paired source-730 baseline from the runner's
supplemental original frozen winner. No acceptance claim or production
integration is made by this evidence commit.
