# Canonicalize NaN when it is observed, not when it is produced — 2026-09-22

Wave 3, item 1 of [the parity plan](performance-parity-plan-2026-09-22.md)
(§4.2, §5.1, §7). Branch `lang/nan-when-observed`, over `base/parity-w2`
(`684be597`, the parity audit plus lane 5). The measured compiler is a
ReleaseFast build of `05e524b4`. The later commit changes only a test's
snapshot digest.

**Status: complete and gated.** The float loops now reach the audit's `l5-nan`
counterfactual, and slightly beat it: `mandelbrot` 1.32× → 1.02× Zig,
`raytrace` 4.5× → 2.4×, `nbody` 5.0× → 1.93×, class `nbody` 4.2× → 1.66×.
No program got slower. Outputs are byte-identical to Zig's on all thirteen
entries. `zig build test` and `test-qbe` add no new failures over the base,
and every other gate step is green.

## The rule

A NaN's payload and sign are never observable. Arithmetic and comparisons
propagate NaNs the way IEEE and the hardware do. Every place a float's bits
leave the value sees the canonical quiet NaN `0x7ff8000000000000`, or treats
every NaN the same way.

The old rule canonicalized after every `+ - * /`: an unordered self-compare,
then a branch to an opaque cold call, `myl_qbe_float_canonical`. That call let
LLVM assume any memory could change, so it could not keep values in registers or
vectorize. The call also forced a source-position store before every float
operation.

SPEC: `QBE-FLOAT-CANON-1` is retired. `FLOAT-NAN-OBSERVED-1` states the rule,
and `-2` through `-6` each cover one family of observation points.
`FLOAT-DOMAIN-1` and `QBE-FLOAT-ENV-1` are reworded to match.

Docs:
- [`docs/floating-point.md`](../floating-point.md) now says "a NaN you can
  observe is the canonical quiet NaN" and has a new
  [NaN payloads](../floating-point.md#nan-payloads) section with a runnable
  example.
- The same edit replaces two stale paragraphs that still claimed the raw `f64_*`
  bit-pattern intrinsics were available. They are removed spellings.
- Feature slug `float-nan-when-observed` points at the new section.

## What stopped canonicalizing (producers)

| producer | before | now |
|---|---|---|
| `qbe_scalar.floatBinary` (`+ - * /`) | `cuod` + `jnz` + cold `call $myl_qbe_float_canonical` + phi | `=d op` then `=l cast`: nothing else |
| `myl_qbe_float_canonical` | runtime helper, header, `pure_callees` entry, adapter signature | deleted |
| `myl_qbe_float_unary` / `_binary` (`sqrt floor ceil trunc abs`, negation, conversions) | `float_bits` replaced a NaN result | raw bits |
| C FFI result (`qbe_c_abi.zig`) | `cned` branch returned the canonical word | raw bits (a foreign NaN enters like a produced one) |
| compiler constant evaluator (`floats.zig`) | canonical | **kept** canonical: unreachable from source today (float literals must be finite, module constants are integer or bool), and harmless either way |

A position store now survives only where something in the instruction's body can
still trap or call. `elideUnobservablePositions` drops the rest by itself, so
there was no separate position change to make.

## Observation points: the exhaustive list

The search behind this list covered the lexer, parser, sema, the generic bodies,
every native boundary and serializer, the runtime's equality, hashing, sorting
and printing, compiler caches, QBE's folder and the LLVM adapter.

The starting fact is that **no guest spelling reads a float's representation**:
- `float` is a compiler-created domain with no declaration, so `unwrap` and
  `wrap` are `E_PRIVATE_DOMAIN`, including in generic bodies.
- `u64(x)` and `i64(x)` are integer-only.
- `int(x)` traps `R_FLOAT_CONVERSION` on any NaN, and the trap carries no
  operand bits.
- All fifteen `f64_*` spellings are `E_REMOVED_SPELLING`. The only intrinsic
  still reachable is `__float_sqrt`, and only from the embedded stdlib.

That leaves these points:

| # | observation point | status before this lane | now | test |
|---|---|---|---|---|
| 1 | `str`, `print`, f-strings, container rendering, `--print-result`, `byte_buffer.append_float`, `strings.format_float`, JSON (`null`) | every printer tests `isnan` before the sign | unchanged (already canonical) | `FLOAT-NAN-OBSERVED-2` in `tests/lang/float_nan.my` (text of `-(0/0)`, `-sqrt(-1)`, `append_float`), plus the doctest in `floating-point.md` |
| 2 | **argument to an `extern def`** | the raw `d` register reached C | the C ABI wrapper selects the canonical word with straight-line mask arithmetic (`cuod` → mask → `and`/`or`) before the call | `FLOAT-NAN-OBSERVED-3`, CLI integration test: `copysign(1.0, -(0/0))` answers `1.0` |
| 3 | **float copied to a `host def` callback**, at any depth in records, arrays or variants | raw bits went into `MylangHostNode.bits` | host metadata gives the builtin float domain `bits: 64`, the only domain with a width, and `qbe_host_write` rewrites that domain's backing word when it is any NaN | `FLOAT-NAN-OBSERVED-6`: a metadata test (float `bits:64`, user `u64` domain `bits:0`) and `tests/qbe_host_bridge.c` (sign NaN and signalling payload become canonical; finite, infinite and a user domain's NaN-shaped word cross unchanged) |
| 4 | `==`, `!=`, `in`, `.index`, `.remove` on lists, records, fixed arrays, options and unions | `myl_native_equal` has a `MYL_NATIVE_FLOAT` kind and compares doubles | unchanged (numeric) | `FLOAT-NAN-OBSERVED-4` (a payload NaN is unequal to a canonical one inside every aggregate) |
| 5 | `list.sort`, `sorted`, `stdlib/sort` | `compare_float` tests `isnan` first; the merge is stable | unchanged | `FLOAT-NAN-OBSERVED-5` (NaNs of both signs sort after the ordered values) |
| 6 | dictionary keys, hashing | keys are integers or `str` only (`E_DICT_KEY`); there is no set type and no `hash` or `id` builtin | nothing to do | — |
| 7 | wire, domain codecs, typed JSON, `invoke`, exports | reject `float` (a domain without a codec) | nothing to do | — |
| 8 | packed and scalar host fast paths | carry integers, `u8` arrays and `bytes` only; a domain always takes the node path | nothing to do | — |
| 9 | compiler caches, interning, content hashes | only see finite float literals | nothing to do | — |

