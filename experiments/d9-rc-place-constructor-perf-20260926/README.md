# Combined n12 receipts

`results.json.gz` is the complete original receipt from `measure.py`, including
five interleaved samples per backend, native manifests and exact hashes/counters.
The driver retains the original worktree paths and uses the frozen
`install-place-constructor` Debug compiler. Its baseline binaries are the immutable
`cumulative-19e` artifacts in the adjacent flat-destruction tree. `measure.log.gz`
records the final medians.

See the [analysis](../../docs/audits/d9-rc-place-constructor-perf-2026-09-26.md).
This diagnostic does not establish full-corpus or RSS acceptance.
