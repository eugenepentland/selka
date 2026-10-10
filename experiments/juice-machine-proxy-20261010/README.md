# Compile-only Juice: Core loop counts plus final machine-code costs

The machine-code prototype improves prediction accuracy on the five transformations
from the [Core-only experiment](../juice-ir-proxy-20261010/README.md). Against one
fresh timing run of the **same executable**, median timing-ratio error falls from
**17.2% to 3.3%**. Four of five corrected predictions have point estimates within
5%; the four-lane vector case still misses by **18.2%**. Median error against
measured CPU-cycle ratios is **1.9%**.

This does **not** establish a general ±5% runtime bound. Every wall-clock
comparison exceeds the predeclared 3% repeat-spread limit, so there are **zero
qualified wall-clock passes**. These are five related register-only kernels, and
the Core-to-native mapping is manually audited for one binary. Installed Juice
and merge policy are unchanged.

## Results

Ratios are candidate/baseline; smaller means less time or fewer cycles. Error is
`abs(predicted_ratio / measured_ratio - 1)`. The identity control is excluded from
all headline statistics.

| Transformation | Core prediction | Stock LLVM prediction | Corrected LLVM prediction | Measured time ratio | Corrected time error |
| --- | ---: | ---: | ---: | ---: | ---: |
| Unroll short chain ×2 | 1.0000 | 0.3571 | 0.3571 | 0.3648 | 2.09% |
| Unroll long chain ×4 | 1.0000 | 1.0000 | 1.0000 | 0.9987 | 0.13% |
| Fuse two lanes | 0.5000 | 0.2917 | 0.5833 | 0.6038 | 3.39% |
| Fuse four lanes | 0.2813 | 0.1458 | 0.2917 | 0.3566 | 18.20% |
| Flatten nested loop | 0.9846 | 1.0000 | 1.0000 | 1.0338 | 3.27% |

| Model | Median time error | Worst time error | Median CPU-cycle error |
| --- | ---: | ---: | ---: |
| Core only | 17.19% | 174.15% | 15.92% |
| Stock LLVM MCA | 3.27% | 59.10% | 2.55% |
| LLVM MCA with two independently checked latencies | 3.27% | 18.20% | 1.90% |

The stock and corrected models have the same median because the latency
correction affects only the two fusion comparisons. The worst error and number
of point estimates within 5% distinguish them: stock has three, corrected four.
The earlier Core-only report's 16.1% median is from its earlier timing run; 17.2%
here compares all three models against the same new measurements.

| Transformation | Measured CPU-cycle ratio | Corrected cycle error | Cycle-ratio spread | Time-ratio spread |
| --- | ---: | ---: | ---: | ---: |
| Unroll short chain ×2 | 0.3665 | 2.55% | 0.47% | 13.01% |
| Unroll long chain ×4 | 1.0000 | <0.01% | 0.02% | 5.59% |
| Fuse two lanes | 0.5946 | 1.90% | 2.67% | 26.50% |
| Fuse four lanes | 0.3554 | 17.94% | 1.15% | 11.51% |
| Flatten nested loop | 0.9999 | 0.01% | 0.33% | 21.39% |

Spread means `(maximum - minimum) / median`, not a confidence interval. The
identity control measures 1.0094 in time and approximately 1.0000 in CPU cycles;
its time spread is 6.35%. Reference-cycle ratios closely track elapsed-time
ratios while ordinary cycle ratios are much more stable. This is consistent with
frequency variation contributing to timing noise; scheduling telemetry also
records interruptions. The four-lane error persists against stable cycle
measurements and cannot be explained away as wall-clock noise.

## What the estimator does

[`scripts/juice_machine_estimate.py`](../../scripts/juice_machine_estimate.py)
combines the existing Core analyzer's concrete loop counts with final native
instructions extracted using `objdump`. This sees LLVM's simplification,
unrolling, instruction selection and vectorization directly.

