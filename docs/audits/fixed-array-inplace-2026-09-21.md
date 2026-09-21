# A fixed array's element write lands in place — 2026-09-21

This fixes the second of the three defects in
[performance-parity-audit-2026-09-21](performance-parity-audit-2026-09-21.md)
§3: "fixed arrays copy the whole value on every element write". One element
write into an `[N]T` local was **O(N)**, and in the schematic renderer that one
line was the single hottest item in the whole profile at 42.5% of samples.

Branch `fix/array-inplace` over `base/defects-20260921`. Nothing about the
language surface changed; no new syntax exists.

## What changed

`replace(x, i, v)` is a whole-value expression: the backend copied the array into
the per-pc aggregate scratch, wrote one element of the copy and yielded the copy,
and the `store_local` that put it back into `x` copied it out again. Two
whole-array `blit`s per element write, plus a scratch buffer the size of the
array in the frame.

**`QBE-ARRAYWRITE-1`** forwards the destination, the way `QBE-CTORFWD-1` already
did for a record constructor. `replaceDestination` in `src/qbe_aggregate.zig`
claims local `slot` for the `replace_index` at `pc` when all of this holds:

* `pc + 1` is `store_local slot`, is reachable, and is not a branch target;
* `locals[slot].ty` is the array's own type, is not scalar, has `drop == false`
  and a nonzero size, and `byReference(slot)` is false — so a parameter the body
  writes keeps its private entry copy and a caller's array is never touched
  (`addressLocals` already clears the flag for any local a `store_local` names,
  which is exactly the shape a replace-assign has);
* the array operand is that local's own storage. `borrowsLocal` proves it by
  walking back from `pc` to the last instruction that ran with an empty operand
  stack and requiring it to be a `load_local`/`move_local` of `slot`, with no
  branch target and no write of the local in between. That is the same window
  `borrowableLocal` walks *forward* from the read when it decides to name the
  slot instead of snapshotting it, so the two answers cannot disagree — the same
  recomputation discipline `constructorForwarded` uses.

The emitter then writes the element through `localPointer(slot)` after the
unchanged bounds check, and `storeForwarded` (which replaces
`constructorForwarded` and now answers for both rules) makes the following
`store_local` emit nothing. `dropUnusedSlots` removes the scratch declaration
forwarding made dead.

The requirement that the array operand sit at the bottom of the operand stack is
what makes the reasoning local: at that point the only live operands are the
array, the index and the element, so no other operand can still name the old
value. The element operand may itself name storage inside the same array
(`x = replace(x, i, x[j])` over an array of aggregates); such a write copies one
stride-sized, stride-aligned region onto another, so the two are identical or
disjoint — exactly as they were when the write went to the scratch copy.

Files changed: `src/qbe_aggregate.zig` (the predicate and the lowering),
`src/qbe.zig` (one call site), `SPEC.md`, `src/qbe_test.zig`,
`src/native_execute.zig`, `tests/lang/array_writes.my`, `docs/performance.md`.

## What the emitted IL shows

| program | whole-array `blit`s before | after |
| --- | ---: | ---: |
| `stage4096.my` — one element write into a `[4096]int` local | 2 × 32768 B | **0** |
| `replace_loop.my` — the audit's isolated flush loop, `[256]u8` | 3 × 256 B | **1** |
| `io::flush` in the schematic guest | 3 × 256 B | **1** |
| `scan4096.my`, `read4096.my`, `peek{8,1024,4096}.my` — element reads | 0 | 0 |

The one `blit` left in a flush loop is the array literal's own store into the
local, paid once per 256-byte block rather than once per byte. The read path was
already one bounds check and one load on this base — the four whole-array copies
`docs/performance.md` used to document for `scan4096` are not in this tree, so
the read half of the defect was already closed before this change and the
documentation was stale; that section is now rewritten.

## Before and after

Method: prebuilt `--mode ReleaseFast` binaries from the base compiler and from
this branch, both backends (`--backend llvm --llvm-opt 3 --lto` for the LLVM
arm); `experiments/perf-parity-audit-20260921/probes/bench.py --cpu 8`, which
pins every arm to one CPU, randomizes the round order, interleaves the arms and
checks stdout equality across them. Medians of 15 rounds after 3 warmups unless
noted. The machine is shared and was loaded (`/proc/loadavg` recorded per batch),
so only within-batch ratios are meaningful.

