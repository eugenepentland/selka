# Readonly callers of managed borrowed helpers

This isolated compiler change removes ownership bookkeeping from a closed scalar
caller only when every managed helper call has an exact public borrowed-entry
certificate. The caller and every plain dependency also pass the production
ownership/COW planner preflight. Immutable byte indexing remains bounds checked.

The three unchanged schematic workloads improve by 23.6–24.2% in QBE instructions
and 24.5–28.4% in LLVM instructions. They still use 12.07–12.14× and 17.57–18.13×
the archived accepted-GC instructions. This is not Stage 4 performance acceptance;
no runtime-default, full-corpus or guest-RSS claim is made.

`schematic.json.gz` contains 36 raw, unscaled CPU10 instruction samples, exact SVG
checks and 12 separate counted runs. Compiler and executable manifests identify
actual QBE and LLVM O3/full LTO. `accepted-gc.json.gz` is the exact older accepted
receipt supplying the denominators, with its original path/hash in `identity.json`.
`source.patch.gz` applies to `6edbe2ed77fc0aaa0e06cdc06dd09b33d731923c`, the real merge
of the named-record change and readonly-v1 prerequisite. The complete changed
production/test files are in `source/`; later reports do not affect the compiler.

**Known baseline failure:** the combined managed-result control's LLVM
ReleaseFast RC wrapper fails frame-map validation both before and after. A fresh
isolated before cache reproduces it. Those two failed builds are not passing
controls. The same complete fixture passes Debug LLVM; separate small and
4816-byte result wrappers pass ReleaseFast LLVM before and after. Original
receipts, sources and commands are preserved in `controls*.json.gz`,
`baseline-llvm-fresh.json.gz` and `split-controls.json.gz`.

Passing controls total 52 guest assertions, 20 exact bounds/step/frame traps and
four successes, with balanced RC counters. Both GC-stress fixture binaries are
unchanged for each actual backend. Cache edits and loss of the managed helper's
certificate invalidate the caller identically in warm/cold caches. Emission
archives show `sexpr::form` calling two `_rc_borrow` entries with no loan/retain
or RC frame, while previously admitted v1 helpers keep byte-identical IL.

Run `python3 experiments/d9-rc-readonly-managed-calls-20260927/verify.py` for the
self-contained archive checks. Add `--live` to verify preserved local compiler,
guest executable and source identities. The verifier recomputes medians and
requires every raw instruction event to report 100% running. No benchmark rerun
is needed. Historical failed intermediate checks remain in `logs/`; only the
final receipts listed above support the result.
