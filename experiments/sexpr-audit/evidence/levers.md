# Four-lever performance log

Each stage is a frozen candidate set built by one compiler revision
(`stage_bench.py build sN`), and every comparison re-measures all frozen stages
interleaved in one batch on `taskset -c 6`, so the ratios are what matter.
Raw JSON per comparison lives beside this file under `stages/`.

## Results

| candidate | s0 baseline | s1 (lever 4) | s3 (levers 1+2) | s4 (lever 3) | s3→s4 | s0→s4 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| loop (empty) | 20.09 ms | 20.09 | 7.99 | 7.32 | 1.09× | **2.74×** |
| scan (byte compare) | 119.95 | 119.90 | 96.79 | 95.20 | 1.02× | **1.26×** |
| index | 63.10 | 62.95 | 52.41 | 51.44 | 1.02× | **1.23×** |
| calls (1M) | 58.04 | 58.03 | 47.81 | 42.82 | 1.12× | **1.36×** |
| tokens | 288.87 | 288.02 | 198.64 | 191.19 | 1.04× | **1.51×** |
| parse | 301.31 | 300.47 | 209.50 | 201.11 | 1.04× | **1.50×** |
| census | 284.29 | 283.95 | 200.37 | 194.53 | 1.03× | **1.46×** |
| render | 336.66 | 336.33 | 249.01 | 242.70 | 1.03× | **1.39×** |
| total | 1472.3 | 1472.0 | 1062.5 | 1026.3 | **1.03×** | **1.43×** |

Per-stage increments (each measured against the previous stage in one batch):
lever 4 = 1.00×, lever 1 = 1.20×, lever 2 = 1.14×, lever 3 = 1.03×.

(Absolute times move with machine load between batches; every row is one
interleaved batch, so only the ratios are comparable across rows.)

All stages print byte-identical output for all eight candidates.

## Lever 4 — straight-line blocks (`QBE-BLOCKS-1`): 1.00×

Instructions now fall through into their successor's body, and an instruction
label is emitted only where a branch names it, so unreferenced labels are
stripped. The IL shrank, but wall clock did not move: QBE already promoted the
stack slots across those blocks, and the step check's own `jnz` label ended every
block anyway. Kept for the smaller IL, not for speed.

## Lever 1 — no step check without a ceiling (`QBE-STEP-ACCOUNTING-1`): 1.20×

A `ReleaseFast` executable whose build arguments name no instruction ceiling now
emits no per-instruction step check and no `max_steps` metadata: `mylang run`
without `--max-steps` and `mylang build --mode ReleaseFast`. Debug builds, shared
libraries, `mylang run --max-steps=N`, and any build argument naming a ceiling
(or the explicit `--step-accounting` a host application passes) keep exact
per-instruction accounting. A binary that cannot honor a ceiling reports
`R_NO_STEP_ACCOUNTING` when the runtime is given `--max-steps=`, naming the way to
get a bounded run, instead of silently ignoring the flag.

Instruction counts (pinned `perf stat`, same input):

| driver | s1 | s2 | ratio |
| --- | ---: | ---: | ---: |
| loop | 124.7M | 52.4M | 2.38× fewer |
| scan | 917.6M | 775.3M | 1.18× fewer |
| tokens | 2,141.5M | 1,650.3M | 1.30× fewer |
| census | 2,248.5M | 1,738.0M | 1.29× fewer |

### What the first attempt got wrong

Removing the position marker together with the step check measured 1.41× — but
the position marker is not budget metadata: `fail()` reads each frame's pc for
trap traces and `myl_qbe_fail_assert` reads it for the `assert` message. Dropping
it silently removed assert messages (`error[R_ASSERT]: native execution failed`
with the text gone) and the located-trap tests. The full gate caught it, the
marker is now emitted in every build, and the honest number is 1.20×. That
measurement is also the size of lever 2's remaining prize: the marker alone was
worth ~1.17×, so placing it only where a trap can observe it is the next stage.

## Lever 2 — position markers only where observable (`QBE-POSITION-1`): 1.14×

The stored pc is read by `fail()` (trap traces) and `myl_qbe_fail_assert` (assert
text), so an instruction needs it only when its body can reach a failure path, is
an `assert`, or is a call site (a callee's trap reads the caller's position). The
rule is derived from the emitted text rather than a hand-written op list: bodies
are delimited by the position stores themselves, and a store survives when its
body mentions `failure`. In `scan` that keeps 24 of 106 stores; a body that cannot
fail at all (`return 7`) keeps none, and its now-unused `%position` address is
dropped too.

Verified by differential diagnostics: bounds, division-by-zero and `assert`
failures produce byte-identical stderr with accounting off (markers elided) and on
(markers kept), including the caller frame's line. Port suite 79 passed, 17/17
goldens byte-identical, full gate green.

## Lever 3 — trap tests and root machinery (`QBE-PROLOGUE-1`): 1.03×

Three changes: every failure check now loads `ctx->trap` through a prologue
address (`_Static_assert(offsetof(Context, trap) == 32)`) instead of calling
`myl_qbe_failed`, so `scan` emits 13 loads and zero helper calls; a function emits
the heap pointer, the root mark and the root restore only when it has a safepoint
(an instruction whose lowering can allocate), so a rooted function that never
calls and never allocates carries none of it and pushes no roots; and an unused
`%heap` call is dropped after emission, since QBE cannot remove a call by itself.
The win is concentrated where per-call overhead dominates — the 1M-call driver
improves 1.12× — while the hot byte loops barely move, because their cost is the
per-safepoint root pushes, which this lever does not reduce.

## Where this leaves the gap

`census`, same input, against the Zig driver (22.9M instructions, 11.3M cycles):

| | s0 | s4 | Zig |
| --- | ---: | ---: | ---: |
| instructions | 2,248.5M | 1,555.3M | 22.9M |
| mylang/Zig | 98× | **68×** | 1× |

Wall clock on `census` is 1.46× better than baseline; the instruction gap is 1.45×
smaller. The four levers were worth 1.43× overall. The dominant remaining cost is
the GC safepoint: `roots()` passes the *address* of every traced local and operand
slot to `myl_native_root_push`, which pins the operand stack in memory (282 of 380
`movq` per scanned byte) and costs ~26 calls per byte in `scan`. Removing
`get_index` and plain scalar `binary_integer` from `allocates()` where the lowering
provably cannot allocate is the next lever, and it needs GC-stress verification
because a wrong answer loses a live reference.

## Status

All four levers are implemented, gated and measured, with the per-stage numbers
above. Full gate green (`zig build test`, `test-qbe`, `test-qbe-build`,
`fmt-check`), port suite 79 passed, 17/17 goldens byte-identical, and all eight
stage candidates print byte-identical output.
