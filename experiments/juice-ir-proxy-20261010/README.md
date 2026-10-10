# Compile-only Juice prototype, 2026-10-10

The loop-counting part works for canonical scalar loops without executing them.
The first timing model is useful for experiments, but is **not accurate enough
to replace runtime validation or enforce a 5% merge gate**. Across five held-out
transformations, median timing-ratio error was 16.1% in the longer repeat,
compared with 39.8% for weighted operation counts alone. The worst miss was
182.3%. All six comparisons, including an identity control, exceeded the 3%
timing-spread limit; these are descriptive point estimates, not qualified accuracy.

## What is implemented

[`scripts/juice_ir_estimate.py`](../../scripts/juice_ir_estimate.py) reads the
optimized **Core IR** emitted by `mylang dump-ir --facts`. It does not link or run
the guest, collect counters, interpret loop bodies, or look up measured runtimes.
It is an experimental developer script, separate from installed native Juice.

The analyzer identifies natural loops using dominators and backedges. It accepts
single-entry, single-latch, pre-test loops with constant positive or negative
induction steps, including inclusive comparisons and rectangular nests. It
derives counts algebraically and rejects a concrete induction that would overflow
on its final increment. Missing scalar inputs produce symbolic formulas; supplied
inputs instantiate those formulas. Symbolic results are conditional on bound
arithmetic and induction not overflowing. Counts assume normal completion.

Each reachable block receives an execution count, including the final failed
loop test. The report contains operation counts, weighted work and a heuristic
cycle score. The score combines a four-operation issue budget with the longest
same-iteration dependency path returning to a loop-header phi. Nested loops are
composed as serial regions. This distinguishes independent work from serial
recurrences, but is not a hardware scheduling model or a worst-case bound.

Data-dependent branches/exits, triangular bounds, memory operations, calls,
recursion and unproven arithmetic checks currently return `unknown` with a
reason. Unknown operations never silently receive zero cost. Triangular nests
are a prototype limitation: many could be handled by summation analysis.

```bash
# Compile only; n = 20 million. No native guest executable is produced/run.
python3 scripts/juice_ir_estimate.py \
  --compiler .tmp/juice/fast/bin/mylang \
  --source experiments/juice-ir-proxy-20261010/kernels.my \
  --function three --param 0=20000000

# Omit the binding to obtain a symbolic formula from the retained IR.
python3 scripts/juice_ir_estimate.py \
  --ir experiments/juice-ir-proxy-20261010/optimized-core.ir \
  --function nested32
```

The `three` loop has `max(0, n)` iterations and three shift/XOR pairs per
iteration. `nested32` has `max(0, n) * 32` inner iterations. In nine warm-cache
samples, compiling the fixture to Core IR and analyzing `nested32` took a median
**5.57 ms**, of which **0.71 ms** was analysis. This used `n = 10^12`, describing
32 trillion inner iterations without traversing any of them. These timings
exclude Python CLI startup and provenance-file hashing and are not cold-build
measurements.

## Evaluation

[`make_suite.py`](make_suite.py) generates [`kernels.my`](kernels.my) and the
predeclared [`suite.json`](suite.json). All base/candidate pairs compute identical
results for equivalent work. There are five actual transformations and one
identity control. They are functions in **one release executable**, selected at
runtime, not historical compiler builds or an application benchmark suite.

The estimator and all predictions were frozen before measurement. The two
calibration functions use different recurrence depths from the held-out cases;
they only fit a nanoseconds-per-score conversion. The relative predictions do
not depend on that conversion. Model weights were not fitted to the held-out
measurements. The fixtures still share a narrow bitwise workload family, so
this is not evidence of generalization to other workloads.

[`evaluate.py`](evaluate.py) runs one discarded warmup pair and nine alternating
AB/BA pairs per comparison, using CPU 10, its actual SMT sibling exclusion,
process-local uclamp and the existing exclusive timing lease. The clock interval
surrounds the selected kernel; it excludes startup and argument parsing. Every
execution checks its output against an independent GF(2) matrix-exponentiation
oracle. No hardware counters are used. Raw output, process resource usage,
predictions and input identities are retained.

The first run's short kernels took roughly 2–124 ms and produced 4.4–16.3% pair
spread. One longer diagnostic repeat used the same model and cases, increasing
work 8x (40x for the short-chain pair), as recorded in
[`suite-longer.json`](suite-longer.json). It did not resolve machine variability.
Both runs are retained; there was no model refit or pass-until-green rerunning.

