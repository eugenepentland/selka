# VP3: run-time cost counters and the copy-elimination target list (2026-10-08)

**Who wrote this file.** An opus-lane agent did the package. Its tool refused report
files, so the coordinating Claude session wrote this file from the agent's final message.
The coordinator first checked the commits, the gate log (exit 0) and `identity.json` (92/92
equal).

**Where the work is.** Branch `claude/vk-vp3` in `mylang-worktrees/claude-vk-vp3`, starting
from `deefad751`. Nothing was merged or pushed.

**Evidence** is in this directory, 6.6 MB:
- the tools;
- raw counter JSON, gzipped;
- one receipt per command;
- `analysis/tables.md`, `analysis/pattern-intensity.md` and the JSON files under
  `analysis/`;
- `identity.json` and `inputs.json`;
- the gate logs.

## Summary

**What was built.**
- `--counters` on `mylang build`, `build --run` and `run` makes a counting build. It is off
  by default.
- At exit, and also when a trap ends the program, the program writes one
  `mylang-counters-v1` JSON document. It goes to the path in `MYLANG_COUNTERS`, else
  `./mylang-counters.json`.
- The document holds, per site and per emitted function:
  - inline retains and releases; each retain also records the data bytes of the block it
    shares;
  - uniqueness tests and their outcomes;
  - copies by kind with bytes: list, dict, buffer, text, and record `memcpy`/`memmove`
    tagged with the Core operation that emitted it;
  - list pushes, and the growth bytes each push caused;
  - allocations and frees with bytes, small-class grows, `realloc` grows and moves, and
    peak live bytes;
  - the runtime's own retains and releases, dict/buffer/text growth, and out-of-line
    appends.
- `mylang cost ENTRY --counters FILE.json` adds a per-function dynamic section after FB1's
  static report, which is printed unchanged.
- Documentation: `docs/tooling/counters.md` (with runnable `bash` examples), feature
  `run-time-counters`, and SPEC bullets `NEW-CORE-COUNTERS-1..5`.

**Byte-identical with counting off.**
- 92 builds were compared: 46 rows × debug and release. The compiler before VP3
  (`deefad751`, Debug) and the final one (`694ae2a11`, Debug) produce identical LLVM text
  and executable SHA-256s in all 92 (`identity.json`).
- The ordinary runtime source is never edited. The counting runtime is that source plus
  anchored insertions (`src/core/count_runtime.zig`).
- This was necessary, not cosmetic. The runtime object's file name is its source digest,
  and that name is a FILE symbol in every executable, so any edit to the runtime text would
  change every executable.

**Counting builds print what ordinary builds print, on every program counted:**
- 48 Lox cells: stdout, stderr and status equal;
- 34 EDA designs: both builds are byte-identical to the goldens;
- 4 parity programs: both equal to their `.expected` files;
- 46 rows: checksums equal.

**Main finding: copies are the cost, not count updates.**
- The core's handling of records larger than four words accounts for 54% of bytes copied
  (mean of the four corpora), 85% of Lox's and 88% of EDA's. The four patterns:
  - P1: moved into phi slots at control-flow joins;
  - P2: copied whole before a field store;
  - P7: returned through `sret`;
  - P8: copied out of a containing record.
- Whole-element list access (P3/P4/P5) is 28% of bytes copied. It is all of nbody, plus
  the Lox VM frame write-back.
- Bytes copied per instruction retired: Lox 3.1, EDA 2.4, nbody 7.5.

**Static-ownership verdict: do not run O1.** By the plan's rule:
- the rows' geomean net saving is 0.47%; the threshold is 3%;
- one row (`mutate_nested`) reaches 10%; the threshold is five rows;
- Lox and EDA are net losses: +389% and +15% instructions.

## What a counting build counts

**Emitter side** (`src/core/emit_count.zig`, plus `emit_llvm.zig` under `Options.counters`):
- **Function records.** Each emitted function gets a record in `myl_count_fns`. Its
  prologue makes that record current and counts the call; every `ret` restores the
  caller's record.
- **Site records.** Each site is an 80-byte record in `myl_count_sites`, kept alive by
  `@llvm.used`. It names:
  - the emitting function;
  - the source function (an inlined callee keeps its own name);
  - path, line and column;
  - the kind, and the Core operation that emitted it.
- **Site kinds:**
  - `retain` (bytes = data bytes of the shared block), `release`, `release_unique`;
  - `unique_test` (extra = tests that found the block unique);
  - `list_copy`, `dict_copy`, `buffer_copy`, `text_copy`;
  - `record_copy`: every `memcpy`/`memmove` of a record, union or array over four words.
    The detail names the operation:
    - `jump`/`branch`: a phi fill;
    - `record_set`, `list_get`, `list_set`, `ret`, `record_get`, …;
    - `list_set.old`: the old element copied out to release its fields;
  - `list_push`: element bytes; extra = growth bytes;
  - `element_load`/`element_store`: aggregates of four words or less.
