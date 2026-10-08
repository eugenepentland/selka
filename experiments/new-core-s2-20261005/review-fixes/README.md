# S2 review fixes (2026-10-06, Claude integrator)

These fixes follow the review of the S2 exit report. They land on `codex/new-core-s2-integration` after `26cd1b1d`:
- **`6121ed2d`: `test-core` sharding.** 4 concurrent Guardian-runner shards. 200 tests went from 4m04 to 1m42.
- **`c18d869c`: four fixes.**
  - caller-derived parameter intervals (NEW-CORE-FACTS-10);
  - 8-bit `psadbw` lanes (NEW-CORE-VECTOR-3);
  - text equality ends and `find` from the nearer end (NEW-CORE-TEXT-2);
  - inline small-table dictionary probes (NEW-CORE-DICT-SMALL-1).
- **`9d6fa976`: equality keeps only the long-text precheck.** The A/B is below.

## Evidence

| Check | Command | Result |
|---|---|---|
| Core tests | `scripts/build-slot.sh gate -- scripts/build-slot.sh build -- zig build test-core --summary all` | 205/205 (4 shards) |
| Conformance | `python3 experiments/new-core-s1-20261005/conformance.py --set all --jobs 4 [--leakcheck --verify]` | debug and release 1224 matching, 0 mismatching, 316 unsupported; leak and verify clean |
| Fuzz | `fuzz_qualification.py --kind K --cases 50` for s0, text (twice: before and after `9d6fa976`), functions, dict, number, iteration | all qualified, 0 mismatches |
| All 35 rows | `measure_all35.py --build --rounds 5 --cpu 10` on `c18d869c` (`all35-after-review.json`) | 35 valid; 0 misses against 1.10× Zig ReleaseSafe; worst against the old core 1.074 (`string_equal/64`, then fixed by `9d6fa976`), 1.028 (`sort_int/4096`), 1.026 (`list_scan/4096`) |
| Rows after `9d6fa976` | the same, `--rows string_equal,dict_lookup_str,dict_update_str,set_dedup` | `string_equal` 1.03× old at 4096 and 0.91× at 64; the dictionary rows 0.14–0.75× old |
| Dictionary layout model | `experiments/new-core-s2-20261005/wave-b/s2-d/layout_real.py` | emitted `word_count` 96.7 → 47.8 cycles/op (n=4096); the other workloads are unchanged within noise |

## Equality A/B at size 64

Cycles per iteration, `row_string_equal 64 250000 7`, three runs:
- Codex's equality (`memcmp` only): 16.5–17.1.
- With the short two-load path: 18.4–20.0.
- Final (long-text precheck only): 17.1–17.7.

## Not done: the fused `split` cursor

`string_split` passes each piece to a user function with a loop (`score`), so the
design's view rule (views only into runtime helpers and inlined callees) means the
pieces must be materialized. Counting the pieces first so the list is allocated once
measured worse (82 against 62 cycles, because it searches twice) and was reverted.
The S3 plan lists multi-block inlining as the lever.
