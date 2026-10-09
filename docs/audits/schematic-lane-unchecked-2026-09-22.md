# Lane 2: an unchecked build policy, taken at emission time — 2026-09-22

Implements item 6 of the
[schematic parity gap audit](schematic-parity-gap-2026-09-22.md#5-what-closes-it-in-order):
the omissions the audit priced by rewriting the emitted manifest
(`experiments/schematic-parity-gap-20260922/scripts/strip_il.py`) are now a
build policy the emitter honours. Branch `perf/schematic-2-unchecked-policy`,
based on `base/schematic-20260922` (`6ee47415`).

**Headline.** `mylang build --unchecked` renders the schematic fixture
**15.8% faster** than the default policy (paired median, byte-identical
49,617-byte SVG), reaching and slightly beating the audit's manifest-strip upper
bound. The default policy's emitted manifest **and linked binary are
byte-identical** to the base compiler's (`sha256 074a4c32…`). On the matched
micro kernels the call-dominated `fib` goes from 3.5× Zig ReleaseFast to
**1.03×**.

## 1. Design

One new emission field, `native_interface.Policy.checks`, selected by
`mylang build --unchecked` / `mylang run --unchecked` and by the emitters'
internal `--drop-safety-checks`. It is orthogonal to the two accounting fields
that already existed (`step_checks`, `frame_checks`), which the three were
grouped into a `Policy` struct for.

### Omitted when `checks` is false

| guard | where | what survives |
|---|---|---|
| overflow on `+`, `-` | `qbe_scalar.checkedAddSub` | the `add`/`sub` |
| overflow on `*` | `qbe_scalar.checkedMul` | the `mul` (the four-limb high half goes too) |
| overflow on unary `-` | `qbe_scalar.neg` | the `neg` |
| narrowing integer cast | `qbe_scalar.cast` | the operand, stored unchanged — exactly the checked path for a source range that already fits |
| fixed-array index | `qbe_aggregate` `.get_index`/`.replace_index` | the index and the element address |
| list, `bytes`, `str`, dictionary `key_at`/`value_at`, `pop_at`, `pop` | `qbe_managed.requireIndexBounds`, `requirePopBounds`, `inlineIndexRead`, `textAt` | the negative-index normalization, the element address, and the runtime call that does the work |

Where a guard also produced a value the fast path uses, the value computation is
kept and only the test and its cold failure block are dropped. Where the
comparison existed *only* to feed the test (`inlineIndexRead`'s `cultl`, the
cast's range compares, `checkedMul`'s 128-bit high half) it is dropped as well —
this is the one place the emitter goes further than `strip_il.py`, which leaves
that arithmetic behind as dead code.

### Additionally omitted when the build also carries no ceiling

With `checks`, `step_checks` and `frame_checks` all false — which is what a
plain `ReleaseFast` executable asks for — `Emitter.framesLinked()` is false and
`enterFrame`/`leaveFrame` emit nothing at all: no 32-byte frame record, no link
or unlink through `ctx->active_frame`, no stack-floor test, no `_meta` store,
and no `storel N, %position`. No generated code touches the frame chain, so
`ctx->active_frame` keeps whatever the runtime itself set — it can never dangle
into a dead stack frame.

### Kept, always

Allocation failure (`myl_qbe_fail_allocation`, `myl_qbe_fail_list_capacity`),
the memory budget, GC roots and everything the collector traces, host-call and
capability validation, `assert`, arena escape checks, shift-count range tests,
dictionary missing-key, list concurrent-modification, `R_TEXT_SCALAR`, and the
division-by-zero and signed `MIN // -1` tests.

**The division decision, stated.** The audit's `overflow` class contains
`myl_qbe_fail_division` and the `MIN // -1` quotient trap: 8 static sites in
this program out of that class's 736. Both guard an instruction that *faults the
hardware*: dropping them would replace a named `R_INT_DIVISION` /
`R_INT_OVERFLOW` with `SIGFPE`, which is neither faster nor more useful. They
stay, and the measurement below shows the class was worth −0.2% anyway.

### Refusals

| asked for | result |
|---|---|
| `mylang test … --unchecked` | exit 2, `mylang test: --unchecked is refused: tests need the traps it removes…` |
| `mylang build --unchecked --mode Debug` | exit 2, usage (`error.InvalidBuildArguments` from `qbe_build_options.validate`) |
| `mylang build --unchecked --library` | exit 2, usage |
| `--unchecked` with `--max-steps` / `--max-frames` / `--step-accounting` | **supported**, not refused: the frame protocol and the accounting that enforces the ceiling are kept and only the value guards go |
| an unbounded unchecked binary given `--max-steps=` at run time | unchanged: `R_NO_STEP_ACCOUNTING`, exit 1 |

The supported-combination decision is deliberate: step accounting and the value
guards are independent, a host that bounds its guest still wants the ceiling
honoured, and refusing the combination would have made `--unchecked` useless to
exactly the callers who most want it.

### What is no longer detected

Under the policy each of these is undefined behaviour: integer overflow on add,
subtract, multiply and negate; a narrowing cast out of range; an out-of-range
index on any container; `pop()` on an empty list; runaway recursion
(`R_FRAME_LIMIT` becomes `SIGSEGV`). A trap that *does* still fire reports no
frames and no `assert` message text, because there is no frame record to read
them from. Heap-frame byte accounting is also lost, for the same reason.

## 2. IL sites removed

`emit-project-qbe src/schematic/guest/main.my --drop-debug --no-cache
--drop-step-checks --drop-frame-checks [--drop-safety-checks]`, counted over
every unit's `il`:

| site | default | unchecked |
|---|---:|---:|
| `myl_qbe_fail_overflow_op` | 703 | 4 |
| `myl_qbe_int_neg` | 29 | 0 |
| `myl_qbe_fail_division` | 4 | 4 |
| `myl_qbe_fail_cast` | 290 | 0 |
| `myl_qbe_fail_index_bounds` | 86 | 0 |
| `myl_qbe_fail_normalized_index_bounds` | 225 | 0 |
| `myl_qbe_fail_array_bounds` | 2 | 0 |
| `myl_qbe_fail_allocation` | 65 | **65** |
| `myl_qbe_fail_list_capacity` | 21 | **21** |
| `myl_qbe_fail_frame` (floor + depth tests) | 82 | 0 |
| `_meta` stores (one per linked frame) | 113 | 0 |
| `alloc8 32` (frame records among other 32-byte slots) | 713 | 600 |
| `%position` mentions (113 definitions + 1,907 stores) | 2,020 | 0 |
| **IL lines** | **111,866** | **97,421** (−12.9%) |

1,331 of the audit's 1,425 guarded sites are gone: the 86 allocation/capacity
sites are kept by design and 8 division sites are kept for the reason above.
The per-class totals reproduce the audit's counts exactly (736 overflow, 290
cast, 313 bounds, 86 allocation).

