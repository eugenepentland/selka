# Reader diagnostic receipt

Diagnostic only; neither variant is adopted. The baseline is immutable C1. Short-only and scalar-IP-only remain separate arms and retain their previously qualified binaries/source manifests.

All three authorized CPU8 timing leases completed with exit 0, within their 58-second guest wrapper. Tickets: 1301 (PID 4190064, admission wait 502 s), 1309 (PID 276298, wait 80 s), 1314 (PID 279225, wait 70 s). Normal shared admission drained gates and earlier timing tickets; no external job was interrupted and no nested admission occurred.

Exact invocation for each CHUNK = 1, 2, 3, from the P2 worktree:

```bash
source /home/epentland/.config/mylang/dev-env.sh
export MYLANG_SLOT_DIR=/home/epentland/.cache/mylang/slots
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/reader-comparison-001/compare.py CHUNK
```

The script pins compiler, binaries, input hashes; samples.json preserves all raw measurements, output hashes, fresh Zig calibration, cutoff, pair order, and statuses. Each chunk used two warmup pairs per comparison and three measured pairs; overall nine alternating measured pairs per comparison. All 36 measured guest samples and 24 warmup guest samples completed with expected stdout, empty stderr, status 0; no censors. Zig calibration used two warmups and three measurements per chunk. No workload was shortened.

| Arm | Median paired variant/C1 | Faster pairs | Median variant/fresh Zig | Matching C1/fresh Zig |
|---|---:|---:|---:|---:|
| Short-only | 0.9929054367 | 8/9 | 2.2562433121 | 2.2721706445 |
| Scalar-IP-only | 0.9008297228 | 9/9 | 2.0379241884 | 2.2625419899 |

Short-only measured 0.71% lower paired wall time; scalar-IP-only measured 9.92% lower. This is one fib diagnostic, not an all-case performance claim. Fresh Zig medians varied materially: chunk1 0.9607160462 s, chunk2 0.6229554780 s, chunk3 0.6055418809 s. The corresponding guest cutoffs were 2.8821481385, 1.8688664341, 1.8166256428 s. Chunk1 first short comparison has a notably slow C1 sample. Every sample is retained; paired ratios provide more useful attribution than cross-chunk absolute medians. summary.json contains all nine individual paired ratios and normalized controls.

Prior source/qualification commits: short-only 8de2ab93a; scalar-only evidence/patch d8e943027. Original rejected direct-fetch and IP-only publication variants remain rejected. Scalar readers still publish full frames and preserve checked operand/error ordering. No combined arm was constructed or measured.
