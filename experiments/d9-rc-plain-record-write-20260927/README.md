# RC plain scalar record publication

This is isolated evidence for the reviewed eight-instruction compiler certificate;
no runtime or benchmark change is included. See the
[report](../../docs/audits/d9-rc-plain-record-write-2026-09-27.md) and
[design](../../docs/audits/d9-rc-plain-record-write-design-2026-09-27.md).

`identity.json` hashes the exact source overlay, raw compressed records, IL,
controls and receipts. The source base is the real merge `51b59806`, equivalent
to frozen integration `468bd8e5`. Before/after Debug compiler hashes and actual
backend manifests are retained. N4/N5 are diagnostics; N10 is the full unchanged
mandated Lox binary_trees script. The accepted GC files were only read.

`lox.json.gz` contains reduced builds, outputs, complete counters and median-three
instruction runs. `full.json.gz` contains interleaved before/after full N10 runs
of those exact binaries. The original perf CSV, event runtime and running fraction
are preserved; no scaled or partial run is accepted. `source-identity.json.gz`
checks the 25 copied Lox source files against the accepted workload.

`guests-final.json.gz` and `traps.json.gz` record actual QBE/LLVM GC-stress/RC
controls. `step-harness.json.gz` records the direct internal-ABI step probe;
this deliberately distinguishes its observable host-owned state from the public
scalar embedding contract. The immutable control and candidate preserve each
runtime's existing publication boundary. The initial failed equal-GC/RC assumption
and interrupted Guardian commit attempt are retained as separate logs, not
positive validation. The standalone `guardian-final.log` is the check-only run.

`vm-run-{before,after}.il.gz` preserves the94→58 loan-site change and18 exact
commit markers. Benchmark and control drivers are the executed recipes; their
original worktree paths identify immutable installations and scratch binaries.
The self-contained verifier needs only this archive:

```console
python3 experiments/d9-rc-plain-record-write-20260927/verify.py
```

`arena-diagnostic.json.gz` retains all eight identical preexisting arena snapshot
failures. `arena-control-original.my` is the added failing assertion, whose expected
result remains True; `arena-diagnostic.my` prints the individual observations.
The verifier checks historical failure attribution, not correctness of that output.
A separate correctness commit must add the permanent fixed regression. None of
these rows is counted among the twenty passing guest assertions.

The experiment does not establish full-corpus or RSS acceptance.
