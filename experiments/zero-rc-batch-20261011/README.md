# JSON lookup and owned field transfer batch

This batch compares the frozen owned-match compiler against direct borrowed JSON
lookup and complete field transfer from a fresh enum payload record. Neither
change introduces ownership or lifetime annotations.

## Measured results

Complete-program release counters (construction, lookups, and startup included):

| Workload | Allocations, before → after | Cumulative allocated bytes | Peak live managed bytes |
|---|---:|---:|---:|
| Array: 128 siblings, 32 successful lookups | 14,066 → 1,650 | 1,553,904 → 165,104 | 101,520 → 75,408 |
| Object: 128 siblings, 32 successful lookups | 18,840 → 2,296 | 1,989,760 → 206,720 | 124,144 → 90,264 |
| Owned payload fields: 1,000 unpacks | 27,000 → 21,000 | 3,136,000 → 2,496,000 | 1,984 → 1,536 |
| Standard JSON fixture | 553 → 538 | 40,480 → 38,720 | 9,952 → 9,952 |

Lookup-only cost per successful lookup, after subtracting its construction control:

| Kind | Unrelated siblings | Allocations, before → after | Allocated bytes, before → after |
|---|---:|---:|---:|
| array | 1 | 10 → 3 | 1,024 → 320 |
| array | 16 | 55 → 3 | 6,080 → 320 |
| array | 128 | 391 → 3 | 43,720 → 320 |
| object | 1 | 12 → 3 | 1,312 → 320 |
| object | 16 | 72 → 3 | 7,648 → 320 |
| object | 128 | 520 → 3 | 56,040 → 320 |

Every candidate miss/out-of-range lookup adds **zero managed allocations or bytes**.
Successful lookups still allocate the selected nested result: three allocations and
320 bytes in these samples, independent of unrelated siblings. This is a local
library rewrite using existing borrowing support.

For owned enum payload fields, the migrated source removes the two explicit copies:

```mylang
# before
return Pair(left=left.copy(), right=right.copy())
# after, inside a fresh owned match
return Pair(left=left, right=right)
```

That migration reduces allocations by 22.2%, cumulative allocated bytes by 20.4%,
and peak live managed bytes by 22.6% in the record workload. Keeping both `.copy()`
calls on the candidate preserves the original allocation count in all five modes.
The compiler now permits this transfer; it does not remove explicit copy semantics.

Observed uninstrumented process timing medians and full nine-run ranges:

| Workload | Before median (range), ms | After median (range), ms | Median ratio |
|---|---:|---:|---:|
| Array: 4,000 lookups | 93.11 (88.30–98.36) | 4.27 (2.76–7.70) | 21.82× |
| Object: 4,000 lookups | 121.14 (109.35–129.69) | 4.49 (2.57–7.08) | 26.96× |
| Owned fields: 20,000 unpacks | 16.45 (12.83–25.65) | 12.23 (7.46–43.17) | 1.34× |

These are targeted shared-host microbenchmarks. The record ranges overlap; its
median improvement is an observation, not a precise claim about general application
performance. See `timing.json` for every measured sample and binary hash.

All **106 counted executions** passed: **101 zero-RC** and **five ordinary-RC**.
Every zero-RC run passed emitted LLVM, native symbol, runtime counter, and managed
leak checks; all counted runs ended with zero live managed bytes.
Integration review also fixed lowering-cache key hashing so the new owned-match
descriptor does not traverse each nested arm body twice. A 64-level nested typed
match regression guards against exponential traversal; related tests check that
body selection, bindings, and source changes still affect cache keys. This is a
structural compile-time safeguard, not a compile-time speed benchmark.
Integrated validation passed 1,025 Core tests, 177 frontend tests, 11 CLI semantic-cache
tests, six fresh/warm/uncached owned-record executions, and all 88 whole-tree Guardian
checks. The final Core suite includes both hashing regressions. Frontend and CLI
semantic-cache tests preceded the cache-hashing follow-up; those implementations
were unchanged. See `integration-validation.json` for source revisions and log hashes.
No total-process RSS or compile-time speedup is claimed.

Raw records: `before.json`, `after.json`, `summary.json`, `timing.json`,
`validation.json`, `integration-validation.json`, and `source-sha256.json`.

## Workloads and interpretation

`generate_samples.py` produces deterministic sources. JSON roots have one selected
array containing two 64-byte strings, plus 1, 16, or 128 unrelated sibling arrays.
Each program parses the same document once and performs 32 operations. For each
shape and size there are three variants:

