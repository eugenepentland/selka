# RC journal initialization without a redundant clear

RC frame entry no longer clears the journal-entry array before writing every
semantic field. It still clears every guard, then initializes every retained
entry, and only then links the frame. Against immutable cumulative `19e16e1d`,
binary-trees n12 uses **2.69% fewer QBE instructions**; LLVM O3/full LTO is neutral.
This is one local improvement, not WP-4 performance acceptance. GC remains the default.

The journal plan assigns a dense slot to each retained local, operand, pending
value and internal value. The corresponding entry loops write its descriptor at
offset 0, payload address at 8, guard pointer at 16 and role at 24. These are all
fields read by the runtime. The last four bytes of the 32-byte C slot are padding
and are never read. There is no fallible operation or callback between entry
initialization and frame linking. Uninitialized guards remain zero, and cleanup
still clears a guard before dropping its value. Neither public layout nor cleanup
order changes. Guard zero alone would not permit leaving an entry's guard pointer
uninitialized; the explicit metadata writes are essential and remain present.

Five interleaved samples per backend on CPU 11, with exact output and identical
ABI3 counters, gave these instruction medians:

| Backend | Before | After | Ratio |
|---|---:|---:|---:|
| QBE | 599,762,678 | 583,626,101 | 0.973095 |
| LLVM O3/full LTO | 329,481,279 | 329,481,198 | 1.000000 |

Both arms allocate and retire 669,060 heap objects, acquire 19 extra O tokens and
release 669,079, with no H tokens. Source and native binary hashes, manifests,
commands and every perf sample are in the
[evidence directory](../../experiments/d9-rc-journal-init-20260926/README.md).

The Debug compiler passes 110 focused RC unit tests and 20 before/after native
runs: 54 standalone assertions, logical frame refusal, step refusal, physical
stack-floor refusal and memory-budget refusal on each backend. Each corresponding
pair has identical balanced counters, output and expected status. Formatting and
whole-tree Guardian 88 pass. The integration branch owns the subsequent full gate.

The initial stack-floor probe recursed only 100,000 times and correctly completed
under the smaller frames; the final probe uses 1,000,000. An initial budget fixture
used unsupported list repetition and failed checking. A second budget probe used
2 KiB and failed during startup before counter reporting. The final fixture uses
`list(range(1000000))` under 1 MiB, after guarded values are initialized, and tests
balanced trap cleanup. These harness failures are preserved rather than counted
as successful runtime controls. The final receipt reuses the first eight verified
QBE rows from the second probe and executes the remaining twelve rows.
