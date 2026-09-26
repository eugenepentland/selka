# D9 WP-4: normal cleanup overhead

The cumulative inline-TAKE/flat-release profile attributes 7% of QBE sampled
CPU time to `myl_qbe_rc_slot_drop`. Normal frame cleanup still invokes that
large helper for every entry even after successful transfers have disarmed
the guards. The new loop checks the guard first and calls the helper only for
live entries. A missing guard pointer still reaches the same invariant check.
Scopes unwind before the reverse-order scan, and live entries retain the same
clear-before-resource-close/count-release behavior. Trap-prefix unwind and the
public slot-drop helper are unchanged. No journal layout or public ABI changes.

ASan/UBSan passes all 20 startup/frame scenarios and all three execution
success/trap/fast-exit scenarios. Existing lifecycle fixtures verify guard
clearing, all-pin restoration before resource callbacks, nested guest frame
entry, prefix/full trap cleanup, and repeated normal cleanup after guards clear.
The joined focused RC set passes all 41 tests.

| Backend | Cumulative baseline | Skip empty normal entries | Improvement |
| --- | ---: | ---: | ---: |
| QBE | 1,365,490,061 | 1,280,505,847 | 1.066x |
| LLVM O3/full LTO | 775,491,064 | 702,647,206 | 1.104x |

The table records three interleaved user-instruction medians using Debug
compilers and unchanged depth-12 binary-tree source. Every stdout byte and
complete ownership counter matches: 669,060 allocations/retirements, 19 owner
acquisitions, 669,079 releases, zero holds/clones and 33 uniqueness checks.
Evidence is in `experiments/d9-rc-cleanup-overhead-20260926/`. The result remains
far above GC and is not WP-4 acceptance.