- `control`: observe the document kind and count iterations without looking up.
- `hit`: select the nested array and read both string lengths from the independent
  returned value, without adding another copy in the observer.
- `miss`: request an absent object key or the first out-of-bounds array index.

Reported **lookup deltas** subtract the matched control's cumulative allocation
count and bytes, then divide by 32. This removes document construction and process
startup costs. The selected result must still be independently owned; a successful
lookup deliberately copies that nested value. Unrelated siblings should contribute
no allocation cost to lookup. Peak live memory is reported for the entire program
and is never subtracted. These are managed-memory counters, not total process RSS.
The library change's `test/core/zero_rc_json_lookup.my` separately checks independence
after source replacement and destruction, wrong variants, empty containers, and
negative/out-of-range indexes.

The record workload constructs an enum case with three managed list fields,
returns two fields in a new `Pair`, and discards the third. Baseline source copies
the two fields explicitly; candidate source transfers them from the fresh match.
Both traverse the returned strings to produce the same checksum. A candidate
control retains both explicit copies and must preserve the baseline allocation
count. Named-source patterns remain borrowed.

## Qualification

Release mode covers every JSON shape/size/operation. All five supported modes
(release, unoptimized debug, verified release, optimized debug, and release without
facts) cover the 128-sibling cases and the record workload. This is 47 zero-RC
executions per compiler plus one release JSON library fixture each, five ordinary-RC
candidate controls, and five zero-RC explicit-copy controls (106 counted executions
total). Every counted execution checks program results, managed leaks, and
(for zero-RC) counters, LLVM, and native symbols for absence of reference counting.

The harness saves source, compiler, LLVM, and executable SHA-256 identifiers, raw
allocation totals, audits, and command logs. Prior experiment reports are imported
as helper libraries only and are never overwritten.

## Runtime methodology

Separate uninstrumented release binaries run 4,000 JSON lookups or 20,000 record
unpacks. Timing uses two warmup pairs, then nine pairs with alternating execution
order pinned to CPU 2. The measurement is process wall time, including startup, on
a shared machine. Compilation durations in raw logs include component-cache state
and shared-host effects and are not presented as compile-time performance claims.

## Reproduction

From the repository root, set the compiler and Zig paths. The captured baseline is
`/home/epentland/ai/canopy/mylang-zero-rc-owned-payload-20261011/.tmp/owned-match/candidate-v2/bin/mylang`
(SHA-256 `98f70fc9bfbfd1e48bfac4af0b1c0c8d7697004b1b6675f3614a8a8e299ef269`).
The combined candidate is
`/home/epentland/ai/canopy/mylang-zero-rc-batch-20261011/.tmp/zero-rc-batch/candidate-v2/bin/mylang`
(SHA-256 `76ef3ab199bfed73ad6e5ffb1e0ef8c11eb65afd65ac7826307d83e713b8d2d3`).
Its compiler source is integration commit `d57510b46`.
Zig is `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig`.

```sh
python3 experiments/zero-rc-batch-20261011/generate_samples.py
scripts/build-slot.sh build python3 experiments/zero-rc-batch-20261011/measure.py capture \
  --phase before --compiler "$BATCH_BASELINE" --zig "$BATCH_ZIG" --output .tmp/batch-measure/before
scripts/build-slot.sh build python3 experiments/zero-rc-batch-20261011/measure.py capture \
  --phase after --compiler "$BATCH_CANDIDATE" --zig "$BATCH_ZIG" --output .tmp/batch-measure/after
python3 experiments/zero-rc-batch-20261011/measure.py summarize
scripts/build-slot.sh build python3 experiments/zero-rc-batch-20261011/measure.py build-timing \
  --phase before --compiler "$BATCH_BASELINE" --zig "$BATCH_ZIG" --output .tmp/batch-measure/before
scripts/build-slot.sh build python3 experiments/zero-rc-batch-20261011/measure.py build-timing \
  --phase after --compiler "$BATCH_CANDIDATE" --zig "$BATCH_ZIG" --output .tmp/batch-measure/after
python3 experiments/zero-rc-batch-20261011/measure.py timing \
  --before .tmp/batch-measure/before --after .tmp/batch-measure/after
```

Coordinate the final timing command with other agents using reserved timing CPUs.
`capture` resumes already completed lanes only when compiler and source hashes
match. Archive/remove this directory's `before.json` or `after.json` when starting
a deliberately different comparison.
