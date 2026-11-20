# Checked arithmetic → LLVM overflow intrinsics — wave 4, lane `perf/checked-arith-intrinsics` — 2026-09-23

Implements the "fix the lowering" half of plan §4.4/§5.2 from
[`performance-parity-plan-2026-09-22.md`](performance-parity-plan-2026-09-22.md),
and the "checked `+` in `fib`" item left by
[`frame-return-map-2026-09-22.md`](frame-return-map-2026-09-22.md#what-is-left).
Base: `base/parity-checked-add` (`625420ce`, the integration branch with the
parity plan merged, including `QBE-NORETURN-1` and `QBE-FRAMEMAP-1`). Result
JSONs, scripts and the trap corpus are under
[`experiments/perf-parity-plan-20260922/results/wave4/`](../../experiments/perf-parity-plan-20260922/results/wave4/)
(`checkedadd-*`, `traps-checked/`).

## Result

- **Every checked 64-bit `+ - *` the suite executes now reaches LLVM as
  `llvm.{s,u}{add,sub,mul}.with.overflow.i64`**, and the machine code is the
  operation and one flag branch: `add; jo`, `sub; jo`, `imul; jo`, `add; jb`,
  `sub; jb`, `mul; jo`. Before, a signed add was `add; mov; xor; mov; xor;
  test; js` and a 64-bit multiply was a four-limb high product (about twenty
  instructions) plus a compare.
- **The mechanism is in the LLVM adapter only.** It matches the frontend's
  existing formulas by value and proves nothing new. The IL, QBE's assembly and
  every non-LLVM path are unchanged. `LLVM-OVERFLOW-INTRINSIC-1`.
- **Trap output is byte-identical**: code, message, operands, width, the `in f
  at file:line` trace, the `MYLANG-TRAP` record and the exit status.
  - Base against lane: 195 of 195 program × mode pairs identical (39 programs
    × LLVM LTO, LLVM without LTO, `--gc-stress`, `--max-steps=5`, QBE).
  - Every width and operation at its boundary: 56 of 56 runs identical across
    the base's LLVM build, the lane's LLVM build and QBE.
  - Pinned in the gate by a new CLI test.
- **Numbers** (loaded machine, CPU 0, 11 rounds, two runs; tables below):
  - thirteen-program geomean **−4.3% / −5.1%** against the base
    (0.957 [0.940, 0.965] and 0.949 [0.919, 0.973]);
  - `spectral_norm` **−28% / −35%** (1.60× → 1.15× Zig), the same at a second
    code placement;
  - `raytrace` −6%, `sieve` −4 to −5%, `fannkuch_redux` −5.5%, `records` −11 to
    −14%;
  - `fib` 2.75× → **2.09–2.14×** Zig, but only because the base happened to
    sit on a slow code placement. At five of six placements the lane is the
    same as the base (within ±1%). See *fib*.
- **What checks cost now.** Checked against `--unchecked` on the geomean:
  **1.09–1.10×**, down from 1.14–1.16×. Zig ReleaseSafe costs **1.14–1.16×**
  against ReleaseFast on the same programs. `--unchecked` also drops the bounds
  and cast checks, so this ratio is an upper bound on what arithmetic checks
  cost.
- **Acceptance**:

  | criterion | verdict |
  |---|---|
  | residual check cost ≤ 10% | met: 1.092 and 1.102, below Zig's own 1.14–1.16 |
  | `spectral_norm` moves toward its `--unchecked` time | met: 1.58× → 1.13× of it |
  | traps byte-identical | met |
  | `fib` ≤ 1.3× Zig | **not met, and it cannot be met while the add is checked**. See *fib*. |
  | nothing slower | met, with one exception: `dict_count` is +2.3% [1.2, 3.9]. Its only code change is in a cold 1000-iteration loop, and the change is an improvement. See *Regressions*. |

- **Gate:** `gate_diff.py` against the coordinator's gate of the base
  (`frame-*.log`) shows **no new failure in any step**. `test`, `test-qbe`,
  `test-qbe-build`, `test-schematic`, `test-byte-io` and `fmt-check` are all
  green, and so is Guardian. `test_adapter.py` passes 31 of 32 tests; the one
  failure is the known registry test, which fails on the base too.

## The shapes

Checked arithmetic is emitted in `src/qbe_scalar.zig`. A census of every
`myl_qbe_fail_overflow_op` branch in the fast-protocol IL covers 11 suite
programs, 9 micro-kernels and the width probe
(`checked_census.py`, `checkedadd-census.txt`). It finds these shapes:

| shape (emitter function) | flag | sites | now |
|---|---|---:|---|
| signed 64-bit add (`checkedAddSub`) | `((a ^ r) & (b ^ r)) < 0` | 127 | `sadd.with.overflow` |
| signed 64-bit sub | `((a ^ b) & (a ^ r)) < 0` | 27 | `ssub.with.overflow` |
| unsigned 64-bit add | `r <u a` | 22 | `uadd.with.overflow` |
| unsigned 64-bit sub | `a <u b` | 1 | `usub.with.overflow` |
| signed 64-bit mul (`checkedMul`) | `unsignedHigh(a, b) − (a<0 ? b : 0) − (b<0 ? a : 0) != r >> 63` | 18 | `smul.with.overflow` |
| unsigned 64-bit mul | `unsignedHigh(a, b) != 0` | 1 | `umul.with.overflow` |
| signed 64-bit add/sub with a literal operand (`constantAddSub`) | `a > MAX − k` (one compare) | 126 | unchanged: already one compare, and LLVM drops it when a loop bound proves it |
| 8/16/32-bit `+ - *` (`checkedAddSub`, `rangeCheck`) | `r < min or r > max` on the exact 64-bit result | 18 (probe only) | unchanged, see below |
| signed `MIN // -1` (`checkedDivRem`) | `a == MIN and b == -1` | 5 | unchanged: not an overflow of `+ - *` |

The `uadd` sites in programs that only use `int` are unsigned adds the
compiler generates itself, for example the size arithmetic after a checked
conversion to `u64` in `sieve`'s list comprehension. They are the same
formula, so they are matched the same way.

**The narrower widths are left alone, deliberately.**

- Their flag tests whether the exact 64-bit result lies in the width's range.
- `llvm.sadd.with.overflow.i32` on truncated operands agrees with that flag only
  if both operands already lie in the width. The emitter maintains that
  invariant, but the IL cannot show it, so a rewrite would rest on an unproved
  fact.
- It would also buy nothing. LLVM already lowers the range test to one compare,
  `add; movslq; cmp; jne` for `i32`, or `imul; cmp $256; jae` for a `u8`
  multiply. The intrinsic's `add r32; jo; movslq` is the same length.

The literal form is left alone for the same reason: it is already one compare,
and LLVM removes it outright when a loop bound implies it (`fib`'s `n - 1`
after `n < 2` has no check at all).

## The mechanism

Option (b) of the brief: the adapter recognizes the emitter's formulas. It is
done by **value**, not by text, so it is exact without being brittle.

`llvm_emit.OverflowChecks` walks each block once, in order:

1. It evaluates the block symbolically.
   - A pure `l` operation the formulas use (`add sub mul and xor shr sar neg
     csltl cultl cnel`) becomes the tuple `(opcode, operand values…)`.
   - A literal becomes `("const", bits mod 2^64)`.
   - A value from another block becomes `("entry", name)`.
   - Anything else (a load, a call, a phi, a `w` operation, `copy`) becomes a
     leaf equal only to itself.

   Temporaries are mutable cells in this IL, and the evaluation follows each
   name's latest definition. A reassignment between the operation and the flag
   therefore makes the values differ.
2. At every `add`/`sub`/`mul`, it builds the frontend's formulas over that
   operation's value (`overflow_formulas`, which mirrors
   `checkedAddSub`/`checkedMul`/`unsignedHigh` term for term) and records
   `formula → (instruction, stem)`. An `add` of an object address is skipped,
   because it is lowered as a `getelementptr`.
