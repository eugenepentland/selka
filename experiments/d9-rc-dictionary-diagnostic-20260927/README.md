# Dictionary lifetime diagnostic

The unchanged two-million-iteration `dict_count` workload runs against the
immutable joined Debug compiler at `d1d8b3c4` and the accepted GC binaries.
`measurements.json.gz` records all 12 interleaved median-three instruction
observations, exact output, binary/backend identities and separate complete
count records. Every production instruction counter reports 100% running.
The source and expected output are copied unchanged here.

The separate QBE sampling run has 249 samples, 249 THROTTLE records and 249
UNTHROTTLE records, with zero lost records. Its attribution is heavily throttled
and qualitative only; it is not a performance acceptance measurement. The full
raw event dump is retained alongside the report and perf data.

`measure.py` is the exact executed driver, with its original temporary paths.
This evidence concerns one diagnostic, not the complete WP-4 acceptance corpus.
