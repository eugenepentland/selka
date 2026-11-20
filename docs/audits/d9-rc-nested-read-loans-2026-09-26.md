# RC nested collection receiver loans

The scalar receiver proof now follows managed list elements into immediate,
single-definition compiler receivers. A chain such as `rows[i][j]` can read its
row without publishing another owner, provided the final result is scalar and
every receiver's complete live interval is inert. An iterative worklist checks
all descendants before annotating any binding. Its bounded work budget and
repeated-local refusal fall back to ordinary ownership.

Every descendant points directly to the stable named root's storage. The
existing physical RC planner retains that root until its last borrowed child
finishes, so no additional liveness or state fields are needed. The result hook
skips owner publication only for a certified read immediately followed by its
hidden receiver store. Its index operand is plain and its journal guard remains
clear. Bounds and arithmetic traps retain the normal frame cleanup.

Named rows, returned or stored managed results, calls, mutations, arena
transitions, dictionary/H roles, boxes, pattern bindings and temporary roots
remain outside this proof. Intermediate reads must originate from a list:
text indexing creates an owned character string and cannot be treated as a
borrowed child. Byte and text elements may still be borrowed from a list for a
final scalar read or length operation if the complete proof succeeds.

Matched Debug compiler installations produce the same n=12 matrix output on
QBE and actual LLVM O3/LTO: `41383` and `485891`. Both backends have these counts:

| Counter | Before | After |
| --- | ---: | ---: |
| Owner acquisitions | 9,343 | 1,831 |
| Owner releases | 9,475 | 1,963 |
| Heap allocations / retirements | 132 / 132 | 132 / 132 |
| Uniqueness checks | 5,652 | 5,652 |
| Clones | 1 | 1 |
| Holds | 0 | 0 |

The 7,512 removed acquisitions and releases belong to read-only receiver
publication. Pending mutation receivers keep their existing ownership. Runtime
code, count ABI and mutation-scope lowering do not change in this slice.

The new seven-case guest fixture covers three-level negative indexing, repeated
loop roots and branches, callbacks that replace the selected row, named row
snapshots after root replacement, pending mutable receivers, dictionary/live
view roles, fresh Unicode character values, and reads inside an arena.

All seven cases pass before and after on both backends, and also pass under
GC stress after the change. Their counted run drops from 347 acquisitions and
755 releases to 284 acquisitions and 688 releases, with 404 allocations and
retirements, 55 holds each way and three clones after the change. Removing
pinned read copies also removes two clones and four allocations in this fixture.
The bounds trap preserves `R_LIST_BOUNDS` and retires all five allocations on
both backends; acquisitions/releases fall from 6/11 to 4/9.

The broader collection set passes 95 assertions on each actual backend with
identical balanced counts: 74,282 allocations/retirements, 472,856 acquisitions,
547,138 releases, and 67,507 holds each way. This includes the prior sorting,
text-view, dictionary-key, live-view, callback and temporary-lifetime regressions.
All six scalar/nested compiler proof tests pass (17 tests including the shared
unnamed tests). Guardian passes all 88 checks.

Exact sources, commands and hashes are in
[the experiment](../../experiments/d9-rc-nested-read-loans-20260926/README.md).
The broader results and GC-stress commands are preserved in
[compressed evidence](evidence/d9-rc-nested-read-loans.json.gz).
These are isolated ownership diagnostics, not a full-corpus timing result.
Integration owns the combined full gate and acceptance measurements.
