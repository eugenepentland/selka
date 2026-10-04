# Independent review of bounded loop-copy admission

Reviewed production commit `5dc31c3af5114938fe1c92fc72941efd0b3074c3` in
`perf/goal110-calls-20261004`. All five changed source/spec files matched that
commit before recording this review. No blocking semantic or allocation-ownership
defect was found. This is code/correctness evidence; it contributes no runtime
timing or LLVM 1.10 confirmations.

The change is confined to native copy admission. Source certification/model
changes are comments only: the 16-literal/64-condition limits, immutable and
unaliased i64 selector, counted single-entry loop, joined-producer refusal,
interior-entry checks and step/frame-accounting refusal remain. Native region,
block, input-text and aggregate copied-text caps remain unchanged. Copies are
measured after label renaming and branch folding, sorted by exact byte count
with original ordinal ties, then selected as the fitting prefix. Once a sorted
copy exceeds remaining room, every subsequent copy also exceeds it. The sum of
selected text is bounded by 256 KiB, twice the region, and the function allowance;
these bound copied text, as before, rather than the guard/fallback overhead.

Selected equality guards use the original value/ordinal pair, even after sorting.
Each guard targets its own renamed header. An excluded certified value or an
unknown value passes every emitted guard and enters the full original graph,
renamed without folding. Pure guards add no body effects on zero-trip loops.
Selected copies retain original operations/PC stores and shared external exits;
only certified decisions are folded and unreachable blocks pruned. Uncertified
joined/short-circuit decisions remain. Instrumentation still runs after copying,
so duplicated sites receive unique symbols with original stored PCs. The earlier
whole-copy callbacks, mutation, RC/GC, division, bounds, overflow and accounting
checks remain relevant, while partial admission has a distinct outcome fixture.

Two test gaps found during review were corrected before the stable commit. The
original cost fixture had the cheap source-first copy and could pass without
sorting; it now puts an expensive value first and requires the later cheaper
value's guard to precede it, while checking source-order ties and excluded-copy
absence. The original native outcome fixture admitted all three copies; the new
ordinary dynamic fixture explicitly requires `0 < guard_count < 3` before
running every certified value, an unknown value, zero trips, bounds failure and
signed overflow. It compares accounted/unaccounted status, result, complete
trap, stdout and stderr. Existing joined-comparison tests assert actual emission,
so their semantic comparisons cannot pass merely because this policy falls back.
The implementation agent's final filtered native log reports 17/17 passed and
the agent reports command exit 0. The log's trailing `failed command` diagnostic
is misleading and is retained as a receipt limitation; those native tests were
inspected, not independently executed here. New partial native outcomes are RC
QBE comparisons; existing whole-copy GC checks remain, and LLVM guest holdouts
are still needed for this changed mechanism before campaign acceptance.

Cleanup was audited through every failure return. `buildCopies` frees preceding
owned copies until ownership transfers; each reachability array, rename prefix
and local writer has a defer; `Copies.deinit` frees selected and omitted copies
once after sorting. The output writer has an error defer and successful slice
transfer resets its buffer. The installed Zig `Allocating.toOwnedSlice`
implementation retains the writer buffer on allocation failure, so its defer
cleans it; successful transfer resets the writer and avoids a double free.
Two independent `checkAllAllocationFailures` scenarios passed: admitted rewrite
with several copies, and zero-fitting-copy refusal preserving identical text.
They ran in the reporting worktree through the build-slot wrapper with private
disk TMPDIR/caches and no timed guests. The isolated component harness uses exact
committed text/model snapshots and the actual Predicate enum, plus the existing
text fixture/certificate; it does not test source certification or execute native
programs. The new implementation materializes all bounded copies before choosing
the fitting set, so compile memory/work may increase relative to early budget
refusal. That tradeoff is bounded but has no compile-cost measurement here.

[review-receipt.json](review-receipt.json) binds the production file hashes,
commands, tool, inspected native log and independent test artifacts.
[allocation-review.tar.gz](allocation-review.tar.gz) retains the isolated fixture,
exact snapshots and successful two-test log. To reproduce, extract into a private
directory, set disk TMPDIR/private Zig caches, and run through
`scripts/build-slot.sh build zig test allocation_review.zig` using the recorded
Zig toolchain. No canonical dashboard or candidate-owned file was edited.