**Element writes** — 409,600 element writes into a `[4096]int` local
(`stage4096`) against the same writes into a `list[int]` (`stagelist4096`); all
arms print `414450`. Load average 9.3 falling to 5.4.

| arm | before | after | after / before |
| --- | ---: | ---: | ---: |
| `[4096]int`, QBE | 2349.7 ms | **7.3 ms** | 0.0031 (321× faster) |
| `[4096]int`, LLVM O3 + LTO | 1423.3 ms | **7.2 ms** | 0.0051 (197× faster) |

An arm that runs for seconds inflates the millisecond arms interleaved with it,
so the four fast arms were re-measured in a batch of their own (31 rounds, load
average 6.6). The ratios above are still fair — every arm in a batch is
interleaved with every other — but these are the honest absolute times:

| arm, after the change | QBE | LLVM O3 + LTO |
| --- | ---: | ---: |
| 409,600 writes into `[4096]int` | **1.91 ms** | **1.76 ms** |
| the same writes into `list[int]` | 3.43 ms | 2.50 ms |

The list control was also measured with the base compiler in its own batch
(15 rounds, load average 7.8): 3.461 ms against 3.448 ms on QBE and 2.582 ms
against 2.561 ms on LLVM — unchanged, as a managed collection must be. The fixed
array now beats the managed list on the same writes, by 1.8× on QBE and 1.4× on
LLVM.

**The isolated flush loop** — `replace_loop_heavy`, 20 passes of the audit's
`replace_loop.my` over 49,617 bytes, 11 rounds, load average 3.5. The
empty-program floor measured in the same session (31 rounds) is 3.71 ms on QBE
and 3.03 ms on LLVM; the per-pass column subtracts it.

| arm | before | after | per pass, floor subtracted |
| --- | ---: | ---: | --- |
| QBE | 35.37 ms | **13.00 ms** | 1.58 ms → **0.49 ms** |
| LLVM O3 + LTO | 29.99 ms | **7.42 ms** | 1.35 ms → **0.22 ms** |

The audit's own single-pass `replace_loop.my` measured 4.00 → 3.73 ms (QBE) and
3.96 → 3.54 ms (LLVM), but on this loaded machine that program is mostly the
process floor, so the 20-pass form above is the one to read.

