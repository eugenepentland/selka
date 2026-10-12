The generator validates all 11 parity and 80 expanded case/size receipts against
frozen specs and independent expanded oracles. It rejects missing accepted
rounds, changed before/after identities, malformed output, counter receipt hash
or metric drift, duplicate rounds, and mismatched inventory. Runtime failures,
refusals, counted failures and calibration limits remain explicit.

Final generation after the parent freezes all 91 receipts and finishes timing:

```
python3 experiments/micro-ownership-20261012/tools/report.py \
  --input-root /home/epentland/ai/canopy/mylang-memory-20261012 \
  --output experiments/micro-ownership-20261012/report/final \
  --check-artifacts
```

Outputs are never overwritten. An incomplete run requires `--draft` and a private
`.tmp` output directory. Six tests in report/test_report.py check damaged receipt
rejection and matched-round bootstrap behavior. Production intervals use 5,000
joint round-index resamples with a deterministic per-comparison seed.

REPORT.md contains case comparisons, separate RSS/managed-count evidence,
calibration/refusals, and practical investigation priorities informed by the
prior full Lox/EDA application report. report.json retains raw status objects,
identities and bootstrap details; per-arm.csv includes each RC component,
uniqueness tests and destruction separately. history.json preserves older
source/tool/host/target policies and descriptive cross-date comparisons without
causal claims. Current LLVM-only support is explicit; historical QBE is retained
under its original identity.
