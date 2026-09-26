# Direct physical RC token transfers — 2026-09-26

The compiler emits a bounded fast path for TAKE of physical layouts containing
at most eight ordinary pointer leaves. It checks disjoint source/destination
ranges and every non-null pointer's common header before changing any bytes.
Arena, pinned or dying sources enter the existing transactional runtime path;
held edges, unique resources and unsupported inline layouts are excluded during
compilation. Pointer null checks and high header masks use full-width comparisons
before QBE's word-sized conditional branch.

Once preflight succeeds, the operation copies the bytes and clears the source.
It allocates nothing, invokes no callback, changes no counts, and leaves the
caller's source-guard handoff after successful publication. Instrumented and
uninstrumented artifacts use the same path. Generated callers provide the current
valid region. The public ownership boundary has already drained deaths, while
reentrant guest execution from a finalizer is inside an active drain; therefore
pure token relocation does not need a redundant drain call. The runtime's
boundary documentation and queued-sibling/reentrant TAKE regression accompany
`5acc3f20`; arbitrary internal C edge-queue manipulation is not a guest boundary.

Focused tests pass 13/13, the aggregate construction test passes 12/12, and actual
uncached RC tests pass 77/77 on each backend. Those tests cover recursive boxes,
arenas, held views, unique capability resources, contracts, borrowed results,
scalar loans and mutation receivers. Whole-tree Guardian88 passes. The initial
aggregate assertion matched a new eight-byte source clear; it now identifies the
sixteen-byte Pair body and still verifies partial ownership before fallible work.

Private binary-trees n12 instruction medians fall from 2,320,872,018 to
1,672,867,859 on QBE (0.720793 after/before) and 1,455,441,814 to 963,137,800 on
LLVM O3/full LTO (0.661749). All four counted runs have identical counters:
19 owner acquisitions, 669,079 releases, 669,060 allocations/retirements, zero
holds/clones, and 33 uniqueness checks. Output bytes are exact. The before source
`53a0341f` already includes flat runtime plans, constructor takes, inert receivers
and empty cleanup guards. This remains a private diagnostic, not WP-4 acceptance.

Evidence is retained in `experiments/d9-rc-inline-take-20260926/`, including
compiler/binary hashes, commands, raw samples, the complete implementation patch,
and all 154 guest verdicts. The original drivers use `.tmp-schematic/inline-take`
and `.tmp-schematic/install-before-inline-take/bin/mylang` as their scratch/control
paths. Guest mode defaults to ReleaseFast; every compiler used is Debug.
