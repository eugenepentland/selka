# Compact RC journal checkpoint — 2026-09-26

Frozen source `7998e84cf7dfd3b74f0f2ff596714034dfc4b4fa` joins compact journals
with the preceding arena/file fixes, allocator optimization, disjoint transfers
and compatibility correction. All required gates pass:

| Check | Result |
|---|---|
| Debug install | 19/19 steps, Guardian88 |
| Main gate | 94/94 steps, 2,241 executed tests passed |
| QBE gate | 51/51 steps, 437/437 tests passed |
| Native-build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Counted RC QBE sweep | 795/795 assertions, 139 programs |
| Counted RC LLVM sweep | 795/795 assertions, 139 programs |

Neither RC sweep cached, skipped, dropped nor unloaded a test. LLVM used
`--release` (actual O3/full LTO). The main suite's 22,794 reported skips are shard
exclusions. Exact compiler SHA-256:
`bacbf1e4794adcc770510414f81bf878c0b418a09b170cf30b8f6d6abaf7bacf`.
[Complete commands, logs and sweep JSON](../../experiments/d9-rc-compact-gate-20260926/identity.json)
are retained with this source identity.

WP-4 remains incomplete. The independent history audit has seven negative RC
cases in a new private 13-case GC-validated matrix, including a fresh dictionary
stored into an arena list. A boxed Option field mutation also loses its write in
this source and is being corrected separately. Those newly discovered cases are
not part of the 795-test sweep and are not obscured by its green result.
Private ABI3 semantic publication and compiler-loan work, the remaining large
instruction/RSS gap, and WP-5 implementation are still open. GC remains default.
