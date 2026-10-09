# Runtime parity wave 3 — 2026-10-09

Status: M0 in progress. No lane has started.

Base: `main` `41ed360fb361c49938488ad111795bad8a726b73`. Integration branch: `codex/runtime-parity-3`.
Worktree: `/home/epentland/ai/canopy/mylang-worktrees/codex-runtime-parity-3` (locked, prune-keep).
Final head: pending X.

## Progress

- Launch: read the complete wave-3 plan, parity-plan §§2/6/8, PM report, F1/S1/F2/U1 reports, FU-X and FU-PORT reports.
- M0 setup: created an isolated worktree from current main; all existing user changes remain in the original checkout.
- Launch commit: `da7759b05`.
- M0 Debug compiler build: 9/9 steps, exit 0. Guardian: 88 checks pass.
- M0 formatting: exit 0; 818 live `.my` files checked, zero formatting failures; six formatter-gate tests pass.
- Copied corpora: 473 Lox files and 210 EDA files, excluding `.tmp/`, `results/` and Git metadata. Source hashes are in `M0/corpora-source-sha256.json`; only the owned Lox baseline compiler path in `bench.json` was retargeted.
- M0 ReleaseFast compiler build: 9/9 steps, exit 0; compiler SHA-256 and source hashes recorded in `M0/compiler-base.json`. Debug and ReleaseFast compiler sources equal the launch base.
- External base gates: Lox conformance 974/974; Lox port tests 65 passed, no cached results; EDA tests 310 passed, no cached results; EDA goldens 34/34 byte-identical. Initial external gates use release guest binaries built with the Debug base compiler; ReleaseFast-built guests are prepared separately for timing.
- Row build: all 46 old/new pairs compile after two private syntax-migration repairs (`M0/row-migration.patch`); no timed work was optimized. All 16 reference binaries rebuilt; 480 registry edge probes pass. All 46 rows match their registered references at sizes 64 and 4096 (`M0/rows-qualification.json`).
- Retargeted timing/counterfactual tools are prepared. Counting covers all 45 parity programs, plus Lox, EDA and rows. CPU-10 timing excludes all admitted builds.
- Base ReleaseFast guest builds completed for Lox, EDA and all 45 parity programs; 45/45 parity outputs match `.expected`. The repository full gate is running; `qualify_merge.py --shards 64` awaits its turn. All reference builds are ready. Parity timing prepares 153 arms of 28 benchmarks; counting builds and corrected CPU-8 counterfactuals continue through build slots. CPU-10 timing is queued behind exclusive admission. No valid timing result claimed yet.
- Counterfactual attempt 1 is invalid: the old norc matcher changed zero LLVM lines after P1. `M0/counterfactual-v1-invalid.json` records the rejection; v2 changes 2,125 Lox count branches and measures again.
- U2, S2, R: pending M0 exit; parallel worktrees will branch from M0's final commit.
- X: pending lane hand-offs.

## Receipts

- Preflight: 402 GiB available on the workspace filesystem; external migrated Lox and EDA sources exist.
- Tools: Zig `0.17.0-dev.1683+5ceec001b`; admission through `scripts/build-slot.sh`.
- No correctness or performance claims yet.
