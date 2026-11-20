# D9 WP-4: plain aggregate copy and indexed-store code generation

This is an isolated compiler optimization on `7c78c511`, not WP-4 acceptance.
It does not include the separately measured terminal read-loan optimization or
runtime zero-edge replacement fast path. Neither the main branch nor the accepted
Stage-3 baseline changes.

## Observed cost and change

The cumulative nbody profile identified generic native ownership work for a Body
containing seven floats. Each `advance` has nine static Body update paths and
executes 75 Body stores, so the exact five-million-step workload executes 375
million stores. Previously each path called `myl_rc_native_copy` to prepare the
plain record base and `myl_rc_list_set` to publish its replacement. The latter
performs typed runtime replacement despite there being no owner to replace.

`prepareBase` now copies eligible inline bytes directly into the existing private
per-instruction aggregate scratch. The indexed-store path admits plain aggregates
alongside the plain scalars it already handled, using the existing checked native
store. The emitted nbody `advance` changes from nine native-copy and nine list-set
calls to zero of each; all 24 native-loan calls remain.

## Admission and correctness argument

The compiler's resolved physical shape must have both `counted == false` and
`unique_drop == false`. Thus ordinary managed edges, lifetime-held edges, and raw
unique resources retain their existing paths. In addition, the base must be an
inline record/array with a nonzero layout; managed records and zero-sized layouts
retain their existing storage protocol. The proof uses the physical catalog,
not absence of mutable fields or the absence of a semantic SHARE event.

The destination for base preparation is the same per-PC aggregate scratch used
by ordinary GC aggregate updates. Frame layout gives it a distinct range from
locals, stable RC operands, other per-PC aggregates and collection backing, for
both stack and heap-backed frames. A prior execution's result is copied to stable
local/operand storage before that scratch is reused. A by-reference parameter
names the caller's frame, not the callee's per-PC scratch. Therefore the copy
preserves the complete old base before the update; it cannot destroy a source
field that a later updated field still needs.

For indexed stores, source and destination are whole same-typed values. They are
separate frame/backing regions or identical/disjoint element strides. A same-typed
inline record cannot recursively contain itself without a managed indirection,
which admission rejects. This is the pre-existing GC inline-write alias contract.
The compiler still performs receiver uniqueness, receiver scope handling, region
barriers, negative-index normalization and the same detail-bearing bounds check.
RHS evaluation order and the snapshot copy remain unchanged.

Eligible bytes contain no lifetime token and require no destructor or callback.
Skipping the temporary internal ownership registration therefore loses no cleanup
obligation on a bounds or arithmetic trap. The regular finishing path still drops
consumed operands and clears the internal guard. Ineligible values continue
through the original transactional helper path, including its failure handling.
No runtime ABI, journal layout, allocator or semantic-history rule changes.

The skipped generic helpers also contain a drain boundary. The existing public
contract in `native_rc.h` guarantees no deferred dead queue at ordinary guest
entry: public runtime operations drain before returning, while reentrant work
inside a finalizer is already under an active drain. Edge adapters cannot invoke
guest code, and arena finalizers run before arena edge release. Copying these
owner-free bytes cannot itself enqueue a dead object. Thus this compiler path
does not skip observable queued cleanup; the separate generic runtime fast path
must retain its pending-queue check because it also serves non-guest callers.

## Measurement

The immutable Debug control compiler is SHA-256
`1b85b2f80b4b229b7bed0c8a120457df28892501edbd0b4732ebb338cd334f8b`.
The immutable candidate is
`49372ab04bd2c1408398f7be97e8b7ec2abbca0a6d0f9872226f322cb8bea3a1`.
The source is the real nbody benchmark with only `steps = 5000000` changed to
`steps = 10000`; both original and diagnostic hashes are in the receipt.
CPU 2, alternating before/after order, median of three retired-instruction samples:

| Backend | Before | After | After / before |
| --- | ---: | ---: | ---: |
| QBE | 4,712,797,904 | 3,305,881,523 | 0.701469 |
| LLVM O3, full LTO | 3,680,960,711 | 2,557,256,275 | 0.694725 |

Output and every counter are identical: heap allocations/retirements 2/2,
ordinary acquire/release 1/3, hold acquire/release 3,620,039/3,620,039,
20,007 uniqueness checks and no clones or arena allocations. This optimization
removes generic work on values that already had zero ordinary-count traffic;
it does not eliminate the remaining list lifetime work. These are reduced-input
instruction diagnostics, not the full 43-program wall-time acceptance gate.

The immutable accepted-f6 GC compiler independently produces the same two output
lines, `-169075163` and `-169016441`. Its reduced-input instruction medians are
66,185,059 QBE and 7,395,983 LLVM O3/full LTO. Consequently this isolated candidate
still takes 49.95 and 345.76 times those diagnostic instruction counts. The
substantial remaining gap is explicit; the isolated percentage gain does not
establish acceptable overall performance.

## Validation and receipts

Three focused codegen cases cover eligible plain record updates, managed-field
fallback and zero-sized fallback. The complete `RC` unit selection passes 118
tests. The permanent guest fixture covers snapshot independence, identical and
neighbor element copies, nested arrays, RHS callbacks, older-region receivers,
plain fixed arrays and zero-sized elements. Standalone before/after controls run
in GC stress and counted RC on both actual backends; bounds and arithmetic traps
retain their located details and balanced counts.

Existing array-place, negative-index, large aggregate-reference, owning aggregate
and dictionary-view fixtures exercise the surrounding paths: 82 actual assertions
pass per backend, including the seven new cases. Whole-tree Guardian
passes all 88 checks without changing any budget. The parent runs the serialized
full integration gate; this branch does not start a competing full gate.

Raw compiler/binary identities, manifests, commands, all samples and counts,
standalone diagnostics, guest results and emitted `advance` bodies are archived
under `experiments/d9-rc-plain-aggregates-20260926/`. The full-source nbody profile
that motivated this change is maintained separately by the parent.
