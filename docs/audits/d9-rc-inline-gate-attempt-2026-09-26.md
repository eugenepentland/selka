# RC inline-transfer integration attempt — 2026-09-26

Source `c09fce2b` and Debug compiler SHA-256 `2b8ed635ac605465afb2c34e98e6412e9f68dd263862a7c15273399a7047c96b` pass both actual RC language sweeps: **747/747 tests on each backend**, 130 programs, zero cached, skipped, dropped or unloaded. LLVM uses `--release` (O3/full LTO), without an overriding QBE option.

This source **does not pass the full gate**. `zig build test --summary all` reports 79/94 successful steps and two failures:

- The minimal `SlotEmitter` mock lacks the full emitter's `cow` field after inline TAKE was introduced. The runtime-publication assertion needs to target the runtime transfer primitive. The compiler and actual RC sweeps build and run, but the complete unit root does not compile.
- GC-stress language tests pass 746/747. `rc_mut_uniqueness::test_rebinding_a_mutable_parameter_requires_fresh_uniqueness` fails. The new regression also fails on the accepted GC compiler `f6bea5d9` on both native backends, exposing a pre-existing mutable-parameter uniqueness defect.

The remaining gate commands were not run after the first command failed. The last full-green source remains `3f300771`; this attempt cannot replace it. Complete logs, sweep verdicts and identities are retained under `evidence/d9-rc-inline-attempt-*`.
