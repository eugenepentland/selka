# Borrow-only calls and bounded stack lists

The prototype removes managed allocations from a fixed-size list passed to a
looped reader, without changing source syntax. It also improves two existing
compiler fixtures. Seven sampled parity benchmarks gain no additional stack
lists, so this evidence supports the specific optimization, not a broad
application speedup.

The frozen baseline is main `1d202d41bfff888ee91354f706cb74e860dc4b94`.
The candidate is the uncommitted `codex/borrow-call-stack-20261010` prototype on
that revision. Both host compilers use ReleaseFast and Zig
`0.17.0-dev.1683+5ceec001b`; guest programs use `--release`.

| Compiler | SHA-256 |
| --- | --- |
| Baseline | `214aa4a3900a614f9e201b1a024ed95122e993c3696c6120529dd56f7f5f73f6` |
| Candidate | `5ca393ede35337754edf06c0cf5551f491dc87037d3988ea4d410b0422e3db2d` |

[results.json](results.json) records compiler/source hashes, workload hashes,
static counts, dynamic counts, and validation results. Raw command lines,
stdout, stderr, LLVM, counting JSON, and binaries are kept privately under
`.tmp/borrow-stack-20261010/`.

## Allocation evidence

[workload.my](workload.my) repeatedly constructs 16 integers from runtime inputs
and computes a weighted checksum through `fold`. The reader contains a loop
and remains a call after Core inlining. Its counted call count is 1,000,000 in
both builds. The local control performs the fold in the constructing function;
the runtime-sized control takes its construction bound from an argument.
All three run 1,000,000 batches with seed 7 and size 16, and print the independently
calculated checksum `540397292`.

All figures below include program startup. The five startup allocations in the
three workload modes account for 320 bytes; the bounded kernel itself changes
from 3,000,000 managed block allocations to zero.

| Run | Managed blocks, baseline → candidate | Cumulative allocated bytes | Peak managed live bytes | Core release events |
| --- | ---: | ---: | ---: | ---: |
| Bounded list → loop reader | 3,000,005 → 5 | 288,000,320 → 320 | 576 → 320 | 1,000,000 → 0 |
| Local fold control | 5 → 5 | 320 → 320 | 320 → 320 | 0 → 0 |
| Runtime-sized control | 1,000,005 → 1,000,005 | 160,000,320 → 160,000,320 | 480 → 480 | 1,000,000 → 1,000,000 |
| `test/core/v_loops.my` | 7 → 5 | 416 → 288 | 128 → 128 | 9 → 7 |
| `test/core/f1_overflow.my unbounded` | 3 → 2 | 192 → 128 | 192 → 128 | 1 → 0 |
| `test/core/rc_stack.my a b c d` | 6 → 6 | 384 → 384 | 384 → 384 | 1 → 1 |
| `bench/parity/micro/alloc_churn.my` | 0 → 0 | 0 → 0 | 0 → 0 | 0 → 0 |

The bounded case also removes 2,000,000 list-growth events and 64,000,000 bytes
copied during growth. These are allocations of successive backing blocks for
1,000,000 logical lists. COW list-copy counters remain zero in all these runs.
The runtime-sized control remains managed even though this invocation passes
16: the compiler must support its other permitted argument values.

These are managed size-class bytes, not RSS or reserved heap. The cumulative
288 MB reduction is allocation traffic; the measured managed peak falls by
256 bytes. Stack space, dictionary side allocations, and text scratch are not
included. Core retain/release counts describe operations emitted before LLVM
optimization and differ from runtime retain/release function counters. See
[counter definitions](../../docs/tooling/counters.md).

## Opportunity census and validation

Static `cost --json` reports, after Core optimization, show stack-list counts
of 0 → 2 for `v_loops`, 0 → 3 for `f1_overflow`, and 1 → 2 for the new workload.
Existing `rc_stack` stays at four. All static totals are unchanged for the six
additional parity samples: `micro/records`, `micro/list_append_sum`,
`micro/dict_count`, `suite/binary_trees_recursive`, `suite/text_ops`, and
`suite/nbody`; none has a stack list in either build. The seventh parity sample,
`micro/alloc_churn`, already has one stack list and remains unchanged.

Each compiler passed 24 executions: eight cases built ordinarily, with
`--counters`, and with `--verify-facts`. Outputs and exit statuses match; all
successful runs use `MYL_CORE_LEAKCHECK=1`, have empty stderr, and counted runs
end with zero managed live bytes. The `f1_overflow huge` case retains its
expected `R_OVERFLOW` trap in all modes. That trap exits without normal cleanup
and is excluded from the successful-run leak claim.

