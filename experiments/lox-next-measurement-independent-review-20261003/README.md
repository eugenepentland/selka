# Independent next-checkpoint measurement audit

The completed measurement records pass independent source, binary, coverage,
output, statistics, PMU-rate and paired-arithmetic checks. No actionable
provenance defect or false pass was found. This review runs no guests, tests,
builds, counters or timings and changes no root file. `review.json` is a
separate timestamped observation of the immutable records, not a replacement
for their original evidence.

The audit checked 1,300 complete rows: source smoke 208, source counters 208,
source timing 468, corrected compiler-write smoke 208 and compiler-write
counters 208. Each phase covers all 13 scripts on VM and tree, with exactly
the requested arm/round Cartesian product and no duplicates. Both smoke
phases contain eight arms and one round; source timing contains six arms
(including Rust and Go) and three rounds. All completed commands exited 0,
with post-run identities and progress logs matching their recorded hashes.

All candidate source directories match their full 37-file manifest and
26-module subset. Inputs exactly match the frozen benchmark scripts with only
the declared benchmark size substituted. All 127 reference-file identities
match in both private workspaces. All ten declared binaries in each manifest
match their hashes, including the unmeasured smoke references. Six source
build receipts (two guests each) match compiler, RC-runtime archive, codegen
metadata, source identities and measured executable bytes. LLVM uses
optimization 3/full LTO, while QBE uses its default optimization. All involved
compiler bundles use the same frozen QBE hash `99ad919d…`.

The baseline was originally built by compiler `9007d053…`. Its preserved
fixed-compiler replay proves the same complete source and byte-identical LLVM
and QBE guests with control compiler `d14a7040…`; this history is explicit in
the audit. The compiler-write guests use `4cbaeafa…` on exactly the unchanged
baseline or combined source. Four copied write-screen control binaries have
no local metadata sidecar; they inherit independently checked original
build/runtime metadata through exact executable identity. New write guests
and the source-screen copies have matching local sidecars.

Every stdout hash equals the frozen expected output. The producer checks raw
stdout equality before saving the hash; raw stdout archives are not retained
here. The producer retains at most 1,500 decoded stderr characters. All 1,300
accepted samples contain complete ASCII text shorter than that limit, either
empty text or the exact collector-statistics line. All 416 smoke statistics
records match across arms for each case. Both counter phases contain all four
events and rate 100 for every row: 1,664 rate checks in total. Raw per-sample
perf CSV is reused and not independently archived; the audit verifies retained
values/rates and the unchanged producer's parsing/checks.

I recomputed all case/round ratios independently, took each case's median of
paired ratios, then its engine's geometric mean. The recorded per-case
ratios, spreads and all engine totals match within float-rounding tolerance.
This reproduces source wall reductions of 3.406371% LLVM/3.028529% QBE on VM
and 0.330067%/0.854986% on tree. The small tree totals remain compatible with
measurement noise. Original one-round source and write counter screens are
diagnostics, not wall-time acceptance or statistical significance claims.
The write-only LLVM instruction totals remain unchanged within tiny run
variation; QBE instruction reductions are about 0.2–0.3%.

The original `smoke.command.json` remains a failed phase selection with
process status 2 and no measurement JSON. Corrected `write-screen-smoke.json`
uses phase `check` and its own command/log/receipt identities. Future write
timing or full-reference counter phases are explicitly absent/unrun in this
review. They require a later receipt; this review does not mark those cells
as passed or rewrite the current observation.

The unchanged producer, build launcher, measurement launcher and arithmetic
helpers match checkpoint `6e516f65`. The independent verifier is reproducible:

```bash
python3 experiments/lox-next-measurement-independent-review-20261003/audit.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-next-measurement-review-20261003/new-review.json
```

Run that command from this review worktree and choose a fresh output path. It
refuses to replace prior observations. The receipt identifies each manifest,
build, measurement, analysis, metadata relationship and unchanged helper. It
records the count and aggregate identity of 571 read inputs, all rehashed at
the end of the review. Root retains the complete underlying receipts and
owns final performance selection and consolidated Guardian feedback.
