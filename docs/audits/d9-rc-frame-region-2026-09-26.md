# RC stable frame region depths — 2026-09-26

RC functions containing no arena boundary instructions now read the region depth once at frame entry and reuse that SSA value for typed transfers. Callees restore their own arena scopes before returning, so the caller's depth remains fixed. Functions containing an arena begin/end retain a fresh runtime depth read for every transfer. Frames opened inside an older caller arena therefore retain that caller depth; this optimization does not assume depth zero or remove arenas. It adds no compiler-state field or runtime ABI change.

The positive/dynamic-counterexample structural selection passes 12 assertions including imports; Debug install and whole-tree Guardian88 pass. Actual uncached RC execution passes **98 assertions per backend**, including arena escape, nested held views, callbacks, unique capabilities and borrowed returns. LLVM uses O3/full LTO. Full integration checks are separate.

The private n12 diagnostic against `0b47cfcf` has median-three after/before instruction ratios **0.955197 QBE** and **1.000117 LLVM**. QBE improves by about 4.5%; LLVM is effectively unchanged, with one higher sample retained in the evidence. Outputs and all counters remain identical: 669,060 allocations/retirements, 19 additional owner acquisitions, 669,079 releases, zero H traffic or clones. This is not complete corpus acceptance.

The source/patch, commands, compiler and binary identities, all samples and guest verdicts are preserved in [the experiment directory](../../experiments/d9-rc-frame-region-20260926/).
