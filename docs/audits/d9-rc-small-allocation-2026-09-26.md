# Cached production allocation for small native bodies

The cumulative source `e2667d56ed6a35e1117ba65daba4e4a87e65f050` was real-merged
as `801ea1115155e4eac2b51109bb9991b3f72d1820` before this independent runtime
experiment. The compiler's ownership lowering is identical in the two arms.

## Change and proof boundary

The native heap allocation adapter now selects a production fast path for one
small heap element. A per-heap cache remembers the most recent successfully
registered immutable native type and its slab class. A hit avoids the repeated
descriptor lookup, generic count/extent validation, indirect allocator dispatch
and class search. Checked small-size admission proves the skipped arithmetic
cannot overflow. A type is cached only after metadata registration succeeds.

The cache stores no allocation, slab or free-list pointer. Type changes replace
the cached class; an empty slab may be trimmed and refilled without invalidating
the type proof. A newly initialized heap has an empty cache. Cold refusal does
not publish an unregistered type. The cache adds 16 charged bytes to each
production allocator context; it is included in the existing `sizeof` budget
reservation and discharge.

Arena requests, counts other than one, oversized or over-aligned objects and
custom allocator hooks retain the generic path. That path keeps descriptor
admission, status propagation and checked bounds. Success produces exactly
O=1/H=0 with a zeroed payload, updates heap allocation accounting once and
records exactly one successful RC allocation event. Slab reuse and retirement
retain the existing ownership, budget and epoch rules.

Slabs now cache their slot capacity, removing the division from allocation and
retirement. This fills eight bytes of prior padding: the aligned metadata extent
remains 80 bytes, asserted at compile time. A budget-limited production test
also confirms exactly 1,363 48-byte slots in one 64 KiB slab. The allocator reads
its private context directly with the same invariant checks, avoiding repeated
out-of-line context accessor calls. No generated ABI, common/RC prefix, public
heap layout or custom hook layout changes.

## Matched private depth-12 measurements

Both compiler installations are immutable Debug builds. Guest QBE uses its
normal optimization; LLVM uses O3 and full LTO. The same private depth-12 binary
trees source runs three interleaved times per arm on CPU 2. Backend/LTO manifests,
source/compiler/binary hashes, exact output hashes, commands, every counter sample
and raw `perf stat` output are preserved under
`experiments/d9-rc-small-allocation-20260926/`.

| Backend | Before instructions | After instructions | Before / after | Fewer instructions |
| --- | ---: | ---: | ---: | ---: |
| QBE | 1,076,792,487 | 923,430,049 | 1.166079x | 14.24% |
| LLVM O3, full LTO | 628,480,834 | 459,754,932 | 1.366991x | 26.85% |

Median cycles are 223,065,289 to 190,242,506 on QBE and 125,265,413 to
104,703,565 on LLVM. These are private diagnostic results, not the matched
43-program WP-4 acceptance corpus.

Every output byte and ownership counter matches across both arms/backends:
669,060 heap allocations and retirements; 19 ordinary acquires and 669,079
ordinary releases; no holds, count refusals, arena allocations or clones; and
33 uniqueness checks. Initial exploratory samples are retained separately:
their QBE median was 907.37 million after instructions. Final-source QBE samples
were 907.37, 923.43 and 923.43 million; this report uses the conservative final
median. Runtime symbol offsets and sizes match between those candidate builds.
Address-dependent metadata hash collisions are a hypothesis for the discrete
spread, not a traced explanation or an excluded sample.

## Checks

The production allocator/collection suite passes 31 ASan+UBSan scenarios. Four
new cases cover type/class switches and heap reinitialization, atomic descriptor
refusal followed by retry, full-slab refusal and trimming followed by a cache
hit, generic counts/arenas/alignment/overflow, and successful/refused custom
allocation hooks with matching retirement. Payload zeroing and frozen prefix
fields are checked across all slab boundaries and the large-object boundary.

Additional held-value (12), arena (10), core-contract (21), statistics (4) and
real-execution (3) sanitizer scenarios pass, as do the existing GC heap,
collection and region sanitizer suites. The final focused Debug RC unit gate
passes 45/45. Both Debug installs exercised Guardian's 88 checks without any rule
or ratchet change. The parent coordinates the joined full gate and feedback log;
the separate broader guest run passes 115/115 on QBE and 115/115 on actual LLVM
across 17 files per backend, using the final immutable Debug compiler. These
cover aggregates, arenas, temporary lifetimes, held views, capabilities,
contracts, recursive values, borrowed results, read loans, mutation receivers,
callback captures, journal types, iteration identity and loop versions. The
commands, compiler hash and individual results are preserved in `guests.json.gz`;
the LLVM invocation uses `--release` without a conflicting `--qbe` selector.
The remaining RC performance gap is still well outside WP-4 acceptance.
