# Owned Result/Option payload transfer

The prototype merged into local `main` at `9225adeb06cca3ab19a0f4437ec2065fbea34e2e`.
That merge combined the previously qualified memory work with the current cache,
callable-identity and durable-filesystem changes. Integration checks passed:
1,003 Core tests, 108 selected frontend tests, all 88 whole-tree Guardian checks,
and 13 counted zero-RC executions (JSON and byte builders in five compiler modes,
plus `parallel.map` with one, two and eight workers).

This follow-up lives on `codex/zero-rc-owned-payload-20261011`.
It introduces a consuming `union_take` operation for zero-RC `try` propagation.
The source checker already consumes the input; the new lowering preserves that
fact through ownership insertion and LLVM emission. The extracted value owns
its descendants. If the payload is boxed, the emitter loads it into its own
value home and frees only the empty box shell. The existing per-function
ownership pass handles both success and error edges and drops unused results.
There is no new syntax or whole-program lifetime analysis.

A nested JSON array previously copied the remaining subtree at each `try`.
At 60 levels this experiment removes 1,830 redundant list allocations per parse
(the sum of 1 through 60), while transferring those same list owners directly.

Ordinary `match` patterns still borrow. Explicit `.copy()` still duplicates
storage. Ordinary RC builds retain their current lowering. This change removes
an implicit deep copy; it does not eliminate necessary allocations for dynamic
collections, JSON trees or recursive boxes. Further `parallel.map` work belongs
to the separate task and is not included here.

## Results

| Workload / metric | Before | After | Change |
|---|---:|---:|---:|
| JSON fixture: allocations | 2,559 | 580 | -77.3% |
| JSON fixture: allocated bytes | 173,376 | 42,240 | -75.6% |
| JSON fixture: peak live bytes | 8,096 | 9,952 | +22.9% |
| 60-level JSON × 1,000: allocations | 1,961,004 | 131,004 | -93.3% |
| 60-level JSON × 1,000: allocated bytes | 129,792,384 | 12,672,384 | -90.2% |
| 60-level JSON × 1,000: peak live bytes | 8,096 | 10,080 | +24.5% |

The nested workload's median process wall time fell from
56.96 ms to 4.34 ms
(**13.1× faster**) in the paired uninstrumented runs.
This is a result for this copy-heavy workload, not a general language speedup.

Peak live storage increases even though allocation traffic falls. Transferred
lists retain their existing capacity; the removed recursive copies requested
only each list's current length (`core_owned_copy.c`), compacting spare capacity.
Avoiding those copies therefore does not guarantee lower peak memory. Capacity
policy is a separate lever from ownership transfer.

All 20 comparison executions and five additional boxed-payload executions passed their expected outputs, emitted-code checks,
linked-symbol checks and managed-leak checks. Every run recorded **zero RC events
and zero live managed bytes at exit**. Explicit recursive `.copy()` behavior
remains covered by the source regression tests.

Raw results: [results.json](results.json). Merged baseline smoke evidence:
[merge-programs.json](merge-programs.json). Compiler source fingerprint:
[source-sha256.json](source-sha256.json). Validation: [validation.json](validation.json).

## Measurement

`measure.py` builds identical sources with the merged compiler and this candidate.
The standard JSON fixture exercises valid input, invalid input, conversion errors,
navigation and nesting. `samples/json_nested.my` parses and renders a 60-level
array 1,000 times. Each source runs under release, unoptimized debug, verified
release, optimized debug and release without facts, with whole-program allocation
counters, managed-leak checks, emitted-IR checks and linked-symbol RC checks.

Allocated bytes mean cumulative managed allocation bytes plus realloc growth.
Peak live bytes mean simultaneously live managed storage, not process RSS.
Timing uses separate uninstrumented release binaries, two warmup pairs followed
by nine alternating pairs on CPU 2. Timings are indicative on this shared host.
The report preserves both compiler hashes, source hashes and individual runs.

Reproduce with two frozen compiler installations:

```sh
scripts/build-slot.sh build python3 experiments/owned-payload-20261011/measure.py \
  --before /path/to/merged/bin/mylang \
  --after /path/to/candidate/bin/mylang \
  --zig /path/to/zig \
  --output .tmp/owned-payload-comparison
```

## Validation

The full Core suite passed all **1,008 tests**. After test-only style cleanup,
the final install and all **20 affected tests** passed again. The final whole-tree
Guardian run passed all **88 checks**. The source and IR regressions cover
recursive ownership, errors, options, mutable writebacks, phi inputs, discarded
payloads, explicit copy independence, and wide boxed values whose freed shell
is reused before their extracted fields are read.

`check_boxed.py` exercises `test/core/zero_rc_payload_box.my` in all five compiler
modes. It verifies both that the shell-free call is actually emitted and that
counted executions preserve output, use no RC and leave no managed memory live.
Its results are in [boxed.json](boxed.json). The final measured compiler is the
`candidate-v2` artifact recorded in `results.json`.

The full run exposed a pre-existing test-setup problem: graph-publication fault
injection reused mutable cache state across attempts, making its allocation
sequence depend on previous failures. Commit `2ad71ee0f` isolates each attempt in
a fresh, identically seeded store; production cache code is unchanged. The
pre-fix reproductions are preserved in [cache-test-reruns.json](cache-test-reruns.json).
The passing full suite and final targeted run include the repaired test.
