# Wall-time confirmation of wave PM's Lox VM bounds on CPU 10 (2026-10-09)

**Why.** Plan §8 asks for the Lox VM bounds to be confirmed in wall time before lanes F2 and U1 start. The parity bounds were confirmed in `../REPORT.md`.

**How.**
- `build.sh` builds the `cf.py` variants of the Lox port with `main` `35df839be`'s compiler (`~/.cache/mylang/main-35df839b`), and the loxvm ladder rungs 0, 2, 5 and 6 from `experiments/parity-measure-20261008/ladders/loxvm.c`.
- The reference ports are the Lox harness's release builds from FS-X's timing prep.
- `confirm.py` (the same tool as for the parity bounds) times them under the CPU-10 lock: 1 warmup round and 5 timed rounds, interleaved and shuffled. Every arm's output equals the mylang port's.
- Raw data: `spec.json`, `result.json`, `confirm.log`, `build-logs/`.

## Results

Wall time ÷ the mylang port today (the rebuild `cf-base` is within 0.8%).

| cell | bounds | checks | norc | checks+norc | Zig RS | Zig RF | Rust |
|---|---:|---:|---:|---:|---:|---:|---:|
| vm/step (step.lox, N = 10⁷) | 0.838 | 0.894 | 0.936 | 0.870 | 0.432 | 0.378 | 0.462 |
| vm/fib (34) | 0.891 | 0.835 | 0.798 | **0.674** | 0.440 | 0.348 | 0.481 |
| vm/string_equality (100k) | **0.694** | 0.666 | 0.933 | 0.677 | 0.320 | 0.251 | 0.427 |
| vm/invocation (1.5M) | 0.883 | 0.807 | 0.668 | **0.509** | 0.386 | 0.228 | 0.436 |

**The step loop ladder** (÷ rung 0, the C transcription of today's dispatch, which runs at 0.946 of mylang):

| rung | what changes | wall ÷ rung 0 | PM cycles ÷ rung 0 |
|---|---|---:|---:|
| 2 | index checks and wraps removed | **0.712** | 0.744 |
| 5 | + uniqueness tests hoisted, count traffic removed, frame in registers | **0.538** | 0.579 |
| 6 | + `stack_top` in a register | **0.501** | 0.559 |

Rung 6 is 305 ms, against Zig ReleaseSafe's 278 ms (1.10×). mylang today is 643 ms (2.31×).

**Verdict.** Every bound PM listed holds in wall time, and most come out slightly stronger than the cycle figures:
- **F2:** string_equality bounds 0.69, against the exit's ≤ 0.80; step rung 2 0.71.
- **U1:** step rungs 5 and 6, 0.54 and 0.50.
- **U2:** invocation checks+norc 0.51; fib 0.67.

The Lox VM's non-monotonic cycle response (step: `checks` 0.894 is worse than `bounds` 0.838) also shows in wall time. Lanes should confirm each step's effect, not assume the variants add up.
