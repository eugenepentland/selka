# Post-allocation instruction-gap evidence

Read the [audit](../../docs/audits/d9-rc-post-allocation-gap-2026-09-26.md) for the
frozen source, accepted GC baseline, limits and next proof boundary.

`gap-allocator.json` contains original n12 median-three samples and exact RC
counters. The repeated source invokes that same workload 240 times; its weighted
instruction samples and assembly are compressed text. `profile-metadata.json`
records binary hashes, manifests and sampling statistics. `gap-allocator-analysis`
uses binary-filtered denominators for its `shares` and `make_ranges`, while
`global_symbol_shares` and `all_period_sum` include other loaded objects. The
audit's summary percentages use the global denominator.

The scripts preserve their original private-worktree commands and expect the
corresponding immutable installations under `.tmp-rc/profile`. Build scripts run
through `scripts/build-slot.sh build`; measurements run separately on CPU 2.
No performance acceptance criterion changes in this experiment.