3. A later definition whose value equals a recorded formula is a flag.

The Emitter then:

- lowers the arithmetic instruction to `call {i64, i1} @llvm.<stem>.with.overflow.i64`.
  The first result is the instruction's value: the wrapped result, bit for
  bit, as `add`/`sub`/`mul` produced it.
- stores `zext` of the second result into the flag's slot instead of
  computing the compare. The old xor/and/limb instructions are still emitted;
  nothing reads them any more, and LLVM deletes them.

**Why it is sound.** Each formula equals the intrinsic's overflow bit for
*every* pair of 64-bit operands. These are identities, not facts about ranges.

- `test_adapter.CheckedArithmeticTests.test_the_formulas_are_identities_on_every_input`
  evaluates each formula tree on 20 000 random pairs plus the full grid of 34
  boundary values, and compares it against big-integer overflow.
- A C harness compiles all six shapes through the adapter and checks result,
  trap and trap operands against `__builtin_*_overflow` on a 23 × 23 boundary
  grid.
- Near misses are not rewritten: operands swapped, a reassigned operand, the
  wrong compare, a `w` operation or compare, a range test, and a signed product
  off by one shift.

Nothing about the check is assumed: the branch, the cold block, the fail call
and its `dbgloc` are untouched. That is why the trap and its frame-map position
cannot change. The fail call's operands are still the operands (`%a`, `%b`),
not the intrinsic's outputs.

