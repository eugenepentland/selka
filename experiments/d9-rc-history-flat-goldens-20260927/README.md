# Immutable ABI3 golden replay receipts

`summary.json` records the compiler/source identities and final classification.
`results.json.gz` preserves every exact command, expected/actual outcome, source
hash, runtime identity, counter record and stderr. `replay.log.gz` preserves the
completion stream. `run.py` is the exact committed driver used for this run.

The compiler is from `19e16e1d`, not the branch hosting this evidence archive.
The work directory and immutable installation paths are recorded in the results.
All 462 selected outcomes match; all 440 counted RC executions balance. Ten
legacy-sharing cases intentionally use GC, and twelve CLI refusals have no guest
counters. The compiler and every declared input were rechecked after completion.
