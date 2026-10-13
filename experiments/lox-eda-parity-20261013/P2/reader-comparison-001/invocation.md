Prepared only; do not run without coordinator timing authorization and cleared relink builds.

Run from `/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p2`, source `/home/epentland/.config/mylang/dev-env.sh`, and export `MYLANG_SLOT_DIR=/home/epentland/.cache/mylang/slots`. Invoke chunks individually through shared admission:

```sh
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/reader-comparison-001/compare.py 1
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/reader-comparison-001/compare.py 2
scripts/build-slot.sh timing timeout 58 taskset -c 8 python3 experiments/lox-eda-parity-20261013/P2/reader-comparison-001/compare.py 3
```

Each chunk verifies compiler/binary/input hashes and CPU affinity, calibrates the pinned frozen Zig ReleaseFast binary with two warmups and three measured full fib runs, and sets each guest cutoff to `min(120, 3 * fresh Zig median)`. Guest warmups and measurements use identical full inputs and exact output/exit checks; no workload is reduced. Every chunk records two warmup pairs for C1/short and C1/scalar separately, then three globally alternating measured pairs per comparison. Across chunks, each comparison has nine measured pairs. C1 runs within each comparison so paired ratios use their corresponding baseline sample. Variant comparison order alternates too. Relative timeouts are recorded rather than reported as completed samples or parity.

The outer timeout applies to one chunk, not the complete experiment. Zig calibration and every completed guest sample are checkpointed to samples.json; an interrupted chunk can resume missing entries without discarding completed observations. No timing has been performed yet.