**Why not option (a).** An explicit marker in the IL (a pseudo-call, or a
`# myl-…` comment) would have to stay valid QBE and leave QBE's output
unchanged. It would add a second statement of each check that could disagree
with the first. The value match needs no IL change at all, and a disagreement
cannot produce a wrong rewrite; it only means no rewrite.

**Drift protection.** The price of (b) is that an emitter change could
silently stop the match. A new Zig test pins the six shapes in the fast
protocol, with temporaries canonicalized:
`src/qbe_test.zig` "a checked 64-bit add, subtract and multiply emit the exact
flag formulas the LLVM adapter lowers to overflow intrinsics". It names the
adapter functions that must change with it.

## Trap evidence

- **Corpus, base against lane**
  (`traps-checked/compare.log`, `compare.py` from the frame-map lane):
  - 39 programs: the 21 `trapdiff` fixtures, the frame-map lane's 16 cases,
    and 4 new ones (a `u64` add four frames deep inside a loop, a signed
    subtract inside a callee LLVM inlines into a loop, a signed multiply at the
    bottom of a recursion, an unsigned borrow after an unsigned multiply);
  - 5 modes each: `build` (LLVM LTO), `nolto`, `gc` (`--gc-stress`), `steps`
    (`--max-steps=5`, the refusal) and `qbe`.

  **195/195 identical** in stdout, stderr and status.
- **Every width at its boundary** (`traps-checked/boundaries.{my,py,log}`):
  - widths `i8`…`i64` and `u8`…`u64`, each with add, sub and mul;
  - operands read from the command line, so nothing folds;
  - the last in-range operand and the first overflowing one.

  56 runs × {base LLVM, lane LLVM, QBE}: **all identical**.
- **In the gate:**
  - `test/integration.zig` "checked arithmetic at every width reports the same
    result and trap from the LLVM overflow intrinsics as from QBE"
    (`// spec: LLVM-OVERFLOW-INTRINSIC-1`) builds the boundary program with
    the release default (LLVM LTO) and with QBE. For all 28 boundaries it
    requires the extreme on stdout for the in-range operand, and `R_OVERFLOW`
    with the exact `(op: left …, right …, width …)` detail for the next one.
    Both backends must match byte for byte. It also pins one trap in full:
    three frames and the record.
  - `tests/lang/checked_arithmetic.my` (`module` + `main`) runs each width's
    extremes, and `wrapping_*`/`saturating_*` past them, under `mylang test`.
    It passes under the QBE default and under `--mode ReleaseFast` (LLVM).

## Numbers

Loaded machine: load average 5–13, other agents building. CPU 0, wall time,
arms shuffled in every round, 11 rounds per run. Ratios are medians of
per-round paired ratios with 95% bootstrap intervals.

Arms:

- `before` is the base compiler with the stock adapter, built into the same
  work directory;
- `lane` is the same compiler with this adapter;
- `unchecked` is `--unchecked`.

The table is run r2 (`checkedadd-r2-suite.json`, CPU 1 sibling busy 24%). The
last column is run r1 (`checkedadd-r1-suite.json`, sibling busy 28%, the gate
running alongside).

| program | before/Zig | lane/Zig | unchecked/Zig | Zig safe/fast | before/unchecked | lane/unchecked | lane/before [95% CI] | lane/before (r1) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| binary_trees | 1.48 | 1.53 | 1.37 | 1.11 | 1.04 | 1.06 | 0.981 [0.959, 1.025] | 1.024 |
| spectral_norm | 1.60 | 1.15 | 1.01 | 1.32 | 1.58 | 1.13 | **0.722** [0.681, 0.735] | 0.654 |
| mandelbrot | 1.02 | 1.02 | 1.01 | 0.99 | 1.00 | 1.01 | 1.004 [0.993, 1.015] | 0.992 |
| raytrace | 1.48 | 1.34 | 1.25 | 1.03 | 1.17 | 1.08 | 0.933 [0.856, 0.957] | 0.944 |
| knucleotide | 3.41 | 3.41 | 3.37 | 1.13 | 1.01 | 1.01 | 1.011 [0.996, 1.017] | 0.968 |
| text_ops | 4.91 | 4.43 | 4.53 | 1.00 | 1.01 | 0.98 | 1.002 [0.865, 1.027] | 0.989 |
| sort_builtin | 0.53 | 0.53 | 0.52 | 1.16 | 1.02 | 1.01 | 0.987 [0.974, 1.018] | 0.981 |
| sort_quick | 1.28 | 1.26 | 1.09 | 1.15 | 1.17 | 1.15 | 0.983 [0.970, 0.998] | 0.975 |
| sort_records | 0.29 | 0.28 | 0.28 | 1.16 | 1.03 | 1.01 | 0.982 [0.966, 1.006] | 0.985 |
| sieve | 1.79 | 1.70 | 1.38 | 1.35 | 1.29 | 1.22 | 0.952 [0.945, 0.967] | 0.961 |
| nbody | 1.76 | 1.75 | 1.64 | 1.00 | 1.07 | 1.07 | 0.994 [0.989, 1.004] | 0.997 |
| fannkuch_redux | 1.21 | 1.15 | 0.95 | 1.18 | 1.28 | 1.21 | 0.945 [0.916, 0.952] | 0.943 |
| matmul | 3.79 | 3.83 | 2.84 | 1.57 | 1.27 | 1.31 | 0.990 [0.940, 1.012] | 0.988 |
| **geomean** | **1.48** | **1.41** | **1.28** | **1.15** | **1.14** | **1.09** | **0.957** [0.940, 0.965] | **0.949** [0.919, 0.973] |

