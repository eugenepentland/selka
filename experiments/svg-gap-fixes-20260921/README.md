# Production SVG performance fixes

This batch qualifies and measures copied block I/O, checked aggregate reads and
scalar projections, and cached net lookups. It compares the combined production
change against the retained pre-change GC/arena binaries and the same-output
Rust, Go and Zig ports. Step accounting remains unchanged.

From the repository root, after a successful compiler build, freeze
`zig-out/bin/mylang` as `.tmp/svg-gap-fixes-20260921/mylang-after`, then run:

```sh
python3 experiments/svg-gap-fixes-20260921/run.py build
python3 experiments/svg-gap-fixes-20260921/run.py qualify
python3 experiments/svg-gap-fixes-20260921/semantics.py
python3 experiments/svg-gap-fixes-20260921/run.py measure
MPLCONFIGDIR=$PWD/.tmp/mplcfg /home/epentland/ai/canopy/rust-workflow/.venv/bin/python experiments/svg-gap-fixes-20260921/charts.py
```

The frozen projects/native ports live in `.tmp/full-svg-benchmark-20260921`;
retained pre-change policies live in `.tmp/svg-arenas-20260921`. These private
binary caches are required to reproduce this exact batch. Their hashes are
retained in the JSON evidence. The original source and native-port provenance is
recorded by `experiments/full-svg-benchmark` and `experiments/svg-arenas-20260921`.

`run.py` builds LLVM O3 + LTO GC and arena policies, both with and without
instruction/call-depth limits. Each arena version wraps the whole invocation in
the language's existing arena region. It verifies SVG bytes, status and located
issues on the three timing inputs and seven additional semantic mutations, both
normally and under GC stress. Bounded builds must also reject tiny step/frame
budgets. `semantics.py` checks LLVM aggregate snapshots and managed fields across
mutation, growth and stress GC, both signs of invalid indices, and `/dev/full`
write failure propagation. It also runs the four output-buffer boundary checks
normally and under GC stress. Those checks live in `bulk_io_test.my` and are
registered by the real provider in `test-schematic`; the standalone language
test runner has no schematic host registrations.

Timing uses fresh processes pinned to CPU 6, 3 warmup rounds, then 31 randomized
interleaved rounds across 11 arms and 3 inputs: 1,023 timed invocations. Every SVG
hash is checked. Compilation, preparation and verification are outside the
timer; startup, input reads, parse/layout/routing, SVG file write and shutdown
are inside. Raw rounds and 95% paired bootstrap ratio intervals are retained in
`measurements.json`. No memory/RSS performance claim is made by this batch.

The retained EDA NetLisp renderer has different output, so this batch's Zig
comparator is the direct port that produces identical SVG bytes.

`validation.json` links the final build and test evidence. C bridge and provider
checks also run under AddressSanitizer and UndefinedBehaviorSanitizer. The direct
provider test specifically verifies that a small write can succeed in the stdio
buffer while the later `finish` reports the `/dev/full` failure.