- **Allocation paths.** In counting builds, list allocation and small-block frees go
  through the runtime, so every block is counted.

**Runtime side** (`runtime/core_count.h` and `core_count.c`, included only in counting
builds). The runtime charges each event to the current function:
- allocations and frees;
- small-class grows, and `realloc` grows and moves;
- list, dict, buffer and text copies;
- the runtime's own retains and releases;
- dict, buffer and text growth;
- out-of-line text appends, byte pushes and byte appends.

**Caveats:**
- Counts are of the core's emitted operations, before LLVM optimizes. A copy LLVM deletes
  is still counted. The 2026-10-08 perf profiles (`profiles/`) confirm that copying
  dominates the optimized binaries anyway.
- `realloc_moved_bytes` is an upper bound.
- Phi-fill sites report the function's line.
- Dictionary side tables are not in the memory counters.

## Programs and method

- **Lox** (`f44302d8`): both engines; the ten timed scripts plus `instantiation` and
  `binary_trees`. Each cell ran at N and N/2 (N−1 for `fib` and `binary_trees`), built
  `--release` with a ReleaseFast compiler of this branch (`13c7d4fc8`; emission is
  unchanged at `694ae2a11`).
- **EDA** (`0008fbc`): all 34 manifest cases.
- **Parity:** `nbody`, `str_build`, `matmul` and `knucleotide` at their fixed sizes.
- **46 rows:** FB1's registry.
- **Instruction counts:** `perf stat -e instructions:u` on the ordinary binaries, pinned to
  E-cores 12–19. These are counts, not timings; no timing was taken, and no run used CPUs
  2, 3, 10 or 11.

**Per-program tables.** Lox (24 cells), EDA (34 designs), parity and the 46 rows are in
`analysis/tables.md` and `analysis/programs.json`. Totals:

| corpus | instructions | retains | releases | copies | record bytes | list/dict/buffer/text bytes | bytes per instruction |
|---|---:|---:|---:|---:|---:|---:|---:|
| Lox (24 cells, larger N) | 405.5 G | 2.31 G | 2.35 G | 8.81 G | 1.16 T | 112.1 G | 3.15 |
| EDA (34 designs) | 16.93 G | 58.3 M | 51.0 M | 797 M | 39.37 G | 307.8 M | 2.41 |
| parity: nbody (5 M steps) | 8.37 G | 0 | 1 | 1.13 G | 63.00 G | 0 | 7.53 |
| 46 rows | 23.78 G | 9.24 M | 7.35 M | — | 363 M | 26.4 M | 0.04 |

## Copy patterns

**Share of bytes moved.** The mean column averages the four corpora.

| pattern | lox | eda | parity | rows | mean |
|---|---:|---:|---:|---:|---:|
| P1 record moved into a phi slot at a join | 44.0% | 28.2% | 0 | 41.5% | 28.4% |
| P3 element copied out of a list | 0.4% | 4.3% | 66.5% | 0 | 17.8% |
| P14 dict/buffer/text growth | 0 | 0.1% | 0.2% | 53.5% | 13.5% |
| P2 whole-record copy before a field store | 20.6% | 16.8% | 0 | 0 | 9.4% |
| P4 record written back into a list element | 3.2% | 0.1% | 33.3% | 0 | 9.1% |
| P7 record returned through sret | 8.0% | 20.6% | 0 | 0 | 7.1% |
| P8 copy out of a containing record | 12.8% | 22.7% | 0 | 0 | 9.0% |
| P9 copy-on-write of a whole list | 8.8% | 0.7% | 0 | 3.0% | 3.1% |
| P13 list growth (class move or realloc) | 0.1% | 2.5% | 0 | 2.0% | 1.1% |
| P6 record pushed into a list | 0 | 3.8% | 0 | 0 | 1.0% |
| P5 old element copied out to release it | 2.2% | 0.1% | 0 | 0 | 0.6% |
| P10 dict copy, P11 text copy | ~0 | ~0 | 0 | ~0 | <0.1% |
| bytes moved | 1.28 T | 40.7 G | 63.2 G | 875 M | |

Bytes moved per 1,000 instructions retired are in `analysis/pattern-intensity.md`. All
patterns together: Lox 3,148, EDA 2,406, parity 4,444, rows 37.

## Top 20 functions by bytes copied

Ranked by each function's share of its corpus's bytes. Up to eight sites per function are
in `analysis/top-functions.json`.

1. **parity `advance`** (nbody): 63.0 GB, 99.8% of parity, 225 record copies (12.6 KB) per
   step.
   - `bodies[i].x - bodies[j].x` copies 56 B per field read through `list_get` (P3, 42 GB).
   - Each field store is another `list_get`, then a `list_set` (P4, 21 GB).