`FLOAT-NAN-OBSERVED-1` itself is tested two ways:
- the rewritten IL test in `src/qbe_test.zig`, which checks for no `cuod`, no
  canonical call and no canonical literal around `+ - * /`;
- `test_a_payload_nan_propagates_and_compares_unordered`, which runs
  arithmetic, the unary helpers and every comparison on a payload NaN.

**`src/native_dictionary.c` does not need a change.** Floats cannot be keys, so
the `perf/lib-dict-hash` lane has nothing to merge from this lane.

## Timing

Loaded machine, CPU 3, paired per-round ratios to Zig ReleaseFast, 95% bootstrap
intervals.
- `wave3-suite.json` is all thirteen entries, 9 rounds, with a full
  `zig build test` gate running alongside.
- `wave3-float.json` is 15 rounds and `wave3-nbody.json` 21 rounds, on the
  float programs.
- `l5` and `l5-nan` are the audit's prebuilt counterfactual binaries (lane-5
  compiler; `l5-nan` also had the NaN branch and its position stores rewritten
  out).

Ratios to Zig move between batches with the load: `raytrace`'s Zig time ranged
from 109 to 142 ms. So the stable comparison is this build against `l5-nan`
**in the same rounds**:

| program | this build ÷ `l5-nan` (suite / float / 21-round) | this build ÷ `l5` |
|---|---|---|
| mandelbrot | 0.989 / 0.996 | 0.79 / 0.67 |
| raytrace | 0.980 / 0.970 / 0.983 | 0.53 / 0.53 / 0.52 |
| nbody | 0.924 / 0.959 / 0.932 | 0.40 / 0.45 / 0.40 |
| nbody (class) | 0.875 / 0.894 / 0.872 | — |
| matmul | 0.976 / 1.000 | 0.54 / 0.55 |
| matmul (flat) | 0.932 / 0.936 | — |
| spectral_norm | 1.088 / 0.994 / 1.006 | 0.93 / 0.93 / 0.94 |
| binary_trees, sieve, knucleotide, text_ops, sort_*, fannkuch_redux | 0.97–1.04 | 0.98–1.02 |

The ratios to Zig, against the acceptance:

| program | acceptance (`l5-nan` in the audit) | this build | `l5` | `l5-nan` (same rounds) | batch |
|---|---:|---:|---:|---:|---|
| mandelbrot | ≈ 1.02× | **1.02** [0.97, 1.07] | 1.32 | 1.03 | suite |
| mandelbrot | | **0.99** [0.97, 1.03] | 1.49 | 1.00 | float, 15 rounds |
| raytrace | ≈ 2.3× | **2.37** [2.34, 2.55] | 4.52 | 2.46 | suite |
| raytrace | | **2.74** [2.40, 3.04] | 5.48 | 2.94 | 21 rounds |
| nbody | ≈ 2.17× | **2.01** [1.96, 3.30] | 5.00 | 2.16 | suite |
| nbody | | **1.93** [1.90, 2.02] | 4.86 | 2.08 | 21 rounds |
| nbody (class) | ≈ 1.8× | **1.65** [1.57, 2.59] | 4.98 | 1.96 | suite |
| nbody (class) | | **1.66** [1.63, 1.69] | 4.21 | 1.87 | 21 rounds |
| matmul | (7.10 → 3.90 on the lang rung) | **3.92** [3.47, 4.26] | 7.32 | 4.07 | suite |
| matmul (flat) | | **2.74** [2.59, 3.28] | — | 2.83 | suite |
| spectral_norm | | 3.78 [3.34, 4.35] | 4.06 | 3.82 | 21 rounds |

