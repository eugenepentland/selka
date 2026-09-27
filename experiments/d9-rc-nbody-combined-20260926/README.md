# Full-workload nbody comparison

`results.json.gz` contains all exact commands, native manifests, binary hashes,
three interleaved GC/RC perf samples per backend and balanced RC counter records.
`measure.py` is the exact driver, retaining original worktree paths. The GC binary
hashes and original five-million-step source are checked before measurement.
`nbody.my` and `expected.stdout` are exact copies of those authoritative inputs.

`profile-*` files preserve supplemental instruction profiles and reports.
The initial one-million-instruction period and later coarser periods all encountered
the host's sampling throttle; these are qualitative attribution evidence, not
instruction totals or acceptance measurements. The first coarse attempt stopped
when its no-throttle assertion failed; its raw data are retained as
`profile-qbe-low-rate.data.gz`. Final coarse receipts explicitly record throttle
counts instead of treating them as lost samples or claiming unthrottled sampling.

See the [report](../../docs/audits/d9-rc-nbody-combined-2026-09-26.md).
