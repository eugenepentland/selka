# Cumulative ABI3 checkpoint at 19e16e1d

The frozen Debug compiler joins semantic-history/loan lowering, indexed mutable
places, boxed write-back and GC rooting, compact journals, inert returns and
single-element flat destruction. Exact source/compiler identities, raw log hashes
and summaries are in `identity.json`; compressed files retain original outputs.

All four required gate commands pass: 94/94 main steps (2,260 executed tests),
51/51 QBE steps (438 tests), 29/29 native-build steps and 2/2 formatting steps.
The separate uncached counted-RC language sweeps each execute 842 assertions
across 145 programs. Both actual backends pass 841 and abort on
`field_augmented::test_augmented_list_field_writeback_preserves_record_snapshot`.
There are no cached verdicts, skips, dropped tests or unloaded programs.

This is a retained negative correctness checkpoint, not RC acceptance. The same
immutable compiler is being used for supplemental native golden replay and the
complete performance corpus; those results are separate and not claimed here.
`--release` selects actual LLVM O3/full LTO for the language sweep. The gate and
sweep scripts record exact commands, slot admission, disk scratch and source
freeze checks. Shard-excluded tests in the main gate are not skipped coverage:
its 2,260 executed selections partition the test roots.