**Why it beats the counterfactual.** The rewrite could only turn the branch into
a `jmp`. It left behind the `cuod` compare, which LLVM mostly deletes, and any
position store that was not immediately before the branch. This build never
emits either. Its binaries have 5 `ucomisd` in `spectral_norm` against 10 in
`l5-nan` and 23 in `l5`.

In the first suite batch the `nbody` interval is wide ([1.96, 3.30]) because a
load swing took every mylang arm from about 420 ms to about 850 ms part-way
through. The 21-round batch after it is tight. `spectral_norm`'s 1.088 in the
suite batch has the same cause: it is 0.994 and 1.006 in the two quieter
batches.

Nothing is slower. Every program without float arithmetic sits within ±4% of
both counterfactual arms, and none of them has a float operation in its hot
code.

## Gate

Logs were diffed with `gate_diff.py` against the base's `l5-*.log`.

| step | result | vs base |
|---|---|---|
| `zig build test --summary all` | 46 failing (base 46) | **no new failures** once the snapshot below is re-pinned. The first run showed one new name, `qbe_build_host…bridge snapshot`. After re-pinning, the filtered test passes. |
| `test-qbe` | 2 failing (base 2) | no new failures |
| `test-qbe-build` | green (30/30) | — |
| `test-schematic` | green (21/21) | — |
| `test-byte-io` | green (11/11) | — |
| `fmt-check` | green | — |
| `test-docs` | green; the new doctest runs | — |
| Guardian | green, whole tree, at both commits | — |

`test-lang` ran inside `zig build test`, and `float_nan.my`'s four tests pass.
`doc-coverage` reports 0 failures and 175 features.

Tests changed on purpose because the rule changed:
- `src/qbe_test.zig`: the `QBE-FLOAT-CANON-1` IL test, which required exactly
  two canonical calls and two `cuod`s, now asserts that none of them exist
  (`FLOAT-NAN-OBSERVED-1`).
- `src/qbe_build_host.zig` `HOST-PACKED-1`: its SHA-256 snapshot of the
  generated bridge source is re-pinned. The source embeds
  `qbe_host_runtime.c`, which gained the binary64 rewrite.
- `tests/qbe_runtime.c`: `0/0` is now "a quiet NaN", not exactly `0x7ff8…`.
  Nothing in the build references this file today.

No golden or expected-output file pinned the old IL.

## Left, and things to know

- **Domain equality compares the u64 bitwise.** `cmp_domain`, lowered as an
  integer `==`, is accepted by the bytecode validator for `float`
  (`bytecode.zig:187`). Nothing emits it for a float, because sema lowers float
  `==` to `f64_eq`. If a future change routed a float through it, NaN payloads
  would become observable. An `InternalError` for `isFloat` there would lock it
  in. That file belongs to the fixed-arrays lane's area, so it was left alone.
- **Folded NaN bits now depend on the backend.** QBE's `fold.c` folds constant
  `d` arithmetic with its own C operations, and LLVM folds `0/0` to `0x7ff8…`.
  The same program can therefore hold differently signed NaNs under `--backend
  qbe` and the default backend. By the rule this is unobservable, and the tests
  above check each exit.
- `experiments/llvm-backend/llvm_emit.py`'s `collect_phi_stores` docstring
  still gives the removed NaN phi as its example. The adapter belongs to the
  `perf/noreturn-fail-paths` lane, so it was not touched. The rest of the
  docstring's reasoning still holds.
- Float negation and the unary helpers still go through the out-of-line
  `myl_qbe_float_unary` call. Now that nothing canonicalizes, `-x`, `abs` and
  `sqrt` could lower inline (QBE `neg`, and an `llvm.sqrt` or `fabs` in the
  adapter). That is a separate lowering item, not part of the counterfactual.
- `float("-nan")` already produced `0xfff8…` before this lane: the old rule was
  never total at its producers either.

Results: `experiments/perf-parity-plan-20260922/results/wave3/`
(`wave3-suite.json`, `wave3-float.json`, `wave3-nbody.json`, plus their stderr
logs).
