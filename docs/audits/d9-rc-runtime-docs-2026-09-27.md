# Experimental RC documentation and managed example repair

The managed-memory and native-build guides now describe explicit GC, RC and
counted RC selection, unchanged value/arena rules, legacy normalization, build-time
artifact contracts and instrumentation. D3 and D9 record the accepted integration
stages while keeping the RC default transition conditional on performance
acceptance. This documentation does not claim Stage 4 completion or change a
runtime selector.

Review against `runtime_contract.zig`, `main_runtime_mode.zig`, native manifests
and `native_heap.c` also corrected obsolete descriptions of the retired tracing
implementation: the native collector uses typed roots and byte/budget triggers,
and has no guest `memory.gc.statistics` API. The legacy cycle example remains a
GC example. A future RC default change must update these current-default clauses
alongside the selector and its compatibility tests.

The previously documented `examples/gc-default/main.my` still assumed that
assigning a list created a shared mutable alias. Both GC and counted RC reproduced
`R_LIST_BOUNDS`: the original empty list was read after only its independent copy
had grown. The example now asserts that the original stays empty and computes its
documented result from the changed copy.

Using immutable Debug compiler `468bd8e5`, SHA256
`082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e`:

- The repaired example prints `142` and returns exit status 142 under GC stress
  and counted RC on both actual backends; RC counters balance.
- All 13 runnable managed-memory documentation blocks pass with inherited GC
  and again with inherited RC. The explicit legacy-sharing block correctly uses
  GC in both runs.
- Feature/document coverage has zero failures. The example passes `fmt --check`
  and whole-tree Guardian passes all 88 checks without a waiver.

The [archive](../../experiments/d9-rc-runtime-docs-20260927/README.md) retains both
original failures, both source versions, all corrected outcomes and documentation
reports. Frozen joined source `2ca89942` passes the complete four-command gate:
2,315 executed main tests, 440 QBE tests, 29 native-build steps and two formatting
steps, plus all 88 whole-tree Guardian checks. The main gate reports 23,608 shard
exclusions separately from executed tests. The [joined receipts](../../experiments/d9-rc-runtime-docs-20260927/joined-gate/README.md)
record exact source and artifact identities. Production compiler/runtime source is
unchanged from `468bd8e5`, whose 931-assertion RC sweeps on each backend remain
valid for that source. The full RC instruction/RSS gate and final default
transition remain open.
