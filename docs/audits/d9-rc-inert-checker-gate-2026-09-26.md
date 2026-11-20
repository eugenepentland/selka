# RC return-path and checker checkpoint, 2026-09-26

Frozen source `78ac051c` passes all four required gate commands and separate
uncached counted-RC language sweeps on both actual native backends. This
checkpoint joins compact journals, the bounded inert-return optimization
`e8696c13`, and indexed mut-argument checker accounting `3b5f54b0`.

| Check | Result |
|---|---|
| Debug install | 19/19 steps; Guardian88 |
| Main gate | 94/94 steps; 2,246 executed tests; 22,849 shard-excluded entries |
| QBE gate | 51/51 steps; 437 tests |
| Native-build gate | 29/29 steps |
| Formatting | 2/2 steps |
| Actual counted RC, QBE | 804/804 executed assertions across 141 programs |
| Actual counted RC, LLVM O3/full LTO | 804/804 executed assertions across 141 programs |

Neither RC sweep reused cached verdicts, skipped tests, dropped tests or left
programs unloaded. The source stayed frozen through installation, the serialized
four-step gate and both sweeps. The immutable Debug compiler is retained at
`.tmp-rc/install-inert-checker/bin/mylang`, SHA256
`428052c91fa5f31f8992de456b259e546034f3e4d3d4952d3807f28c0553737a`.
Commands, complete logs and JSON are in
[`experiments/d9-rc-inert-checker-gate-20260926`](../../experiments/d9-rc-inert-checker-gate-20260926).

The [return-path measurements](d9-rc-inert-return-2026-09-26.md) improve the
isolated tree probe by 24.7% QBE and 16.4% LLVM, but still cost 6.46× and 7.69×
the accepted GC baseline. No complete instruction/RSS acceptance is claimed.

Private ABI3 semantic-history work is not included. Boxed write-back, indexed
mut-argument code generation and recursive resource admission remain active
correctness follow-ups. A new standalone boxed-repeat probe also differs from
its accounted guest-test execution under GC; the positive sweeps above do not
establish correctness for that probe. GC remains the default, WP-4 is unfinished,
and `main` and the devspeed merge are untouched.
