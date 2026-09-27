# Joined managed helper and dictionary overwrite diagnostic

Eight rows cover the unchanged dictionary count and three schematic workloads
on both backends. The [report](../../docs/audits/d9-rc-helpers-word-joined-2026-09-27.md)
states the remaining failing instruction limits and the exact source identities.

`results.json.gz` preserves the current three-side comparison, including raw
counter stderr, separate RSS observations, native manifests and counted RC
executions. `gc-builds.json.gz` and `prior-results.json.gz` bind the accepted GC
and immutable preceding RC binaries; their original bytes are hash checked.
`run.py` reuses the mandated corpus harness. `verify.py` recomputes and checks
all receipts without executing any guest; `--live` also checks local artifacts.

This archive contains 72 unscaled instruction observations, 72 separate RSS
observations and sixteen balanced counted runs. It is explicitly a focused
diagnostic and cannot establish full Stage 4 acceptance. No workload, threshold
or accepted baseline changed.
