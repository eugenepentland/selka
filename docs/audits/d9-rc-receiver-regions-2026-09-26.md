# RC receiver detachment preserves the allocation region

Two actual golden replays exposed a lifetime error in the RC COW adapters:
`qbe_arena/6c55b0021d5ed868571a0a8ebed536d2` grows a heap list through a mutable
helper while an arena is open; `qbe_arena/6e52fe21c1654619f755a88c87b174bf`
appends an older list to a heap list through a helper in an arena. GC returns
12 (the process exit representation of sum 780) and 4 respectively. Before
this correction, RC reports `R_ARENA_ESCAPE` at arena exit on both backends.

The caller's uniqueness check cloned an older receiver into the currently open
arena. Backing growth correctly followed that header's region. The surviving
outer binding then reached younger storage, so the exit barrier correctly
rejected it. GC's `myl_native_cow_copy` preserves the source payload's region.

The typed local, field, held-field and bulk-element uniqueness bridges now
preserve the original payload region, subject to any stricter containing-object
bound. Pending scope preparation applies the same rule to each managed leaf,
including leaves reached through inline records and fixed arrays. Region lookup
uses only the common 16-byte header, so literal and arena values never require
an RC-prefix read. The O/H role, pin behavior, failure transaction and cleanup
order are unchanged. Explicit copy, take, clone and escape APIs still honor
their requested destination region. The store barrier still refuses a genuinely
younger child in older storage.

## Evidence

The before compiler is Debug source `a02970080a4f212855acdef2c6be1839837d7568`
(constructor publication joined with `d57fef03`); the after compiler is the same
source plus this runtime correction. Source/compiler/binary hashes, commands,
actual backend manifest fields and raw counts are preserved in
`experiments/d9-rc-receiver-regions-20260926/`.

Both exact fixtures now return the GC results on QBE and LLVM. For each backend:

| Fixture | Heap allocation/retirement | Ordinary acquire/release | Hold acquire/release |
| --- | ---: | ---: | ---: |
| `grow.my` | 7 / 7 | 1 / 8 | 2 / 2 |
| `stash.my` | 5 / 5 | 4 / 9 | 1 / 1 |
| Eight-test arena driver | 68 / 68 | 138 / 206 | 7 / 7 |

The driver checks heap receiver growth, outer-arena receiver growth under an
inner arena, inline field detachment, snapshots, escape, early return and error
propagation. All eight guest cases pass in GC and RC on both backends. Another
75 affected arena, view, mutation, loan, iteration and callback cases pass in RC
on each backend. LLVM commands use `--release` without a subsequent `--qbe`
override; exact replay manifests confirm `backend=llvm`.

Five production C suites pass with ASan and UBSan: startup/frame 22, held values
12, arenas 10, core contract 21 and collections 27 (92 top-level scenarios).
Added C coverage includes owned and borrowed roots, fields, H fields, heap and
outer-arena origins, pinned shared sources, ownerless held reuse, 16-byte literal
headers, inline array paths and a younger-store refusal. Existing refusal,
rollback, explicit arena clone and iterative teardown tests remain active.
The bulk-element fixture now requires older heap children to remain in region
zero, rather than being moved into their arena parent.

Focused Debug `zig build test-units -Dtest-filter='RC '` passes 45/45. The Debug
install exercised all 88 Guardian checks without changing rules or ratchets.
The parent owns the joined full gate and Guardian feedback log. This is a
correctness fix; it is not WP-4 performance acceptance.
