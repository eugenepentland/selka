# Provisional Wave 3 Juice comparison

The shared gate uses polling, not a numbered FIFO queue. The current Wave 3 repository run was admitted after 2,217 seconds (36 minutes 57 seconds).

Fresh native Juice captures compare the frozen M0 compiler with the repaired compiler after merging main `e9011d9`. These are full, unchanged benchmark workloads, three samples per build on CPU 8, with identical output oracles and backend-mode source/context checks. Every comparison reports repeatable counts and no linked-library changes.

Old build = 100. These scores measure instructions per completed workload, not elapsed time. They are provisional and do not replace the complete qualification or final CPU-10 acceptance run.

| Workload | Current Juice score | Instruction reduction |
|---|---:|---:|
| fannkuch_redux_array | 14.70 | 85.30% |
| intloop | 100.00 | 0.00% |
| scan_split | 31.54 | 68.46% |
| sort_builtin | 31.34 | 68.66% |
| sort_records_sorted | 100.00 | 0.00% |
| text_ops | 63.69 | 36.31% |

Candidate compiler SHA256: `7489a2882613c21a2b02b542d046f7976b686850dc790cb4e2b1290c50f42944`. Its production source is unchanged between `90982ff631b68f1a47e32e5919ba949510edba99` and the qualification head `6a40a150a84e3bc4a0091a539618ee04e2ec1193`.

The first mylang-adapter comparison retained complete captures but rejected the counter-site report because several sites share the same attribution identity. That attempt remains in `../juice-current-01/`; it found 10 duplicate site identities in the baseline and 2 in the candidate. The successful native-adapter captures measure the same ordinary release programs without counter-site attribution. No compiler, benchmark, correctness oracle or gate was edited.

Historical broader instruction comparison, before the latest repair/main merge: Lox VM 91.24, Lox tree 99.00, EDA 92.87, parity 86.01, rows 97.23 (equal-cell geometric scores, baseline 100). These are saved perf comparisons expressed on Juice’s scale, not current full-suite Juice captures.
