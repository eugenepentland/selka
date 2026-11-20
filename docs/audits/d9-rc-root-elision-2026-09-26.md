# Remove tracing-root publication from counted frames — 2026-09-26

Counted native functions no longer allocate, publish or restore tracing-GC root
records. Their guarded O/H/unique journals, mutable receiver scopes, arena
barriers and failure unwinding remain the lifetime protocol. The heap pointer
is still emitted when runtime helpers need it. GC artifacts retain their
existing root protocol.

The runtime audit found only the tracing collector walking `heap.roots`.
`myl_native_heap_collect` delegates counted heaps to `myl_rc_drain`; counted
allocation never enters tracing allocation. Native C helpers retain their own
balanced temporary root pushes/pops, which remain harmless and are outside this
change. Existing RC COW scopes already avoid publishing tracing roots.

The compiler skips RC root-liveness planning, root marks, safepoint publication,
restores and root-slot reservations. The conservative and final frame size
calculations both exclude those omitted root slots. It keeps `has_roots` as the
existing managed-heap requirement, since many native helpers still use `%heap`.
No ownership, journal, runtime ABI, type budget or count-limit rule changes.

The structural test compares GC and counted RC from the same source: GC still
links roots, RC still enters/cleans its ownership journal and obtains its heap,
and an arena body retains no stale root mark. It passes 12/12 focused tests.
The frame-admission suite passes 14/14, including unique incoming resources,
heap frames and indirect calls. The Debug install passes 19/19 and Guardian88.
All 116 uncached assertions from 19 selected guest files pass on each actual
backend, covering arenas, callbacks, held views, recursive values, journal type
reuse, rebinding and iteration identity. LLVM uses `--release`.

Matched before/after private binary trees at depth12 use a frozen Debug compiler
from `d57fef03`, O3/full LTO for actual LLVM, and three interleaved retired-user-
instruction samples. This is diagnostic evidence, not WP-4 corpus acceptance.

| Backend | Before median | After median | After/before |
|---|---:|---:|---:|
| QBE | 1,142,588,275 | 1,129,759,957 | 0.988773 |
| LLVM | 673,023,862 | 635,833,489 | 0.944741 |

The larger LLVM before sample is retained in raw evidence. All four counted
controls have identical outputs and counts:669,060 heap allocations/retirements,
19 owner acquires,669,079 releases,zero H operations or clones,and33 uniqueness
checks. [Drivers, hashes, full samples, patch and guest verdicts](../../experiments/d9-rc-root-elision-20260926/identity.json)
are archived together. The parent integration still owns the required full gate
for this slice; the broader native-golden replay is separate and already exposed
preexisting arena and failed-file cleanup gaps. GC remains the default.