**The residual cost of checks** is the lane/unchecked geomean:

| run | lane/unchecked | before/unchecked | Zig safe/fast |
|---|---:|---:|---:|
| r2 | 1.092 [1.084, 1.108] | 1.138 | 1.155 |
| r1 | 1.102 [1.093, 1.121] | 1.157 | 1.140 |

Where the cost remains:

- `matmul` (1.31) and `fannkuch_redux`/`sieve` (1.21–1.22) keep list bounds
  checks in their inner loops, which `--unchecked` also drops.
- `spectral_norm` keeps `(i + j) * (i + j + 1)` checked, now `add; jo; imul;
  jo`. That is the range-fact residue the plan names.

**Placement check** (`checkedadd-placement-suite.json`: each program built
from two source paths of different length, which moves the code, 9 rounds,
lane/base):

| program | placement 1 | placement 2 |
|---|---:|---:|
| `spectral_norm` | 0.722 | 0.721 |
| `records` | 0.881 | 0.902 |
| `raytrace` | 0.952 | 0.953 |
| `sieve` | 0.994 | 0.933 |
| `fannkuch_redux` | 0.932 | 0.986 |

The `spectral_norm`, `records` and `raytrace` gains are the code, not the
layout.

### Micro-kernels (`checkedadd-r{1,2,3}-micro.json`)

| kernel | before/Zig | lane/Zig | unchecked/Zig | Zig safe/fast | lane/before r2 | r1 | r3 (21 rounds) |
|---|---:|---:|---:|---:|---:|---:|---:|
| fib | 2.75 | 2.09 | 1.00 | 1.85 | 0.761 | 0.778 | 0.767 [0.760, 0.774] |
| calls | 1.03 | 1.02 | 1.05 | 0.99 | 0.988 | 1.002 | — |
| intloop | 0.93 | 0.95 | 0.95 | 1.03 | 1.008 | 1.004 | — |
| float_loop | 1.01 | 1.01 | 1.02 | 1.01 | 1.028 | 1.001 | — |
| list_records | 1.48 | 1.47 | 1.21 | 1.10 | 0.966 | 0.956 | 0.954 [0.949, 0.959] |
| records | 1.15 | 0.97 | 1.04 | 0.96 | 0.863 | 0.889 | 0.889 [0.881, 0.895] |
| dict_count | 0.92 | 1.07 | 1.01 | 1.17 | 1.142 (sibling 54% busy) | 1.025 | **1.023** [1.012, 1.039] |
| bytes_scan | 0.97 | 0.94 | 1.04 | 1.03 | 1.007 | 0.991 | — |
| list_append_sum | 1.26 | 1.28 | 1.29 | 1.05 | 0.950 | 0.970 | — |

r2's micro batch ran with CPU 1 54% busy, and its wide intervals
(`dict_count`, `bytes_scan`) are that. r3 re-measured the kernels that moved,
with 21 rounds.

### fib

