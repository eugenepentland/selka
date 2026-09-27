# Cumulative RC correctness gate attempt — 2026-09-26

Frozen source `dab80d845760ed3282322925203b8f0afb487d23` includes the arena
receiver-region correction, failed-file cleanup, live-view snapshot correction
and small-allocation fast path. The Debug install passed 19/19 with Guardian88.
Its compiler SHA-256 is
`d2a61a896346098f87b96367853562fc49fc88367b9c801fe0349840dc0c04b2`.

**This attempt did not pass the full gate.** The main suite passed 2,237 tests
and failed one existing ownership explanation expectation: a read-only list field
projected from a legacy class was classified `copy` instead of `borrow`.
The 22,761 other reported skips are shard exclusions. The separate QBE gate
passed 437/437 tests (51/51 steps), native-build passed 29/29 steps and formatting
passed 2/2. The compatibility correction is tracked separately; this receipt
does not claim its rerun has passed.

The same immutable compiler passed all 792 uncached counted-RC guest assertions
across 138 programs on each actual backend. Neither sweep cached, skipped,
dropped nor unloaded a test. LLVM used `--release`, selecting O3/full LTO.
These guest results do not erase the main-gate failure or establish performance
acceptance. The known RC semantic-history divergence also remains separate work.

[Raw logs, sweep JSON, commands and identities](../../experiments/d9-rc-correctness-gate-20260926/identity.json)
preserve the failed attempt alongside its successful checks. GC remains default.
