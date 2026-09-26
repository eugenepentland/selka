# D9 WP-4: cached ordinary-edge release

The first slice reuses the immutable private flat plan for `myl_rc_native_drop`.
Admitted records/arrays contain at most eight unconditional ordinary owner
leaves. Registration already excludes H edges, raw unique kinds, variants and
custom descriptor callbacks. The offsets preserve the authoritative shape
walk's depth-first field/index order, including fields not ordered by address.

The helper clears each physical pointer slot before enqueueing its owner
release, without draining, allocating or borrowing the descriptor walker.
Typed drop then zeroes the complete value before draining, just as the generic
path does. Null, arena and literal edges retain the existing count guards;
pinned objects may reach O0 while their holds preserve lifetime. Duplicate
aliases release one token per physical edge. Generic and ordinary-pointer
paths remain available; there is no public ABI or metadata layout change.

Production ASan/UBSan checks pass: core 20, collections 26, holds 12, arenas 10,
stats 4, and execution success/trap/fast-exit 3. The new test deliberately lists
record fields out of memory order, repeats one alias, retains a pinned last
owner, includes arena/literal/null leaves, closes the allocation budget, and
checks exact finalizer order plus complete value clearing before callbacks.
All 37 focused RC tests pass.

The isolated O2 C copy/drop diagnostic improves from 1,015,144,525 to 651,143,727
median user instructions (1.559x), with 500,000 iterations of eight repeated
owner leaves. This measures copy plus drop, not drop in isolation. The actual
scaled binary-tree medians are QBE 2,387,990,401→2,391,775,191 (no demonstrated
improvement) and LLVM 1,544,765,380→1,522,068,647 (1.015x). Constructor TAKE has
already removed much of that workload's aggregate drop traffic. Both backends
preserve exact stdout and all counters: 669,060 heap allocations/retirements,
19 owner acquisitions, 669,079 releases, zero holds/clones and 33 uniqueness
checks. These results are not WP-4 performance acceptance. Commands, hashes,
raw runs and the focused C source are in
`experiments/d9-rc-flat-release-20260926/`.

The second slice applies the plan to eligible dying object bodies. Admission
excludes every descriptor callback, so this branch needs no second descriptor
lookup and cannot reenter before enqueueing all ordinary children. It clears
only owner fields, preserving the generic body walk's treatment of scalar
bytes, then retires the parent before draining its queued children. Repeated
allocation elements iterate without a fixed count bound; a zero-leaf body
returns immediately. Custom edges/finalizers, H tokens, raw unique kinds,
variants and unadmitted shapes retain the complete existing fallback.

The production million-node chain now uses a fully described flat one-field
record; the core fixture continues exercising generic million-node release.
A new two-element allocation test verifies duplicate alias releases and exact
queued finalizer order across element boundaries, including parent retirement
before child callbacks. ASan/UBSan passes core 20, collections 27, holds 12,
arenas 10, stats 4 and execution 3; all 37 focused RC tests pass.

| Backend | Before release changes | Typed drops | Plus object bodies |
| --- | ---: | ---: | ---: |
| QBE | 2,387,989,758 | 2,391,775,037 | 2,139,834,663 |
| LLVM | 1,517,873,829 | 1,511,277,297 | 1,330,292,365 |

These are three interleaved instruction medians from the repeated experiment.
Both release changes improve this scaled workload by 1.116x QBE and 1.141x
LLVM; the object-body increment is 1.118x and 1.136x. The much smaller typed-drop
LLVM delta varies between runs alongside descriptor hash/address overhead;
no large whole-workload typed-drop claim is supported. Output and complete
ownership counters remain exactly identical. This still does not approach the
WP-4 performance threshold. A longer QBE self profile after the body change
points primarily to descriptor lookup (14.91%), native take (14.23%), generated
make (14.35%), slot drop (6.14%) and allocation (5.48%). Independent newer
compiler inline-TAKE changes are absent from this isolated slice and must be
measured after joining.