2. **lox `vm::run`**: 669 GB, 52.4% of Lox.
   - `vm.my:429` phi fills of `rt` (200 B) and `frame` (68 B): P1, 493 GB.
   - `vm.my:433` and `vm.my:534` (`rt.frames[rt.frame_count - 1] = frame`): `record_set`
     of `rt` (P2) and `list_set` (P4 and P5).
3. **rows `row_record_pass::batch_result`**: 363 MB, 41.5% of rows (P1).
4. **eda `sexpr_tokenizer::advance`** (`t: mut Cursor`, 48 B): 13.6 GB, 33.3% of EDA.
   - Phi fills: P1, 5.43 GB.
   - The `mut` copy-out through `sret`: P7, 2.71 GB.
   - `t.pos += 1` and `t.col += 1` each copy the whole Cursor: P2, 2.71 and 2.65 GB.
5. **rows `row_dict_update::batch_result`**: 22.4% of rows (P14).
6. **rows `row_dict_update_str::batch_result`**: 22.4% of rows (P14).
7. **eda `sexpr_parser::parse_list`**: 5.48 GB, 13.4%. The `?` on `next_token`/`parse_node`
   copies the Result payload out (P8), plus phi fills (P1).
8. **eda `sexpr_tokenizer::next`**: 4.28 GB, 10.5% (P8, P2, P7).
9. **eda `sexpr_parser::next_token`**: 3.40 GB, 8.4% (P8, P7).
10. **rows `row_set_dedup::batch_result`**: 7.4% (P14).
11. **eda `kicad_sch_textbox::overlaps_of`**: 2.77 GB, 6.8%.
    - All at line 137: `for b in ordered[i + 1:len(ordered)]:` materializes the rest of the
      list for every `a`, although the loop breaks early.
    - P3, P6 and P13.
12. **lox `interpreter::instantiate`**: 81.4 GB, 6.4%.
    - `interpreter.my:472` copies the whole 262 KB `rt.stack` per instantiate: P9.
    - `__wb_413` write-back copies: P2.
13. **eda `sexpr_tokenizer::skip_whitespace_and_comments`**: 2.38 GB, 5.8% (P1, P7).
14. **lox `interpreter::evaluate`**: 64.1 GB, 5.0% (P2 `it.rt = __wb_318`, P8, P7).
15. **lox `interpreter::execute`**: 55.3 GB, 4.3% (P2, P1, P7, P8).
16. **lox `heap::allocate`**: 53.7 GB, 4.2%.
    - `heap.my:117` copies `rt.objects`: P9, quadratic on the VM `instantiation`.
    - P2 and P1.
17. **eda `sexpr_tokenizer::next_in`**: 1.65 GB, 4.0% (P7, P8).
18. **lox `interpreter::binary`**: 50.1 GB, 3.9% (P1, P2, P8).
19. **lox `heap::sweep`**: 39.9 GB, 3.1% (P1, P2, P9).
20. **eda `sexpr_tokenizer::read_atom`**: 1.27 GB, 3.1% (P1, P7).

## The plan's candidates

1. **Whole record written back into a list element while the local stays live (Lox VM):
   confirmed, and worse than expected.**
   - Each dispatch copies `rt` (200 B), two 68 B list elements and an 88 B old element.
   - The write-back also makes `rt` a new memory value on every iteration, so it is
     copied into phi slots about 41 times per dispatch.
   - About 6.4 KB is copied per VM instruction (fib).
2. **Element-field store lowered as a whole-record copy (nbody): confirmed.**
   - Every `bodies[i].f = …` is a 56 B `list_get` plus a 56 B `list_set`.
   - Every field read is a whole-element `list_get`.
3. **Copy-on-write of a whole list when one element is held across a `mut` call: confirmed.**
   - VM: `heap.my:117` is quadratic.
   - Tree: `interpreter.my:472` copies `rt.stack`, and `interpreter.my:318` copies
     `rt.objects`.
   - These copies also drive 60–284 M runtime count updates per run.
4. **Slice materialized in a `for` loop / accessor returning a payload copy (EDA): the slice
   is confirmed, at `overlaps_of`, not `scan`; the accessor half is rejected.**
   - `overlaps_of:137` is 38% of rds3+flat's bytes moved and 96% of EDA's `realloc` moves.
   - `scan`'s slices are small.
   - `ast.as_list(root)` is a retain, not a copy.
5. **Dict copies: rejected.** 4.9 MB across EDA, 0.01%.
6. **List growth through `realloc`: confirmed but narrow.** It is almost all the
   `overlaps_of` slice, plus dict growth in three rows and `str_build`'s buffer.
