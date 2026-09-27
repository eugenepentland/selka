# Immutable-byte loop evidence

Run `python3 experiments/d9-rc-immutable-byte-loop-20260927/verify.py --live`
from the preserved worktree. Without `--live`, verification uses only archived
receipts, source snapshots and raw samples; it performs no new timing.

The report is `docs/audits/d9-rc-immutable-byte-loop-2026-09-27.md`. The measured
prototype and final admission-budget correction are both retained. Final emission
and all four benchmark binaries are identical to those measured. The accepted GC
reference names exact samples and keeps its baseline untouched.

`refusal-probe.patch` is diagnostic only: it disables the new elision so the
unchanged generated-text veto must discard speculative output. The production
source was restored before final build. The standalone guard probe runs the exact
emitted QBE guard against zero/nonzero words without constructing forged guest
owners. The invalid-fixture, wrong-label and initial failed-build receipts are
historical diagnostics, not accepted test results.

Drivers retain their original `.tmp-bytes` paths and commands. Re-running them
requires the named immutable compilers and source tree; verification does not.
Only CPU10 instructions/RSS samples are performance evidence. Diagnostic probe
binaries are excluded from performance comparison.
