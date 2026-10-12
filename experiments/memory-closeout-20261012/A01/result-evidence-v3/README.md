# A01 Result-list private qualification

Compiler SHA256: `a6795771960a0540e9c573b99dc5117d8450b8010e242ed485744eb725edf320`.
Source label: `38dc781a897+A01-Result-draft-v3`; this is an uncommitted private
implementation snapshot, not integrated C1. It predates the final symbolic-cycle
memoization fix and its regression. Final integrated qualification remains required.

`result-list-matrix-v3/results.json` records all eighteen successful executions:
release, unoptimized debug, verified release, optimized debug, release without facts,
and ThreadSanitizer, each at 1/2/8 workers. All fifteen counted executions have zero
RC events, zero emitted RC operations and zero exit-live managed bytes. LLVM/symbol
audits find no legacy RC helpers. The three TSan executions pass without diagnostics.

`result-list-repeat-v3/results.json` adds 100 release and 100 TSan executions at eight
workers using the exact preceding binaries; `qualification-input.json` snapshots
the consumed manifest. These exercise managed success/error payloads, independent
copies, pop transfers, borrowed inspection, empty/uneven input, nested Results,
nested maps, comprehensions and explicit discarded output. This is correctness
evidence, not uninstrumented timing or RSS evidence.

Frozen fixture: `samples/result_list.my` in the parent A01 directory, SHA256
`6c5ad78bda5b1908889e1a32956456bacbf615ecbc5d36b2fbc7100875865cf6`.
Output: `27 4 5 4 5\n3889\n`. The unhandled-list fixture is refused with
`E_RESULT_UNHANDLED`. C0 refuses the positive fixture with `E_GENERIC_REQUIREMENT`;
A03 keeps this denominator entry and A08 tests the cache transition.

`result-final-focused.log` records five Core and twenty-one frontend checks passing,
including cross-module public interfaces and preserved resource/capability/dict/set/
boxed/generic-copy boundaries. `result-boundaries/` keeps individual source inputs
and diagnostics. Its later `generic_cycle.my` attempt uses unsupported generic record
unpacking and fails with `E_TYPE`; it is not evidence for the cycle fix. The separate
`src/a01_result_shapes_test.zig` metadata regression covers that defect precisely.

`prototype-final-matrix-v2/results.json` preserves the earlier map prototype matrix:
all eighteen combined-source executions pass. Its eighteen trap executions produced
the expected division-by-zero and `(item 17)`, but were recorded as failed because
the old oracle required `parallel.map item 17`. The current harness corrects that
oracle; these raw failures remain visible and need a fresh final rerun. Fatal trap
exit-live counters are not treated as leak-free normal exits.

Compressed counters are original JSON bytes compressed with reproducible gzip time0.
`qualify-v3.py` is the exact consumed harness, SHA256
`a91f2adc4c1c8b183a2d0003d7386e02228f8edbba04b2bac88d9949552663db`.
`sha256.json` records archived evidence identities. Original absolute paths describe
this machine; checked-in harnesses accept new compiler/output paths for reruns.
