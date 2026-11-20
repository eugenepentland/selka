# Failure paths end in `unreachable` — wave 2, lane `perf/noreturn-fail-paths` — 2026-09-22

Implements plan items 6.2 and the first half of 6.4 from
[`performance-parity-plan-2026-09-22.md`](performance-parity-plan-2026-09-22.md),
and assesses 6.11. Base: `base/parity-w2` (`684be597`, the parity audit plus
lane 5).

## Result

- **Acceptance is met without IL rewriting.** With only the failure-path change,
  the branch's plain ReleaseFast build lands on the ladder's `lad-l5-nr` column:
  0.985× of the ladder binaries on the thirteen-program geomean and **0.916× of
  lane 5 (−8.4%)**. `spectral_norm` is 0.57× of lane 5 (the ladder predicted
  0.54×: 3.68× → 2.00× Zig).
- **With the helper attribute as well** (below), the final build is **0.874× of
  lane 5 (−12.6%)** and 0.940× of the ladder column. `matmul` −34%, `raytrace`
  −29%, `nbody` −15%, `mandelbrot` −10%, and `spectral_norm` −46%.
- **Trap output is byte-identical**: code, message, the `in f at file:line`
  trace, the `MYLANG-TRAP` record and the exit status. This holds for an
  overflow three frames deep and for an out-of-range list write, through both
  `mylang build` (LLVM) and `mylang run` (QBE). It is pinned by a CLI test and
  was also compared against the lane-5 compiler's output.