`fib`'s checked add is now `add; jo` instead of `add; mov; xor; mov; xor;
test; js`. The −23% in the batch is not the add, though. It is code
placement:

- `checkedadd-fib-placement.json` builds `fib` from six source paths.
- The function lands at three offsets (`…90`, `…a0`, `…b0`).
- At `…90` and `…a0`, base and lane run the same: lane/base 0.983–1.000,
  about 82 and 75 ms.
- At `…b0`, the base runs at 110 ms and the lane at 84 ms (0.766). The
  longer xor sequence is what makes the base sensitive to that placement; the
  exact front-end cause was not isolated.
- The bench's source path lands on `…b0`, which is where both batches'
  "before" came from.

So the lane removes a placement cliff, and at a good placement it gains
nothing on `fib`. The add's result is on the return path, and the two
recursive calls dominate.

**Why `fib` ≤ 1.3× Zig is out of reach while the add is checked:**

- `--unchecked` runs at 0.98–1.00× Zig because LLVM turns `fib(n-1) +
  fib(n-2)` into accumulator recursion. That makes one call per level instead
  of two (visible in the unchecked binary: a loop around a single `call`).
- Reassociating a *checked* add would move the trap to a different partial
  sum, so LLVM rightly does not do it.
- Zig ReleaseSafe pays the same: 1.85–1.96× on this kernel.

The lane's `fib` is 2.09–2.14× Zig (1.07–1.13× Zig ReleaseSafe). The rest of
the gap to ReleaseSafe is the stack-floor compare and the context argument the
frame-map lane left.

### Regressions

`dict_count` +2.3% [1.2, 3.9] (r3; r1 +2.5%) is the one consistent slowdown,
and it is layout:

- Its hot loop (`keys[(i * 7919) % 1000]`, dictionary get and set) compiles
  to the same instructions at the same address in both binaries (`imul
  $0x1eef` at `0x1013980`; LLVM already knew that multiply cannot overflow).
- The only code difference is in the 1000-iteration final loop. There a
  23-instruction `mulx`/`sar`/`xor` sequence became `imul; jo; add; jo`.
- That shortened the guest code by 48 bytes and moved every runtime function
  linked after it, including the dictionary helpers the hot loop calls.

`binary_trees` reads +2.4% in r1 and −1.9% in r2. Both intervals contain 1.

## Tests

- `experiments/llvm-backend/test_adapter.py` — `CheckedArithmeticTests` (5 tests):
  - each shape emits its intrinsic, the flag is the intrinsic's bit, and the
    fail call is untouched;
  - each shape compiles to the operation and one branch, with no limb shifts
    left;
  - the C harness checks results and traps against `__builtin_*_overflow`;
  - near misses are not rewritten, and the sticky protocol is matched too;
  - every formula is an identity on all inputs.

  The file runs 32 tests: 31 pass, and the one failure is the known
  `test_benchmark_runtime_registry_is_complete`, which fails on the base too.
- `src/qbe_test.zig` — the emitter's six formulas, pinned
  (`// spec-case: LLVM-OVERFLOW-INTRINSIC-1`).
- `test/integration.zig` — the width × op boundary test with the pinned trap
  (`// spec: LLVM-OVERFLOW-INTRINSIC-1`).
- `tests/lang/checked_arithmetic.my` — width extremes, `wrapping_*` and
  `saturating_*` (`# spec-case`).
- `SPEC.md` `[LLVM-OVERFLOW-INTRINSIC-1]`; `docs/tooling/native-build.md`
  (*What the LLVM backend is allowed to assume*) says what the adapter does
  and why it assumes nothing.

## Gate

Final tree `9a27042d` (the code; this report and the evidence were added after
it). `gate_diff.py` against the coordinator's `frame-*.log`, logs in the lane's
`.tmp/gate/ca-*.log`:

| step | verdict |
|---|---|
| `zig build test` | green; base 0 failures, lane 0: **no new failure** |
| `zig build test-qbe` | green; no new failure |
| `zig build test-qbe-build` | green |
| `zig build test-schematic` | green |
| `zig build test-byte-io` | green |
| `zig build fmt-check` | green |
| Guardian | 88/88 in every step and in the whole-tree pre-commit run. The first commit attempt was refused for an untested `errdefer` in a test helper. The helper now uses an arena. |

## Left

- **`u64` trap details print the operands as signed.** An overflowing
  `18446744073709551614u64 + 2u64` reports `(add: left -2, right 2, width
  64)`, in every backend and on the base, so this lane did not change it.
  `myl_qbe_fail_overflow_op` formats `left`/`right` as `int64_t` whatever the
  signedness. Fixing it changes trap text, so it is left for a lane that owns
  that contract.
- **`fib`** needs range facts or reassociation-safe accumulation to go
  further. Neither is a lowering fix.
- **`spectral_norm`'s residue** is its `(i + j) * (i + j + 1)` check. Plan §5.2's
  range facts from `range()` induction variables would remove it.
- **`test_adapter.py` is still not in the gate.** The Zig shape test and the
  CLI test are, and between them they catch emitter drift and wrong results.
  An adapter regression that silently stopped matching would show up only in
  the benchmark.
