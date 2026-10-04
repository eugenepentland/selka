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
