# Joined gate receipts

`identity.json` records frozen source and Debug compiler hashes.
`gate-place-constructor.sh` contains the exact build/four-step gate command sequence;
it ran under `flock ../.d9-closeout-gate.lock`. The separate sweep script uses
`--force --rc-runtime=stats` on both actual backends, with `--release` selecting LLVM.
Both scripts check the frozen source identity. Logs and sweep JSON are compressed
without altering their contents.

See the [checkpoint report](../../docs/audits/d9-rc-place-constructor-gate-2026-09-26.md).
This is correctness evidence; performance acceptance remains separate.
