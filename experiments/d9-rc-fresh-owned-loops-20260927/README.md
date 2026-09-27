# Fresh-owned RC loop evidence

See [the report](../../docs/audits/d9-rc-fresh-owned-loops-2026-09-27.md).
Run `python3 experiments/d9-rc-fresh-owned-loops-20260927/verify.py` to validate
archived receipts. Drivers run from the repository worktree root and name the
immutable before/after compiler prefixes in `identity.json`. They use build
slots, CPU10 and actual LLVM `--release`; counted guests are separate from timing.

`measurements.json.gz` contains all 24 build commands/identities, 36 raw perf
receipts and 12 counted runs. Guest assertions and paired failure controls are
separate archives. The final rebuild produced byte-identical native binaries;
`final-equivalence.json.gz` preserves full and `.text` hashes. Emitted manifests,
source controls and the tracked patch preserve the exact proof/input boundary.

The two rejected control-runner receipts preserve a Python variable-name error
and an incorrect expected overflow-code spelling; neither was a product failure.
The focused cache error is retained alongside the successful regenerated run.
