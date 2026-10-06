# grid_dp: notes

Contract: `../CONTRACT.md`, section grid_dp. Verified against `oracle.py` for all five arms at all five probes
(`rows.py verify grid_dp`: PASS). Calibrated iterations (`rows.py calibrate grid_dp`, CPU 12): 4096 -> 1542, 64 -> 70968.

## Idioms per language (how each port allocates the nested grids)

The cost grid and the dp grid are each H rows of W cells, built row by row inside the batch, released inside the batch.
No arena, pool or reuse across batches in any port. Rows are created at their final width (the widths are known),
so no port reallocates a row while building it.

| arm | cost grid | dp grid | release |
|---|---|---|---|
| mylang (`row.my`) | `[[expr for j in range(w)] for i in range(h)]` | `[[0 for j in range(w)] for i in range(h)]`, then `dp[i][j] = ...` | reference count, at function exit |
| Rust | `(0..h).map(\|i\| (0..w).map(..).collect()).collect()` -> `Vec<Vec<i64>>` | `(0..h).map(\|_\| vec![0; w]).collect()`, then `dp[i][j] = ...` (bounds-checked) | drop at function exit |
| Zig | `c_allocator.alloc([]i64, h)` + one `alloc(i64, w)` per row (`allocGrid`), filled in place | same helper; rows are not zeroed (every cell is written before it is read) | `defer freeGrid` (frees every row, then the outer slice) |
| Go | `make([][]int64, h)` + `make([]int64, w)` per row | same, rows zeroed by `make` | garbage collector (`runtime.GOMAXPROCS(1)` is set in `main`) |

- **mylang `dp[i][j]`:** the dp fill is written exactly as the contract formula, nested element reads and nested element
  writes: `dp[i][j] = cost[i][j] + min(dp[i - 1][j], dp[i][j - 1])`. `batch_result(w, h, batch, seed)` owns both grids as
  plain locals (no `mut` parameter needed) and returns `dp[h - 1][w - 1] + sum(dp[h - 1])`.
- **Fill order (all five):** `dp[0][0]`, then the rest of row 0, then for each `i >= 1`: `dp[i][0]`, then `j = 1..W-1`.
  This is the contract's four cases written as boundary statements, not a branch per cell.

## Left open by the contract, and how I decided

- **`isqrt`:** W and H depend only on SIZE, so they are computed once, outside the timed loop, by the same integer loop
  in every language (`while (w+1)*(w+1) <= n: w += 1`), and passed to the batch function. No float sqrt, no per-language
  library `isqrt`, so W is identical everywhere and the setup cost is out of timing.
- **dp rows allocated first, then filled** (rather than appending each row after computing it). This keeps the contract's
  `dp[i][j]` indexing and makes the nested element write the mechanism under test. See finding 2: it is not free in the
  new core.
- **Zero-fill:** Zig does not memset dp rows, Rust (`vec![0; w]`) and Go (`make`) get zeroed rows from the allocator or
  runtime, mylang writes the zeros through the comprehension. Each is the natural spelling in its language; the contract
  does not say.
- **Validation:** SIZE >= 2, ITERATIONS >= 1, 1 <= SEED <= 1000000, exactly the right argument count. References
  exit 2 on a wrong case name, a non-numeric or out-of-range argument, a negative number, or a number that overflows 64
  bits. `row.my` returns 2 from `main` (a non-numeric or overflowing argument parses as 0, which fails the `size < 2` /
  `iterations < 1` / `seed < 1` check). I ran each of: wrong case, 1 1 7, 64 0 7, 64 1 0, 64 1 1000001, abc 1 7,
  -4 1 7, a missing argument, 99999999999999999999 1 7 against every arm: all exit 2 with empty stdout and stderr.
- **`part < 0` guard** in `row.my` is the template's (`row_list_append.my`); the part is never negative.

## Findings

1. **No refusal, no wrong answer.** Both mylang compilers build `row.my`; the new core accepts every function
   (`mylang-core coverage`: `ok` for `isqrt`, `batch_result`, `parse_number`, `main`; only the extern
   `runtime_bench_now` is "refused extern", exactly as for the `row_list_append.my` template). All five arms agree
   with the oracle, so there is no `new-core-refusal.txt`.

2. **Performance cliff in the new core: a nested element write `dp[i][j] = v` copies the whole row `dp[i]` on
   every write.** Not a wrong answer, but it decides this row.
   - `mylang-core dump-ir` lowers the write to `list_set.exact list[i64] %row, %j, %v` followed by
     `list_set.exact list[list[i64]] %dp, %i, %newrow`. The emitted LLVM puts an unconditional
     `call ptr @myl_core_list_copy(ptr %row, i64 8)` between the row load and the row store (malloc, memcpy of the
     row, retain of children, release of the old row). The direct write `parent[ra] = rb` in `union_find` has a
     runtime shared check with a copy arm instead; the nested one has no uniqueness branch.
   - Cost per nested write (user cycles on CPU 12, grid built but unfilled subtracted, `row_width` = W):
     new core 42 (W=16), 45 (32), 58 (64), 271 (128), 303 (256), 550 (512); old core 4 to 8 at every width.
     So it is O(W) per write, 14x the old core at the measured 4096 cells (W=64).
   - Whole row, indicative (user cycles per element incl. startup, CPU 12, noisy, not a measurement): 4096 cells:
     old 29, new 74, Rust 13, Zig ReleaseSafe 16, Go 20; 64 cells (W=8): old 85, new 60, Rust 20, Zig 22, Go 38.
   - Repro: `repro-nested-write-copy.my` (copy to `repro.my` first, see below). 6.3M nested writes: old core
     about 13 ms, new core about 165 ms, same output `194292`.
   - A formulation that avoids the nested write (build each `row = [0 for j in range(w)]`, fill `row[j]` reading
     `dp[i-1][j]` and `row[j-1]`, then `dp.append(row)`) gives the same checksum and runs about 4.6x faster in the
     new core (104M vs 481M user cycles at 4096/1542 on CPU 12). I kept the contract's `dp[i][j]` form as the row:
     switching would move the work off the mechanism the row is meant to cover. Say the word if the coordinator
     prefers the row-at-a-time form.

3. **`[0] * w` is rejected by both compilers when `w` is not a literal** (`error[E_LIST_TYPE]: operation requires a
   managed list`, pointing at the `[0]`). `[0] * 3` and `b * w` with `b: list[int]` check; `[0] * w` does not.
   Language limitation, not a refusal. I use `[0 for j in range(w)]`, which is the equally natural spelling.
   Repro: `repro-list-repeat.my`.

4. **Repro file names:** the compiler requires the entry file name to be an identifier plus `.my`, and `repro-*.my` has a
   dash, so neither compiler loads these in place (`InvalidModuleName`). Copy to `repro.my` (module name `repro`)
   and build with `--link benchmarks/runtime/ports/native_clock.c` for the timing repro.
