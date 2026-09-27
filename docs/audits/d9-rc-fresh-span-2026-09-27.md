# D9 WP-4: preflight the complete fresh constructor

This slice removes redundant partial-body journal publication only when a whole
constructor can finish without another fallible operation after its allocation.
It improves the existing depth-12 diagnostic by 6.42% retired instructions on QBE
and 5.16% on LLVM. Ownership traffic and output are unchanged. This is an
incremental result, not WP-4 acceptance; the diagnostic remains about 3.84 times
accepted GC on QBE and 4.50 times on LLVM.

## Proof and implementation

`qbe_rc_fresh_constructor.beginSpan` reuses the existing bounded closed-function
certificate. Scalar locals and self recursion produce linearly consumed fresh
values. It rejects all physical copies, including immutable box aliases, other
calls, captures, semantic sharing, loans, held values, unique resources and arena
transitions. Fallible Result variants are rejected, so their trace construction
cannot call out inside the fast span. Large-result ABIs and output/field layouts
over 256 bytes also refuse. The existing constructor operand bound is 128.

Before allocation or any guard change, each counted source must have a live guard
and exactly the ordinary `COUNTED` role (2). A failed role test enters the original
whole constructor, including its internal partial-body guard, field fast paths
and generic transfer fallback. The certificate proves one inherited region
through recursive calls. It admits a caller already inside an arena without
changing any requested escape region or weakening a barrier.

All source guards remain live during managed allocation and its failure check.
After success, the fast arm only writes existing plain representations, moves
counted bytes, clears the corresponding source guards and publishes the complete
typed output. Inline destination zeroing and tag stores remain. There are no
value-seed, retain/release, drain, contract or finalizer calls in this interval;
the region read is nonallocating. No count acquisition is bypassed: these are
physical token moves between fresh disjoint storage and an existing source.

The heap body or per-instruction aggregate scratch is separate from the stable
operand storage. Every original input is read and its token consumed before the
first logical operand is replaced by the complete result. Consequently source
zero can become the result slot without a second owner or an overwritten live
input. The final publication keeps `values.constructed` and its typed live guard;
normal return and trap frame linkage are unchanged. No frame/state layout or
runtime ABI changes are included. The values helper has only a comment correction.

Independent review by the compiler agent found no blocker in source-zero reuse,
post-allocation operations or named-field ordering. The original field-level fast
path is in both the control and the candidate, so measured gains are incremental
to that earlier optimization.

## Measurements

The cumulative control is source
`7d68202d59cf834bf9649fd77df2000f548ffec9`, real-merged as `4781613e`.
Its immutable Debug compiler is
`d9-rc-integration/.tmp-rc/install-scope-scalar/bin/mylang`, SHA-256
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.
The immutable candidate is
`d9-rc-mut-argument-astra/.tmp-mut-argument/span-candidate/bin/mylang`, SHA-256
`fa98edc4e7a6124db3bd30ac81f2de79949d3396684f6b0d13acbfcf826ccc35`.
The final helper-comment clarification and test corrections change no emission.

The unchanged private n12 source hash is
`97137bff09108d9560736833ae682733abd5d728ca8066edb5cda4caede62a7c`.
Runs use CPU 2, alternating before/after order and the median of three samples.
LLVM manifests confirm the actual LLVM backend, optimization 3 and full LTO.

| Backend | Before instructions | After instructions | After/before |
| --- | ---: | ---: | ---: |
| QBE | 434,533,954 | 406,635,854 | 0.935798 |
| LLVM | 239,809,019 | 227,432,521 | 0.948390 |

Median cycles also decreased: QBE 89,618,544 to 81,449,146; LLVM 57,789,302 to
54,030,665. Every sample's output matches. Both counted executables retain
669,060 allocations and retirements, 19 ordinary acquisitions, 669,079 ordinary
releases, zero holds, zero clones and 33 uniqueness checks. Raw samples are
preserved; there is no full-corpus or acceptance claim here.

The preceding profile identifies the readonly checker exactly as
`myl_f_20f65c28671b40937c5bf23acc7c6f37e5a5ec0622e347b57685725df5ba9e50`.
Its approximate absolute instruction cost is already near GC (LLVM about 13.7M
versus 13.6M). Allocation, retirement and the constructor remain the useful
remaining targets. See the separate
[baseline profile](d9-rc-fresh-field-profile-2026-09-27.md) for sampling limitations.

## Validation and receipts

- 138 focused RC unit tests pass. Five new span tests check live sources across
  allocation, complete fallback retention, alias/callback/H/arena refusal,
  fallible Result refusal and incoming unique-resource cleanup. The existing
  wide-result test now explicitly refuses the whole-constructor arm.
- Forty actual guest assertions pass on each backend, including aggregate
  transactions, semantic history, fresh constructors, fresh returns and four new
  span cases. New cases cover nullable/literal fields, reordered named fields,
  mixed scalar and owned inputs, nested parent arenas, aliases and a recursive
  union whose plain alternative leaves counted fields inactive.
- Thirty-six before/after standalone rows pass: both fixtures in GC stress and
  counted RC, plus memory, logical-frame, step, arithmetic and physical-stack
  refusal controls on each backend. The memory-budget failure occurs after 4,089
  successful child allocations; every allocation retires. All before/after
  counted output and counters match, including 124 nested-arena clones.
- Six production C suites pass with ASan and UBSan: contract, collections, holds,
  arena, stats and execution. They retain count-limit rollback, ownerless holds,
  reentrant finalizers, allocation budgets and deep release controls. Count-limit
  and finalizer paths are not newly admitted by this compiler arm.
- Guardian's unchanged 88 checks pass; no ratchet or rule changes. Parent owns
  the combined full gate and serialized Guardian feedback.

During test preparation, an unhandled Result fixture and a direct open-file
binding passed to another function were rejected by their existing source rules.
The refusal test now inspects a valid typed resource parameter without executing
filesystem I/O. An arena fixture initially declared its escaped local inside the
closing region and correctly trapped; declaring the destination in its parent
region makes the intended parent-lifetime test valid. Initial rejected receipts
are retained separately, along with a resolved Zig local-name shadow error.

`experiments/d9-rc-fresh-span-20260927/` contains reproduction drivers, compressed
measurement/build identities, all validation results, generated fast/fallback
IL, both native `make` disassemblies and check logs. The emitted evidence confirms
that reordered-field `branch` and mixed `literal_chain` really admit fast spans,
while the aliasing constructor and readonly `check` do not. No fixture pass is
being used as a substitute for fast-path emission evidence.
