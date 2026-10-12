# Text microbenchmark checkpoint

Further performance optimization stopped at the user's request on 2026-10-12.
The measured combined changes are preserved on
`codex/text-gaps-main-final-20261012`. String splitting and CSV meet the
below-one target at both sizes. JSON small remains above Rust; JSON large is
uncertain around parity. The target is achieved in four of six cells.

## Final measured result

The [full comparison](bench/reports/common-final-002/REPORT.md),
[paired assessment](bench/reports/common-final-002/ASSESSMENT.md), and
[machine-readable target assessment](bench/reports/common-final-002/target-assessment.json)
retain all six cases and every sample. Ratios below one favor MyLang.

| Workload | Small ratio [95% CI] | Large ratio [95% CI] | Fastest foreign arm |
| --- | --- | --- | --- |
| String splitting | 0.847 [0.840, 0.858] | 0.969 [0.956, 0.982] | Rust |
| JSON transformation | 1.036 [1.011, 1.058] | 1.015 [0.933, 1.028] | Rust |
| CSV aggregation | 0.973 [0.962, 0.993] | 0.868 [0.857, 0.889] | Zig ReleaseFast |

The report includes separate Zig ReleaseSafe, Zig ReleaseFast, Rust and Go
comparisons. JSON is faster than both Zig arms and Go in these measurements.
All six cases passed oracle, binary/source identity, sample ordering, counters
and RSS validation. No case triggered the predefined MAD/drift noise flags;
raw ranges remain available. These are exploratory intervals from one session.

Against the original checked-ownership text baseline, runtime is about 59–60%
lower for splitting, 49–52% lower for JSON, and 32–33% lower for CSV. Relative
to the already-merged compiler, JSON improves another 4.8–5.8%, CSV improves
1.6–5.3%, and splitting is unchanged within uncertainty.

## Memory and allocation

Managed peak and process RSS are distinct observations. The following values
compare original text C0 with the final candidate in the same campaign.
RSS values are medians of three separate process runs, in KiB.

| Workload / size | Managed peak bytes: C0 → final | RSS KiB: C0 → final |
| --- | ---: | ---: |
| Split / small | 7,528 → 7,944 | 1,860 → 1,852 |
| Split / large | 401,440 → 401,312 | 2,340 → 2,328 |
| JSON / small | 18,592 → 13,728 | 2,052 → 1,992 |
| JSON / large | 287,408 → 213,464 | 2,372 → 2,152 |
| CSV / small | 8,192 → 8,096 | 1,892 → 1,832 |
| CSV / large | 118,160 → 118,064 | 2,052 → 1,992 |

JSON managed peak is about 26% lower. The small split reserve policy raises
managed peak by 5.5%; that tradeoff is retained. Whole-program allocation
counts, including setup at matched iteration counts, are 98.5–99.9% lower for
splitting, 73–75% lower for JSON, and 43–44% lower for CSV. Raw allocation
counts, cumulative bytes, reallocations and copies are retained in the report.
Managed counters omit native allocator overhead and some nonmanaged storage;
foreign managed counters are unavailable. No RSS saving is inferred from
managed counters. All counted checked runs have zero RC events and zero
managed live bytes at exit. Follow-up changes leave managed allocation,
growth, copy and peak totals unchanged versus the merged compiler.

## Code and qualification

The combined compiler was built from
`8b7d59eba868775b1b8d7f64c54b07abdd23d470`; the complete installation,
host/guest hashes, source and flags are pinned in the
[common-002 receipt](coordinator/common-002/build-receipt.json).
Its runtime and counted binaries passed 100 independent oracle probes.

The follow-up changes separate general UTF-8 append work from CSV's ASCII
path, iterate JSON dictionary entries directly, guard the private JSON
cursor, and forward proven nonnegative borrowed byte indices. The latter
keeps exact runtime/receiver contracts, bounds checks and fixed analysis
limits. Its eight focused tests cover seven native modes and matching
uncached/cold/warm LLVM. See [span qualification](span-index/handoff.md),
[serializer qualification](json-serializer/handoff.md), and
[actual combined native code](coordinator/common-002/native-audit.json).

Complete registered verification passed on
`12ae2cb9b09d765dbb7861618efe1819103c5fe1`: 115/115 gate build steps,
3,060 selected native tests and zero failures. All 46 required actions are
covered: 30 executed and 16 reused valid receipts; 27,068 reported skips are
shard exclusions. The language suite passed 1,596 tests and retained its one
pre-existing unsupported view-copy case in ordinary mode. Inputs were stable.
All 88 whole-tree Guardian checks passed. See the [final summary](coordinator/final-closeout/summary.json),
[raw complete gate](coordinator/gate-05/), and [Guardian log](coordinator/final-closeout/guardian.log).
Production and verification source files match the measured compiler revision;
subsequent commits add evidence only. Complete verification does not include
full application/performance qualification.

## Method and boundaries

Text C0 is `78b4bb5934748d5942389b12dfe66cb0031cafdc`, the later
microbenchmark baseline rather than the original memory-closeout plan base.
Common-001 is the merged compiler at
`1994cb76e266080d971be6f41e98fba5707234dd`. The campaign uses unchanged
benchmark source, foreign ports and oracles: three warmups, fifteen
alternating paired rounds, three separate RSS runs, and independent counted
executions. CPU 8 and shared exclusive timing admission are used; queue wait
is excluded. Per-cell read-only host snapshots and all artifact hashes are
preserved. Build logs include admission and are not paired compile-time
performance evidence.

Local `main` was fast-forwarded to `1994cb76e266080d971be6f41e98fba5707234dd`
before these follow-ups. All five pre-existing documentation edits were
preserved byte-for-byte. See [merge and preservation proof](coordinator/main-integration/local-main-fast-forward.json).
The follow-up branch is separate; nothing was pushed and GitHub's unrelated
`origin/main` was untouched.

The two-line quote-writing experiment remains unintegrated and unmeasured in
the JSON worker tree; its already-running checks finished, and no timing was
submitted. Its handoff is recorded in the final closeout evidence. No further
performance experiment or full Lox/EDA benchmark is pending in this session.
The next optimization decision and application campaign are deferred to the
user's review.

This checkpoint does not claim complete public-library/corpus qualification,
zero-RC default promotion, or legacy RC retirement. Those broader memory
milestones remain unfinished. The prior numeric/iteration test flakes and
their diagnostic improvements remain documented in the main integration
evidence; no cause is asserted for those unreproduced failures.

Earlier measurements remain available in [common-001](bench/reports/common-final-001/REPORT.md),
the [CSV trial](bench/reports/csv-final-trial-001/REPORT.md),
the [JSON guard trial](bench/reports/json-final-trial-001/REPORT.md), and
the [serializer trial](bench/reports/json-serializer-trial-001/REPORT.md).
The serializer trial's noisy large case remains inconclusive and is not
pooled with the final campaign.
