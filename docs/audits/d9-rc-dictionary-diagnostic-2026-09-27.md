# Dictionary lifetime overhead on the joined RC runtime

The unchanged `bench/parity/micro/dict_count.my` performs two million updates
across 1,000 string keys. Frozen source `d1d8b3c4`, Debug compiler SHA256
`12a3693929913d50385248a5938fcf57694de8a3538e65f150432c998936d268`, was measured
against immutable accepted GC binaries on CPU 10. Every output matches; actual
LLVM uses O3 and full LTO. All 12 production instruction observations report
100% counter running.

| Backend | Accepted GC median | Joined RC median | RC / GC |
|---|---:|---:|---:|
| QBE | 661,306,134 | 7,841,566,609 | 11.857695 |
| LLVM | 441,035,727 | 5,774,369,900 | 13.092749 |

Separate counted executions on both backends agree exactly: 2,030 heap
allocations and retirements, 2,002,001 owner acquisitions, 2,004,031 owner
releases, 12,001,999 hold acquisitions and releases, 4,001,000 uniqueness checks,
and zero copy-on-write clones. Counters do not saturate or hit a dynamic limit.
The substantial lifetime traffic is therefore a concrete optimization target;
the diagnostic does not attribute it to copying the dictionary payload.

The emitted source maps repeated dictionary writes to two uniqueness calls
followed by a pin scope. Native scope capture allocates a metadata journal entry;
its end restores the pin, releases the hold and frees that entry. The generic
read paths also produce list/key lifetime loans. These observations motivate
separate bounded proofs for read-only receiver/key lifetimes and closed mutation
intervals; none is authorized merely by the benchmark's source spelling.

A separate QBE profile places descriptor lookup, hold release, drain and scope
metadata allocation/free among sampled costs. It has only 249 samples and the
raw events record 249 THROTTLE and 249 UNTHROTTLE events, despite the ordinary
text script omitting them. These percentages are qualitative, heavily throttled
attribution and are excluded from instruction acceptance. No lost event is
reported. The instruction medians above come from separate unscaled perf-stat
runs.

The [archive](../../experiments/d9-rc-dictionary-diagnostic-20260927/README.md)
retains exact commands, copied inputs, compiler and binary identities, counters,
emitted code and raw profiling events. No production code or workload was
changed. This single-program result fails the performance threshold and does
not establish complete Stage 4 acceptance.
