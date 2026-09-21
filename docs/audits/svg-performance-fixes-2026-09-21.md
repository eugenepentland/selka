# Production SVG performance fixes — 2026-09-21

This implements the measured priorities from the
[slowdown audit](svg-slowdown-drivers-2026-09-21.md). The comparison uses the
existing EDA NetLisp functional SVG renderer and retained pre-change mylang
executables from the [full SVG benchmark](full-svg-netlisp-benchmark-2026-09-21.md).

## Measured result

The complete fixture render is **4.03× faster with step/frame limits retained**:
45.47 → 11.30 ms. Enabling LTO brings the bounded result to 10.54 ms. The fastest
unbounded configuration is now O3+LTO at 5.30 ms, versus 2.54 ms for NetLisp.
The earlier LTO slowdown is eliminated; performance parity is not yet reached.

| Configuration | Before, ms | After, ms | Speedup |
|---|---:|---:|---:|
| LLVM O3 | 18.561 | 5.998 | 3.09× |
| LLVM O3 + LTO | 35.350 | 5.305 | 6.66× |
| LLVM O3, step/frame accounting | 45.467 | 11.296 | 4.03× |
| LLVM O3 + LTO, step/frame accounting | — | 10.545 | — |
| Zig NetLisp ReleaseFast reference | — | 2.543 | — |

These are fresh, interleaved measurements of the retained before binaries and
the final combined production changes. They supersede the earlier audit's
absolute timings for this before/after comparison. The paired bootstrap 95%
interval for the bounded after/before ratio is 0.2469–0.2499; for O3+LTO it is
0.1476–0.1514. Gains from the individual fixes overlap and should not be added.

| Input | NetLisp, ms | After O3, ms | After LTO, ms | After bounded, ms | After bounded LTO, ms |
|---|---:|---:|---:|---:|---:|
| Fixture | 2.543 | 5.998 | 5.305 | 11.296 | 10.545 |
| Changed net | 2.563 | 6.013 | 5.361 | 11.338 | 10.475 |
| Changed value | 2.594 | 5.934 | 5.299 | 11.314 | 10.546 |

The fastest unbounded result remains 2.09× the NetLisp time, and bounded LTO is
4.15×. Step/frame accounting still contributes substantial cost. Bulk byte
transport and the remaining repeated layout lookups are candidates for the
next audit; the original phase percentages are not measurements of this new
implementation.

## Changes

- **Pin lookup:** layout uses normalized `Part.pin1`/`pin2` indexes when the
  index, owner and number match. The original scan remains the fallback.
- **Row construction:** stable counting buckets produce the same pin-number
  order, including source-order ties. Row heights use precomputed passive
  counts and bridge-presence facts instead of nested whole-pin scans. Group
  order and ownership remain unchanged. NC hub labels remain part of the raw
  net-presence calculation, preserving the previous edge-case behavior.
- **LLVM target policy:** the native build driver resolves CPU/features from
  the selected Zig C driver, includes them in object-cache identity, and carries
  them into LLVM function attributes so LTO retains the policy.
- **Scalar host calls:** scalar parameters/results use a checked stack path
  when argument count, depth and value budget permit it. All other calls use
  the generic marshaler. Registration, capabilities, call/work budgets,
  reentry checks and callback-result validation still apply.

The real schematic host continues to request step and frame accounting. The
index changes reduce accounted work; they do not remove the accounting. Normal
managed allocation, collection and runtime checks remain enabled.

## Validation

- Final `zig build test-schematic test-byte-io test-qbe-build -Doptimize=ReleaseFast -j4`
  exited 0: 88 Zig tests, the C bridge harness, and all 88 Guardian checks passed.
  The first run exposed the intentional generated-host-source hash change;
  its reviewed snapshot was refreshed and the four focused generator tests passed.
- The LLVM adapter's 21 tests and the 25 focused backend/options/I/O tests passed.
  The CPU and feature cache dimensions are tested independently. A real
  112-byte QBE copy survived full LTO and executed correctly under both native
  and portable-baseline feature policies. Native emitted AVX `vmovups`; baseline
  emitted SSE `movups`, with explicit AVX disablement retained in the IR.
- The expanded host bridge passed O3 and ASan/UBSan with leak detection. Tests
  cover narrow scalar ranges/sign extension, zero/seven/eight arguments, exact
  and insufficient value budgets, generic fallback, malformed results, work
  inflation/exhaustion, reentry, registration, capabilities and cleanup.
- Full SVG acceptance passed with QBE and LLVM O3: 30 components, 95 connected
  pads, four NC pins, nine ports, all 34 expected nets, and 23 invalid-input
  cases rejected with located diagnostics and no partial output. LLVM LTO
  passed independent geometry checks, source rewiring and the deliberately
  broken route-drawing mutation.
- All four final configurations reproduce the exact old SVG on three benchmark
  inputs, normally and under GC stress. Both accounting builds reject one-step
  and one-frame limits with the expected runtime errors.
- Seven additional index-sensitive variants match the retained binary in all
  four final builds, normally and under GC stress. They cover pin/declaration
  ordering, swapped names, display/raw identity separation, two NC collisions
  (including an NC-only bridge match) and empty-net rejection.
- All **744 measured executions** produced the expected per-implementation hash.
  The fixture mylang SVG remains 49,617 bytes, SHA-256
  `68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388`.

Raw results: [measurements](../../experiments/svg-fixes-20260921/measurements.json),
[output and budget qualification](../../experiments/svg-fixes-20260921/qualification.json),
[variant qualification](../../experiments/svg-fixes-20260921/variant-qualification.json),
[build receipts](../../experiments/svg-fixes-20260921/builds.json), and
[native/portable LTO qualification](../../experiments/svg-fixes-20260921/llvm-target-qualification.json).

## Reproduction

From the mylang checkout, build and validate the compiler before invoking the
comparison driver:

```sh
zig build -Doptimize=ReleaseFast
zig build test-schematic test-byte-io test-qbe-build -Doptimize=ReleaseFast
python3 experiments/svg-fixes-20260921/run.py build
python3 experiments/svg-fixes-20260921/run.py qualify
python3 experiments/svg-fixes-20260921/qualify_variants.py
python3 experiments/svg-fixes-20260921/run.py measure
```

The comparison reuses the frozen projects and retained binaries under
`.tmp/full-svg-benchmark-20260921`; the earlier benchmark documents their
construction. It writes fresh binaries under `.tmp/svg-fixes-20260921`, with
build commands, source hashes, object receipts, output qualification and every
timing sample retained under `experiments/svg-fixes-20260921`.

Timed runs include process startup, input reads, model construction, placement,
routing, SVG file output and shutdown. Compilation and output validation are
outside the timer. Eight arms run in randomized order on CPU 6, with three
warmup rounds and 31 measured rounds for each of three inputs. Every timed SVG
is checked against its implementation's retained hash.

This remains an implementation comparison: NetLisp and mylang differ in
algorithms, validation, dependency loading, memory policy and SVG content.