**The production consumer** — the schematic renderer over
`experiments/schematic/fixtures/straps-synth-lmx2595.sexp`, producing the same
49,617-byte SVG. `zig build test-schematic` passes (27/27 steps). The host
rebuilds the guest on every invocation (12.9 s warm), which swamps a 3.5 ms
render, and the private harnesses the task named
(`experiments/svg-gap-fixes-20260921`, `experiments/full-svg-benchmark`) are not
in this snapshot; so the guest was rebuilt with the same command
`src/schematic/app.zig` issues (`--project --provider provider.c
--step-accounting`, provider taken from the host's own staging directory) and
invoked directly with the `MYLANG_SCHEMATIC_*` environment the host supplies.
31 rounds.

| arm | before | after | after / before |
| --- | ---: | ---: | ---: |
| render, QBE (load 7.3) | 9.165 ms | **8.606 ms** | 0.94 |
| render, LLVM O3 + LTO (load 9.0) | 8.398 ms | **8.100 ms** | 0.96 |

0.56 ms and 0.30 ms of a whole render, which brackets the 0.55–0.60 ms the audit
predicted from the profile. These renders carry `--step-accounting` and write the
SVG to a file, as the host runs them, so the absolute times are above the 3.5 ms
of pure compute the audit quotes. The SVG is byte-identical before and after, and
identical to what `schematic-svg` itself produces.

**No change where none was expected** — the read and call probes, 15 rounds, load
average 7.8. Every ratio is 1.00 ± 0.05 between the base and this branch.

| probe | QBE before → after | LLVM before → after |
| --- | --- | --- |
| `read4096` — 4,096,000 element reads from a local | 29.98 → 29.99 ms | 17.80 → 17.85 ms |
| `peek8` — 100,000 calls returning `values[0]` | 4.40 → 4.24 ms | 3.92 → 3.99 ms |
| `peek1024` | 443.7 → 449.1 ms | 458.1 → 463.9 ms |
| `peek4096` | 1422.0 → 1424.0 ms | 1417.8 → 1425.0 ms |
| `scan4096` — 1,000 scans of a `[4096]int` parameter | 41.0 → 41.5 ms | 34.0 → 31.8 ms |
| `scanlist4096` — the same scans over a `list[int]` | 16.0 → 16.0 ms | 8.95 → 8.49 ms |

## What the tests pin

* `SPEC.md` gains `- [QBE-ARRAYWRITE-1]` at the end of "Projects and native
  output".
* `src/qbe_test.zig` carries the primary `// spec: QBE-ARRAYWRITE-1`: the
  forwarded spelling emits no `blit` at all and no `%agg`, writes through a copy
  of `%l0`, and keeps its bounds check; a `spec-case` pins that the same replace
  stored into a *different* local keeps both whole-array copies.
* `src/native_execute.zig` adds the out-of-range case for the forwarded spelling
  to the structured-trap table: `R_INDEX_BOUNDS`, operation `index`, index 7,
  length 3, and the same rendered detail as the non-forwarded read.
* `tests/lang/array_writes.my` carries ten guest tests, run under `--gc-stress`
  by `zig build test-lang`: write-then-read; a copy taken before the write; a
  loop of writes against a copy taken before it; the byte-staging loop; an array
  pulled out of a record (the record is unchanged); an array parameter the callee
  writes (the caller's value is unchanged); a nested array; a row copied out of
  the same nested array; a traced element type (`[3]str`); an enum-keyed table.

## Gate

Run on this branch, after merging the base's fixture commit `0c871992`:

| step | result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | **pass** — 70/70 steps, 1523/17142 tests passed (15619 skipped by sharding), every one of the 18 shard verdicts `"failed":0` |
| `zig build test-qbe --summary all` | **pass** — 48/48 steps, 206/206 tests |
| `zig build test-qbe-build --summary all` | **pass** — 30/30 steps |
| `zig build fmt-check` | **pass** |

Guardian's whole-tree run passed 88/88 at both commits. `zig build test-schematic`
passed 27/27. `mylang doc-coverage .` reports 0 failures and `mylang doctest .`
runs 157 examples with 0 failed and 0 mis-tagged.

## Limits and what is left

* **Only locals.** `r.cells = replace(r.cells, i, v)` on a record field lowers to
  `update_record`, not `store_local`, and still copies. Array-typed fields were
  in scope only "if it falls out naturally"; they do not.
* **Only the bottom of the operand stack.** A replace nested inside a larger
  expression keeps the copy. In practice `x = replace(x, i, v)` is a statement, so
  this costs nothing on the shapes that matter, but it is a real restriction.
* **The array literal still copies once.** `payload: [256]u8 = [0u8, …]` builds in
  the scratch and stores; that is one copy per block, not per element, and it is
  `QBE-CTORFWD-1`'s territory rather than this rule's. In the `[4096]int` probe
  the literal does forward, so that program emits no `blit` at all.
* **Passing a large `[N]T` is still the expensive habit**, and for a reason this
  change does not touch: `frameBytes` in `src/qbe.zig` sizes a frame from the
  full byte size of every local *plus twice the per-pc aggregate scratch of every
  instruction that might use one* — including scratch that forwarding or
  `dropUnusedSlots` later removes — and a frame over 32 KiB is heap-allocated on
  every call. A `kernel(values: [1024]int)` that only reads `values[0]` therefore
  calls `myl_qbe_frame_allocate(82128)` per call even though its emitted body
  contains no `%agg` at all. That is what the `peek` and `scan` rows above are
  measuring, and it is the obvious next item.
* Measurements were taken on a shared machine under load average 3.5–9.3. Every
  number above is a within-batch ratio of interleaved arms; absolute times are
  not comparable with the audit's quiet-machine figures.
