# Wall-time confirmation of wave PM's bounds on CPU 10 (2026-10-09)

**Why.** Wave PM measured cycles on CPU 8 of a busy machine. Plan §8 asks the coordinator to confirm the main bounds as wall time on the quiet timing CPU before lanes F1 and S1 start.

**How.**
- `tools/build.sh` builds the arms:
  - `cf.py` variants, using the PM-1 compiler `~/.cache/mylang/pm-a677da7a`. Its code generation is the same as `main` `cafe7fea7`.
  - The ladder rungs from `experiments/parity-measure-20261008/ladders/`, with the same `zig cc` flags.
  - The reference binaries are PM's, from `claude-parity-measure/.tmp/pm/parity/work/bin`.
- `tools/confirm.py` times the arms under `flock cpu10.lock`, with `taskset -c 10`.
  - Each group's arms are interleaved and shuffled per round: 2 warmup rounds, then 9 timed rounds. Figures are medians.
  - Every arm's stdout equals the mylang arm's.
- Raw data: `spec.json`, `result.json`, `confirm.log`, `build-logs/`.

## Results

"÷ today" is the arm's median wall time divided by the mylang binary's. For ladders it is divided by rung 0, the C transcription of today's code. "→ ÷ Zig RS" is the projected position: today's mylang wall time times the bound, divided by Zig ReleaseSafe.

| program | lever | PM cycle bound | wall ÷ today | today ÷ Zig RS | → ÷ Zig RS | lane exit | verdict |
|---|---|---:|---:|---:|---:|---|---|
| matmul | cf `tbaa` | 0.11 | **0.137** | 2.59 | **0.36** | ≤ 0.4 | confirmed |
| matmul | ladder rung 2 (hoisted rows, no store-back) | 0.114 | 0.130 | | 0.33 | | confirmed |
| matmul | ladder rung 6 (typed data, check hoisted) | 0.113 | 0.130 | | 0.33 | | confirmed |
| bytes_scan | cf `overflow` | 0.29 | **0.368** | 1.08 | **0.40** | ≤ 0.4 | confirmed, at the exit's edge |
| sieve | cf `overflow` | 0.74 | 0.768 | 1.15 | 0.88 | ≤ 0.9 | confirmed |
| sieve | cf `checks` | 0.73 | 0.762 | | 0.87 | | |
| knucleotide | ladder rung 1 (views; allocate on insert) | 0.441 | **0.470** | 2.07 | **0.97** | ≤ 1.0 | confirmed |
| knucleotide | ladder rung 2 (+ short-key compare inlined) | 0.366 | 0.387 | | 0.80 | | confirmed |
| scan_split | ladder rung 1 (pieces as views) | 0.492 | **0.493** | 1.46 | **0.72** | S2: ≤ 0.6 | confirmed |
| scan_split | ladder rung 2 (lazy split) | 0.397 | 0.365 | | 0.53 | | confirmed |
| nbody | cf `unique` | 0.82 | 0.779 | 1.71 | 1.33 | U1: ≤ 1.35 | confirmed |
| str_build | ladder rung 1 (uniqueness test hoisted) | 0.714 | 0.880 | 1.72 | | U1: ≤ 1.0 | **weaker than cycles** |
| str_build | ladder rung 2 (len and cap in registers) | 0.424 | 0.748 | | | | **weaker than cycles** |

**Notes.**
- **The cf rebuilds are faithful.** The unedited rebuild (`cf-base`) is within 0.6% of the real binary everywhere.
- **The ladders' rung 0 matches mylang**, within 1% for matmul. The exceptions:
  - knucleotide's rung 0 is 8% faster;
  - scan_split's is 16% faster;
  - **str_build's rung 0 is 39% faster than mylang** (51.6 against 84.5 ms).
- **str_build's gap is mostly outside the ladder.** Its wall-time bounds are weaker than its cycle bounds, and the transcription itself already runs at 1.05× Zig ReleaseSafe. PM's open question (realloc growth placement, or L1 misses) is the bigger lever. Lane U1 should start there, not from the ladder.
- **scan_split is 1.46× Zig ReleaseSafe in wall time**, against 1.14× in cycles. The mylang arm is also noisy (67.8–77.8 ms). Allocation is the likely cause: page faults and kernel time count in wall time but not in user cycles. Views remove most of it.
- **References, in ms:**

  | program | Zig RS | Zig RF | Rust with overflow checks | Rust |
  |---|---:|---:|---:|---:|
  | matmul | 55.6 | 37.4 | 101.9 | 75.2 |
  | bytes_scan | 45.2 | 34.6 | 51.7 | |
  | knucleotide | 101.8 | 90.1 | 122.7 | |
  | scan_split | 50.8 | 31.9 | | |
  | sieve | 68.2 | | 60.4 | |
  | str_build | 49.1 | 39.8 | 42.6 | |
  | nbody | 127.6 | | 147.6 | |

**Not yet confirmed.** These belong to lanes F2, U1 and U2 and will be confirmed before those lanes start:
- the Lox VM ladder rungs 0, 2, 5 and 6;
- `checks+norc` on vm/fib, string_equality and invocation.

**Verdict.** F1's and S1's bounds hold in wall time, so both lanes start.
