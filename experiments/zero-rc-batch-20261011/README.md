# JSON lookup and owned field transfer batch

This batch compares the frozen owned-match compiler against direct borrowed JSON
lookup and complete field transfer from a fresh enum payload record. Neither
change introduces ownership or lifetime annotations.

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
candidate controls, and one zero-RC explicit-copy control (102 counted executions total). Every counted execution checks output, managed leaks, and
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
