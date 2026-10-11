# Fresh match payload transfer

This follow-up builds on `a97ef51bb` (owned `try` payloads) on branch
`codex/zero-rc-owned-match-20261011`. It stays separate from the `parallel.map`
work. The zero-RC mode remains opt-in.

A match directly on a fresh result owns that temporary and can transfer its
active payload:

```mylang
func load_name() -> Result[str, str]:
    match read_name():
        case Ok(name):
            return Ok(name)
        case Err(message):
            return Err(message)
```

Previously both returns required `.copy()`. This rule admits calls, callback
invocations, variant constructors, and collection `.copy()`/`.pop()`
results, plus built-in decoding, UTF-8 validation and numeric parsing results.
Compiler-generated expression blocks preserve the classification.
Checking and lowering use one shared syntactic predicate; there is no last-use
search, whole-program analysis, new annotation or runtime ownership test.
The existing consuming `union_take` operation transfers the payload, frees a
recursive box shell when needed, and lets ordinary ownership insertion destroy
unused payloads. JSON decoding and rendering now return the owned decoded
string directly. The same change removes the decoded string copy in
`strings.chr`.

Named values and field/index projections continue to borrow, even at their last
use. Destructured record fields also remain projections. For example, matching
`saved_result` still requires an explicit copy to return an independently owned
payload. Explicit `.copy()` keeps its deep-copy meaning. Ordinary RC builds keep
their existing match behavior.

## Results

These are **additional changes relative to the previous owned-`try` step**.

| Workload | Allocations before → after | Cumulative allocated bytes before → after | Peak live bytes before → after |
| --- | ---: | ---: | ---: |
| Standard JSON fixture | 580 → 553 (−4.7%) | 42,240 → 40,480 (−4.2%) | 9,952 → 9,952 |
| Standard strings fixture | 103 → 103 | 6,816 → 6,816 | 352 → 352 |
| Nested JSON × 1,000 | 131,004 → 130,004 (−0.8%) | 12,672,384 → 12,512,384 (−1.3%) | 10,080 → 10,080 |
| String-heavy JSON × 1,000 | 237,000 → 204,000 (−13.9%) | 103,784,000 → 85,184,000 (−17.9%) | 35,568 → 35,568 |
| Boxed payload workload | 25,308 → 21,978 (−13.2%) | 1,683,648 → 1,470,528 (−12.7%) | 864 → 768 (−11.1%) |

The string-heavy workload additionally performs 4,000 reallocations in both
versions; their growth bytes are included above. Removing copies lowers memory
traffic without necessarily lowering the peak. The earlier capacity-related
peak increase is still present; this change does not alter collection growth.
The strings fixture reports no allocation reduction on its exercised inputs.

| Uninstrumented workload | Median runtime before → after | Speedup |
| --- | ---: | ---: |
| Nested JSON | 3.30 → 3.17 ms | 1.04× |
| String-heavy JSON | 19.06 → 17.99 ms | 1.06× |
| Boxed payload workload | 1.32 → 1.26 ms | 1.04× |

These are shared-host process timings, including startup. The nested and boxed
sample ranges overlap, so their small median differences should not be treated
as established speedups. String-heavy JSON improved across the recorded ranges
(18.80–19.76 ms before, 17.82–18.07 ms after). No compile-time speedup is claimed;
the new rule is a local syntactic check and reuses the existing lowering and
ownership passes.

## Validation

All **1,016 Core tests**, **13 focused tests**, and **88 whole-tree Guardian
checks** passed. The new regressions cover returns, mutation writebacks, callback
results, popped values, recursive boxes, loop exits, ignored cases, explicit-copy
independence, decoding success/errors, JSON integration, and rejected double
moves and borrowed escapes.

All **51 counted zero-RC executions** used zero RC events and ended with zero live
managed bytes. Their emitted LLVM and linked symbols also passed the RC guards.
All five ordinary RC controls passed. The candidate with the boxed workload's
explicit copy retained has the same allocation count as the baseline, confirming
that the language still honors explicit copies. Box-shell destruction is actually
emitted in every candidate boxed mode.

Raw evidence: [results.json](results.json), [validation.json](validation.json),
and the [source fingerprint](source-sha256.json). The final frozen candidate is
`.tmp/owned-match/candidate-v2/bin/mylang`; prior failed probes are not the measured
compiler. No `parallel.map` implementation or runtime ABI changes are included.

## Measurement

The baseline is the frozen previous-step `candidate-v2` compiler, including owned
`try` transfer. `measure.py` checks five cases in release, unoptimized debug,
verified release, optimized debug, and release without facts:

- The existing standard JSON and strings fixtures.
- The previous 60-level JSON workload, parsed and rendered 1,000 times.
- A JSON array of 32 strings of 256 bytes, parsed/rendered 1,000 times.
- Boxed Option payloads crossing a match and return, with another allocation
  before reading the extracted value.

The JSON entry sources are identical for both compilers; their embedded standard
libraries omit the two JSON copies and the `strings.chr` copy. The boxed comparison
uses separately recorded before/after sources: the candidate removes one
`.copy()` at the fresh match boundary. An additional candidate run retains that
copy and must preserve the baseline allocation count. Five ordinary RC controls
check unchanged behavior.

Every zero-RC lane checks expected output, whole-program counters, managed leaks,
emitted LLVM and linked symbols. Allocated bytes are cumulative managed allocation
bytes plus realloc growth. Peak bytes measure simultaneously live managed memory,
not process RSS. Neither metric counts compiler memory or native allocator
metadata. Timings use uninstrumented release executables, two warmup pairs and
nine alternating pairs on CPU 2 of the shared host.

```sh
scripts/build-slot.sh build python3 experiments/owned-match-20261011/measure.py \
  --before .tmp/owned-payload/candidate-v2/bin/mylang \
  --after .tmp/owned-match/candidate-v2/bin/mylang \
  --zig /path/to/zig \
  --output .tmp/owned-match/comparison-v2
```
