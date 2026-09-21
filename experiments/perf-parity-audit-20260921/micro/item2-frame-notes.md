# Item 2 — taking the frame protocol off the call path (working notes)

Branch `perf/roadmap-2-frame-off-call-path`, rebased onto `c59cd230`.

## What landed

* `f07f1eb2` **perf: deliver qbe traps by non-local exit instead of a per-call
  sticky test.** The guest-stack trampoline arms a `setjmp` before the entry
  runs; the first failing `myl_qbe_fail_*` helper builds the trace on the
  generated stack and `longjmp`s to it. A build that dropped both accounting
  modes emits no `loadl %trap` after a call. Accounting builds keep the flag
  test and the sticky path, and the direct C entry points and budget parsing
  keep the sticky behavior because no jump is armed for them. Runaway recursion
  on the fast path is still `R_FRAME_LIMIT` through the unchanged floor guard.
* `6aebe574` **fix: restore the LLVM adapter's LTO-object branch.** Needed to
  measure the LTO arm; it is a strict subset of item 1's `f16d9b60`
  (`MYLANG_QBE_LLVM_EMIT_LTO_OBJECT` handling only), so integration should keep
  item 1's copy and drop this one.

`9a30d143` (depth-indexed frame slots replacing the record) was implemented,
measured and **reverted in `416ae04e`**; `c63c8311` (the assert-message fix it
needed) is reverted in `d8f45264`.

## `fib` medians

`fib(36)`, 29,860,703 calls, `taskset -c 6`, 3 warmups + 21 rounds, fresh
processes, stdout to `/dev/null`, arm order shuffled inside each round. Both
runs used the same compiler build path; the adapter LTO fix above was applied
to the baseline as well.

```bash
export ZIG_GLOBAL_CACHE_DIR=$PWD/.zig-cache-global
python3 experiments/perf-parity-audit-20260921/micro/run.py --only fib \
  --rounds 21 --warmups 3 --cpu 6 --work .tmp/rm2/final2-work \
  --json .tmp/rm2/results-final2.json --markdown .tmp/rm2/results-final2.md
```

| arm | baseline `c59cd230` | ratio | after (`f07f1eb2` + adapter) | ratio |
| --- | ---: | ---: | ---: | ---: |
| zig-fast | 43.4 | 1.00x | 32.1 | 1.00x |
| zig-safe | 83.6 | 1.93x | 61.3 | 1.91x |
| mylang-qbe | 161.2 | 3.71x | 119.9 | 3.74x |
| mylang-o3 | 149.5 | 3.44x | 115.0 | 3.59x |
| mylang-o3-lto | 152.7 | 3.52x | 106.9 | 3.34x |

The two runs were not on an equally quiet machine (`zig-fast` moved 43.4 ms to
32.1 ms), so read the ratios: the change is **perf-neutral on `fib` within
noise** (qbe +0.8%, o3 +4.3%, o3-lto -5.1% relative). `fib <= 1.9x Zig
ReleaseFast` on LLVM is **not met**.

## Why the record replacement lost

The audit priced "no record + no floor check" at LLVM 17.64 -> 11.82 ms by
deleting the IL outright (its patched binary cannot report traps). Replacing the
record while keeping the trace costs more than it saves on this shape:
`alloc8 32` is a compile-time stack adjustment, so the record's per-call work is
one `ctx->active_frame` load, one `prev` store, one metadata store, one zero
store and one `active_frame` store. A depth-indexed array needs a `ctx->frames`
load, a `frame_slots` load, an `imul $16`, an index add, the metadata store, the
zero store, a `frames+1` store and a matching depth decrement on return — plus
the floor guard that was never removed. Direct timings of the built binaries
were 0.22-0.25 s versus 0.10-0.12 s, and the harness put the LLVM arms at
~5.9x. The measured verdict is in the commit message of `416ae04e`.

## Trap verification (final tree)

* Before/after corpus diff, `.tmp/rm2/corpus.py` + `.tmp/rm2/corpus_diff.py`:
  21 fixtures (`experiments/sexpr-audit/evidence/hot-loops/trapdiff` plus the
  `experiments/llvm-backend/tests/traps` overrides) x 6 accounting modes x 2
  backends, each run with and without `--gc-stress`, comparing status, stdout
  and stderr: **"compared 252 fixture/arm cases; 0 differ"**.
* `python3 experiments/llvm-backend/verify_traps.py`: **"504 built-binary
  comparisons across 21 fixtures, including LLVM GC stress, 0 mismatches/build
  failures"**.
* `--max-frames=N` is the accounting path and is unchanged; `-Dtest-filter=frame`
  is 27/27, including the `compiler_test.zig` pins (max_frames=1 -> one frame,
  20000 -> sixteen frames plus `omitted_frames`). A fast build still refuses a
  runtime ceiling with `R_NO_FRAME_ACCOUNTING` through `requireAccounting`.

The corpus caught one real defect during development: on the slots path
`myl_qbe_fail_assert` read only `ctx->active_frame`, losing the assert message
and the machine trap record. Fixed in `c63c8311` and then reverted with the
slots path.

## Smallest next step toward 1.9x

The remaining per-call work is the record link, the floor guard and the position
store. Removing all three needs a return-address-to-source-position map
consulted only at trap time. QBE emits `push rbp; mov rsp, rbp` for every
non-leaf function, so a native walk can recover the return addresses, but the
position half needs an address->position map, and QBE cannot emit the address of
an interior label into a data section. The smallest credible step is a
driver-side pass that annotates each call site with a distinct symbol (or an IL
extension giving each call site a label reference), so the map can be built
without QBE change.
