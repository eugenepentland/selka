# Frozen e926d1e1 correctness gate

All four gates pass, and both actual backend counted-RC sweeps pass 892
assertions across 153 programs. `identity.json` records exact source/compiler
identity and summaries. Compressed logs and complete sweep JSON preserve the
underlying receipts. `gate.sh` and `sweep.sh` are the exact launched scripts;
the gate was invoked under `flock ../.d9-closeout-gate.lock`.

The [audit](../../docs/audits/d9-rc-field-frame-span-gate-2026-09-27.md)
describes the joined changes, shard counts and remaining acceptance work.
This archive establishes correctness of the frozen checkpoint, not the final
Stage 4 performance gate or the still-pending ordinary RC default transition.