[`regions.json`](regions.json) identifies 15 machine regions for 11 functions,
including loops inlined into `main`. It records exact executable and Core IR
hashes, symbols, addresses and corresponding Core loop headers. Native loop
latches supply grouping factors; the fixed inner loop in the nested case is
expanded into its outer region. This is an explicit, manually checked mapping,
**not an implemented general source-to-native correspondence algorithm**. A new
binary requires a new audited map; mismatched hashes are rejected.

For each region, LLVM MCA simulates 200, 400 and 800 repetitions. The estimator
uses the slope of total simulated cycles, checks convergence within 1%, and
multiplies by the number of native iterations. It does not use
`BlockRThroughput`, which excludes loop-carried dependencies. MCA simulates the
instruction stream; it does **not** execute the guest program. Its model omits
instruction fetch/decode, branch prediction and a cache hierarchy. See the
[LLVM MCA documentation](https://llvm.org/docs/CommandGuide/llvm-mca.html).

The prototype accepts only long, concrete, register-only loops with all Core
loops covered and no unmapped native remainder. Memory operations, unsupported
instructions, data-dependent exits, small loops and uncovered tails produce
`unknown`. Function setup is not scored. These restrictions are intentional;
the current implementation is unsuitable for general application estimates.

The 45 MCA subprocesses took 5.34 seconds in total for the stock model and 3.79
seconds for the corrected model. These are observed analysis costs on an already
compiled binary, excluding compilation, disassembly and other bookkeeping.
Regions are reused within one suite; persistent caching across runs is not
implemented. The work is independent of the guest's actual iteration count,
unlike running hundreds of millions of guest iterations.

## Why stock LLVM needed calibration

LLVM 22.1.2's `alderlake` model reports latency 1 for `MOV64rr` and latency 2 for
`XOR64rr`. Separate instruction microbenchmarks on this i7-12700H using
[LLVM exegesis](https://llvm.org/docs/CommandGuide/llvm-exegesis.html) found:

| Independent probe | Measured cycles |
| --- | ---: |
| Scalar register XOR dependency chain | 1.00305 per instruction |
| Copy to a distinct register, XOR, copy back | 1.01002 per three-instruction snippet |
| Same-register MOV dependency chain | 1.00163 per instruction |

[`latency-profile.json`](latency-profile.json) therefore overrides only
distinct-register 64-bit GPR moves to latency 0 and distinct-register 64-bit GPR
XORs to latency 1. Same-register moves, 32-bit forms, immediates and vector
instructions retain LLVM's costs. LLVM MCA's latency annotations apply the
overrides. No coefficient was fitted to the five transformation timing ratios.
Both stock and corrected predictions are retained.

Vector latency probes were about one cycle; a subsequent diagnostic throughput
probe also agreed with the individual vector-instruction costs. Those results
do not explain the four-lane miss. The remaining instruction interactions and
unmodeled machine behavior need investigation; this report does not assign a
proven cause. The subsequent throughput probes were not used to alter the
frozen predictions.

## Measurement method and evidence

All predictions were frozen before this fresh run. Previous measurements of
these workloads were already known, so this is not a new blind workload holdout.
The native executable is exactly the one from the Core experiment:

```text
SHA-256 0a78dc6ea0fc9b47a6b543b768d89c111c73096e20a7738c4888eff1dcb2169e
```

[`evaluate.py`](evaluate.py) uses the previous `suite-longer.json`: two calibration
kernels, five transformations and an identity control. It retains nine
alternating AB/BA pairs per case after one warmup pair, and nine samples per
calibration kernel after a warmup. All 140 executions have independently checked
GF(2) output oracles. Calibration-kernel measurements are retained for diagnosis
and do not set model coefficients. Kernel intervals range from about 61 to 1042
milliseconds.

Both `perf` and the guest were pinned to P-core CPU 10 before event setup; the
controller excluded CPU 10 and SMT sibling 11. The run requested utilization
clamps of 1024/1024 and held the repository's runtime timing lease. Grouped user
cycles/reference cycles had to report 100% running without scaling. These
counters are **validation labels only**, never inputs to the static estimator.
Counters cover process startup as well as the kernel; the guest clock covers
only the kernel interval. No global scheduler or frequency policy was changed.

[`results.json`](results.json) contains all three model comparisons.
[`predictions.json`](predictions.json) contains the corrected static scores.
[`evidence.tar.gz`](evidence.tar.gz), identified by
[`evidence-receipt.json`](evidence-receipt.json), contains:

- Both models' disassembly, region assembly, raw MCA JSON, costs and predictions.
- Frozen model scripts, input IR, suite, region map and latency profile.
- Original timing outputs, perf counters, oracles, scheduling telemetry and methods.
- Original instruction-calibration outputs, including the later vector diagnostic.
- Tool/package identities and hashes. Large executables and LLVM libraries are
  identified by hash but are not bundled.

The measured estimator snapshots precede a final defensive counter-register
alias check. Replaying with the final estimator reproduces every saved
prediction exactly.

## Reproduction

From the repository root, with the original binary and locally extracted LLVM
22.1.2 tools available:

```bash
python3 scripts/juice_machine_estimate.py \
  --binary .tmp/juice-ir/kernels \
  --ir experiments/juice-ir-proxy-20261010/optimized-core.ir \
  --map experiments/juice-machine-proxy-20261010/regions.json \
  --suite experiments/juice-ir-proxy-20261010/suite-longer.json \
  --mca .tmp/juice-machine/toolchain/root/usr/lib/llvm-22/bin/llvm-mca \
  --mca-library-path .tmp/juice-machine/toolchain/root/usr/lib/x86_64-linux-gnu \
  --latency-profile experiments/juice-machine-proxy-20261010/latency-profile.json \
  --output .tmp/juice-machine/reproduce-corrected
```

Omit `--latency-profile` and use a different new output directory for the stock
model. The tools were downloaded as Ubuntu packages with `apt-get download` and
extracted using `dpkg-deb -x`, without installing system packages. Exact versions
and package hashes are retained in `evidence/toolchain.json`; tool and shared
library hashes are in each model's method. LLVM 22.1.2 and its `alderlake` model
are part of this experiment's identity, not an interchangeable dependency.

Replay the retained evidence without LLVM, the guest executable or more timing:

```bash
python3 - <<'PY'
import hashlib, json
from pathlib import Path
p = Path('experiments/juice-machine-proxy-20261010')
r = json.loads((p / 'evidence-receipt.json').read_text())
b = (p / r['archive']).read_bytes()
assert len(b) == r['bytes'] and hashlib.sha256(b).hexdigest() == r['sha256']
PY
mkdir -p .tmp/juice-machine/replay
tar -xzf experiments/juice-machine-proxy-20261010/evidence.tar.gz \
  -C .tmp/juice-machine/replay
python3 experiments/juice-machine-proxy-20261010/replay.py \
  .tmp/juice-machine/replay/evidence
python3 tests/test_juice_machine_estimate.py
python3 tests/test_juice_ir_estimate.py
```

Replay checks all 15 region costs and 11 predictions per model, every native
output/oracle/counter record and all result arithmetic. The nine machine-model
tests and eleven Core-model tests cover the supported calculations and refusal
paths.

## Implication for Juice

Keep Core's semantic loop/count analysis, and use final machine code for
architecture-specific costs. The short-chain simplification demonstrates why
Core operation counts alone miss important changes. Small, separate CPU-model
calibrations can be reused without executing each candidate program.

Before using this for merge decisions, automate reliable Core-to-native mapping,
investigate the four-lane interaction and evaluate independent workload
families. Memory, calls and input-dependent work still need explicit coverage
or an `unknown` result. Nightly runtime comparisons could validate and refresh
such a model; this prototype does not yet justify replacing them with a ±5%
compile-only gate.