7. **Out-of-line checked appends (`str_build`): confirmed as a call-count problem.** 16 M
   out-of-line 8-byte appends. It needs an inline append fast path, not copy elimination.

## Ranked copy-elimination targets

1. **Memory-record plumbing in the emitter** (P1 + P2 + P7 + P8): 54% share; 85% of Lox and
   88% of EDA bytes. Four changes:
   - **(a) P1, 28.4%.** Coalesce memory-phi slots with incoming slots that die on the edge,
     and give loop-carried memory records one home slot (`emit_llvm`
     `analyzeMemory`/`fillMemoryPhis`).
   - **(b) P8, 9.0%.** Read fields of memory records by pointer projection when the source
     outlives the use (`record_get`, `union_payload`, release/retain field loads).
   - **(c) P2, 9.4%.** Update a memory record in place when its old version has no later
     reader (extend `writableInPlace` to liveness, including `mut` parameters and phis).
   - **(d) P7, 7.1%.** Pass `mut` records over four words by reference instead of copy-in
     plus `sret` copy-out, and build returned records in the caller's destination.
2. **Whole-element list access** (P3 + P4 + P5): 27.5% share; all of nbody and the Lox frame
   write-back. Changes:
   - lower `xs[i].f` to `list_get_field`;
   - store `xs[i].f = v` in place after the uniqueness test;
   - release the old element's fields in place;
   - store from `v`'s slot.
3. **Copy-on-write of a whole list across a `mut` call or a write-back temporary** (P9):
   3.1% share, Lox 8.8%, quadratic in the worst case. In `own.zig`:
   - promote only the element read;
   - end the `__wb_N` temporary before the element store.
4. **`for x in xs[a:b]`** (slice sites): EDA 7.1%, rds3+flat 38%. Lower it to an index loop
   over the source list, and give slice copies their exact capacity.
5. **Dictionary growth** (P14): rows only. Reserve from a known size. Low priority.
6. **Not copy-elimination targets:**
   - `str_build` needs an inline `append_range` fast path;
   - dict copies, text copies and accessor retains are negligible.

## Static-ownership verdict

**Model.**
- Static ownership removes the inline retains, releases and uniqueness tests, and the count
  work of the runtime's own count updates.
- Every retain of a value that stays live becomes a copy of the shared block's data.
- Estimated costs: retain 5 instructions, release 7, uniqueness test 3, runtime count
  update 6; a copy is 60 plus bytes/16. The verdict does not depend on these estimates.

| corpus | programs | geomean net saving | upper bound if the extra copies were free | programs ≥ 10% net |
|---|---:|---:|---:|---|
| 46 rows | 46 | **0.47%** | 0.83% | 1 (`mutate_nested` 16.2%) |
| EDA | 34 | **−14.8%** | 4.73% | 0 |
| Lox | 24 | **−389%** (×4.9 instructions) | 16.4% | 0 |
| parity | 4 | 1.11% | 1.11% | 0 |

**Rule outcome: do not run O1.**
- Lox's retains share large blocks (the `__wb_` write-backs of `rt`'s lists, and the frame
  lists). As copies they cost far more than the counts.
- The take/put-back analysis that would let static ownership move those values would remove
  them under one-count RC too.

## Gates

| gate | result |
|---|---|
| `zig build` (Guardian) | 88/88 checks |
| `zig build test --summary all` at `694ae2a11` | 88/88 steps, 0 failures (`logs/gate-full.log`, exit 0) |
| `zig build fmt-check` | exit 0 |
| focused `test-core` | counting 6/6, `--counters` 3/3, cost 8/8 |
| byte identity, counting off | 92/92 LLVM and executable SHA-256s equal (`identity.json`) |
| counting output = ordinary output | Lox 48/48, EDA 34/34, parity 4/4, rows 46/46 |

No Guardian ratchet acceptance was needed. To keep `pipeline.Show` at 7 fields, the agent
moved `generic_vectors` and `trap_frames` into a new `Show.codegen` struct with
`counters`.

## Commits on `claude/vk-vp3`

- `26b5d8f28` core: `--counters` counting builds (NEW-CORE-COUNTERS-1..4)
- `13c7d4fc8` core: counters record retained bytes, growth per push site and byte appends
- `694ae2a11` cost: `--counters` adds one counting run's executions per function
  (NEW-CORE-COUNTERS-5)
- `6ba9aa34e` evidence: counts, analysis and identity receipts

## Open or uncertain

- The replay key's flags JSON gained a `counters` member, so existing replay records miss
  once. Outputs are unaffected.
- The static-ownership instruction costs are estimates. Retained bytes are shallow; deep
  copies would only strengthen the verdict.
- Measurement binaries came from `13c7d4fc8`; emission is unchanged at `694ae2a11`.
