# D9 RC optional constructor experiment — deferred

The candidate directly published an optional payload after its existing pin-aware transfer, avoiding the intermediate optional aggregate journal. It was tested against `b49f0f8c` on the private n12 binary-tree diagnostic. Three interleaved instruction samples per backend gave after/before ratios **0.963632 QBE** and **1.013238 LLVM O3/full LTO**. Outputs and counted ownership totals matched.

The LLVM regression does not justify adopting the change. The source, specification bullet and candidate regressions were restored to the parent; only evidence is committed. The aggregate-focused suite passed 12 assertions and the Debug build passed Guardian, but the planned expanded guest suite and full gate were not run on this discarded candidate. This is neither full-corpus performance acceptance nor a correctness sign-off.

The complete candidate patch, measured source, commands, compiler and binary hashes, counters and samples are in [the experiment directory](../../experiments/d9-rc-niche-deferred-20260926/). `guests.py` records the unexecuted follow-up, not passing evidence.
