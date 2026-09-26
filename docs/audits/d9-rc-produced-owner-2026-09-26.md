# RC immediate producer ownership proof — 2026-09-26

The compiler skips the initialization-guard branch when the immediately preceding completed instruction unconditionally published an ordinary operand owner. Eligible producers are calls, record/variant constructors, explicit value copies and local moves. The proof rejects alternate entry to the consumer, active receiver captures, borrowed bodies, terminal held mappings, unique resources, other instructions and non-top operands. It adds no persistent compiler state and never carries a proof across an intervening instruction.

The existing typed TAKE still checks pin and arena headers and preserves its fallible runtime path. Source ownership is disarmed only after success. Borrowed reads retain guarded copy/take selection.

The structural positive/counterexample selection passes 12 assertions including imported tests; the Debug build passes Guardian88. Actual uncached RC execution passes **96 assertions on each QBE and LLVM backend**, including aggregates, arenas, temporary/receiver lifetimes, unique capabilities, borrowed results, dictionaries and callback captures. LLVM uses O3/full LTO. These are focused checks; the integration gate remains separate.

Against source `2c0f7bde`, the private n12 binary-tree diagnostic has after/before median-three instruction ratios **0.992138 QBE** and **0.989803 LLVM**. Every output and counter is unchanged: 669,060 allocations/retirements, 19 additional owner acquisitions, 669,079 releases, no H tokens or clones. QBE samples are separated, while LLVM sample ranges overlap, so the LLVM gain's size remains uncertain. This is not full-corpus acceptance.

Complete source, candidate patch, commands, compiler/binary hashes, all instruction samples and guest verdicts are in [the experiment directory](../../experiments/d9-rc-produced-owner-20260926/).
