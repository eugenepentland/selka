S2-F qualification repairs

The first cold runtime compile failed at `isnan` in the port (C99 forbids
implicit declarations). Adding `<math.h>` fixed the compile. A concurrent
cold conformance launch also left an 824-byte runtime object with no symbols,
so subsequent suites were started only after a serial guest build had warmed
the private runtime cache.

Command: `scripts/build-slot.sh build -- python3 experiments/new-core-s1-20261005/conformance.py callbacks python_arrays array_negative_index array_places array_writes keyed_sorting lambda_sort_keys sorted_keys --jobs 3 --why --mylang /home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s2-integration/zig-out/bin/mylang`

The affected source tree initially reported keyed record sorts as false at
both modes. `row_sort_records 4 1 7` printed checksum `58` instead of `5186`.
The exact cause was inferring element stride from `reserved`: unmanaged
record lists carry no child-reference layout, so a 24-byte record was copied
and permuted at an assumed 8-byte stride. The builder now passes both actual
module strides in one packed u64 runtime argument. The validated smoke
checksum is `5186` and focused conformance has zero mismatches.

Enum-keyed fixed arrays initially failed IR verification because the source
index was a payload-free union rather than an integer. Normalizing through
`union_tag` preserves the checker-approved case order and fixes the signature.

Callbacks initially passed debug but crashed the release compiler at
`inline.zig:90` (a map lookup at ref 4294967295). The leaf inliner did not clone
blockless `func_ref` constants returned by a chooser. It now clones them,
folds the resulting known calls, and excludes unresolved indirect calls from
leaf eligibility. The callback file now matches all 8 tests in both modes.

These were explained implementation errors. The coordinator received the
stop signal before the keyed-sort repairs and authorized the narrow fixes
once the cause was established. No language behavior or frozen IR changed.

The first held lane gate completed in 252.95 seconds with 186/189 tests
passing. The remaining failures were obsolete Wave A fixtures: fixed-array
and function-value refusal expectations, and `list_sort` on a null/undef
list. The latter native exit 255 is explained by the invalid handbuilt input,
not by a source program. The fixtures now use a real empty list and retain
the failure-cache regression with an unsupported capability field. The
initial nested wrappers released the outer gate descriptor; that attempt
was stopped and `test-core-unheld.log` is not qualification evidence. A
parent shell now retains the gate descriptor across the build-slot child.

The next held gate completed in 241.31 seconds, 187/189 passing. Two exact
refusal expectations still used the wrong text: a Stream-bearing record is
refused as `record field type`, and F's temporary text-index stub says `index
of a non-array`. Both expectations now match the actual precise refusals.

The first Guardian run failed spec-tag placement, anytype-budget, dead-pub
and line-length. Primary tags belong on tests; the two target tests now use
spec-case and helper doc comments describe behavior. Array node helpers now
use their concrete checked types. The consuming sort shares flags' symbol;
the emitter's small sort case avoids a third generic helper. Named call
contracts keep argument lines readable without changing the ABI. Cold Zig
adapter typing repairs were dereferencing the module pointer passed to
sortKind and giving the staged call-contract value its declared struct type.
Guardian then passed all 88 checks.

An added ownership fixture attempted to form a value from a function with a
mut fixed-array parameter. The accepted old frontend rejects this with
E_CALLBACK_TYPE (PY-ARRAY-MUT-1), before either core executes. The fixture and
fuzz generator now use legal mut list[str] callbacks; fixed-array mut updates
remain direct calls. The failed ownership report preserves the exact old
frontend diagnostic. No language change was needed.

The first sort_records row missed the size-64 performance gate: 62.088
cycles/element versus Zig ReleaseSafe 50.780 (1.223x), with identical checksums.
A 611-sample CPU10 profile attributed 32.96% to the keyed runtime and 5.58%
to the memcpy PLT, with more copy instructions inside the runtime. The
borrowed owning clone was entering the in-place cycle permutation path.
The existing sorted-copy path instead gathers from the unchanged source
into that clone. The clone already owns the full reference multiset, so
reordering it changes no child count and needs no ownership or IR change.
The coordinator approved this repair. Affected leak/verify tests passed
36/40 (0 mismatches; four outside-scope blockers). The new size-4096/64 row
is 31.086/39.806 versus Zig 117.620/51.026 (0.264x/0.780x), with every
configuration's checksums equal. Only the changed row was remeasured.
