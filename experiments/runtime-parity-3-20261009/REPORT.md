# Runtime parity wave 3 — 2026-10-09

Status: M0 complete. U2, S2 and R are running in parallel; X preparation is in progress.

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
- Base ReleaseFast guest builds completed for Lox, EDA and all 45 parity programs; 45/45 parity outputs match `.expected`. The full repository gate passed 95/95 steps: 2,323 passing tests and 21,506 shard-routing skips (`M0/full-gate-receipt.json`). Conformance reproduced raw 1516/4/0 per mode and all 12 known PROBLEM lines, then passed the reviewed additive reference at 1547/0/0 per mode. The 64 core shards passed 600/600 tests. Frozen fuzz passed 9×50 with source and oracle identities unchanged (`M0/conformance-baseline.json` and `M0/fuzz50-base-41ed360fb-01/matrix.json`). Parity covers 153 arms of 28 benchmarks.
- Counterfactual attempt 1 is invalid: the old norc matcher changed zero LLVM lines after P1. `M0/counterfactual-v1-invalid.json` records the rejection; v2 changes 2,125 Lox count branches and measures again.
- Counting: 74 Lox cells (all 48 historical cases plus all 26 current full-size cells) and all 34 EDA designs match with counters on/off. Exact count files remain in owned cache; committed summaries retain every cell's totals and detailed hot sites. Parity (45/45) and rows (46/46) also match; the complete 199-cell receipt is M0/counting-gate.json.
- Rows timing: the retained pilot validates all 46 rows at both sizes against the inherited gate references. csv_aggregate is above Zig RS at both sizes (1.118× / 1.128×); this is a base gap. Three fresh 7-round batches additionally include all rebuilt Go and Zig RF arms; their strict method and thresholds are unchanged.
- Counterfactuals: all six Lox CPU-8 probes match. Both EDA reference_at-inlining probes match; EDA inline-norc and checks+norc abort and provide no valid bound. A diagnostic C-runtime stub removes the abort but changes EDA's answer, confirming that these probes cannot be used as speed evidence. All 30 valid arms across eight cells pass CPU-10 confirmation (9 rounds, 2 warmups); counterfactuals.md and u2-exits.json record the measured bounds. No production compiler or runtime source changed.
- Timing adapters: parity qualification now remains off reserved CPUs after availability preflight; all 153 completed builds are hashed and requalified before any timing. X's paired parity registry validates 45 base + 45 candidate + 108 reference arms interleaved in each round, with separate compiler caches.
- Current-base hot counters confirm read_constant at 3 retains and 3 releases per execution in invocation and method_call, and parse_list P6 at 444,833,472 copied bytes across all 34 EDA designs (`M0/hot-counts.md`). Remaining plain/counting guest builds are batched serially in one admitted build slot; 118 completed binaries are hash-verified on reuse.
- Remaining counting builds finished (68 new, 118 hash-verified retained); all 199 counting cells pass. The full 151-cell CPU-8 instruction baseline completed all three rounds with positive instruction/cycle samples and zero guest failures (M0/instructions-base.json.gz). compare_instructions.py will reject incomplete lane receipts and report every cell above 1.03×.
- Lox CPU-10 baseline completed: all 390 timed outputs match (26 cells × 5 arms × 3 rounds), with no noise-related waits. VM geomean 1.595× Zig RS; tree geomean 0.972×. Parity and rows are complete in the final M0 checkpoint below.
- validate_qualification.py checks later raw and additive receipts against the exact M0 totals and PROBLEM lines, all 64 core shards, leak/fact flags, and matching compiler hashes. The validator passes on the saved M0 receipts.
- EDA CPU-10 baseline completed: all 34 designs × 5 implementations × 10 timed rounds, plus warmup and RSS rounds, match their golden files. Mylang geomean 1.171× Zig RS.
- CPU-10 counterfactuals set U2 final/base limits: invocation 0.803193, fib 0.863836, method_call 0.816397, tree/equality 0.761930. All three complete row-reference timing batches are valid: 3,780 checked timing samples per batch and unchanged hashes for all 126 binaries. The median-of-within-batch-ratios base control geomean is 0.999347; no median exceeds 1.03. csv_aggregate at both sizes remains above Zig RS. A single sort_records/4096 batch was noisy despite identical binaries; one separate confirmation passed the original threshold and replaces none of the full batches.
- M0 final checkpoint: `f42bac79740d1c5363680025d1c2ac67c717b944`.
- U2, S2, R: launched from that checkpoint in locked, prune-kept worktrees `codex-rp3-u2`, `codex-rp3-s2`, and `codex-rp3-r`, under `/home/epentland/ai/canopy/mylang-worktrees/`. Their branches are `codex/rp3-u2`, `codex/rp3-s2`, and `codex/rp3-r`. Each received the exact M0 corpora manifest and the 186 base counting/plain guest binaries. Each lane owns its source changes and machine evidence; the coordinator writes the reports and decision log.
- X: pending lane hand-offs.

## M0 outcome

- Complete gap table: [M0/gap.md](M0/gap.md), covering all 45 parity arms, 26 Lox cells, 34 EDA designs and 92 row/size cells.
- Counterfactual table: [M0/counterfactuals.md](M0/counterfactuals.md), with four binding U2 cell targets in [M0/u2-exits.json](M0/u2-exits.json).
- Primary parity geomean: 0.741× Zig RS and 0.893× Zig RF. Lox VM: 1.595× Zig RS; tree: 0.972×. EDA: 1.171× Zig RS. These are baseline gaps, not achieved wave-3 exits.
- All 153 parity arms match output and have nine CPU-10 timing rounds. The native runner omits the reference-free recursive-tree arm; an additive adapter measures it with the same timing primitive. Its relative gate remains unavailable. The native report's five historical speed-threshold misses are retained separately from the wave-3 targets.
- Correctness: repository 95/95 steps; conformance exact raw baseline and additive 1547/0/0 in both modes; 64 core shards / 600 tests; fuzz 9×50; Lox 974/974 plus 65 port tests; EDA 310 tests plus 34 goldens; parity 45/45; counting 199/199. Full CPU-8 instruction coverage is 151/151, three rounds, with maximum repeat variation 0.0124%.
- Measurement corrections and invalid diagnostic attempts are documented in DECISIONS.md. No hard stop was reached. M0 changed no compiler, runtime, live benchmark, frozen oracle, or other worktree; the two private row syntax repairs are recorded above.
- Main remains 41ed360fb361c49938488ad111795bad8a726b73. Evidence is approximately 4.1 MB at the M0 checkpoint. Base compilers, owned guest binaries and exact count journals remain available for all lanes and X.

## Receipts

- Preflight: 402 GiB available on the workspace filesystem; external migrated Lox and EDA sources exist.
- Tools: Zig `0.17.0-dev.1683+5ceec001b`; admission through `scripts/build-slot.sh`.
- Completed M0 correctness and measurement claims are limited to the receipts listed above. Lane changes and final parity claims remain pending.
