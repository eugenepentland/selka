# Common candidate comparison

Common source commit1994cb76e266080d971be6f41e98fba5707234dd. Compiler0ba1684ea76140b07675bf01b39baafe8a7253ea675bfba8057186f1f9f16a3b; runtime429854488c74f3bc0a39aa0e0a8216e81bb21362bfad58e573a7fb1a96bc7994; countede35fb42e9a5fa64a49787c420634993fe3900664c11f0e1073f9d13c5b1ca51b. Source remains71f5e74e25f894e779c6248b9f52c144e9d53a8c482c0121e4249374dbe05754.

All six fresh cells use six arms, three warmups, fifteen paired measured rounds, three independent RSS observations and a separate counted binary. Each cell has its own CPU8 exclusive shared timing lease. Frozen source/flags/oracles and historical evidence remain unchanged; no full application benchmarks. All identity, checksum, order, ownership and exit-live checks passed. Installation hashes verified before/after. Harness6tests and reporter2tests pass.

The target is incomplete: both split cells and large CSV have every foreign CI upper bound below1. Small CSV/ZigFast straddles1; both JSON/Rust CIs exceed1. See target-assessment.json and REPORT.md for all foreign ratios/CIs. No flagged MAD/drift noise. CSVlarge and splitsmall calibration stopped near50ms (49.70/48.49ms), disclosed as limited. Absolute timings differ from prior sessions; no cross-session elapsed-speedup inference.

Managed allocations, cumulative tracked storage, managed peak, and process RSS are separate. Counted totals include setup and use the same cell iterations as timing. Raw libc dictionary metadata allocations and aligned-realloc temporary storage are not represented by managed counters. SPLIT uses an owned API with fragment elimination for immediate consumers and a managed offset table; small managed peak is7944B versus baseline7528B, a reserve tradeoff, while traffic and owner counts decrease. No zero-heap or raw allocator peak claim. Independent3-run processRSS is coarse and includes setup.

Corrected reporter representation text; its preceding exact source is retained as report_trials_second.py so historic reporter hashes remain available. The old JSON10 admission remains explicitly unmeasured; commonfinal is a fresh distinct run.
