# RC fresh-loop and plain-retain composition — 2026-09-27

This is a separate four-program diagnostic after real-merging compiler proof
`4f7eeea9` and runtime plain-retain fast path `5237aebc` on the gated `e926d1e1`
base. The joined source is `79b8492495fead5ab6c9d7137b6813d80d173fcb`.
The Debug compiler SHA256 is
`92d4836a7983d6cc9cc2225e809f450d8fe91c7384d7bc5e8436b41744cbb21a`.

The baseline binaries are the immutable accepted GC corpus built with Debug
compiler `f6bea5d9`, SHA256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
The driver verifies that compiler, every selected baseline binary, the accepted
manifest and the entire unchanged corpus input map. Source sizes, checks, build
arguments and runtime environment come directly from the mandated `pc.py`.
Both actual backends use ReleaseFast; LLVM uses `-O3` and full LTO. CPU 10 runs
three complete observations per side, alternating GC/RC order and recording raw
`perf stat instructions:u`. Counted binaries are separate.

| Workload | QBE RC / accepted GC | LLVM RC / accepted GC | RC uniqueness checks |
|---|---:|---:|---:|
| alloc_churn | 3.425720 | 3.956209 | 1,000,000 |
| sieve | 10.860962 | 30.209437 | 6 |
| list_append_sum | 8.169198 | 15.879437 | 1 |
| fannkuch_redux | 1.744179 | 1.022040 | 10 |

All 16 output checks, 48 measured executions and eight counted executions pass.
All RC allocations retire and owner/hold totals balance; both backends have
identical counters. The three overlapping workloads retain the isolated proof
slice's exact counter dictionaries after the runtime merge.

This does not satisfy Stage 4 acceptance: seven of these eight backend ratios
remain above 1.3. It establishes the next cost boundary rather than multiplying
component ratios. Fannkuch has removed nearly all dynamic uniqueness checks;
the large construction-loop residual remains in the per-append path.

Read-only inspection confirms that RC append still unconditionally calls
`rc_collections.append`. `rc_list_insert_at` stages 128 bytes, checks input aliases
and regions, reserves backing, calls retain, then copies the element. A future
scalar room fast path requires actual queued-finalizer admission, capacity and
generation guards, scalar capture before mutation, and the original generic
cold/growth/refusal path. It must retain uniqueness and journals. No append
implementation change is included in this evidence commit.

[Archived receipts and verifier](../../experiments/d9-rc-owned-loops-composed-20260927/README.md)
include all compiler/source/binary identities, actual command lines, raw perf
records, outputs and counters. No accepted binary or baseline manifest was
rewritten. This diagnostic measures no RSS and makes no corpus-wide verdict.
