# Joined RC receiver correctness checkpoint — 2026-09-26

Frozen integration `a49441c1` passes the complete required gate and both actual
RC language sweeps. The Debug compiler SHA-256 is
`fc1f3fc16f5f3d1deecf3a7446ac1df27362e2d7dedf18e77a39ea9b7263361e`.

| Validation | Result |
|---|---|
| `zig build test --summary all` | 94/94 steps; 2,209 executed tests |
| `zig build test-qbe --summary all` | 51/51 steps; 437/437 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check` | 2/2 steps |
| Uncached actual RC QBE language sweep | 723/723 tests, 125 programs, zero dropped/unloaded |
| Uncached actual RC LLVM language sweep (`--release`) | 723/723 tests, 125 programs, zero dropped/unloaded |

Compressed logs, full sweep verdicts and structured source/compiler identity are
in `evidence/d9-rc-receivers-*`. The 22,442 main-gate exclusions are shard
exclusions. Both language sweeps use `--rc-runtime=stats --force --json`; no
`--qbe` option appears in the LLVM command.

This checkpoint adds the copied-codec held-view fix, transactional mutation of
held view mappings, and the physical receiver-anchor lifetime fix. Earlier
sorted receivers could outlive the compiler temporary owning their list. The
fix keeps that owner while the receiver alias is live, resolving all eight
text/range-key/sorting failures while retaining matrix temporary cleanup.
All ten new receiver/sort assertions are included in the full sweeps.

An independent actual LLVM O3/full LTO schematic build passes all three required
SVG hashes with balanced ownership. Its exact evidence is
`experiments/d9-rc-plain-projection-20260926/actual-llvm-a49441c1.json`.
The historical plain-projection `llvm.json` was mislabeled by a later `--qbe`
option; the explicit correction preserves the old file and withdraws its LLVM
claim. Other affected agent runners are separately corrected and rerun.

GC remains the default, and this is not WP-4 performance acceptance. Initial
matched instruction measurements on preceding checkpoint `39f75f3f` show large
regressions on binary trees, fannkuch and matrix multiplication. Profiling and
physical borrow/transfer optimizations are underway. The complete 43-program
per-backend instruction/RSS gate, RC default transition and WP-5 remain open.
Main and the pending devspeed branch remain unchanged; arenas are retained.
