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

The second slice changes only the private invariant helper: its condition is
inline, while a failed condition calls a cold, nonreturning abort function.
Every production check remains active and every argument is evaluated once.
The new fixture verifies single evaluation and uses a child process with core
dumps disabled to verify failure still terminates with SIGABRT. The public
runtime ABI, ownership rules, allocation refusal and count-limit statuses are
unchanged. Both QBE and LLVM artifacts retain only the failure helper symbol.

ASan/UBSan passes core 21, collections 27, holds 12, arenas 10, stats 4,
execution success/trap/fast-exit 3 and startup/frame 20. All 41 focused RC tests
pass, including the new abort regression through the linked C fixture.

| Backend | Cumulative baseline | Empty scan | Plus inline checks |
| --- | ---: | ---: | ---: |
| QBE | 1,365,490,303 | 1,280,505,140 | 1,240,714,730 |
| LLVM O3/full LTO | 775,491,060 | 702,690,827 | 702,646,748 |

The invariant change adds a 1.032x QBE instruction improvement; LLVM is
unchanged within 0.01%. Together the two runtime slices improve the cumulative
baseline by 1.101x QBE and 1.104x LLVM. These are three interleaved medians with
exact output and complete counter equality across every arm. Remaining cost
is still far above the GC reference. Newer root compiler guard/metadata/region
experiments are absent from this isolated comparison.