The table uses the longer repeat. Ratios are candidate time / baseline time;
smaller means faster. Error is `abs(predicted_ratio / measured_ratio - 1)`.

| Change | Predicted ratio | Measured median ratio | Relative error | Pair spread |
| --- | ---: | ---: | ---: | ---: |
| Identity control | 1.0000 | 1.0078 | 0.77% | 23.88% |
| Unroll short chain 2x | 1.0000 | 0.3542 | 182.31% | 35.94% |
| Unroll long chain 4x | 1.0000 | 0.9850 | 1.53% | 8.70% |
| Fuse two independent lanes | 0.5000 | 0.5959 | 16.10% | 16.77% |
| Fuse four independent lanes | 0.2813 | 0.3528 | 20.29% | 14.86% |
| Flatten the nested loop | 0.9846 | 1.0026 | 1.79% | 6.66% |

Excluding the control, median error was 17.1% in the initial run and 16.1% in
the longer run. Two of five transformation point estimates were within 5% in
both runs, but **zero comparisons qualify** under the timing-spread requirement.
The JSON rollup includes the identity control and therefore has a lower median
(8.94% in the longer run); it must not be reported as the transformation median.
Absolute nanosecond predictions were worse and sensitive to frequency/load
drift: the calibration factor changed from roughly 0.28 to 0.36 ns per score
between runs. There is no claim of 5% absolute-time accuracy.

Generated assembly exposes two concrete missing pieces:

- LLVM combines repeated shifts/XORs in the short-chain case; the candidate's
  remainder loop uses a shift by 26 for two original shift-by-13 steps. Core
  operation counts and dependencies no longer describe the final work.
- LLVM vectorizes the fused lanes. Signed 64-bit vector right shift becomes
  `vpsrad`, `vpsrlq` and `vpblendd`, rather than the one operation modeled here.
  The four-lane case uses two vector chains. Scalar IR costs cannot describe
  these instruction choices and dependencies accurately.

These observations explain why a Core-only model needs backend information;
they do not attribute every percentage point of timing error to one cause.

## Coverage and verification

The two explicit negative fixtures, `data_exit` and `triangular`, correctly
return `unknown`. [`coverage.py`](coverage.py) also checks five existing benchmark
kernels: list scan, bytes scan, dictionary lookup, tree walk and list filtering.
All five abstain, respectively at list length, list length, checked multiply,
union tag and data-dependent control flow. Supporting actual collection-heavy
programs requires substantial additional work. This coverage probe also found
and fixed handling of empty, unreachable blocks left in optimized dumps; the
fix leaves every frozen prediction identical.

`python3 tests/test_juice_ir_estimate.py` passes 11 tests, including 2,000
independent small-loop count comparisons, overflow boundaries, negative/zero/
large counts, descending loops and predecessor order, symbolic/nested counts,
refusal cases, independent-chain modeling and an oracle cross-check.

[`evidence.tar.gz`](evidence.tar.gz) contains both raw runs, frozen model source,
final model source, input manifests, generated Core and LLVM IR, selected native
assembly, calibration/coverage/speed results and the build recipe. Compiler and
binary hashes are recorded; executables are not included. The archive's identity
is in [`evidence-receipt.json`](evidence-receipt.json).

```bash
mkdir -p /tmp/juice-ir-replay
tar -xzf experiments/juice-ir-proxy-20261010/evidence.tar.gz -C /tmp/juice-ir-replay
python3 experiments/juice-ir-proxy-20261010/replay.py /tmp/juice-ir-replay/evidence
```

Replay verifies every frozen prediction against the final analyzer, all 252
non-warmup output hashes and oracle values, and exact reconstruction of the
reported statistics. No guest execution is needed for replay. To reproduce native
measurement, build `kernels.my` with `--release` and
`--link benchmarks/runtime/ports/native_clock.c` through `scripts/build-slot.sh`,
then run `evaluate.py --compiler COMPILER --binary BINARY --ir IR --output NEW_DIR`
under the recorded uclamp settings. Compiler/CPU changes are new experiments.

## Next useful step

Keep the algebraic count analysis and add a model of the **final optimized
machine code**, with instruction dependencies and CPU execution resources.
That still requires compilation, not guest execution, and addresses the two
observed failures. Add shape/length contracts and conservative memory summaries
for collection code, retaining `unknown` for uncovered cases. Nightly runtime
measurements can calibrate and validate that richer model; this prototype is
advisory only and does not change merge policy.
