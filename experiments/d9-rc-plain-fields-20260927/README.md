# Schematic plain-field projection experiment

The [report](../../docs/audits/d9-rc-plain-fields-2026-09-27.md) documents the
bounded compiler change and matched measurements. This is diagnostic evidence,
not WP-4 full-corpus acceptance.

`measure.py` uses the unchanged `pc.py` build/run/check commands and exact three
schematic inputs. `measure.json.gz` preserves all eight build manifests, 24
output checks and 36 unscaled CPU3 instruction observations with raw perf event
runtime and running percentages. Separate counting runs preserve full ownership
counters. `before-emitted.json.gz` and `after-emitted.json.gz` contain exact IL.
The guest/trap runners and sources preserve standalone GC-stress and RC checks.
`source.patch.gz` is the production/test delta from the real two-parent base.

Runner absolute paths are original provenance. Adapt paths only in a separate
worktree; preserve workloads and expected output. The accepted GC tree is never
written by these runners. `verify.py` checks archived hashes, backend identities,
output checks, instruction medians and ownership balances without executing code.
