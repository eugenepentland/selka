# D9 WP-4: remaining constructor instruction gap

The cumulative compiler/runtime at `7fc669a7` (`743fea73` plus the flat release,
empty-cleanup scan and cold invariant changes) still fails the WP-4 performance
criterion. This is a private depth-12 diagnosis, not the 43-program acceptance
corpus. No production behavior changes in this report.

The same Debug compiler built GC, RC and counting RC versions of the same
source. QBE uses its normal optimization; LLVM uses O3/full LTO, verified in
each manifest. Three interleaved CPU-0 measurements count retired user
instructions. All output hashes match, and both counting binaries report
669,060 allocations and retirements, 19 owner acquisitions, 669,079 releases,
no holds or clones, and 33 uniqueness checks.

| Backend | RC instructions | GC instructions | RC / GC |
| --- | ---: | ---: | ---: |
| QBE | 1,229,932,997 | 105,808,956 | 11.6241 |
| LLVM | 694,618,424 | 50,540,743 | 13.7437 |

## Where the instructions remain

`check` is already the same machine-code size in GC and RC: 455 bytes on QBE
and 152 bytes on LLVM. `make` is 7,983 versus 739 bytes on QBE, and 5,212 versus
518 on LLVM. The QBE fixed stack reservation is 616 versus 152 bytes. Code size
includes cold paths and is not a dynamic instruction estimate.

The profile driver repeats the unchanged n12 workload 240 times in one
process. This avoids repeatedly sampling the same initial positions of a short
process. `perf record -e cpu_core/instructions/u -F 199` samples retired
instructions. Approximate weighted self shares are:

| Site | QBE | LLVM |
| --- | ---: | ---: |
| generated `make` | 32.9% | 44.6% |
| allocator `allocate` | 11.5% | 14.0% |
| descriptor lookup / `native_shape` / `rc_new` | 10.9% | 13.6% |
| `memset` | 7.4% | 1.3% |
| frame cleanup | 6.7% | inlined |
| region mark | 5.1% | inlined |
| flat edge release + drain | 6.0% | 16.6% |

These are sampled attribution, not exact component instruction totals. The
machine limits perf sampling to 1,000 events/second; throttle/unthrottle records
remain even at frequency 199. No samples were reported lost. Per-profile
sampling metadata and weighted samples are retained. Earlier fixed-period,
short-process profiles were discarded because repeated process startup biased
their sampled PCs. In particular, no speedup is inferred from a profile share.

For QBE, `make`'s entry before the depth branch accounts for about 5.1% of
all sampled instructions, its nonleaf body 20.3%, and its leaf body 7.5%; helper
costs are separate. The fixture calls `make` 674,518 times, including 339,988
leaves, as derived from its tree depths and iteration counts. Every entry
executes 109 caller instructions before selecting the depth branch, including
calls that clear 240 bytes and then publish six 28-byte journal entries.
That is approximately 275 MB of prologue stores even though leaf results
contain only null edges. The private profile is dominated by completed-value
publication and allocation, not ordinary retain traffic.

## Concrete opportunities and proof boundaries

1. **Publish a completed constructor directly to its stable operand slot.**
   Currently a returned Node travels through aggregate scratch, pending work,
   operand storage, pending work again, and its destination body. Completed
   constructors repeat pending-result registration and clear-guard input drops.
   Keep the internal partial-constructor guard through every fallible field
   transfer. Once every input obligation has transferred or been released,
   copy the complete result directly to its stable operand slot, publish the
   typed initialized guard, and disarm the internal guard without a callback
   or fallible step between those writes. Payload-less ordinary variants may
   publish their initialized typed zero directly. H conversion, pin-aware
   transfer, region checks, partial rollback and unique cleanup remain on their
   existing paths. This has no journal ABI change. It is the next approved
   implementation slice; it is not implemented by this report.
2. **Add an RC allocation fast path with an explicit proof contract.**
   `qbe_alloc.cell` enables inline small allocation only when RC is disabled.
   Each RC body currently calls `native_heap_alloc`, `native_heap_alloc_at`,
   `native_shape`, `rc_new`, then the allocator hook, repeating descriptor
   validation and a size-class search for a statically known one-element body.
   A specialized registered-body/small-class entry could retain the existing
   allocator's reuse and budget behavior while eliminating the wrappers and
   repeated classification. Full inline windows require a separate proof of
   slab lifetime, immediate free-list reuse, unused reservations, exact live
   counts, counting events, arena fallback and cold allocation refusal. The GC
   16-byte header/window path cannot be reused unchanged for 32-byte RC objects.
3. **Remove duplicate GC root publication in RC.**
   The generated constructor still links tracing roots while its RC journal
   owns the same values, including the all-null leaf record. Root mark alone
   is only about 0.3% of the QBE RC profile; inline link stores and their register
   pressure are inside `make`. This is useful but cannot explain a 12x gap.
   Removing roots requires preserving the independently used heap pointer,
   native stack/heap-frame admission accounting, RC scopes, trap journals and
   host callback lifetime contracts. Native C roots can remain for GC providers;
   counted mode must never silently enter tracing collection.

Static journal tags or frame compaction could remove more metadata, but change
more proof surface than eliminating a redundant completed-result publication.
The prior empty-entry experiment did not establish a speedup, so deleting its
stores alone is not presented as the solution. None of the opportunities above
is individually claimed to close the measured gap.

## Evidence and checks

`experiments/d9-rc-instruction-gap-20260926` contains source, commands, compiler
and binary hashes, original n12 samples/counts, repeated-workload profile
samples, assembly and sampling limitations. The Debug install passed Guardian
88 checks and 12/12 build steps. No full corpus or new full regression gate was
run for this read-only diagnosis. The parent agent owns the serialized Guardian
feedback entry and final integrated gate.
