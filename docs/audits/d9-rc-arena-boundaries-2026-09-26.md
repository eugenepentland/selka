# RC arena frame boundaries

At an explicit arena boundary the compiler previously zeroed inner local
storage before releasing its guarded owner. An inner binding could still own
an older heap object: forty iterations binding an existing list through a
returning helper produced 121 owner acquires but only four releases, with four
heap allocations and two retirements. The missing owners could also remain
inside inline records and escaped text-view temporaries.

Implementation `ab3bf7f1` restores receiver scopes born in the ending region,
then reverse-drops guarded inner locals and operand/pending scratch slots while
the arena chunks remain live. Only afterward does it clear borrowed local
storage and close the arena. Surviving outer bindings keep the existing region
checks. The bytecode boundary has an empty operand stack; scopes inherited from
an older region remain active. Return and trap paths retain frame cleanup before
arena restoration. Escape continues to return an owned source-preserving copy.

The runtime bridge is `myl_qbe_rc_arena_prepare(context, frame, watermark)`.
It uses the existing frame and scope records and allocates no cleanup metadata.
The C fixture verifies idempotent partial boundary cleanup, a retained outer
pin, cleared inner guards and release before chunk reuse.

## Executed evidence

A Debug compiler built through the build-slot wrapper ran ReleaseFast guests
on QBE and LLVM. The two backends produced identical counters:

| Group | Cases | Heap allocations / retirements | Owner acquires / releases | Holds acquired / released |
| --- | ---: | ---: | ---: | ---: |
| Arena boundaries and escaped graphs | 32 | 3,597 / 3,597 | 1,329 / 4,926 | 10 / 10 |
| Pending array receivers | 19 | 4,041 / 4,041 | 9,973 / 14,014 | 413 / 413 |
| Real trap through nine nested arena frames | 1 | 2 / 2 | 46 / 48 | 0 / 0 |

Every group has `heap_allocate + owner_acquire == owner_release`, balanced
holds, and no saturated counters. The trap reports `R_ASSERT` and the expected
`arena unwind probe` diagnostic. The arena group includes all tests in
`arena_managed`, `arena_scopes`, `arena_regions`, and `arena_class_escape`, five
new ownership regressions, `option_niche.test_an_escaped_graph_keeps_its_optional_links`,
and `text_views.test_pieces_in_arenas_read_and_escape`. Both previously excluded
escape cases pass.

The C startup/frame fixture passes 16 scenarios under ASan and UBSan; its Debug
Zig wrapper passes both named tests. Whole-tree Guardian passes all 88 checks.
One intermediate build correctly rejected a duplicate primary spec tag; the
new behavior now has `RC-ARENA-FRAME-1`, with no gate or ratchet changes.

Commands, source hashes, compiler identity, counters and diagnostics are retained
in [QBE evidence](../../experiments/d9-rc-arena-probes-20260926/qbe.json) and
[LLVM evidence](../../experiments/d9-rc-arena-probes-20260926/llvm.json). The
`compiler_source` field records the joined checkout before the tested edits were
committed; `implementation_commit` and changed-source hashes identify those edits.
This is arena correctness evidence, not WP-4 performance or full-gate acceptance.