For contrast, the manifest-stripped `s-all` arm has 108,076 IL lines: replacing
a `jnz` with a `jmp` leaves the comparison and the failure block behind. Taking
the omission at emission time removes 14,445 lines instead of 3,790, which is
why it is the faster of the two.

Linked binary: 1,103,704 bytes default, **494,816** unchecked, 492,000 `s-all`.

## 3. Measurement

Harness `experiments/schematic-parity-gap-20260922/scripts/{build_arms,bench_svg}.py`
(`build_arms.py` gained an `"unchecked": true` arm option;
`spec-unchecked.json` is the arm spec). Compiler built `-Doptimize=ReleaseFast`
into the lane worktree's `.tmp/install`. Fresh process per sample, `taskset -c
4`, three warmups, 31 interleaved randomized rounds, three inputs, **every run's
SVG hashed and required to equal the Zig port's**. Ratios are paired bootstraps
over rounds.

**Caveat, stated up front: the machine was heavily loaded by three other lanes
throughout (load average 31–40 on 20 cores).** Absolute times are roughly 1.8×
what the audit measured on a quiet machine — the audit's `zig-o3` fixture time
is 1.31 ms against 2.09 ms here. Paired ratios between interleaved arms are the
transferable numbers; the integrator should re-measure absolutes on a quiet
machine.

### Fixture, run 1 (seed 20260922)

| arm | fixture, ms | × zig-o3 | vs default |
|---|---:|---:|---:|
| `zig-o3` | 2.086 | 1.00 | — |
| `rust-o3` | 2.424 | 1.16 [1.07, 1.18] | — |
| `before-gc-lto` (base compiler, default policy) | 4.608 | 2.21 | −0.3% [−3.1%, +2.9%] |
| `gc-lto` (this compiler, default policy) | 4.622 | 2.22 | — |
| **`unchecked`** | **3.892** | **1.87** | **−15.8% [−17.3%, −12.8%]** |
| `s-all` (audit's manifest strip, the upper bound) | 3.950 | 1.89 | −14.5% [−17.4%, −11.4%] |

All three inputs, both runs, paired against this compiler's default policy:

| input | run 1 unchecked | run 1 `s-all` | run 2 unchecked | run 2 `s-all` |
|---|---:|---:|---:|---:|
| fixture | −15.8% | −14.5% | −15.9% | −14.1% |
| changed-net | −16.3% | −15.3% | −19.3% | −18.4% |
| changed-value | −14.6% | −13.5% | −17.1% | −17.8% |

**Acceptance.**

- *Default policy unchanged in time and bytes*: the default-policy arm's
  emitted manifest (`sha256 10ec89bc…`) and linked binary
  (`sha256 074a4c32…`, 1,103,704 bytes) are byte-identical to the audit's
  base-compiler build. Timing: −0.3% / +0.8% / +0.5% across the three inputs in
  run 1, intervals containing 1.0.
- *Unchecked ≥ 12% faster than default*: 14.6–19.3% across six
  input×run cells, every interval below unity in run 1.
- *Unchecked reaches the ladder's upper bound*: it is at or faster than `s-all`
  in five of six cells.

### Micro kernels

`experiments/perf-parity-audit-20260921/micro/run.py` still runs; it gained an
`o3-lto-unchecked` arm. Its rule that every arm of a kernel must print a
byte-identical checksum is the correctness check: all four kernels reported
`agrees=True` with the unchecked arm included. 21 rounds, CPU 4, same loaded
machine.

| kernel | default `o3-lto`, ms | `o3-lto-unchecked`, ms | change | `zig-fast` | `zig-safe` |
|---|---:|---:|---:|---:|---:|
| `intloop` | 186.4 | 188.2 | +1.0% | 197.3 | 205.6 |
| `fib` | 267.7 | **78.2** | **−70.8%** | 75.6 | 134.1 |
| `list_records` | 123.9 | 114.1 | −7.9% | 90.5 | 96.7 |
| `bytes_scan` | 132.8 | 113.3 | −14.7% | 116.3 | 112.5 |

`fib` is the frame protocol in isolation — naive recursion, nothing else — and
it goes from 3.54× Zig ReleaseFast to 1.03×, confirming the audit's attribution
of the frame protocol as the dominant safety cost. `intloop` is a loop-carried
dependency chain where the checks are free, and the policy changes nothing.
(An 11-round first pass put `bytes_scan` at +12%; the 21-round re-run under the
same load puts it at −14.7%, so the first figure was contention.)

## 4. Gate

All through `ZIG_LOCAL_CACHE_DIR=… ~/capbuild ./zigw …`.

| step | exit | note |
|---|---:|---|
| `zig build test --summary all` | 1 | **identical to the base commit**: the same 50 named test failures, the same 2 doctest failures, the same `test-native-boundary` driver failure |
| `zig build test-qbe --summary all` | 1 | **identical to the base commit**: `native_test_wire` receipt reuse, and `golden_parity` with the same 11 mismatches |
| `zig build test-qbe-build --summary all` | 0 | 69 + 2 passed |
| `zig build fmt-check` | 0 | |

`base/schematic-20260922` is not green. The two failing steps were re-run on
the base commit inside this same worktree and the failure *sets* diff clean
(`diff` of the sorted `error: '…' failed:` lines is empty; the golden-mismatch
lines are identical). The failures are a half-landed `mutates(...)` → `mut`
migration (`E_REMOVED_SPELLING`) plus a golden corpus that cannot replay; both
are outside this lane and the two doctest files are already being edited in the
main checkout. Test totals moved 1,452 → 1,456 (`src/root_test.zig`) and
163 → 165 (`test/integration.zig`): the six tests this lane adds.

Guardian is green: the policy commit installs through `zig build`, which runs
`guardian-check run-all` as a blocking gate.

## 5. Tests added

| test | root | covers |
|---|---|---|
| `the unchecked policy emits no overflow cast or bounds guard and no frame record` (`// spec:`) | `src/qbe_test.zig` | every fail-site class and the `_meta`/`%position` stores are absent, and present under the default policy |
| `the unchecked policy keeps allocation failure division by zero and the collector` | `src/qbe_test.zig` | allocation failure, `%heap`, and both division guards survive |
| `an unchecked build that was given a ceiling keeps the accounting that enforces it` | `src/qbe_test.zig` | the supported bounded combination |
| `a release build accepts --unchecked and Debug and library builds refuse it` | `src/qbe_build_options.zig` | parse, usage text, both build refusals, the `--` boundary |
| `an unchecked executable computes the same results and refuses a runtime ceiling` | `test/integration.zig` | end-to-end: identical stdout and exit status under both policies; `R_NO_STEP_ACCOUNTING` |
| `the unchecked policy is refused where its traps are still needed` | `test/integration.zig` | the `mylang test` refusal by name, and the Debug refusal |

The default policy's IL being unchanged is checked directly against the base
compiler by hash rather than by a golden file: `emit-project-qbe` output for the
schematic guest (bounded and unbounded) and for five other programs is
byte-identical before and after.

## 6. Known limits

- The policy is whole-program. It is selected once, travels in the emitted
  manifest, and is part of the run-manifest cache identity
  (`native_run_cache.Identity.checks`); object-cache entries cannot collide
  because they are content-addressed on the IL that differs.
- `--select-file` (the native-test planner's selective emission) ignores the
  policy, as it already ignored `--drop-debug`/`--drop-step-checks`. It cannot
  be reached with `--unchecked`, because `mylang test` refuses the flag.
- `mylang run --unchecked` on a single file already dropped frame accounting by
  default, so the flag changes only the value guards there unless a project run
  is involved; the table above is measured on `mylang build`.
- Absolute times were taken on a loaded machine (see §3). The per-phase
  attribution of the audit's §3.2 was not repeated for this lane.
- `s-all` remains the right upper bound for the *check* classes, but it is no
  longer an upper bound overall: emission-time omission removes 3.8× more IL and
  is measurably faster.
