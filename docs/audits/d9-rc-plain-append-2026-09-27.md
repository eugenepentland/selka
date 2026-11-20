# RC scalar append with spare capacity — 2026-09-27

This slice avoids the generic publication machinery for one already-evaluated
plain scalar when a list has spare capacity. The actual COW uniqueness checks,
owner journals, pending receivers and growth path remain in place.

The compiler admits only scalar layouts of 1, 2, 4 or 8 bytes with no counted or
unique edges. It captures the scalar bits before mutation, checks `length <
capacity` and `generation != UINT64_MAX`, then calls the nonmutating
`myl_rc_list_plain_ready`. That query requires an RC heap, no queued deaths, an
actual native plain/float scalar element and an already registered binding whose
flat plan has zero edges. It neither registers metadata nor drains callbacks.
The binding proof excludes finalizers and custom ownership hooks. No admission
is cached across another operation.

After success, no allocation, callback or failure lies between reading backing
and writing the scalar, length and generation. Valid capacity bounds the byte
offset and length increment; the separate generation guard preserves overflow
refusal. The helper cannot change the saved header values. Every refused check
uses the original append helper with the original source address and failure
mapping. Growth preserves backing relocation/alias handling and receiver region.
There is no presizing, ownership-frame elision, mutable-uniqueness relaxation or
GC lowering change. The internal C helper adds no layout or ownership ABI change.

The runtime contract worker independently reviewed these boundaries without
finding a blocker. The queued-finalizer C regression observes the old length and
changes an aliased source scalar: the retained generic path captures its old
bits before the callback, then publishes them. Cold descriptors, finalized,
managed, held, raw-unique and nonscalar types refuse. Tests also cover generation
overflow, aliased growth into an older receiver and an exact budget refusal.

## Measurements

The immutable before compiler is the joined `a9eae92e` Debug build, SHA256
`5fb1935f74b11dd59bb6f21dbbe1f98f2637bd3a80c7504aaab933bcaddedb46`.
The candidate Debug compiler SHA256 is
`d048016b4b097c4a3ec1ab3d2b5a01fd404943c134207f88ff9bcbec00316637`.
The parent source is `c16a1c6a5da4b642fcdbe039bbe409f3208570f8`, a real merge
containing that same production baseline plus the prior composition receipts.
The archive records the exact changed source identities and patch.

All unchanged full-size sources run on CPU 10 with three `instructions:u`
observations per binary. QBE guests use ReleaseFast; actual LLVM manifests prove
O3 and full LTO. Separate counted binaries preserve every counter exactly across
both arms and backends. The accepted GC binaries are independently hash-checked
and remeasured for the residual columns; these are actual counters, not multiplied
component estimates.

| Workload | After/before QBE | After/before LLVM | After/accepted GC QBE | After/accepted GC LLVM |
|---|---:|---:|---:|---:|
| alloc_churn | 0.842390 | 0.749490 | 2.832940 | 2.971290 |
| fannkuch_redux | 1.000000 | 0.994421 | 1.744179 | 1.016339 |
| sieve | 0.713356 | 0.508156 | 7.747745 | 15.351200 |
| list_append_sum | 0.553588 | 0.345387 | 4.522380 | 5.484580 |

All 48 RC timing executions, 24 accepted-GC timing executions and 16 counted
executions have exact output. Allocations retire and O/H totals balance. The
fresh uniqueness proof's counts remain unchanged: alloc_churn 1,000,000,
fannkuch 10, sieve 6, list_append_sum 1. The residuals still fail Stage 4 acceptance;
this is one bounded performance component, with no RSS/corpus-wide verdict.

## Validation and receipts

- 148 focused RC tests, including the emitted room/generation/runtime-admission
  guards and generic managed/aggregate fallback; whole-tree Guardian 88 and fmt.
- 42 production collection cases under ASan/UBSan. Two initial budget-test
  assumptions were corrected: freeing unused allocator slabs can allow growth at
  the previous byte total, so the permanent refusal uses an explicit lower limit.
- 364 uncached assertions over ten suites, GC stress and counted RC on both
  actual backends. Six permanent append cases cover all scalar widths, snapshots,
  callbacks, heap/arena lifetime and excluded managed/inline elements.
- Forty before/after standalone controls preserve zero-iteration behavior,
  growth-budget, arithmetic, bounds and iterator-mutation traps. The iterator
  case deliberately creates spare capacity before entering the loop.
- Both unaccounted six-case RC programs pass with identical balanced totals:
  87 heap allocations/retirements, six arena allocations, O 31/118 and eight H pairs.

The initial zero-name test filter was rejected by Guardian and corrected; no
zero-test run is counted. Source style/spec findings were corrected before the
successful build. The initial iterator control discarded a non-unit `pop()`
result and was rejected by the checker; the fixture now explicitly discards it
with `_ =`. Its failed receipt is preserved, and all eight affected runs were
reexecuted. No gate was bypassed.

[Reproducible archive and verifier](../../experiments/d9-rc-plain-append-20260927/README.md)
retain source/compiler/binary hashes, manifests, emitted code, exact commands,
raw perf records, outputs, counters, controls and sanitizer logs. All immutable
compilers and measured binaries remain in private scratch; no accepted artifact
was rebuilt or overwritten.
