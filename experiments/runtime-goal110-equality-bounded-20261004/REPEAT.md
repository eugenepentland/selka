# Independent bounded-equality guest repeat

This supplement retains the unchanged 3dcbe723 ReleaseFast candidate against
the immutable 6cf7bdce G4 control. The original archive at 32b747be and its
evidence index remain unchanged. The candidate remains unintegrated.

The session ran 2026-10-04 08:18:39–08:18:50 UTC, UUID
9583c652-49d0-4387-8367-8545c80946aa, CPU 2 under the normal timing lock,
15 measured rounds and 3 warmups with randomized paired arm order. All 144
outcomes passed status, checksum and clock checks. Per-sample host counters,
arm order and elapsed times are in the raw report. Both source/receipt/asset
and all 48 guest identities passed checks before and after this repeat.
Complete guest process streams are unknown; the timing helper retains the
status/checksum/clock fields rather than full stdout/stderr streams.

| Case | Backend | Before ns/op | After ns/op | Ratio | Paired 95% interval |
| --- | --- | ---: | ---: | ---: | --- |
| small equality | LLVM | 3.971826 | 3.845976 | 0.968314 | [0.959732, 0.973093] |
| small equality | QBE | 20.720732 | 14.908959 | 0.719519 | [0.718267, 0.722865] |
| large search | LLVM | 83.516849 | 86.456520 | 1.035199 | [1.016944, 1.056329] |
| large search | QBE | 87.907929 | 88.318304 | 1.004668 | [0.995348, 1.018015] |

The interval calculation resamples paired rounds and computes the ratio of
arm medians in 20,000 deterministically seeded draws. These are pointwise
intervals; they do not cover systematic noise or multiple comparisons. Run
`analyze-repeat.py RAW OUTPUT` to replay all outcomes and intervals. The
structured timing command remains in the original `rf-commands.json`.

The broad standalone 17–64-byte helper gains, including 64-byte owned/view
equal and mismatch cases, survive their native repeat. They translate to a
3.2% LLVM small-equality gain and a 28.0% QBE gain here. LLVM small equality
remains above the 1.10 target. The earlier 5-round LLVM large-search cost
of 5.64% is retained, and this independent repeat confirms a smaller 3.52%
cost whose interval upper bound still exceeds the 1.05 regression guard.
The standalone 128-byte owned-middle control also retains an interval
upper bound of 1.053095. The adoption recommendation is to defer this
candidate while investigating shared kernel/checksum lowering; no normal
goal confirmation or causal layout claim follows from these observations.
