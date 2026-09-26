# Invocation-local flat descriptor cache

This bounded runtime change follows the invariant and invalidation audit in
[the cumulative ABI3 report](d9-rc-flat-abi3-next-runtime-2026-09-26.md).
Its parent is `d95621a7`, which includes frozen integration `19e16e1d` and
the ABI3 compatibility tests. It changes no compiler code or runtime ABI.

`myl_rc_drain` keeps one type/binding/batch-head tuple on its native stack.
Consecutive objects with the same admitted flat type reuse the copied binding.
The generic path discards the tuple before callbacks and still resolves the
descriptor after a finalizer. Retirement remains per object, after ordered
clear-before-release of its children. H/O death, LOAN traversal, arenas, budgets,
and counters are unchanged.

Copied bindings live in immutable metadata batches, never the replaceable hash
index. Rehash cannot invalidate their addresses; registration never appends to
an existing batch or replaces a binding. Successful new registration prepends
a batch and invalidates the tuple conservatively. Failed registration changes
neither. Heap destruction forbids an active drain. No callback occurs while a
flat object's descriptor is being used; a custom allocator retirement callback
can register metadata before the next iteration, where the head is rechecked.

The new core test alternates two flat pointer offsets, with poisoned nonpointer
bytes and consecutive same-type objects. Its custom retirement hook registers
64 types, forces index growth, and checks the old descriptor address remains
stable. A finalized tail registers metadata and enqueues another object during
draining. Existing zero/multiple-element, ordered child release, held/loan,
million-chain, budget and rollback cases remain active.

## Separate measurement

Five interleaved samples per arm run on CPU 3. The before binaries are the
immutable cumulative19e builds; accepted GC is unchanged. The candidate changes
only descriptor caching, not slab clearing or concurrent compiler experiments.
Both actual backend manifests are recorded, including LLVM O3/full LTO.

| Backend | Before instructions | After instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 599,762,494 | 571,358,738 | 0.952642 |
| LLVM | 329,481,584 | 305,674,533 | 0.927744 |

All output bytes match. Both backends retain exactly 669,060 allocations and
retirements, O 19/669,079, H 0/0, 33 uniqueness checks and zero clones/refusals.
This is a diagnostic improvement, not WP-4 corpus acceptance.

## Validation and evidence

The actual standalone 54-assertion driver passes before/after on both backends
with identical balanced counts: 1,464 heap allocations/retirements, O 906/2,370,
H 208/208, 96 arena allocations and 31 clones. ASan/UBSan pass contract 22,
collections 32, loans 9, semantic history 27, held views 12 and arenas 10, plus
the execution/statistics harnesses. The focused core wrapper passes 12/12 and
the Debug build passes Guardian's 88 checks.

Commands, compiler/binary/source hashes, backend manifests, raw instruction
samples, counter records and validation receipts are archived in
`experiments/d9-rc-drain-cache-20260926`. Full combined gates and acceptance
remain with the root integration task.
