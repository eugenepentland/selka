# Text microbenchmark improvements

Local `main` was fast-forwarded to
`1994cb76e266080d971be6f41e98fba5707234dd`, preserving all five pre-existing
documentation edits. This is the development lineage, not GitHub's unrelated
`origin/main` snapshot. Nothing was pushed.

The merged source passed complete registered verification: 147/147 build steps,
3,109 selected native tests, all 46 required verification actions, and all 88
Guardian checks. Gate inputs were stable. See
[qualification](coordinator/main-integration/qualified-summary.json),
[raw gate evidence](coordinator/gate-04/), and
[main preservation and merge proof](coordinator/main-integration/local-main-fast-forward.json).
This does not claim zero-RC default promotion or legacy RC retirement.

## Merged compiler comparison

The common compiler was built from the exact merged commit. Its installation,
compiler, guests, inputs, and qualification are pinned in the
[common receipt](coordinator/common-001/build-receipt.json). All comparisons use
the unchanged text benchmark source and unchanged foreign ports and oracles.

The [complete common report](bench/reports/common-final-001/REPORT.md) includes
all raw samples, paired intervals, counters and RSS. Each of six cells used three
warmups and fifteen alternating measured rounds on CPU 8 under exclusive shared
timing admission. Instrumented counter runs and three RSS runs are separate from
runtime samples. Admission wait is excluded from runtime measurements.

Ratios below one favor MyLang. The fastest foreign implementation in each cell
is shown; the report retains all Zig ReleaseSafe/ReleaseFast, Rust, and Go arms.

| Workload | Small ratio | Large ratio | Fastest foreign arm |
| --- | ---: | ---: | --- |
| String splitting | 0.794 | 0.963 | Rust |
| JSON transformation | 1.086 | 1.089 | Rust |
| CSV aggregation | 1.002 | 0.910 | Zig ReleaseFast |

Split passes the requested below-one target at both sizes. JSON still needs an
improvement. Small CSV is uncertain: its paired 95% interval is 0.966–1.013, so
the target is not established. No noise flags were raised; two calibrations
landed just below the 50 ms target and are disclosed in the report.

Against the frozen checked-ownership C0 compiler, merged runtime is about
60–62% lower for splitting, 46–49% lower for JSON, and 30% lower for CSV.
C0 in these text comparisons is
`78b4bb5934748d5942389b12dfe66cb0031cafdc`; it is the later microbenchmark
baseline, distinct from the original memory-closeout plan's starting revision.
JSON managed peak is about 26% lower; process RSS is reported independently.
The small split reserve policy raises managed peak from 7,528 to 7,944 bytes.
All counted cells have zero runtime RC events and zero managed live bytes at
exit. These are workload-specific measurements, not package-wide RC claims.

## Follow-up experiments

Post-merge work stays on `codex/text-gaps-main-final-20261012` while isolated
JSON and CSV candidates are measured against both the merged compiler and C0.
The isolated CSV trial has passed the runtime target and its production change
has been integrated on that branch; combined qualification remains pending.

The [CSV trial](bench/reports/csv-final-trial-001/REPORT.md) measures the helper
that keeps general UTF-8 capture work out of the ASCII path. Candidate/Zig
ReleaseFast ratios are 0.975 [0.970, 0.989] small and 0.876 [0.867, 0.888] large.
All foreign-target intervals are below one. Against the merged common compiler,
runtime is 3.3% lower small and 4.1% lower large; managed totals are unchanged.

The [private JSON cursor guard trial](bench/reports/json-final-trial-001/REPORT.md)
removes redundant negative-index normalization but improves runtime only about
1%. Candidate/Rust remains 1.078 [1.061, 1.100] small and 1.064 [1.056, 1.076]
large. The large common comparison includes one in its interval. This experiment
has not closed the JSON gap; further narrowly scoped work is in progress.

The subsequent [serializer change](json-serializer/handoff.md) uses borrowed
dictionary-entry iteration to avoid looking up a value again under its stored
key. It passed 176 native configuration checks and 100 unchanged text oracle
probes; managed allocation/copy totals match the guard candidate. Its generated
serializer no longer hashes or searches those keys. The production change and
its independent ordering, ownership, and numeric regressions are integrated;
combined timing is pending. The small private peek guard is also included in
that tested source, with its isolated timing limitations retained above.

The [standalone serializer trial](bench/reports/json-serializer-trial-001/REPORT.md)
subsequently measured 0.968 [0.959, 0.981] against common on the stable small
case, but 1.055 [1.040, 1.072] against Rust. It does not establish the requested
target. All seven arms of the large case triggered noise flags; its broad
intervals are inconclusive. Every sample is retained. A post-cell observation
found heavy browser CPU activity; it is contemporaneous context, not proof of
the cause of variation during individual samples. No standalone repeat or
selective sample removal was performed.

A [read-only JSON audit](split/json-guard-readonly-deferred.md) records the
serializer and byte-loop costs before these follow-ups. The broader dictionary
lookup compiler transformation it outlines remains deferred.

The narrower [span-index extension](span-index/handoff.md) has passed eight focused
tests, seven native modes, cold/warm cache equivalence, and all 88 Guardian
checks. It forwards only proven nonnegative indices with the exact borrowed
receiver and runtime contract; bounds traps remain covered. Analysis has fixed
size and candidate limits. The combined compiler is frozen at
`8b7d59eba868775b1b8d7f64c54b07abdd23d470` in the
[common-002 receipt](coordinator/common-002/build-receipt.json). Its runtime
and counted guests passed 100 oracle probes, including zero RC and zero
exit-live checks. The [native audit](coordinator/common-002/native-audit.json)
confirms removal of the quoted-string normalization call and serializer key
hash/search calls. Combined timing and complete verification remain pending.

The [read-only CSV audit](split/csv-common001-readonly.md) records a separate,
deferred bounds-check opportunity with required safety conditions.

Full Lox/EDA application benchmarking remains deferred for the user's review
of these microbenchmark results.