- `fib` and the S-expression parser do not move beyond noise, as the audit
  predicted (`fib`'s cost is the frame protocol).

All timings come from a **loaded machine** (load average 13–21 on 20 threads,
other agents building). They were pinned to CPU 0. Ratios are medians of
per-round paired ratios with 95% bootstrap intervals. The coordinator
re-measures at integration.

## What changed

### 1. Failure paths end in `hlt` under the fast protocol (6.2) — `QBE-NORETURN-1`

`src/qbe.zig` adds a last text pass, `haltFailurePaths`, which runs after
position sinking and the dead-slot passes and before label stripping. It turns
a ` jmp @failure` or ` jmp @entry_failure` into ` hlt` when the line before it
is one of these:

- a `call $myl_qbe_fail_*`. Every such helper unconditionally calls the
  runtime's `fail`.
- a `call $myl_qbe_int_neg` in an `@neg_overflow` block, or a
  `call $myl_qbe_int_binary` in a `@shift_invalid` block. These value helpers
  also compute ordinary results. They are only accepted in the cold block that
  checked negation or a checked shift opens for the operand class that always
  traps: the width's minimum for signed negation, non-zero for unsigned
  negation, and a count outside `0..bits` for a shift. In each of those cases
  the helper's `checked`/shift test fails.

The pass runs only when `stickyFlagTest()` is false, which means neither step
nor frame accounting. That is the fast protocol that `QBE-UNWIND-1` introduced.
The result is exactly the audit's `noreturn` rewrite. Diffing the emitted IL
against the ladder's rewritten manifest shows `a`, `mul_av`, `mul_atv` and
`mul_atav` in `spectral_norm` byte-identical. `main` differs only by the three
negations, which the rewrite left alone.

Across the suite in fast mode, every fail call now ends in `hlt`. There are 20
to 161 per program. Two kinds of `@failure` edge remain:

- a `match` default arm (`jmp @failure` after the last arm, in `binary_trees`'
  `check`)
- one in `text_ops_tuned`'s `main`

The adapter (`experiments/llvm-backend/qbe_llvm.py`) now parses `hlt`, with no
operands and no destination. `llvm_emit.on_hlt` already lowered it to
`unreachable`, and vendored QBE emits `ud2`.

### 2. Helper attributes (6.4, first half)

- **Fail helpers** (`llvm_emit.declaration_attributes`):
  - Every `myl_qbe_fail_*` declaration is `cold`. This is a hint, and it is true
    everywhere, because the helpers are only called once a check has failed.
  - It is also `noreturn`, but only in a unit where *every* call to that helper
    is followed by `hlt`. A unit that keeps a sticky `jmp @failure` after any
    call gets `cold` alone. The attribute therefore follows the same mode
    boundary as the IL.
  - Under LTO the final binary was byte-identical with and without these
    declarations, because `unreachable` after the call already says everything.
    They mainly help per-unit (non-LTO) builds.
- **`myl_qbe_float_canonical`**: `memory(inaccessiblemem: readwrite) nounwind
  willreturn` (`runtime_signatures.ATTRIBUTES`, documented there).
  - The helper ignores its context argument. It returns a constant after one
    volatile read of `float_canonical_probe`, a file-static in `qbe_runtime.c`
    whose address never leaves that file, so it touches no guest memory at all.
  - `readwrite` rather than `read`, because LLVM treats a volatile access as a
    side effect.
  - It is not `speculatable`, so the call still stays on the NaN branch
    (`QBE-FLOAT-CANON-1`'s intent).
  - Effect: LLVM keeps list headers, lengths and the frame position in registers
    across the cold NaN branch. The frame-position stores in `mandelbrot`'s
    inner loop disappear and the loop becomes a countdown. In the per-unit
    assembly of `nbody_class` `advance`, 117 memory-operand loads became 96.
  - Declaration attributes are dropped when LTO links the runtime's definition.
    So the claim only has to hold for the pre-link, per-unit module, where it is
    exactly true.
  - No other helper qualified. The root mark/restore helpers read or write
    `ctx->heap.roots`, which generated code also reaches. The allocation, list
    and text helpers write guest objects. Everything else is off the hot paths
    of this suite.

### 3. Small lowering fixes (6.11) — both skipped

- **`memset` of the record-result scratch (`%empty`).**
  - In a fast-protocol unit, its only reader is `ret %empty` in the
    `@failure`/`@entry_failure` epilogue. That epilogue is now unreachable in
    every record-returning unit of the suite: 11 of 11 had no live `@failure`
    edge. LLVM deletes the block, the alloca and its zeroing (checked:
    `raytrace`'s `add` has no zeroing stores at `-O3`).
  - In a sticky-protocol unit, the scratch is exactly what the failure path
    returns, so it is not "fully written anyway" and zeroing it keeps the
    returned record deterministic.
  - Only Debug `mylang run` (QBE) still executes a `call memset`.
  - Nothing is left worth a change.
- **Float temporaries in `d` slots.**
  - Skipped. The loop-carried `vmovq` round-trip is visible in per-unit
    assembly (`spectral_norm` `mul_av`). Its cause is the i64-returning
    `myl_qbe_float_canonical` merging into the accumulator's phi, so the NaN
    change (5.1, lane `lang/nan-when-observed`) removes it.
  - The slot typing lives in `src/qbe_scalar.zig` and `src/qbe.zig`, which the
    NaN and root-liveness lanes own.
  - It was not measured under LTO.

## Soundness, mode by mode

The only new assumption is this: in a fast-protocol unit, a `myl_qbe_fail_*`
helper (and the two value helpers in their trap blocks) does not return. That
assumption was already required for correctness by `QBE-UNWIND-1`, which dropped
the sticky `loadl %trap` test after calls in exactly these units. A returning
helper would already have let the caller continue silently. Now it would
execute `ud2`.

| mode | policy | `ctx->unwind` armed? | lowering |
|---|---|---|---|
| `mylang build` ReleaseFast, no ceiling | step off, frame off | yes, `myl_qbe_on_stack` → `launch` | **`hlt`** |
| `mylang run` (single file) without a ceiling | step off, frame off | yes | **`hlt`** |
| `mylang build --max-frames/--max-steps`, or `run` with a ceiling | accounting on | yes | sticky `jmp @failure` (unchanged) |
| `mylang build --mode Debug` | accounting on (`fast_executable` needs ReleaseFast) | yes | sticky (unchanged) |
| library / embed API (`mylang_native_run_v1`, `call_v1`, wire, codecs) | accounting on (`qbe_build.zig`: "A library always keeps it") | yes, `execute` → `mylang_qbe_execute_config` → `myl_qbe_on_stack` | sticky (unchanged) |
| guest-test runner (`mylang test`, `native_test_runner.c` via the codec API) | library build, accounting on | yes | sticky (unchanged) |
| `run-project` | frame accounting kept by default (`runPolicy(true)`) | yes | sticky (unchanged) |
| C code before arming: budget parsing, `myl_qbe_host_begin`, `myl_qbe_on_stack`'s own failures | — | no | C only; no generated unit runs there |

Two further facts support the table:

- Every guest execution enters through `execute_config_args` → `myl_qbe_on_stack`.
  That function is the only place a runtime `Context` is created (the other
  `calloc` in `qbe_io.c` allocates a print buffer). `fail` longjmps only on the
  first trap, and `on_stack` is entered only when no trap is pending.
- So under the fast protocol, no generated instruction runs with a trap already
  set. That is the one case in which `fail` returns while unwind is armed.

Tests:

- `src/qbe_test.zig` "the fast protocol ends each fail helper's path in hlt and
  accounting keeps the sticky exit" (`// spec: QBE-NORETURN-1`). Under the fast
  policy, the overflow, list-bounds, negation and shift paths end in `hlt` and
  no `jmp @failure` remains. Frame-only accounting and the fully accounted
  policy (library, guest tests, Debug) keep `)\n jmp @failure\n` and contain no
  `hlt`.
- `test/integration.zig` "a trap through a halting failure path reports the same
  code, trace, record and status" (`// spec-case`). It builds each probe
  ReleaseFast with no ceiling (`hlt`) and with `--max-frames=100000` (sticky).
  It pins the exact stderr bytes, including the `\x1e` record marker, and exit
  status 1, and requires the two builds to match. It then does the same through
  `mylang run` with and without a ceiling.
- `experiments/llvm-backend/test_adapter.py`:
  - `hlt` is parsed and lowered to `unreachable`.
  - The declaration is `noreturn cold` only when every call is halted, and `cold`
    when any call keeps the sticky jump, including a mixed unit.
  - `hlt` with an operand is rejected.
  - An end-to-end build whose helper `longjmp`s out of the halted path.
  - The canonical-NaN attribute is present and still computes correctly.
  - The file now imports `ATTRIBUTES`. Its existing heap-getter test raised
    `NameError` on the base.

## Numbers (loaded machine, CPU 0, 9 rounds, wall; CPU-time geomeans agree to 0.001)

### Failure paths alone — `results/wave2/noreturn-suite-r1.json`

| program | my/Zig | lane 5/Zig | `lad-l5-nr`/Zig | my / lane 5 | my / `lad-l5-nr` |
|---|---:|---:|---:|---:|---:|
| binary_trees | 1.79 | 2.17 | 2.01 | 0.920 [0.631,1.071] | 0.845 [0.693,0.971] |
| spectral_norm | 2.36 | 3.63 | 2.58 | **0.572** [0.535,0.629] | 0.981 [0.954,1.069] |
| mandelbrot | 1.34 | 1.32 | 1.35 | 1.009 [0.990,1.032] | 0.995 [0.971,1.024] |
| raytrace | 5.66 | 6.05 | 5.16 | 0.952 [0.919,1.028] | 1.014 [0.985,1.163] |
| knucleotide | 5.06 | 5.03 | 5.36 | 1.024 [0.920,1.276] | 0.980 [0.832,1.116] |
| text_ops | 7.92 | 7.89 | 7.63 | 0.999 [0.972,1.056] | 1.029 [1.004,1.075] |
| sort_builtin | 1.49 | 1.50 | 1.48 | 0.995 [0.971,1.006] | 0.996 [0.968,1.028] |
| sort_quick | 1.24 | 1.28 | 1.23 | 0.965 [0.907,0.992] | 1.028 [0.982,1.076] |
| sort_records | 6.11 | 6.13 | 6.19 | 1.012 [0.948,1.046] | 0.990 [0.965,1.018] |
| sieve | 1.79 | 1.92 | 1.86 | 0.934 [0.910,0.986] | 0.975 [0.904,1.054] |
| nbody | 7.59 | 7.64 | 7.67 | 0.996 [0.967,1.008] | 0.994 [0.966,1.015] |
| fannkuch_redux | 1.27 | 1.45 | 1.27 | 0.840 [0.790,0.965] | 1.009 [0.916,1.097] |
| matmul | 7.25 | 8.99 | 7.12 | 0.819 [0.786,0.842] | 0.984 [0.955,1.017] |
| **geomean** | **3.03** | **3.30** | **3.07** | **0.916** | **0.985** |

### Final build (failure paths + canonical-NaN attribute) — `noreturn-suite-r2.json` (first four) and `noreturn-suite-r3.json`

| program | my/Zig | lane 5/Zig | `lad-l5-nr`/Zig | my / lane 5 | my / `lad-l5-nr` |
|---|---:|---:|---:|---:|---:|
| binary_trees | 1.98 | 2.04 | 2.00 | 0.993 [0.957,1.027] | 0.995 [0.986,1.071] |
| spectral_norm | 2.67 | 4.91 | 2.61 | **0.536** [0.528,0.564] | 1.001 [0.969,1.115] |
| mandelbrot | 1.35 | 1.50 | 1.47 | 0.904 [0.874,0.909] | 0.906 [0.888,0.920] |
| raytrace | 5.03 | 7.07 | 6.83 | 0.713 [0.709,0.761] | 0.741 [0.733,0.778] |
| knucleotide | 5.14 | 5.20 | 4.92 | 1.001 [0.961,1.040] | 1.024 [0.967,1.160] |
| text_ops | 7.10 | 6.97 | 6.96 | 1.019 [0.966,1.129] | 0.989 [0.912,1.086] |
| sort_builtin | 1.44 | 1.45 | 1.45 | 0.994 [0.962,1.007] | 1.004 [0.983,1.020] |
| sort_quick | 1.25 | 1.25 | 1.29 | 0.983 [0.961,1.018] | 0.981 [0.967,1.063] |
| sort_records | 5.55 | 5.34 | 5.44 | 1.034 [1.001,1.075] | 1.019 [1.002,1.036] |
| sieve | 1.70 | 1.68 | 1.71 | 0.999 [0.934,1.033] | 0.981 [0.907,1.019] |
| nbody | 4.69 | 5.54 | 5.43 | 0.846 [0.827,0.858] | 0.862 [0.857,0.900] |
| fannkuch_redux | 1.15 | 1.30 | 1.14 | 0.887 [0.836,0.900] | 1.006 [0.997,1.043] |
| matmul | 4.34 | 6.84 | 5.72 | 0.659 [0.641,0.662] | 0.778 [0.756,0.796] |
| **geomean** | **2.75** | **3.16** | **2.92** | **0.874** | **0.940** |

`sort_records` +3% over lane 5 is at the edge of its interval, and it was
+1% [0.948,1.046] in the first batch. Neither change touches its hot code,
which is the library sort.

### Canonical-NaN attribute A/B (same compiler, adapter with and without) — `noreturn-fattr-r1.json`, `noreturn-fattr-mb.json`

| program | with / without |
|---|---:|
| spectral_norm | 1.019 [1.002,1.031] |
| raytrace | 0.872 [0.867,0.880] |
| nbody | 0.816 [0.811,0.834] |
| nbody_class | 0.920 [0.901,0.968] |
| matmul | 0.809 [0.780,0.817] |
| mandelbrot (21 rounds) | 0.986 [0.976,0.996] |

A first 9-round `mandelbrot` batch read 1.074. It did not reproduce over 21
rounds, and the loop's assembly only lost stores.

### `fib` and the parser — `noreturn-fib.json`, `noreturn-parser.json`

- `fib` (11 rounds): 3.14× Zig against `lad-l5` 3.21× and `lad-l5-nr` 3.13×.
  my/`lad-l5` is 1.075 [0.951,1.182], which is noise.
- Parser, 11 rounds, ratios to `zig-bench`:
  - census: 1.64× (lane 5 1.67×, `lad-l5-nr` 1.56×)
  - render: 2.24× (lane 5 2.27×, `lad-l5-nr` 2.20×)

The tables are rendered with `experiments/perf-parity-plan-20260922/pairs.py`,
which gives paired arm-to-arm ratios across one or more result files.

## Gate

The logs are in the worktree's `.tmp/gate/`. They were compared against the
lane-5 base logs with `gate_diff.py`.

| step | verdict | gate-diff |
|---|---|---|
| `zig build test` | rc=1 (base is red) | first run: 46 base failures, plus one new, my own spec test. Its fixture spelled a shift `<<`, which the language rejects. Fixed in `14d171b7`, and it passes focused. Second run on the fixed tree: one new, `integration.test.guest benchmarks write a candidate and enforce an approved baseline immutably`. That is a timing-policy test run while this lane's benchmark loaded CPU 0. It passes when re-run alone, and it builds Debug guests (sticky, untouched by this change). |
| `zig build test-qbe` | rc=1 (base is red) | 2 base, 2 lane, **no new** |
| `zig build test-qbe-build` | green | no new |
| `zig build test-schematic` | green | no new |
| `zig build test-byte-io` | green | no new |
| `zig build fmt-check` | green | no new |
| Guardian | green on every commit (whole-tree pre-commit run) | — |

`experiments/llvm-backend/test_adapter.py` has 27 tests. They all pass except
`test_benchmark_runtime_registry_is_complete`, which fails on the base too
(`myl_native_text_points` has no signature).

## Left

- **`match` default arms.** A `switch_variant` ends with `jmp @failure` after
  its last arm. Validation (`validateOpSwitchVariant`) requires one arm per
  variant case, so that edge is unreachable by type. Ending it in `hlt` would
  let `binary_trees`' hot `check` drop a compare. It is a type-exhaustiveness
  claim rather than a noreturn fact, and a future `Option` niche (6.9) changes
  the tag representation, so it is left for that lane to decide.
- **6.11's second item** is left to the NaN lane (above).
- **The remaining `@failure` edge in `text_ops_tuned`'s `main`** was not
  investigated. It is not a fail-helper path.
