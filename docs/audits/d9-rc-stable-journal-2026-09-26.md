# Stable RC operand journal addresses — 2026-09-26

Generated operand and pending-value journal entries now update only the type descriptor and ownership flags at publication. Frame entry already initialized their storage/guard addresses, and every later publisher uses the same operand buffer or pending work buffer. Local and partial-construction entries retain full metadata publication because their address contracts differ. Held-view publishers retain their complete role updates; ordinary publication still restores the current typed role. Guards become live only after metadata and ownership commit.

The complete writers audit covers `qbe_rc_values`, `qbe_rc_aggregate`, and `qbe_rc_views`: all operand slots use their corresponding `rcs` buffer and every pending entry uses `rcwork`; the separate internal construction slot can change addresses and is excluded. `stableEntry` rejects local/internal indices. The runtime frame layout and compiler state size are unchanged.

Focused frame tests pass 33 assertions; the Debug build and whole-tree Guardian pass. Two new guest regressions exercise repeated ordinary/held aggregate reconstruction and arena escape. Those and the broader aggregate, capability, callback, borrow and lifetime selection pass **98 actual RC assertions per backend**, uncached. LLVM is O3/full LTO. Full integration validation remains separate.

The private n12 binary-tree diagnostic against `2ad450cd` reports after/before instruction medians **0.979373 QBE** and **0.971918 LLVM**. Outputs and all counters remain identical: 669,060 allocations/retirements, 19 additional owner acquisitions, 669,079 releases, zero H traffic and clones. This is focused evidence, not complete D9 corpus acceptance.

Commands, compiler/binary hashes, source/patch, all instruction observations and guest results are preserved in [the experiment directory](../../experiments/d9-rc-stable-journal-20260926/).
