# Empty ownership frame evidence

The before compiler is immutable joined `7d68202d`; the after compiler adds only
the bounded empty-frame proof and its lowering checks. `full.json.gz` contains
all compiler/binary identities, build commands, exact stdout, physical counts,
and CPU10 median-three retired-instruction samples for the unchanged 5M nbody.

`validate.py` rebuilds paired snapshot/arena, bounds, overflow, step, logical
frame, physical stack-floor and heap-frame controls on actual QBE and LLVM.
`guests.py` runs nine uncached guest suites in RC and GC-stress on both backends.
Adjust the explicit worktree/install paths when replaying elsewhere.

`advance.il.gz` is accounted Debug structural emission; actual timed guests use
QBE ReleaseFast or LLVM O3/full LTO. `heap-edit.il.gz` records an admitted
706,480-byte heap frame without RC linkage, preserving independent native frame
allocation and cleanup. No compiler was built in ReleaseFast.

Initial receipts retain two fixture-only corrections: explicit discard was
required for three test calls, and the existing integer trap is R_OVERFLOW.
Guardian initially requested splitting two compound conditions. Final receipts
use corrected fixtures/conditions. No rejected sample is part of the medians.

`validation.json.gz` preserves all 32 standalone executions, including the LLVM
physical-floor count difference. Its optimized recursive machine frame shrinks,
so more balanced H operations execute before the same R_FRAME_LIMIT trace.
All logical-limit counters remain exact. `physical-floor-count-comparison.log.gz`
retains the initial overstrict assertion; run `python3 verify.py` here to check
all saved executions with that explicit physical boundary. Both before/after
`dive` disassemblies are included. The runtime maps its own guest stack, so the
host RLIMIT_STACK setting does not define its size.

`guests.json.gz` contains all 320 assertions plus four expected bounds traps;
`summary.json` indexes totals. `tracked-source.patch.gz` describes edits to
already tracked source files; the new proof/test/guest files are preserved in
this commit. Guardian passed all 88 checks, focused tests passed 16/16 and the
broader RC filter passed 65/65. The parent integration owns the full gate.