The focused ReleaseFast gate passed 18/18 tests, including the counter
regression that compares a borrowed-call list with the already optimized local
case and checks that returned storage still allocates. The full Debug Core
suite passed all 815 tests across eight shards, and the whole-tree Guardian
gate passed 88 checks. The Debug build reports 5,705 skipped test instances
because each shard only runs its assigned tests; no test was left uncovered.

## Timing

After the shared timing lock became available, ordinary `--release` binaries
ran seven alternating-order pairs, after one discarded warmup pair. Each
process handled 5,000,000 batches, pinned to CPU 10 of an i7-12700H. No counters,
leakcheck, or fact-verification instrumentation ran during timing. Every output
matched the independent checksum.

| Mode | Baseline median seconds | Candidate median seconds | Median paired candidate/baseline | Paired ratio range |
| --- | ---: | ---: | ---: | ---: |
| Bounded | 0.195669 | 0.071919 | 0.369 | 0.358–0.383 |
| Local control | 0.041971 | 0.042065 | 0.995 | 0.973–1.072 |
| Runtime-sized control | 0.104213 | 0.104368 | 0.980 | 0.969–1.097 |

These are exploratory whole-process observations on a shared machine. The
broader Core Debug gate and unrelated selfhost work were active; admitted builds
exclude the reserved timing CPUs, but the host was not isolated (one-minute load
average 5.03 at start). The paired ratios are not confidence intervals. The
bounded case consistently improves in this run; the controls do not establish
a change. Raw samples are retained in `results.json`. Allocation evidence comes
from separate counting builds; qualification wall times are not performance
results.

## Reproduction

Keep the baseline checkout clean and apply the prototype only to the second
tree. From each tree, build the corresponding compiler with the same pinned
toolchain. The install prefix preserves its required native components:

```bash
borrow_zig=/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig
borrow_baseline_tree=/home/epentland/ai/canopy/mylang-lifetime-main-review-20261010
borrow_candidate_tree=/home/epentland/ai/canopy/mylang-borrow-stack-20261010

cd "$borrow_baseline_tree"
mkdir -p .tmp/borrow-stack-20261010/tmp
TMPDIR="$PWD/.tmp/borrow-stack-20261010/tmp" scripts/build-slot.sh build \
  "$borrow_zig" build -Doptimize=ReleaseFast \
  --prefix "$PWD/.tmp/borrow-stack-20261010/baseline"

cd "$borrow_candidate_tree"
mkdir -p .tmp/borrow-stack-20261010/tmp
TMPDIR="$PWD/.tmp/borrow-stack-20261010/tmp" scripts/build-slot.sh build \
  "$borrow_zig" build -Doptimize=ReleaseFast \
  --prefix "$PWD/.tmp/borrow-stack-20261010/candidate"

borrow_baseline="$borrow_baseline_tree/.tmp/borrow-stack-20261010/baseline/bin/mylang"
borrow_candidate="$borrow_candidate_tree/.tmp/borrow-stack-20261010/candidate/bin/mylang"
```

The script requires fresh output directories and explicitly passes the Zig
path. Run from the candidate tree; both compilers receive identical sources:

```bash
scripts/build-slot.sh build python3 experiments/borrow-stack-20261010/measure.py capture \
  --compiler "$borrow_baseline" --compiler-source-tree "$borrow_baseline_tree" \
  --zig "$borrow_zig" --output .tmp/borrow-stack-20261010/repro-base --rounds 1000000
scripts/build-slot.sh build python3 experiments/borrow-stack-20261010/measure.py capture \
  --compiler "$borrow_candidate" --compiler-source-tree "$borrow_candidate_tree" \
  --zig "$borrow_zig" --output .tmp/borrow-stack-20261010/repro-candidate --rounds 1000000
scripts/build-slot.sh build python3 experiments/borrow-stack-20261010/measure.py census \
  --compiler "$borrow_baseline" --zig "$borrow_zig" \
  --output .tmp/borrow-stack-20261010/repro-base-census
scripts/build-slot.sh build python3 experiments/borrow-stack-20261010/measure.py census \
  --compiler "$borrow_candidate" --zig "$borrow_zig" \
  --output .tmp/borrow-stack-20261010/repro-candidate-census
```

For an exploratory comparison, separately time the already-built ordinary
executables. The script takes the shared timing lock, pins each executable to
CPU 10, discards one warmup pair, then records seven pairs with alternating
order. Each invocation processes 5,000,000 batches and checks its output:

```bash
python3 experiments/borrow-stack-20261010/measure.py timing \
  --baseline .tmp/borrow-stack-20261010/repro-base/capture.json \
  --candidate .tmp/borrow-stack-20261010/repro-candidate/capture.json \
  --output .tmp/borrow-stack-20261010/repro-timing --cpu 10 --repeats 7 --rounds 5000000
```
